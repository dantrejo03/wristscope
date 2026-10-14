import math

import pytest
from PySide6 import QtCore, QtNetwork

from wristscope.channels import Source
from wristscope.receiver import WatchFeed
from wristscope.samples import Sample
from wristscope.wire import encode_frame, encode_records


@pytest.fixture(scope="module")
def qapp():
    return QtCore.QCoreApplication.instance() or QtCore.QCoreApplication([])


@pytest.fixture
def feed(qapp):
    feed = WatchFeed(port=0, advertise=False)  # port 0: any free port
    yield feed
    feed.close()


def pump(predicate, timeout=2.0):
    clock = QtCore.QElapsedTimer()
    clock.start()
    while not predicate() and clock.elapsed() < timeout * 1000:
        QtCore.QCoreApplication.processEvents(QtCore.QEventLoop.ProcessEventsFlag.AllEvents, 10)
    assert predicate()


def connect(feed) -> QtNetwork.QTcpSocket:
    sock = QtNetwork.QTcpSocket()
    sock.connectToHost("127.0.0.1", feed.port)
    pump(lambda: sock.state() == QtNetwork.QAbstractSocket.SocketState.ConnectedState)
    pump(lambda: feed._socket is not None)
    return sock


def gyro(t):
    return Sample(Source.GYRO, t, {"gyro.x": t})


def send(sock, seq, samples):
    sock.write(encode_frame(encode_records(samples), seq, 0.0))
    sock.flush()


def test_waiting_status_names_address(feed):
    assert f":{feed.port}" in feed.status() and "Waiting" in feed.status()


def test_samples_arrive_in_poll(feed):
    sock = connect(feed)
    send(sock, 0, [gyro(1.0), gyro(2.0)])
    pump(lambda: len(feed._pending) == 2)
    assert [s.timestamp for s in feed.poll()] == [1.0, 2.0]
    assert feed.poll() == []
    assert "Streaming" in feed.status()


def test_sequence_gap_counts_dropped_frames(feed):
    sock = connect(feed)
    for seq in (5, 6, 9):
        send(sock, seq, [gyro(seq)])
    pump(lambda: feed.frames == 3)
    assert feed.dropped_frames == 2
    assert "2 frames dropped" in feed.status()


def test_sequence_restart_is_not_a_drop(feed):
    sock = connect(feed)
    for seq in (50, 51, 0, 1):
        send(sock, seq, [gyro(seq)])
    pump(lambda: feed.frames == 4)
    assert feed.dropped_frames == 0 and feed.phone_restarts == 1


def test_gap_across_reconnect_is_counted(feed):
    first = connect(feed)
    send(first, 0, [gyro(0)])
    pump(lambda: feed.frames == 1)
    first.disconnectFromHost()
    pump(lambda: feed._socket is None)
    second = connect(feed)
    send(second, 4, [gyro(4)])
    pump(lambda: feed.frames == 2)
    assert feed.dropped_frames == 3


def test_new_connection_replaces_old_with_fresh_splitter(feed):
    first = connect(feed)
    first.write(encode_frame(encode_records([gyro(1.0)]), 0, 0.0)[:10])  # half a frame
    first.flush()
    QtCore.QCoreApplication.processEvents()
    old = feed._socket
    second = QtNetwork.QTcpSocket()
    second.connectToHost("127.0.0.1", feed.port)
    pump(lambda: feed._socket is not old)
    send(second, 0, [gyro(2.0)])
    pump(lambda: len(feed._pending) == 1)
    assert feed.poll()[0].timestamp == 2.0


def test_garbage_length_closes_connection(feed):
    sock = connect(feed)
    sock.write(b"\xff\xff\xff\xff" + bytes(12))
    sock.flush()
    pump(lambda: feed._socket is None)
    assert "bad stream" in feed.status()


def test_bad_frame_keeps_earlier_samples_and_carries_on(feed):
    sock = connect(feed)
    good = encode_records([gyro(1.0)])
    sock.write(encode_frame(good + bytes([99]), 0, 0.0))
    sock.write(encode_frame(encode_records([gyro(2.0)]), 1, 0.0))
    sock.flush()
    pump(lambda: feed.frames == 2)
    assert [s.timestamp for s in feed.poll()] == [1.0, 2.0]
    assert feed.bad_frames == 1


def test_wrong_version_is_reported(feed):
    sock = connect(feed)
    sock.write(encode_frame(b"WRSC\x02", 0, 0.0))
    sock.flush()
    pump(lambda: feed.bad_frames == 1)
    assert "v2" in feed.status()


def test_late_frame_is_not_a_drop_or_restart(feed):
    sock = connect(feed)
    for seq in (3, 5, 4, 6):
        send(sock, seq, [gyro(seq)])
    pump(lambda: feed.frames == 4)
    assert feed.dropped_frames == 0 and feed.phone_restarts == 0
