import math

import numpy as np
import pytest

from wristscope.core import quaternion as quat


def test_rotate_quarter_turn_about_z():
    q = quat.from_axis_angle([0, 0, 1], math.pi / 2)
    assert quat.rotate(q, [1, 0, 0]) == pytest.approx([0, 1, 0])


def test_multiply_applies_right_rotation_first():
    about_z = quat.from_axis_angle([0, 0, 1], math.pi / 2)
    about_x = quat.from_axis_angle([1, 0, 0], math.pi / 2)
    v = np.array([0.3, -1.2, 0.7])
    assert quat.rotate(quat.multiply(about_z, about_x), v) == pytest.approx(quat.rotate(about_z, quat.rotate(about_x, v)))


def test_conjugate_undoes_rotation():
    q = quat.from_axis_angle([1, 2, 3], 0.9)
    v = np.array([0.3, -1.2, 0.7])
    assert quat.rotate(quat.conjugate(q), quat.rotate(q, v)) == pytest.approx(v)
