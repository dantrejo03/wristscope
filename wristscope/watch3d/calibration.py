"""Turning the on-screen watch to face the same way as the real one.

CoreMotion measures tilt against gravity, so tilt is already right. Which way is
"forward" (yaw) is arbitrary: CoreMotion picks it when it starts and it slowly
drifts. Calibration fixes only the yaw, from a pose where the face's 12 o'clock
points at the computer screen, which the scope shows as +y.
"""

import math

import numpy as np

from wristscope.core import quaternion as quat
from wristscope.watch3d.watch_settings import WatchSettings

# 12 o'clock must be within 60° of level: below that its compass direction is unreliable.
MIN_LEVEL = math.cos(math.radians(60))


class CalibrationError(ValueError):
    pass


def yaw_offset(attitude: np.ndarray, settings: WatchSettings) -> np.ndarray:
    """The turn about the vertical that points the face's 12 o'clock along +y.

    Show `quaternion.multiply(offset, attitude)` instead of `attitude`.
    Raises CalibrationError if 12 o'clock is too far from level to have a direction.
    """
    twelve = quat.rotate(attitude, settings.twelve_o_clock)
    if math.hypot(twelve[0], twelve[1]) < MIN_LEVEL:
        raise CalibrationError("hold 12 o'clock level, pointing at the screen")
    yaw = math.atan2(twelve[1], twelve[0])
    return quat.from_axis_angle((0.0, 0.0, 1.0), math.pi / 2 - yaw)
