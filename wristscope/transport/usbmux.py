"""Messages for usbmuxd, the macOS service that carries connections to iPhones over USB. No network code, no Qt.

A client opens the Unix socket SOCKET_PATH and sends one request. Requests and replies are
a little-endian header followed by an XML property list (the format Python's plistlib reads):

    UInt32 total length | UInt32 version (1) | UInt32 type (8: plist) | UInt32 tag | plist

After a Connect request succeeds, the same socket stops carrying usbmuxd messages and becomes
a plain byte stream to that port on the phone, as if it were a TCP connection.
"""

import plistlib
import socket
import struct

SOCKET_PATH = "/var/run/usbmuxd"

RESULT_OK = 0
RESULT_NO_DEVICE = 2
RESULT_REFUSED = 3  # nothing on the phone is listening on that port

_HEADER = struct.Struct("<IIII")  # total length, version, message type, tag
_VERSION = 1
_PLIST = 8
_MAX_REPLY_BYTES = 1_000_000  # a device list is a few KB; anything bigger means the stream is garbage


class UsbmuxError(Exception):
    """usbmuxd sent something that isn't a reply. The socket should be dropped."""


def list_devices(tag: int = 1) -> bytes:
    """Asks which phones usbmuxd can reach. The reply is read by `usb_devices`."""
    return _request("ListDevices", tag)


def connect(device_id: int, port: int, tag: int = 1) -> bytes:
    """Asks usbmuxd to open `port` on the device. The reply is read by `result_code`."""
    # usbmuxd wants the port's two bytes swapped into network order, then read back as a number.
    return _request("Connect", tag, DeviceID=device_id, PortNumber=socket.htons(port))


def take_reply(buffer: bytearray) -> dict | None:
    """Remove the first complete reply from `buffer` and return it, or None if it isn't all there yet.

    Raises UsbmuxError on bytes that can't be a reply.
    """
    if len(buffer) < _HEADER.size:
        return None
    length, version, message_type, _tag = _HEADER.unpack_from(buffer)
    if version != _VERSION or message_type != _PLIST or not _HEADER.size <= length <= _MAX_REPLY_BYTES:
        raise UsbmuxError(f"unexpected reply header (version {version}, type {message_type}, length {length})")
    if len(buffer) < length:
        return None
    body = bytes(buffer[_HEADER.size : length])
    del buffer[:length]
    try:
        reply = plistlib.loads(body)
    except Exception as error:  # plistlib raises several types for bad input
        raise UsbmuxError(f"reply is not a property list ({error})") from error
    if not isinstance(reply, dict):
        raise UsbmuxError("reply is not a dictionary")
    return reply


def usb_devices(reply: dict) -> list[int]:
    """The device IDs in a ListDevices reply that are plugged in by cable.

    usbmuxd also lists phones it reaches over Wi-Fi, which would defeat the point.
    """
    return [
        device["DeviceID"]
        for device in reply.get("DeviceList", [])
        if device.get("Properties", {}).get("ConnectionType") == "USB"
    ]


def result_code(reply: dict) -> int | None:
    """The outcome of a Connect request (RESULT_OK and so on), or None if the reply isn't a result."""
    if reply.get("MessageType") != "Result":
        return None
    return reply.get("Number")


def _request(message_type: str, tag: int, **fields) -> bytes:
    body = plistlib.dumps({
        "MessageType": message_type,
        "ClientVersionString": "wristscope",
        "ProgName": "wristscope",
        "kLibUSBMuxVersion": 3,
        **fields,
    })
    return _HEADER.pack(_HEADER.size + len(body), _VERSION, _PLIST, tag) + body
