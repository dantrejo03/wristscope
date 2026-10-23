"""Bytes to samples and back. No network code, no Qt.

Two layers arrive on the wire, with opposite byte orders:

    phone frame (big-endian)                     payload (little-endian)
    UInt32 length | UInt32 seq | Float64 time  | "WRSC" | version | UInt32 watch seq | record | record | ...

    record: tag | Float64 timestamp | Float64 value | Float64 value | ...

The phone adds the frame, the magic and the version. The watch seq and the records are the
watch's: the seq goes up by one for each message WatchConnectivity took, and each record holds
one measurement, such as gravity. Nothing gives a record's length: the tag says which
measurement it is, and RECORDS below says which channels its values fill.

One sensor event becomes several records with the same timestamp, written back to back and never
split across messages. Decoding joins them into one Sample again.

RECORDS must match `Motion.Sample.tag` in xcode/Shared/Motion/MotionTypes.swift and the layout in
SampleFormatter.swift there. MAGIC, VERSION and the payload header must match `ComputerFormatter`
in the phone app. tests/test_wire.py decodes a payload the Swift code wrote, to catch drift.
"""

import math
import struct
from dataclasses import dataclass

from wristscope.core.channels import FUNDAMENTAL_CHANNELS, Channel, Source
from wristscope.core.samples import Sample

MAGIC = b"WRSC"
VERSION = 2


def _group(prefix: str) -> tuple[Channel, ...]:
    """The channels whose ids are `prefix` plus an axis, in the order channels.py lists them."""
    return tuple(c for c in FUNDAMENTAL_CHANNELS if c.id.rpartition(".")[0] == prefix)


# tag -> the channels a record's values fill, in the order the watch writes them
RECORDS: dict[int, tuple[Channel, ...]] = {
    1: _group("accel"),  # Motion.Sample.rawAcceleration
    2: _group("motion.user_accel"),  # .userAcceleration
    3: _group("gyro"),  # .rawGyro
    4: _group("motion.rotation_rate"),  # .rotationRate
    5: _group("motion.quaternion"),  # .attitude, w x y z
    6: _group("motion.gravity"),  # .gravity
}
# The order the watch writes each sensor event's records in (MotionReadingConversion.swift)
_TAGS_OF = {Source.ACCELEROMETER: (1,), Source.GYRO: (3,), Source.DEVICE_MOTION: (5, 2, 4, 6)}
_RECORD_STRUCTS = {tag: struct.Struct(f"<{1 + len(channels)}d") for tag, channels in RECORDS.items()}

_PAYLOAD_HEADER = struct.Struct("<4sBI")  # magic, version, watch seq
PAYLOAD_HEADER_BYTES = _PAYLOAD_HEADER.size
_FRAME_HEADER = struct.Struct(">IId")  # length, seq, phone's Unix time
FRAME_HEADER_BYTES = _FRAME_HEADER.size
MAX_FRAME_BYTES = 1_000_000  # a real frame is a few KB; anything bigger means the stream is garbage


class WireError(Exception):
    """The bytes are not valid. The connection should be dropped."""


class PayloadError(WireError):
    """A frame's payload could not all be read. `samples` holds those read before the problem,
    and `watch_seq` the watch's sequence number if the header was readable.

    The frame boundary is still known, so the connection can carry on with the next frame.
    """

    def __init__(self, message: str, watch_seq: int | None = None, samples: list[Sample] | None = None) -> None:
        super().__init__(message)
        self.watch_seq = watch_seq
        self.samples = samples or []


@dataclass(frozen=True)
class Frame:
    seq: int
    phone_time: float
    payload: bytes


@dataclass(frozen=True)
class Payload:
    watch_seq: int
    samples: list[Sample]


class FrameSplitter:
    """Restores the phone's frame boundaries from whatever chunks TCP delivers."""

    def __init__(self) -> None:
        self._buffer = bytearray()

    def feed(self, chunk: bytes) -> list[Frame]:
        """Add received bytes; return every frame now complete. Raises WireError on an absurd length."""
        self._buffer += chunk
        frames: list[Frame] = []
        start = 0
        while len(self._buffer) - start >= FRAME_HEADER_BYTES:
            length, seq, phone_time = _FRAME_HEADER.unpack_from(self._buffer, start)
            if length > MAX_FRAME_BYTES:
                raise WireError(f"frame length {length} is not plausible")
            end = start + FRAME_HEADER_BYTES + length
            if len(self._buffer) < end:
                break
            frames.append(Frame(seq, phone_time, bytes(self._buffer[start + FRAME_HEADER_BYTES : end])))
            start = end
        del self._buffer[:start]
        return frames


def decode_payload(payload: bytes) -> Payload:
    """Decode a frame's payload. Raises PayloadError (carrying what was read so far)."""
    # The version comes before anything whose layout it could change, so it's checked first.
    if len(payload) < len(MAGIC) + 1 or payload[: len(MAGIC)] != MAGIC:
        raise PayloadError("watch payload does not start with WRSC")
    if payload[len(MAGIC)] != VERSION:
        raise PayloadError(f"phone sends format v{payload[len(MAGIC)]}, receiver reads v{VERSION}")
    if len(payload) < PAYLOAD_HEADER_BYTES:
        raise PayloadError("watch payload is too short for its sequence number")
    _, _, watch_seq = _PAYLOAD_HEADER.unpack_from(payload)

    samples: list[Sample] = []
    offset = PAYLOAD_HEADER_BYTES
    while offset < len(payload):
        tag = payload[offset]
        channels = RECORDS.get(tag)
        if channels is None:
            raise PayloadError(f"unknown record tag {tag}", watch_seq, samples)
        fields = _RECORD_STRUCTS[tag]
        offset += 1
        if len(payload) - offset < fields.size:
            raise PayloadError(f"truncated record (tag {tag})", watch_seq, samples)
        timestamp, *readings = fields.unpack_from(payload, offset)
        offset += fields.size
        _add(samples, channels[0].source, timestamp, {c.id: v for c, v in zip(channels, readings)})
    return Payload(watch_seq, samples)


def _add(samples: list[Sample], source: Source, timestamp: float, values: dict[str, float]) -> None:
    """Append a record's values, joining them to the sample before when both came from the same
    sensor event: the same source and the same timestamp."""
    if samples and samples[-1].source is source and samples[-1].timestamp == timestamp:
        samples[-1] = Sample(source, timestamp, {**samples[-1].values, **values})
    else:
        samples.append(Sample(source, timestamp, values))


def encode_payload(samples: list[Sample], watch_seq: int = 0) -> bytes:
    """The payload the phone sends: the header, then one record for each measurement a sample
    has values for. A channel missing from a record that has others is sent as NaN."""
    out = bytearray(_PAYLOAD_HEADER.pack(MAGIC, VERSION, watch_seq))
    for sample in samples:
        for tag in _TAGS_OF[sample.source]:
            channels = RECORDS[tag]
            if not any(c.id in sample.values for c in channels):
                continue
            readings = [sample.values.get(c.id, math.nan) for c in channels]
            out.append(tag)
            out += _RECORD_STRUCTS[tag].pack(sample.timestamp, *readings)
    return bytes(out)


def encode_frame(payload: bytes, seq: int, phone_time: float) -> bytes:
    """Wrap a payload the way the phone does."""
    return _FRAME_HEADER.pack(len(payload), seq, phone_time) + payload
