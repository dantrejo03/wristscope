import math

import pytest

from wristscope.core.channels import Source, channels_for
from wristscope.core.samples import Sample
from wristscope.sources.wire import (
    MAGIC,
    MAX_FRAME_BYTES,
    VERSION,
    RECORDS,
    FrameSplitter,
    PayloadError,
    WireError,
    decode_records,
    encode_frame,
    encode_records,
)


def make_sample(source: Source, timestamp: float = 12.5) -> Sample:
    return Sample(source, timestamp, {c.id: i + 0.25 for i, c in enumerate(channels_for(source))})


ALL_SAMPLES = [make_sample(Source.ACCELEROMETER, 1.0), make_sample(Source.GYRO, 2.0), make_sample(Source.DEVICE_MOTION, 3.0)]


def test_record_table_matches_channels():
    # Every source needs a tag, and its size must be timestamp + one double per channel.
    assert {source for source, _ in RECORDS.values()} == set(Source)
    for source, count in RECORDS.values():
        assert count == 1 + len(channels_for(source))


def test_swift_tags_and_sizes():
    # Locked to Motion.Source / fieldCount in MotionDataTypes.swift.
    assert {tag: (source, count) for tag, (source, count) in RECORDS.items()} == {
        1: (Source.ACCELEROMETER, 4),
        2: (Source.GYRO, 4),
        3: (Source.DEVICE_MOTION, 18),
    }


def test_device_motion_field_order():
    # Swift writes: timestamp, quaternion wxyz, rotation xyz, user accel xyz, gravity xyz, magnetic xyz, heading.
    ids = [c.id for c in channels_for(Source.DEVICE_MOTION)]
    assert ids[0] == "motion.quaternion.w" and ids[3] == "motion.quaternion.z"
    assert ids[4:7] == ["motion.rotation_rate.x", "motion.rotation_rate.y", "motion.rotation_rate.z"]
    assert ids[7:10] == [f"motion.user_accel.{a}" for a in "xyz"]
    assert ids[10:13] == [f"motion.gravity.{a}" for a in "xyz"]
    assert ids[13:16] == [f"motion.magnetic_field.{a}" for a in "xyz"]
    assert ids[16] == "motion.heading"


def test_known_bytes_are_little_endian():
    payload = MAGIC + bytes([VERSION, 1]) + bytes.fromhex("000000000000f03f") * 4  # tag 1, four 1.0 doubles
    [sample] = decode_records(payload)
    assert sample == Sample(Source.ACCELEROMETER, 1.0, {"accel.x": 1.0, "accel.y": 1.0, "accel.z": 1.0})


@pytest.mark.parametrize("sample", ALL_SAMPLES)
def test_record_round_trip(sample):
    assert decode_records(encode_records([sample])) == [sample]


def test_several_records_round_trip():
    assert decode_records(encode_records(ALL_SAMPLES * 2)) == ALL_SAMPLES * 2


def test_header_only_payload_has_no_samples():
    assert decode_records(MAGIC + bytes([VERSION])) == []


def test_missing_magic():
    with pytest.raises(PayloadError):
        decode_records(b"")
    with pytest.raises(PayloadError):
        decode_records(b"NOPE" + bytes([VERSION]))


def test_other_version_is_named():
    with pytest.raises(PayloadError, match="v2"):
        decode_records(MAGIC + bytes([2]))


def test_missing_channel_encodes_as_nan():
    [decoded] = decode_records(encode_records([Sample(Source.GYRO, 1.0, {"gyro.y": 2.0})]))
    assert decoded.values["gyro.y"] == 2.0
    assert math.isnan(decoded.values["gyro.x"])


def test_unknown_tag_keeps_earlier_samples():
    with pytest.raises(PayloadError) as info:
        decode_records(encode_records([ALL_SAMPLES[0]]) + bytes([99]) + bytes(32))
    assert info.value.samples == [ALL_SAMPLES[0]]


def test_truncated_record():
    payload = encode_records([ALL_SAMPLES[2]])
    with pytest.raises(PayloadError) as info:
        decode_records(encode_records([ALL_SAMPLES[0]]) + payload[len(MAGIC) + 1 : -1])
    assert info.value.samples == [ALL_SAMPLES[0]]


def test_frame_round_trip():
    [frame] = FrameSplitter().feed(encode_frame(b"abc", seq=7, phone_time=1234.5))
    assert (frame.seq, frame.phone_time, frame.payload) == (7, 1234.5, b"abc")


def test_zero_length_frame():
    [frame] = FrameSplitter().feed(encode_frame(b"", 0, 0.0))
    assert frame.payload == b""


def test_several_frames_in_one_chunk():
    data = b"".join(encode_frame(bytes([i]) * i, i, float(i)) for i in range(1, 5))
    frames = FrameSplitter().feed(data)
    assert [(f.seq, f.payload) for f in frames] == [(i, bytes([i]) * i) for i in range(1, 5)]


def test_frames_split_at_every_byte():
    data = encode_frame(encode_records(ALL_SAMPLES), 1, 1.0) + encode_frame(encode_records(ALL_SAMPLES[:1]), 2, 2.0)
    for cut in range(len(data) + 1):
        splitter = FrameSplitter()
        frames = splitter.feed(data[:cut]) + splitter.feed(data[cut:])
        assert [f.seq for f in frames] == [1, 2], cut
        assert decode_records(frames[0].payload) == ALL_SAMPLES


def test_one_byte_at_a_time():
    data = encode_frame(b"xyz", 1, 1.0) * 3
    splitter = FrameSplitter()
    frames = [f for byte in data for f in splitter.feed(bytes([byte]))]
    assert len(frames) == 3


def test_absurd_length_raises():
    with pytest.raises(WireError):
        FrameSplitter().feed((MAX_FRAME_BYTES + 1).to_bytes(4, "big") + bytes(12))
