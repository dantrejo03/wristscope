"""Quaternion helpers. A quaternion is a numpy array ordered [w, x, y, z].

An attitude quaternion rotates vectors from the watch's own frame into the
reference frame, whose z axis points up.
"""

import numpy as np


def from_axis_angle(axis, angle: float) -> np.ndarray:
    axis = np.asarray(axis, dtype=float)
    axis = axis / np.linalg.norm(axis)
    return np.concatenate(([np.cos(angle / 2)], np.sin(angle / 2) * axis))


def multiply(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """The rotation b followed by the rotation a."""
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return np.array([
        aw * bw - ax * bx - ay * by - az * bz,
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
    ])


def conjugate(q: np.ndarray) -> np.ndarray:
    """The opposite rotation (for a unit quaternion)."""
    return q * np.array([1.0, -1.0, -1.0, -1.0])


def rotate(q: np.ndarray, v) -> np.ndarray:
    """The vector v rotated by q."""
    v = np.asarray(v, dtype=float)
    u = q[1:]
    t = 2 * np.cross(u, v)
    return v + q[0] * t + np.cross(u, t)
