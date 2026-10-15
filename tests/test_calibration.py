import math

import numpy as np
import pytest

from wristscope.core import quaternion as quat
from wristscope.watch3d.calibration import CalibrationError, yaw_offset
from wristscope.watch3d.watch_settings import Crown, WatchSettings

UP = [0.0, 0.0, 1.0]
X = [1.0, 0.0, 0.0]


def random_attitudes(count: int, seed: int = 0) -> list[np.ndarray]:
    rng = np.random.default_rng(seed)
    attitudes = rng.normal(size=(count, 4))
    return list(attitudes / np.linalg.norm(attitudes, axis=1, keepdims=True))


def test_points_twelve_o_clock_into_the_screen():
    # Facing 40° to one side, with 12 o'clock tipped up 20°.
    attitude = quat.multiply(quat.from_axis_angle(UP, math.radians(40)), quat.from_axis_angle(X, math.radians(20)))
    offset = yaw_offset(attitude, WatchSettings())
    twelve = quat.rotate(quat.multiply(offset, attitude), [0, 1, 0])
    assert twelve[0] == pytest.approx(0, abs=1e-12)
    assert twelve[1] > 0
    assert twelve[2] == pytest.approx(math.sin(math.radians(20)))


def test_only_turns_about_the_vertical():
    offset = yaw_offset(quat.from_axis_angle([1, 2, 3], 1.0), WatchSettings())
    assert offset[1:3] == pytest.approx([0, 0])


def test_keeps_tilt():
    vectors = np.random.default_rng(1).normal(size=(5, 3))
    calibrated = 0
    for attitude in random_attitudes(50):
        try:
            offset = yaw_offset(attitude, WatchSettings())
        except CalibrationError:
            continue
        calibrated += 1
        shown = quat.multiply(offset, attitude)
        for v in vectors:
            assert quat.rotate(shown, v)[2] == pytest.approx(quat.rotate(attitude, v)[2])
    assert calibrated > 25


@pytest.mark.parametrize("degrees_from_level, refused", [(90, True), (-90, True), (65, True), (55, False)])
def test_refuses_when_twelve_o_clock_is_far_from_level(degrees_from_level, refused):
    attitude = quat.from_axis_angle(X, math.radians(degrees_from_level))
    if refused:
        with pytest.raises(CalibrationError):
            yaw_offset(attitude, WatchSettings())
    else:
        yaw_offset(attitude, WatchSettings())


def test_crown_left_uses_minus_y():
    attitude = quat.from_axis_angle(UP, 1.0)
    shown = quat.multiply(yaw_offset(attitude, WatchSettings(crown=Crown.LEFT)), attitude)
    assert quat.rotate(shown, [0, -1, 0]) == pytest.approx([0, 1, 0])  # the face's 12 o'clock
