import numpy as np
import pytest

from wristscope.watch3d.watch_model import Mesh, axis_arrows, load_watch, watch_face
from wristscope.watch3d.watch_settings import Crown, WatchSettings, Wrist

EVERY_SETTING = [WatchSettings(wrist, crown) for wrist in Wrist for crown in Crown]


def bounds(mesh: Mesh) -> tuple[np.ndarray, np.ndarray]:
    return mesh.vertices.min(axis=0), mesh.vertices.max(axis=0)


@pytest.fixture(scope="module")
def watch() -> dict[str, Mesh]:
    return load_watch()


def test_watch_has_every_part(watch):
    assert set(watch) == {"case", "screen", "band", "crown"}
    for mesh in watch.values():
        assert len(mesh.faces) > 0
        assert mesh.faces.min() == 0 and mesh.faces.max() == len(mesh.vertices) - 1


def test_watch_is_centered_and_sized_in_centimetres(watch):
    low, high = bounds(watch["case"])
    assert high[1] - low[1] == pytest.approx(4.5)  # 12 o'clock to 6 o'clock
    assert (low + high) / 2 == pytest.approx([0, 0, 0], abs=0.05)


def test_crown_is_toward_x_and_display_toward_z(watch):
    _, case_high = bounds(watch["case"])
    crown = watch["crown"].vertices.mean(axis=0)
    assert crown[0] > 0.75 * case_high[0]
    assert crown[1] > 0  # nearer 12 o'clock than 6, as on the real watch

    screen = watch["screen"]
    assert screen.vertices[:, 2].min() == pytest.approx(case_high[2], abs=0.01)
    a, b, c = (screen.vertices[screen.faces[:, i]] for i in range(3))
    assert (np.cross(b - a, c - a)[:, 2] > 0).all()


@pytest.mark.parametrize("settings", EVERY_SETTING)
def test_face_marks_twelve_o_clock_on_the_glass(watch, settings):
    low, high = bounds(watch["screen"])
    face = watch_face(watch["screen"], settings)
    assert (face.vertices[:, 2] > high[2]).all()
    assert (face.vertices[:, :2] >= low[:2]).all() and (face.vertices[:, :2] <= high[:2]).all()
    # The mark reaching furthest from the center is the tip of the 12 o'clock triangle.
    offsets = face.vertices[:, :2] - (low[:2] + high[:2]) / 2
    tip = offsets[np.argmax(np.linalg.norm(offsets, axis=1))]
    assert tip / np.linalg.norm(tip) == pytest.approx(settings.twelve_o_clock[:2])


def test_axis_arrows_point_along_their_axes():
    arrows = axis_arrows(8.0, np.eye(3, 4) + [0, 0, 0, 1])  # red, green, blue
    a, b, c = (arrows.vertices[arrows.faces[:, i]] for i in range(3))
    assert np.einsum("ij,ij->i", a, np.cross(b, c)).sum() > 0  # closed, with triangles facing outward
    for axis in range(3):
        faces = arrows.faces[arrows.face_colors[:, axis] == 1]
        points = arrows.vertices[np.unique(faces)]
        tip = points[np.argmax(np.linalg.norm(points, axis=1))]
        assert tip == pytest.approx(8.0 * np.eye(3)[axis], abs=0.02)
