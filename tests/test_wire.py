import math
from pathlib import Path

import pytest

from wristscope.core.channels import CHANNELS, Source, channels_for
from wristscope.core.samples import Sample
from wristscope.transport.wire import (
    MAGIC,
    MAX_FRAME_BYTES,
    PAYLOAD_HEADER_BYTES,
    RECORDS,
    VERSION,
    FrameSplitter,
    Payload,
    PayloadError,
    WireError,
    decode_payload,
    encode_frame,
    encode_payload,
)

FIXTURES = Path(__file__).parent / "fixtures"


def make_sample(source: Source, timestamp: float = 12.5) -> Sample:
    return Sample(source, timestamp, {c.id: i + 0.25 for i, c in enumerate(channels_for(source))})


ALL_SAMPLES = [make_sample(Source.ACCELEROMETER, 1.0), make_sample(Source.GYRO, 2.0), make_sample(Source.DEVICE_MOTION, 3.0)]

# What tools/swift_fixtures/main.swift puts in tests/fixtures/live_payload.bin, with watch seq 41
SWIFT_SAMPLES = [
    Sample(Source.DEVICE_MOTION, 1000.25, {
        "motion.quaternion.w": 0.5, "motion.quaternion.x": -0.5, "motion.quaternion.y": 0.25, "motion.quaternion.z": -0.25,
        "motion.user_accel.x": 0.125, "motion.user_accel.y": -0.125, "motion.user_accel.z": 1.5,
        "motion.rotation_rate.x": 2.0, "motion.rotation_rate.y": -2.0, "motion.rotation_rate.z": 0.75,
        "motion.gravity.x": 0.0, "motion.gravity.y": -0.5, "motion.gravity.z": -1.0,
    }),
    Sample(Source.ACCELEROMETER, 1000.5, {"accel.x": 0.1, "accel.y": 0.2, "accel.z": -0.98}),
    Sample(Source.GYRO, 1000.75, {"gyro.x": -0.3, "gyro.y": 0.4, "gyro.z": 0.05}),
]


def test_every_channel_is_in_exactly_one_record():
    ids = [c.id for channels in RECORDS.values() for c in channels]
    assert sorted(ids) == sorted(CHANNELS)


def test_a_record_holds_one_source():
    for channels in RECORDS.values():
        assert len({c.source for c in channels}) == 1


def test_swift_tags_and_layout():
    # Locked to Motion.Sample.tag in xcode/Shared/Motion/MotionTypes.swift: each tag's channels,
    # in the order the Swift vector holds them.
    assert {tag: [c.id for c in channels] for tag, channels in RECORDS.items()} == {
        1: ["accel.x", "accel.y", "accel.z"],
        2: ["motion.user_accel.x", "motion.user_accel.y", "motion.user_accel.z"],
        3: ["gyro.x", "gyro.y", "gyro.z"],
        4: ["motion.rotation_rate.x", "motion.rotation_rate.y", "motion.rotation_rate.z"],
        5: ["motion.quaternion.w", "motion.quaternion.x", "motion.quaternion.y", "motion.quaternion.z"],
        6: ["motion.gravity.x", "motion.gravity.y", "motion.gravity.z"],
    }


def test_decodes_what_the_swift_code_writes():
    # The fixture was written by the real Swift formatters. Rerun tools/swift_fixtures/generate.sh
    # after changing the format on either side.
    assert decode_payload((FIXTURES / "live_payload.bin").read_bytes()) == Payload(41, SWIFT_SAMPLES)


def test_encodes_what_the_swift_code_writes():
    assert encode_payload(SWIFT_SAMPLES, 41) == (FIXTURES / "live_payload.bin").read_bytes()


def test_known_bytes_are_little_endian():
    one = bytes.fromhex("000000000000f03f")  # 1.0
    payload = MAGIC + bytes([VERSION]) + bytes.fromhex("07000000") + bytes([1]) + one * 4  # seq 7, tag 1
    expected = Sample(Source.ACCELEROMETER, 1.0, {"accel.x": 1.0, "accel.y": 1.0, "accel.z": 1.0})
    assert decode_payload(payload) == Payload(7, [expected])


