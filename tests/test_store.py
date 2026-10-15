import numpy as np
import pytest

from wristscope.core.channels import Source
from wristscope.core.samples import Sample
from wristscope.core.store import MotionStore, SourceBuffer


def gyro(t: float, x: float) -> Sample:
    return Sample(Source.GYRO, t, {"gyro.x": x})


def test_missing_channels_are_nan():
    buffer = SourceBuffer(Source.GYRO, capacity=4)
    buffer.append(gyro(0.0, 1.0))
    assert buffer.values("gyro.x").tolist() == [1.0]
    assert np.isnan(buffer.values("gyro.y")).all()


def test_keeps_newest_samples_in_order_after_wrapping():
    buffer = SourceBuffer(Source.GYRO, capacity=3)
    for t in range(5):
        buffer.append(gyro(float(t), t * 10.0))
    assert len(buffer) == 3
    assert buffer.timestamps().tolist() == [2.0, 3.0, 4.0]
    assert buffer.values("gyro.x").tolist() == [20.0, 30.0, 40.0]


def test_latest_follows_newest_sample_after_wrapping():
    buffer = SourceBuffer(Source.GYRO, capacity=3)
    assert np.isnan(buffer.latest("gyro.x"))
    assert np.isnan(buffer.latest_timestamp())
    for t in range(5):
        buffer.append(gyro(float(t), t * 10.0))
    assert buffer.latest("gyro.x") == 40.0
    assert buffer.latest_timestamp() == 4.0


def test_rate_counts_recent_samples():
    buffer = SourceBuffer(Source.GYRO, capacity=1000)
    for i in range(500):
        buffer.append(gyro(i / 100, 0.0))
    assert buffer.rate() == pytest.approx(100.0)


def test_rejects_sample_from_another_source():
    buffer = SourceBuffer(Source.GYRO, capacity=3)
    with pytest.raises(ValueError):
        buffer.append(Sample(Source.ACCELEROMETER, 0.0, {"accel.x": 1.0}))


def test_store_keeps_each_source_on_its_own_timeline():
    store = MotionStore(capacity=8)
    store.add(Sample(Source.ACCELEROMETER, 0.00, {"accel.x": 0.5}))
    store.add(Sample(Source.DEVICE_MOTION, 0.01, {"motion.heading": 90.0}))
    store.add(Sample(Source.ACCELEROMETER, 0.02, {"accel.x": 0.6}))

    t, v = store.series("accel.x")
    assert t.tolist() == [0.0, 0.02]
    assert v.tolist() == [0.5, 0.6]

    t, v = store.series("motion.heading")
    assert t.tolist() == [0.01]
    assert v.tolist() == [90.0]

    assert store.latest_timestamp() == 0.02
    assert store.latest("motion.heading") == 90.0


def feed_gyro(store: MotionStore, times) -> None:
    for t in times:
        store.add(gyro(t, 1.0))


def test_lost_samples_leave_a_blank_row():
    store = MotionStore()
    feed_gyro(store, [i * 0.01 for i in range(10)])
    feed_gyro(store, [0.5])  # 41 samples missing
    t, v = store.series("gyro.x")
    assert len(t) == 12 and store.gaps == 1
    assert np.isnan(v[-2]) and v[-1] == 1.0
    assert t[-2] == pytest.approx(0.10) and t[-1] == 0.5
    assert np.isnan(store.series("gyro.y")[1]).all()


def test_a_gap_does_not_change_the_usual_spacing():
    store = MotionStore()
    feed_gyro(store, [i * 0.01 for i in range(10)])
    feed_gyro(store, [0.5, 0.51, 0.52])
    feed_gyro(store, [1.0])  # a second gap is still a gap
    assert store.gaps == 2


def test_normal_jitter_is_not_a_gap():
    store = MotionStore()
    feed_gyro(store, [0.0, 0.01, 0.025, 0.03, 0.045, 0.05, 0.065, 0.07])
    assert store.gaps == 0 and len(store.buffer(Source.GYRO)) == 8


def test_no_gap_is_claimed_before_the_spacing_is_known():
    store = MotionStore()
    feed_gyro(store, [0.0, 0.01, 5.0])
    assert store.gaps == 0


def test_older_sample_is_dropped_and_counted():
    store = MotionStore()
    feed_gyro(store, [0.0, 0.01, 0.02, 0.015, 0.03])
    assert store.buffer(Source.GYRO).timestamps().tolist() == [0.0, 0.01, 0.02, 0.03]
    assert store.out_of_order == 1


def test_sources_are_ordered_independently():
    store = MotionStore()
    store.add(Sample(Source.ACCELEROMETER, 5.0, {"accel.x": 1.0}))
    store.add(gyro(4.9, 1.0))  # older than accel's newest, but gyro has none yet
    assert store.out_of_order == 0 and len(store.buffer(Source.GYRO)) == 1


def test_big_jump_backward_restarts_everything():
    store = MotionStore()
    store.add(Sample(Source.ACCELEROMETER, 100.0, {"accel.x": 1.0}))
    feed_gyro(store, [100.0, 100.01])
    feed_gyro(store, [3.0])
    assert store.restarts == 1
    assert len(store.buffer(Source.ACCELEROMETER)) == 0
    assert store.buffer(Source.GYRO).timestamps().tolist() == [3.0]
    assert store.out_of_order == 0


def test_restart_forgets_the_old_spacing():
    store = MotionStore()
    feed_gyro(store, [i * 0.01 for i in range(10)] + [0.5])
    feed_gyro(store, [-10.0, -9.0, -8.0, -7.0, -6.0])  # a slower watch, no gaps
    assert store.gaps == 1 and store.restarts == 1
