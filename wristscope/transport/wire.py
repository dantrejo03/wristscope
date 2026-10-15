"""Bytes to samples and back. No network code, no Qt.

Two layers arrive on the wire, with opposite byte orders:

    phone frame (big-endian)                     watch payload (little-endian)
    UInt32 length | UInt32 seq | Float64 time  | "WRSC" | version | tag | doubles... | tag | doubles... | ...

The watch payload starts with the magic and format version, then records with no
lengths: the tag says which source a record is from, and RECORDS below says how
many doubles follow. That table and VERSION must match `Motion.Source`,
`fieldCount` and `Format.version` in MotionDataTypes.swift.
"""

import struct
from dataclasses import dataclass

from wristscope.core.channels import Source, channels_for
from wristscope.core.samples import Sample

MAGIC = b"WRSC"
VERSION = 1

# tag -> (source, number of doubles in the payload, including the timestamp)
RECORDS: dict[int, tuple[Source, int]] = {
    1: (Source.ACCELEROMETER, 4),
    2: (Source.GYRO, 4),
    3: (Source.DEVICE_MOTION, 18),
}
_TAG_OF = {source: tag for tag, (source, _) in RECORDS.items()}
_PAYLOAD_STRUCTS = {tag: struct.Struct(f"<{count}d") for tag, (_, count) in RECORDS.items()}

_FRAME_HEADER = struct.Struct(">IId")  # length, seq, phone's Unix time
FRAME_HEADER_BYTES = _FRAME_HEADER.size
MAX_FRAME_BYTES = 1_000_000  # a real frame is a few KB; anything bigger means the stream is garbage


class WireError(Exception):
    """The bytes are not valid. The connection should be dropped."""


class PayloadError(WireError):
    """A frame's payload could not all be read. `samples` holds those read before the problem.

    The frame boundary is still known, so the connection can carry on with the next frame.
    """

    def __init__(self, message: str, samples: list[Sample] | None = None) -> None:
        super().__init__(message)
        self.samples = samples or []


@dataclass(frozen=True)
class Frame:
    seq: int
    phone_time: float
    payload: bytes


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


def decode_records(payload: bytes) -> list[Sample]:
    """Decode a frame's watch payload. Raises PayloadError (carrying the samples read so far)."""
    header = len(MAGIC) + 1
    if len(payload) < header or payload[: len(MAGIC)] != MAGIC:
        raise PayloadError("watch payload does not start with WRSC")
    if payload[len(MAGIC)] != VERSION:
        raise PayloadError(f"watch sends format v{payload[len(MAGIC)]}, receiver reads v{VERSION}")
    samples: list[Sample] = []
    offset = header
    while offset < len(payload):
        tag = payload[offset]
        record = RECORDS.get(tag)
        if record is None:
            raise PayloadError(f"unknown source tag {tag}", samples)
        source, _ = record
        fields = _PAYLOAD_STRUCTS[tag]
        offset += 1
        if len(payload) - offset < fields.size:
            raise PayloadError(f"truncated {source.name} record", samples)
        timestamp, *readings = fields.unpack_from(payload, offset)
        offset += fields.size
        channels = channels_for(source)
        samples.append(Sample(source, timestamp, {c.id: v for c, v in zip(channels, readings)}))
    return samples


def encode_records(samples: list[Sample]) -> bytes:
    """The watch's payload format. A channel missing from a sample is sent as NaN."""
    out = bytearray(MAGIC + bytes([VERSION]))
    for sample in samples:
        tag = _TAG_OF[sample.source]
        readings = [sample.values.get(c.id, float("nan")) for c in channels_for(sample.source)]
        out.append(tag)
        out += _PAYLOAD_STRUCTS[tag].pack(sample.timestamp, *readings)
    return bytes(out)


def encode_frame(payload: bytes, seq: int, phone_time: float) -> bytes:
    """Wrap a payload the way the phone does."""
    return _FRAME_HEADER.pack(len(payload), seq, phone_time) + payload
