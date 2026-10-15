import math

import numpy as np
import pytest

from wristscope.core import quaternion as quat
from wristscope.core.channels import Source
from wristscope.core.samples import Sample
from wristscope.feeds.simulator import MOTIONS, Simulator, spin


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now


def vector(sample: Sample, prefix: str, axes: str = "xyz") -> np.ndarray:
    return np.array([sample.values[f"{prefix}.{axis}"] for axis in axes])


def test_poll_returns_samples_as_time_passes():
    clock = FakeClock()
    simulator = Simulator(rate=100.0, clock=clock)
    clock.now = 1.0
    samples = simulator.poll()
    for source in Source:
        assert sum(sample.source is source for sample in samples) == 100
    assert simulator.poll() == []


def test_sources_keep_their_own_timestamps():
    clock = FakeClock()
    simulator = Simulator(clock=clock)
    clock.now = 0.5
    timestamps = [sample.timestamp for sample in simulator.poll()]
    assert len(set(timestamps)) == len(timestamps)
    assert timestamps == sorted(timestamps)


def test_spin_reads_steady_rotation_about_vertical():
    simulator = Simulator(motion=spin)
    motion = simulator.sample(Source.DEVICE_MOTION, 2.0)
    gyro = simulator.sample(Source.GYRO, 2.0)
    assert vector(motion, "motion.rotation_rate") == pytest.approx([0, 0, math.pi / 2], abs=0.01)
    assert vector(gyro, "gyro") == pytest.approx([0, 0, math.pi / 2], abs=0.05)  # includes bias
    assert vector(motion, "motion.gravity") == pytest.approx([0, 0, -1])


@pytest.mark.parametrize("name", MOTIONS)
def test_channels_agree_with_each_other(name):
    simulator = Simulator(motion=MOTIONS[name])
    for t in np.linspace(0, 5, 11):
        motion = simulator.sample(Source.DEVICE_MOTION, t)
        accel = simulator.sample(Source.ACCELEROMETER, t)
        attitude = vector(motion, "motion.quaternion", "wxyz")
        gravity = vector(motion, "motion.gravity")

        assert np.linalg.norm(attitude) == pytest.approx(1)
        # Gravity, turned back into the reference frame, points straight down.
        assert quat.rotate(attitude, gravity) == pytest.approx([0, 0, -1])
        # The raw accelerometer reads gravity plus user acceleration.
        assert vector(accel, "accel") == pytest.approx(gravity + vector(motion, "motion.user_accel"), abs=0.03)


def test_drift_turns_only_the_reported_attitude():
    still = Simulator(motion=MOTIONS["rest"])
    drifting = Simulator(motion=MOTIONS["rest"], yaw=0.5, drift=0.1)
    plain, turned = (simulator.sample(Source.DEVICE_MOTION, 10.0) for simulator in (still, drifting))

    reference = quat.from_axis_angle([0, 0, 1], 0.5 + 0.1 * 10.0)
    expected = quat.multiply(reference, vector(plain, "motion.quaternion", "wxyz"))
    assert vector(turned, "motion.quaternion", "wxyz") == pytest.approx(expected)
    # Same seed, same noise: everything the sensors measure is unchanged.
    for channel_id, value in plain.values.items():
        if not channel_id.startswith("motion.quaternion"):
            assert turned.values[channel_id] == value
