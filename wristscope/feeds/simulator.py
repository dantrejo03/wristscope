"""A simulated watch that produces the samples the real one would send.

A motion is a function of time giving the watch's attitude and its position in
metres. The simulator differentiates it for rotation rate and acceleration, so
every channel agrees with every other, then adds sensor noise and runs each
source on its own clock the way the watch's separate handlers do.
"""

import time
from collections.abc import Callable

import numpy as np

from wristscope.core import quaternion as quat
from wristscope.core.channels import Source
from wristscope.core.samples import Sample

Motion = Callable[[float], tuple[np.ndarray, np.ndarray]]

STANDARD_GRAVITY = 9.80665  # m/s² per g
UPTIME = 1000.0  # CoreMotion timestamps count from boot, so the first sample isn't at 0


def rest(t: float) -> tuple[np.ndarray, np.ndarray]:
    """Lying still, tilted a little: only sensor noise moves."""
    return quat.from_axis_angle([1, 0, 0], 0.2), np.zeros(3)


def spin(t: float) -> tuple[np.ndarray, np.ndarray]:
    """Turning flat about the vertical at a steady 90°/s."""
    return quat.from_axis_angle([0, 0, 1], np.pi / 2 * t), np.zeros(3)


# Arm hanging at your side: display facing outward (+x), 12 o'clock toward the ground.
_HANGING = quat.multiply(quat.from_axis_angle([0, 1, 0], np.pi / 2), quat.from_axis_angle([0, 0, 1], -np.pi / 2))


def swing(t: float) -> tuple[np.ndarray, np.ndarray]:
    """An arm swinging from the shoulder like a pendulum."""
    angle = np.sin(2 * np.pi * t / 1.6)
    arm = 0.6
    attitude = quat.multiply(quat.from_axis_angle([1, 0, 0], angle), _HANGING)
    return attitude, arm * np.array([0.0, np.sin(angle), -np.cos(angle)])


def wander(t: float) -> tuple[np.ndarray, np.ndarray]:
    """Slow tumbling about all three axes with a little wrist movement."""
    yaw = quat.from_axis_angle([0, 0, 1], 0.3 * t + 0.8 * np.sin(0.31 * t))
    pitch = quat.from_axis_angle([0, 1, 0], 0.6 * np.sin(0.53 * t + 1))
    roll = quat.from_axis_angle([1, 0, 0], 0.7 * np.sin(0.71 * t + 2))
    position = 0.05 * np.array([np.sin(1.3 * t), np.sin(1.7 * t + 0.5), np.sin(2.1 * t + 1)])
    return quat.multiply(yaw, quat.multiply(pitch, roll)), position


MOTIONS: dict[str, Motion] = {"rest": rest, "spin": spin, "swing": swing, "wander": wander}


class Simulator:
    """A Feed that produces samples in real time, as if a watch were streaming."""

    def __init__(
        self,
        motion: Motion = wander,
        rate: float = 100.0,
        seed: int = 0,
        clock: Callable[[], float] = time.monotonic,
        yaw: float = 0.0,
        drift: float = 0.0,
    ) -> None:
        """`yaw` (radians) and `drift` (radians per second) turn the reported attitude about
        the vertical, as CoreMotion's arbitrary reference frame does: its "forward" is
        wherever it happened to start, and it slowly wanders. Nothing else is affected."""
        self.motion = motion
        self.yaw = yaw
        self.drift = drift
        self._period = 1 / rate
        self._rng = np.random.default_rng(seed)
        self._clock = clock
        self._start = clock()
        # Each handler starts at a different moment, so their timestamps never line up.
        self._next = {source: self._rng.uniform(0, self._period) for source in Source}
        self._gyro_bias = self._rng.normal(0, 0.01, 3)

    def poll(self) -> list[Sample]:
        now = self._clock() - self._start
        samples = []
        for source in Source:
            while self._next[source] <= now:
                samples.append(self.sample(source, self._next[source]))
                self._next[source] += self._period
        samples.sort(key=lambda sample: sample.timestamp)
        return samples

    def status(self) -> str:
        return "Simulated watch"

    def close(self) -> None:
        pass

    def sample(self, source: Source, t: float) -> Sample:
        """What `source` would report `t` seconds into the simulation."""
        attitude, rotation_rate, acceleration = self._kinematics(t)
        to_watch = quat.conjugate(attitude)
        gravity = quat.rotate(to_watch, [0.0, 0.0, -1.0])
        # CoreMotion reads -1 g on z lying face up, the opposite of a textbook
        # accelerometer, so user acceleration points against the actual acceleration.
        user_accel = -quat.rotate(to_watch, acceleration) / STANDARD_GRAVITY
        timestamp = UPTIME + t + self._rng.normal(0, 0.0002)

        if source is Source.ACCELEROMETER:
            values = _vector("accel", gravity + user_accel + self._noise(0.005))
        elif source is Source.GYRO:
            values = _vector("gyro", rotation_rate + self._gyro_bias + self._noise(0.005))
        else:
            values = {
                **_vector("motion.quaternion", self._reported(attitude, t), axes="wxyz"),
                **_vector("motion.user_accel", user_accel + self._noise(0.002)),
                **_vector("motion.rotation_rate", rotation_rate + self._noise(0.001)),
                **_vector("motion.gravity", gravity),
            }
        return Sample(source, timestamp, values)

    def _reported(self, attitude: np.ndarray, t: float) -> np.ndarray:
        """The attitude against the drifting reference frame."""
        return quat.multiply(quat.from_axis_angle([0.0, 0.0, 1.0], self.yaw + self.drift * t), attitude)

    def _kinematics(self, t: float, h: float = 1e-3) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """Attitude, rotation rate in the watch's frame (rad/s), and acceleration (m/s²) at t."""
        attitude, position = self.motion(t)
        attitude_before, position_before = self.motion(t - h)
        attitude_after, position_after = self.motion(t + h)
        # A quaternion changes as q̇ = ½ q ⊗ (0, ω) for rotation rate ω in the watch's frame.
        derivative = (attitude_after - attitude_before) / (2 * h)
        rotation_rate = 2 * quat.multiply(quat.conjugate(attitude), derivative)[1:]
        acceleration = (position_after - 2 * position + position_before) / h**2
        return attitude, rotation_rate, acceleration

    def _noise(self, sigma: float) -> np.ndarray:
        return self._rng.normal(0, sigma, 3)


def _vector(prefix: str, components, axes: str = "xyz") -> dict[str, float]:
    return {f"{prefix}.{axis}": float(value) for axis, value in zip(axes, components)}

