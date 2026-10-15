import plistlib
import socket
import struct
import uuid

import pytest
from PySide6 import QtCore, QtNetwork

from wristscope.core.channels import Source
from wristscope.core.samples import Sample
from wristscope.sources import receiver
from wristscope.sources.receiver import WatchFeed
from wristscope.transport.wire import encode_frame, encode_records
from wristscope.transport import usbmux


@pytest.fixture(scope="module")
def qapp():
    return QtCore.QCoreApplication.instance() or QtCore.QCoreApplication([])


@pytest.fixture(autouse=True)
def quick_retry(monkeypatch):
    monkeypatch.setattr(receiver, "RETRY_SECONDS", 0.02)


def pump(predicate, timeout=2.0):
    clock = QtCore.QElapsedTimer()
    clock.start()
    while not predicate() and clock.elapsed() < timeout * 1000:
        QtCore.QCoreApplication.processEvents(QtCore.QEventLoop.ProcessEventsFlag.AllEvents, 10)
    assert predicate()


def gyro(t):
    return Sample(Source.GYRO, t, {"gyro.x": t})


def frame(seq, samples):
    return encode_frame(encode_records(samples), seq, 0.0)


def send(sock, seq, samples):
    sock.write(frame(seq, samples))
    sock.flush()


# MARK: Straight to a host over TCP


class FakePhone:
    """Listens like the iPhone app does."""

    def __init__(self) -> None:
        self.server = QtNetwork.QTcpServer()
        assert self.server.listen(QtNetwork.QHostAddress.SpecialAddress.LocalHost, 0)
        self.port = self.server.serverPort()

    def accept(self) -> QtNetwork.QTcpSocket:
        pump(self.server.hasPendingConnections)
        return self.server.nextPendingConnection()


@pytest.fixture
def phone(qapp):
    phone = FakePhone()
    yield phone
    phone.server.close()


@pytest.fixture
def feed(phone):
    feed = WatchFeed(port=phone.port, host="127.0.0.1")
    yield feed
    feed.close()


def connect(feed, phone) -> QtNetwork.QTcpSocket:
    sock = phone.accept()
    pump(lambda: feed._stream is not None)
    return sock


def test_waiting_status_says_why(qapp):
    closed = FakePhone()
    port = closed.port
    closed.server.close()
    feed = WatchFeed(port=port, host="127.0.0.1")
    try:
        pump(lambda: feed._hint != "")
        assert feed.status().startswith(f"Waiting for iPhone at 127.0.0.1:{port} · ")
    finally:
        feed.close()


def test_samples_arrive_in_poll(feed, phone):
    sock = connect(feed, phone)
    send(sock, 0, [gyro(1.0), gyro(2.0)])
    pump(lambda: len(feed._pending) == 2)
    assert [s.timestamp for s in feed.poll()] == [1.0, 2.0]
    assert feed.poll() == []
    assert feed.status().startswith("Streaming from iPhone at 127.0.0.1")


def test_sequence_gap_counts_dropped_frames(feed, phone):
    sock = connect(feed, phone)
    for seq in (5, 6, 9):
        send(sock, seq, [gyro(seq)])
    pump(lambda: feed.frames == 3)
    assert feed.dropped_frames == 2
    assert "2 frames dropped" in feed.status()


def test_sequence_restart_is_not_a_drop(feed, phone):
    sock = connect(feed, phone)
    for seq in (50, 51, 0, 1):
        send(sock, seq, [gyro(seq)])
    pump(lambda: feed.frames == 4)
    assert feed.dropped_frames == 0 and feed.phone_restarts == 1


def test_late_frame_is_not_a_drop_or_restart(feed, phone):
    sock = connect(feed, phone)
    for seq in (3, 5, 4, 6):
        send(sock, seq, [gyro(seq)])
    pump(lambda: feed.frames == 4)
    assert feed.dropped_frames == 0 and feed.phone_restarts == 0


def test_reconnects_and_counts_the_gap(feed, phone):
    first = connect(feed, phone)
    send(first, 0, [gyro(0)])
    pump(lambda: feed.frames == 1)
    first.disconnectFromHost()
    pump(lambda: feed._stream is None)
    second = connect(feed, phone)
    send(second, 4, [gyro(4)])
    pump(lambda: feed.frames == 2)
    assert feed.dropped_frames == 3


def test_reconnect_starts_with_fresh_splitter(feed, phone):
    first = connect(feed, phone)
    first.write(frame(0, [gyro(1.0)])[:10])  # half a frame
    first.flush()
    pump(lambda: len(feed._splitter._buffer) == 10)
    first.disconnectFromHost()
    pump(lambda: feed._stream is None)
    second = connect(feed, phone)
    send(second, 1, [gyro(2.0)])
    pump(lambda: len(feed._pending) == 1)
    assert feed.poll()[0].timestamp == 2.0


def test_garbage_length_closes_connection_then_reconnects(feed, phone):
    sock = connect(feed, phone)
    sock.write(b"\xff\xff\xff\xff" + bytes(12))
    sock.flush()
    pump(lambda: feed._stream is None)
    assert "bad stream" in feed.status()
    connect(feed, phone)
    assert "bad stream" not in feed.status()