@pytest.mark.parametrize("sample", ALL_SAMPLES)
def test_record_round_trip(sample):
    assert decode_payload(encode_payload([sample], 3)) == Payload(3, [sample])


def test_several_records_round_trip():
    assert decode_payload(encode_payload(ALL_SAMPLES * 2)).samples == ALL_SAMPLES * 2


def test_one_sensor_event_becomes_one_sample():
    # A device-motion event goes as four records with the same timestamp: attitude's 4 values
    # and three vectors of 3, each with the timestamp in front.
    payload = encode_payload([ALL_SAMPLES[2]])
    assert len(payload) == PAYLOAD_HEADER_BYTES + (1 + 5 * 8) + 3 * (1 + 4 * 8)
    [sample] = decode_payload(payload).samples
    assert len(sample.values) == len(channels_for(Source.DEVICE_MOTION))


def test_different_timestamps_stay_apart():
    first, second = make_sample(Source.GYRO, 1.0), make_sample(Source.GYRO, 1.01)
    assert decode_payload(encode_payload([first, second])).samples == [first, second]


def test_different_sources_stay_apart():
    accel, gyro = make_sample(Source.ACCELEROMETER, 1.0), make_sample(Source.GYRO, 1.0)
    assert decode_payload(encode_payload([accel, gyro])).samples == [accel, gyro]


def test_header_only_payload_has_no_samples():
    assert decode_payload(encode_payload([], 9)) == Payload(9, [])


def test_missing_magic():
    with pytest.raises(PayloadError):
        decode_payload(b"")
    with pytest.raises(PayloadError):
        decode_payload(b"NOPE" + bytes([VERSION]))


def test_other_version_is_named():
    with pytest.raises(PayloadError, match="v1"):
        decode_payload(MAGIC + bytes([1]))


def test_too_short_for_the_watch_seq():
    with pytest.raises(PayloadError) as info:
        decode_payload(MAGIC + bytes([VERSION, 0, 0]))
    assert info.value.watch_seq is None


def test_missing_channel_encodes_as_nan():
    [decoded] = decode_payload(encode_payload([Sample(Source.GYRO, 1.0, {"gyro.y": 2.0})])).samples
    assert decoded.values["gyro.y"] == 2.0
    assert math.isnan(decoded.values["gyro.x"])


def test_unknown_tag_keeps_earlier_samples():
    with pytest.raises(PayloadError) as info:
        decode_payload(encode_payload([ALL_SAMPLES[0]], 5) + bytes([99]) + bytes(32))
    assert info.value.samples == [ALL_SAMPLES[0]]
    assert info.value.watch_seq == 5


def test_truncated_record():
    gyro_record = encode_payload([ALL_SAMPLES[1]])[PAYLOAD_HEADER_BYTES:]
    with pytest.raises(PayloadError) as info:
        decode_payload(encode_payload([ALL_SAMPLES[0]]) + gyro_record[:-1])
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
    data = encode_frame(encode_payload(ALL_SAMPLES), 1, 1.0) + encode_frame(encode_payload(ALL_SAMPLES[:1]), 2, 2.0)
    for cut in range(len(data) + 1):
        splitter = FrameSplitter()
        frames = splitter.feed(data[:cut]) + splitter.feed(data[cut:])
        assert [f.seq for f in frames] == [1, 2], cut
        assert decode_payload(frames[0].payload).samples == ALL_SAMPLES


def test_one_byte_at_a_time():
    data = encode_frame(b"xyz", 1, 1.0) * 3
    splitter = FrameSplitter()
    frames = [f for byte in data for f in splitter.feed(bytes([byte]))]
    assert len(frames) == 3


def test_absurd_length_raises():
    with pytest.raises(WireError):
        FrameSplitter().feed((MAX_FRAME_BYTES + 1).to_bytes(4, "big") + bytes(12))
