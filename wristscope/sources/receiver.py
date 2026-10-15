"""The live feed: connects to the iPhone app and turns what it sends into samples.

The phone app listens on PORT and the Mac connects to it, over USB through usbmuxd (see
usbmux.py), or straight to a host over TCP when one is given (tools/fake_phone.py uses that).
An attempt that fails or gets no answer within DIAL_TIMEOUT_SECONDS, or a connection that
drops, is retried every RETRY_SECONDS.

Everything runs on the Qt main thread, the same one as the window's redraw timer,
so bytes arriving and `poll()` never overlap and no locks are needed.
"""

import logging

from PySide6 import QtCore, QtNetwork

from wristscope.core.samples import Sample
from wristscope.transport import usbmux
from wristscope.transport.wire import FrameSplitter, PayloadError, WireError, decode_records

log = logging.getLogger(__name__)

PORT = 9000  # the iPhone app listens here
RETRY_SECONDS = 1.0
DIAL_TIMEOUT_SECONDS = 5.0
LATE_FRAMES = 8  # a frame this far behind is late; further back means the phone restarted

Socket = QtNetwork.QTcpSocket | QtNetwork.QLocalSocket


class WatchFeed(QtCore.QObject):
    """A Feed of samples streamed from the watch through the iPhone app."""

    def __init__(self, port: int = PORT, host: str | None = None, usbmuxd: str = usbmux.SOCKET_PATH) -> None:
        """Connect to the phone app on `port`: over USB, or straight to `host` over TCP if one is given."""
        super().__init__()
        self.port = port
        self.host = host
        self._usbmuxd = usbmuxd
        self._pending: list[Sample] = []
        self._stream: Socket | None = None  # the open connection to the phone
        self._dialing: Socket | None = None  # a connection to the phone, or a request to usbmuxd, under way
        self._device: int | None = None  # the USB device being connected to, once usbmuxd has listed it
        self._mux_buffer = bytearray()
        self._splitter = FrameSplitter()
        self._expected_seq: int | None = None  # kept across connections so a reconnect shows up as a gap
        self._hint = ""  # why there's no connection yet
        self._closed = False
        self.frames = 0
        self.dropped_frames = 0
        self.bad_frames = 0
        self.phone_restarts = 0
        self.last_error = ""

        self._retry = QtCore.QTimer(self)
        self._retry.setSingleShot(True)
        self._retry.setInterval(round(RETRY_SECONDS * 1000))
        self._retry.timeout.connect(self._dial)
        self._timeout = QtCore.QTimer(self)
        self._timeout.setSingleShot(True)
        self._timeout.setInterval(round(DIAL_TIMEOUT_SECONDS * 1000))
        self._timeout.timeout.connect(self._timed_out)
        self._dial()

    # MARK: Feed

    def poll(self) -> list[Sample]:
        samples, self._pending = self._pending, []
        return samples

    def status(self) -> str:
        route = "over USB" if self.host is None else f"at {self.host}:{self.port}"
        if self._stream is None:
            text = f"Waiting for iPhone {route}"
            if self._hint:
                text += f" · {self._hint}"
        else:
            text = f"Streaming from iPhone {route}"
        if self.dropped_frames:
            text += f" · {self.dropped_frames} frames dropped"
        if self.last_error:
            text += f" · {self.last_error}"
        return text

    def close(self) -> None:
        self._closed = True
        self._retry.stop()
        for sock in (self._dialing, self._stream):
            if sock is not None:
                self._discard(sock)

    # MARK: Connecting

    def _dial(self) -> None:
        """Start one attempt to reach the phone. If it fails, the next starts RETRY_SECONDS later."""
        if self._closed or self._stream is not None or self._dialing is not None:
            return
        if self.host is not None:
            sock = QtNetwork.QTcpSocket(self)
            self._track(sock)
            sock.connected.connect(lambda: self._opened(sock))
            sock.connectToHost(self.host, self.port)
        else:
            self._device = None
            self._ask_usbmuxd(usbmux.list_devices())

    def _ask_usbmuxd(self, request: bytes) -> None:
        """Send one request on a new socket to usbmuxd. The reply arrives in `_usbmuxd_replied`."""
        sock = QtNetwork.QLocalSocket(self)
        self._mux_buffer = bytearray()
        self._track(sock)
        sock.connected.connect(lambda: sock.write(request))
        sock.connectToServer(self._usbmuxd)

    def _track(self, sock: Socket) -> None:
        """Make `sock` the one dialing and route its events here.

        A socket's events can arrive after it has been replaced, so each handler first
        checks whether `sock` is still the one dialing or streaming.
        """
        self._dialing = sock
        self._timeout.start()
        sock.readyRead.connect(lambda: self._read(sock))
        sock.disconnected.connect(lambda: self._lost(sock))
        sock.errorOccurred.connect(lambda _error: self._error(sock))

    def _usbmuxd_replied(self, sock: QtNetwork.QLocalSocket, reply: dict) -> None:
        if self._device is None:  # the reply to ListDevices
            self._discard(sock)  # Connect gets a socket of its own, since success turns it into the stream
            devices = usbmux.usb_devices(reply)
            if not devices:
                self._failed(None, "plug the iPhone into this Mac with a cable")
                return
            self._device = devices[0]
            self._ask_usbmuxd(usbmux.connect(self._device, self.port))
            return

        code = usbmux.result_code(reply)  # the reply to Connect
        if code == usbmux.RESULT_OK:
            self._opened(sock, leftover=bytes(self._mux_buffer))  # anything after the reply came from the phone
        elif code == usbmux.RESULT_REFUSED:
            self._failed(sock, "open Wristscope on the iPhone")
        elif code == usbmux.RESULT_NO_DEVICE:
            self._failed(sock, "the iPhone was unplugged")
        else:
            self._failed(sock, f"usbmuxd couldn't connect (result {code})")

    def _opened(self, sock: Socket, leftover: bytes = b"") -> None:
        self._dialing = None
        self._timeout.stop()
        self._stream = sock
        self._splitter = FrameSplitter()
        self._hint = ""
        self.last_error = ""
        if leftover:
            self._read_frames(sock, leftover)

    def _failed(self, sock: Socket | None, hint: str) -> None:
        """The attempt to reach the phone didn't work: say why and try again soon."""
        if sock is not None:
            self._discard(sock)
        self._hint = hint
        self._retry.start()

    def _timed_out(self) -> None:
        if self._dialing is not None:
            self._failed(self._dialing, "usbmuxd didn't answer" if self.host is None else "no answer")

    def _error(self, sock: Socket) -> None:
        if sock is self._dialing:
            reason = sock.errorString()
            self._failed(sock, reason if self.host is not None else f"can't reach usbmuxd ({reason})")
        elif sock is self._stream:
            self._lost(sock)

    def _lost(self, sock: Socket) -> None:
        if sock is self._stream:
            self._discard(sock)
            self._hint = ""
            self._retry.start()
        elif sock is self._dialing:
            self._failed(sock, "usbmuxd closed the connection")

    def _discard(self, sock: Socket) -> None:
        """Close a socket. It's forgotten first, so the events that closing it sends are ignored."""
        if sock is self._dialing:
            self._dialing = None
            self._timeout.stop()
        if sock is self._stream:
            self._stream = None
        sock.abort()
        sock.deleteLater()

    # MARK: Reading

    def _read(self, sock: Socket) -> None:
        if sock is self._stream:
            self._read_frames(sock, sock.readAll().data())
        elif sock is self._dialing and isinstance(sock, QtNetwork.QLocalSocket):
            self._mux_buffer += sock.readAll().data()
            try:
                reply = usbmux.take_reply(self._mux_buffer)
            except usbmux.UsbmuxError as error:
                self._failed(sock, f"usbmuxd: {error}")
                return
            if reply is not None:
                self._usbmuxd_replied(sock, reply)

    def _read_frames(self, sock: Socket, data: bytes) -> None:
        try:
            frames = self._splitter.feed(data)
        except WireError as error:
            self.last_error = f"closed bad stream ({error})"
            log.warning("%s", self.last_error)
            self._lost(sock)  # reconnect and start clean
            return
        for frame in frames:
            self._note_sequence(frame.seq)
            self.frames += 1
            try:
                self._pending += decode_records(frame.payload)
            except PayloadError as error:
                self.bad_frames += 1
                self.last_error = str(error)
                log.warning("bad frame %d: %s", frame.seq, error)
                self._pending += error.samples

    def _note_sequence(self, seq: int) -> None:
        if self._expected_seq is not None:
            if seq > self._expected_seq:
                self.dropped_frames += seq - self._expected_seq
            elif seq < self._expected_seq:
                if self._expected_seq - seq <= LATE_FRAMES:
                    # Arrived after its successor: it was counted as dropped, so take that back.
                    self.dropped_frames = max(0, self.dropped_frames - 1)
                    return
                self.phone_restarts += 1  # the phone app restarted and numbers from 0 again
        self._expected_seq = seq + 1
