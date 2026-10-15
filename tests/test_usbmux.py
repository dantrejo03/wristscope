import socket
import struct

import pytest

from wristscope.transport import usbmux


def test_connect_request_round_trips_with_port_in_network_order():
    buffer = bytearray(usbmux.connect(device_id=7, port=9000, tag=3))
    length, version, message_type, tag = struct.unpack_from("<IIII", buffer)
    assert (length, version, message_type, tag) == (len(buffer), 1, 8, 3)
    request = usbmux.take_reply(buffer)
    assert request["MessageType"] == "Connect"
    assert request["DeviceID"] == 7
    assert request["PortNumber"] == socket.htons(9000) == 0x2823
    assert buffer == bytearray()


def test_take_reply_waits_for_the_whole_reply_and_leaves_what_follows():
    whole = usbmux.list_devices()
    buffer = bytearray(whole[:20])
    assert usbmux.take_reply(buffer) is None
    buffer += whole[20:] + b"phone bytes"
    assert usbmux.take_reply(buffer)["MessageType"] == "ListDevices"
    assert buffer == bytearray(b"phone bytes")


def test_take_reply_rejects_a_bad_header():
    with pytest.raises(usbmux.UsbmuxError):
        usbmux.take_reply(bytearray(struct.pack("<IIII", 16, 0, 8, 1)))  # binary protocol, not plist


def test_take_reply_rejects_a_body_that_is_not_a_plist():
    body = b"not a plist"
    with pytest.raises(usbmux.UsbmuxError):
        usbmux.take_reply(bytearray(struct.pack("<IIII", 16 + len(body), 1, 8, 1) + body))


def test_usb_devices_skips_phones_on_wifi():
    reply = {"DeviceList": [
        {"DeviceID": 1, "Properties": {"ConnectionType": "Network"}},
        {"DeviceID": 2, "Properties": {"ConnectionType": "USB"}},
    ]}
    assert usbmux.usb_devices(reply) == [2]
    assert usbmux.usb_devices({"DeviceList": []}) == []


def test_result_code():
    assert usbmux.result_code({"MessageType": "Result", "Number": 3}) == usbmux.RESULT_REFUSED
    assert usbmux.result_code({"MessageType": "Attached"}) is None
