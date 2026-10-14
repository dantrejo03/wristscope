"""The live feed: listens for the iPhone app and turns what it sends into samples.

Everything runs on the Qt main thread, the same one as the window's redraw timer,
so bytes arriving and `poll()` never overlap and no locks are needed.
"""

import logging
import socket

from PySide6 import QtCore, QtNetwork

from wristscope.samples import Sample
from wristscope.wire import FrameSplitter, PayloadError, WireError, decode_records

log = logging.getLogger(__name__)

PORT = 9000
LATE_FRAMES = 8  # a frame this far behind is late; further back means the phone restarted
SERVICE_TYPE = "_motionstream._tcp.local."


def local_ip() -> str:
    """The address other devices on the network reach this computer at."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        try:
            probe.connect(("10.255.255.255", 1))  # UDP: picks a route without sending anything
            return probe.getsockname()[0]
        except OSError:
            return "127.0.0.1"


class WatchFeed(QtCore.QObject):
    """A Feed of samples streamed from the watch through the iPhone app."""

    def __init__(self, port: int = PORT, advertise: bool = True) -> None:
        super().__init__()
        self._pending: list[Sample] = []
        self._socket: QtNetwork.QTcpSocket | None = None
        self._splitter = FrameSplitter()
        self._expected_seq: int | None = None  # kept across connections so a reconnect shows up as a gap
        self.frames = 0
        self.dropped_frames = 0
        self.bad_frames = 0
        self.phone_restarts = 0
        self.last_error = ""

        self.ip = local_ip()
        self._server = QtNetwork.QTcpServer(self)
        self._server.newConnection.connect(self._accept)
        self._listen_error = ""
        if not self._server.listen(QtNetwork.QHostAddress.SpecialAddress.Any, port):
            self._listen_error = self._server.errorString()
        self.port = self._server.serverPort() or port

        self._zeroconf = None
        self._service = None
        if advertise and not self._listen_error:
            self._advertise()

    # MARK: Feed

    def poll(self) -> list[Sample]:
        samples, self._pending = self._pending, []
        return samples

    def status(self) -> str:
        if self._listen_error:
            return f"Can't listen on port {self.port}: {self._listen_error}"
        if self._socket is None:
            text = f"Waiting for iPhone on {self.ip}:{self.port}"
        else:
            text = f"Streaming from {self._socket.peerAddress().toString().removeprefix('::ffff:')}"
        if self.dropped_frames:
            text += f" · {self.dropped_frames} frames dropped"
        if self.last_error:
            text += f" · {self.last_error}"
        return text

    def close(self) -> None:
        if self._socket is not None:
            self._socket.abort()
            self._socket = None
        self._server.close()
        if self._zeroconf is not None:
            try:
                self._zeroconf.unregister_all_services()
                self._zeroconf.close()
            except Exception:
                log.exception("Bonjour shutdown failed")
            self._zeroconf = None

    # MARK: Connection

    def _accept(self) -> None:
        while self._server.hasPendingConnections():
            new = self._server.nextPendingConnection()
            if self._socket is not None:
                self._drop(self._socket)  # one phone at a time: the newest wins
            self._socket = new
            self._splitter = FrameSplitter()
            self.last_error = ""
            new.readyRead.connect(lambda sock=new: self._read(sock))
            new.disconnected.connect(lambda sock=new: self._lost(sock))
            if new.bytesAvailable():
                self._read(new)

    def _drop(self, sock: QtNetwork.QTcpSocket) -> None:
        sock.readyRead.disconnect()
        sock.disconnected.disconnect()
        sock.abort()
        sock.deleteLater()

    def _lost(self, sock: QtNetwork.QTcpSocket) -> None:
        if sock is self._socket:
            self._socket = None
        sock.deleteLater()

    def _read(self, sock: QtNetwork.QTcpSocket) -> None:
        if sock is not self._socket:
            return
        try:
            frames = self._splitter.feed(sock.readAll().data())
        except WireError as error:
            self.last_error = f"closed bad stream ({error})"
            log.warning("%s", self.last_error)
            sock.abort()  # the phone reconnects and starts clean
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

    # MARK: Bonjour

    def _advertise(self) -> None:
        """Announce _motionstream._tcp so the phone's "Find automatically" can see us."""
        try:
            from zeroconf import ServiceInfo, Zeroconf

            host = socket.gethostname().split(".")[0]
            info = ServiceInfo(
                SERVICE_TYPE,
                f"Wristscope on {host}.{SERVICE_TYPE}",
                addresses=[socket.inet_aton(self.ip)],
                port=self.port,
                server=f"{host}.local.",
            )
            self._zeroconf = Zeroconf()
            self._zeroconf.register_service(info)
        except Exception as error:
            self.last_error = f"Bonjour unavailable ({error})"
            log.exception("Bonjour advertising failed")
            self._zeroconf = None