def test_bad_frame_keeps_earlier_samples_and_carries_on(feed, phone):
    sock = connect(feed, phone)
    good = encode_records([gyro(1.0)])
    sock.write(encode_frame(good + bytes([99]), 0, 0.0))
    sock.write(frame(1, [gyro(2.0)]))
    sock.flush()
    pump(lambda: feed.frames == 2)
    assert [s.timestamp for s in feed.poll()] == [1.0, 2.0]
    assert feed.bad_frames == 1


def test_wrong_version_is_reported(feed, phone):
    sock = connect(feed, phone)
    sock.write(encode_frame(b"WRSC\x02", 0, 0.0))
    sock.flush()
    pump(lambda: feed.bad_frames == 1)
    assert "v2" in feed.status()


# MARK: Over USB through usbmuxd


class FakeUsbmuxd:
    """Answers like usbmuxd. After a Connect it answers with `result`, that socket is `phone`."""

    def __init__(self, devices: list[tuple[int, str]], result: int = usbmux.RESULT_OK) -> None:
        self.devices = devices  # (device ID, "USB" or "Network")
        self.result = result
        self.silent = False  # read requests but never answer
        self.greeting = b""  # sent straight after a successful Connect's reply, as a quick phone would
        self.requests: list[dict] = []
        self.phone: QtNetwork.QLocalSocket | None = None
        self.server = QtNetwork.QLocalServer()
        assert self.server.listen(f"wristscope-test-{uuid.uuid4().hex[:8]}")
        self.path = self.server.fullServerName()
        self.server.newConnection.connect(self._accept)

    def _accept(self) -> None:
        while self.server.hasPendingConnections():
            sock = self.server.nextPendingConnection()
            buffer = bytearray()
            sock.readyRead.connect(lambda sock=sock, buffer=buffer: self._read(sock, buffer))

    def _read(self, sock: QtNetwork.QLocalSocket, buffer: bytearray) -> None:
        buffer += sock.readAll().data()
        request = usbmux.take_reply(buffer)  # requests are framed the same way as replies
        if request is None:
            return
        self.requests.append(request)
        if self.silent:
            return
        if request["MessageType"] == "ListDevices":
            devices = [{"DeviceID": device_id, "MessageType": "Attached",
                        "Properties": {"ConnectionType": kind, "DeviceID": device_id}}
                       for device_id, kind in self.devices]
            sock.write(self._reply({"DeviceList": devices}))
        else:
            sock.write(self._reply({"MessageType": "Result", "Number": self.result}) + self.greeting)
            if self.result == usbmux.RESULT_OK:
                self.phone = sock

    @staticmethod
    def _reply(reply: dict) -> bytes:
        body = plistlib.dumps(reply)
        return struct.pack("<IIII", 16 + len(body), 1, 8, 1) + body


@pytest.fixture
def usbmuxd(qapp):
    fake = FakeUsbmuxd(devices=[(5, "Network"), (7, "USB")])
    yield fake
    fake.server.close()


def test_streams_from_the_phone_plugged_in_by_cable(usbmuxd):
    feed = WatchFeed(port=9000, usbmuxd=usbmuxd.path)
    try:
        pump(lambda: feed._stream is not None)
        assert [r["MessageType"] for r in usbmuxd.requests] == ["ListDevices", "Connect"]
        assert usbmuxd.requests[1]["DeviceID"] == 7  # the USB one, not the one on Wi-Fi
        assert usbmuxd.requests[1]["PortNumber"] == socket.htons(9000)
        send(usbmuxd.phone, 0, [gyro(1.0)])
        pump(lambda: len(feed._pending) == 1)
        assert feed.status() == "Streaming from iPhone over USB"
    finally:
        feed.close()


def test_keeps_frames_that_arrive_with_the_connect_reply(usbmuxd):
    usbmuxd.greeting = frame(0, [gyro(1.0)])
    feed = WatchFeed(usbmuxd=usbmuxd.path)
    try:
        pump(lambda: len(feed._pending) == 1)
    finally:
        feed.close()


def test_ignores_a_phone_on_wifi(usbmuxd):
    usbmuxd.devices = [(5, "Network")]
    feed = WatchFeed(usbmuxd=usbmuxd.path)
    try:
        pump(lambda: len(usbmuxd.requests) >= 2)  # it has listed devices at least twice
        assert {r["MessageType"] for r in usbmuxd.requests} == {"ListDevices"}
        assert "plug the iPhone into this Mac" in feed.status()
    finally:
        feed.close()


def test_asks_for_the_app_until_it_listens(usbmuxd):
    usbmuxd.result = usbmux.RESULT_REFUSED
    feed = WatchFeed(usbmuxd=usbmuxd.path)
    try:
        pump(lambda: "open Wristscope on the iPhone" in feed.status())
        usbmuxd.result = usbmux.RESULT_OK
        pump(lambda: feed._stream is not None)
    finally:
        feed.close()


def test_gives_up_on_an_attempt_that_gets_no_answer(usbmuxd, monkeypatch):
    monkeypatch.setattr(receiver, "DIAL_TIMEOUT_SECONDS", 0.05)
    usbmuxd.silent = True
    feed = WatchFeed(usbmuxd=usbmuxd.path)
    try:
        pump(lambda: "usbmuxd didn't answer" in feed.status())
        usbmuxd.silent = False
        pump(lambda: feed._stream is not None)
    finally:
        feed.close()


def test_says_when_usbmuxd_is_missing(qapp):
    feed = WatchFeed(usbmuxd="/nonexistent/usbmuxd")
    try:
        pump(lambda: "can't reach usbmuxd" in feed.status())
    finally:
        feed.close()
