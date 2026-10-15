"""The watch as triangle meshes in the watch frame.

Units are centimetres. x points toward the Digital Crown, y toward the hardware's
12 o'clock and z out of the display. The watch itself comes from assets/watch.npz
(see assets/README.md); the watch face and axis arrows are built here.
"""

import math
from dataclasses import dataclass
from importlib import resources

import numpy as np

from wristscope.watch3d.watch_settings import WatchSettings

FACE_LIFT = 0.02  # how far the face's markings float above the glass, so they don't flicker against it


@dataclass(frozen=True)
class Mesh:
    vertices: np.ndarray  # (n, 3) positions
    faces: np.ndarray  # (m, 3) vertex indices per triangle
    face_colors: np.ndarray | None = None  # (m, 4) RGBA, for meshes drawn without lighting

    @staticmethod
    def join(*meshes: "Mesh") -> "Mesh":
        offsets = np.cumsum([0] + [len(mesh.vertices) for mesh in meshes[:-1]])
        colors = [mesh.face_colors for mesh in meshes]
        return Mesh(
            np.concatenate([mesh.vertices for mesh in meshes]),
            np.concatenate([mesh.faces + offset for mesh, offset in zip(meshes, offsets)]),
            None if any(c is None for c in colors) else np.concatenate(colors),
        )


def load_watch() -> dict[str, Mesh]:
    """The watch's parts from the converted model: "case", "screen", "band" (the connectors) and "crown"."""
    with resources.files("wristscope.watch3d").joinpath("assets/watch.npz").open("rb") as file:
        data = np.load(file)
        vertices, faces, parts, names = (data[key] for key in ("vertices", "faces", "parts", "part_names"))
    meshes = {}
    for index, name in enumerate(names):
        part_faces = faces[parts == index]
        used, inverse = np.unique(part_faces, return_inverse=True)
        meshes[str(name)] = Mesh(vertices[used].astype(float), inverse.reshape(part_faces.shape))
    return meshes


def watch_face(screen: Mesh, settings: WatchSettings) -> Mesh:
    """Hour ticks, a bold 12 o'clock triangle and hands at 10:10, floating just above the glass.

    When the display is flipped (crown on the left) the design turns 180°, so 12 o'clock is at -y.
    """
    low, high = screen.vertices.min(axis=0), screen.vertices.max(axis=0)
    radius = 0.45 * min(high[:2] - low[:2])

    shapes = []
    for hour in range(1, 12):
        major = hour % 3 == 0
        shapes.append(_bar(hour * 30, (0.74 if major else 0.84) * radius, radius, (0.045 if major else 0.025) * radius,
                           (0.86, 0.87, 0.9, 1.0) if major else (0.6, 0.62, 0.66, 1.0)))
    white = (1.0, 1.0, 1.0, 1.0)
    # The 12 o'clock triangle points outward and reaches into the space above the dial.
    shapes.append(_polygon([(-0.24 * radius, 0.7 * radius), (0.24 * radius, 0.7 * radius), (0.0, 1.25 * radius)], white))
    shapes.append(_bar(305, -0.1 * radius, 0.5 * radius, 0.05 * radius, white))  # hour hand at 10:10
    shapes.append(_bar(60, -0.1 * radius, 0.78 * radius, 0.035 * radius, white))  # minute hand
    shapes.append(_polygon(0.07 * radius * _circle(16), (1.0, 0.6, 0.2, 1.0)))

    face = Mesh.join(*shapes)
    xy = face.vertices[:, :2] * (-1.0 if settings.display_flipped else 1.0) + (low[:2] + high[:2]) / 2
    return Mesh(np.column_stack((xy, np.full(len(xy), high[2] + FACE_LIFT))), face.faces, face.face_colors)


def axis_arrows(length: float, colors) -> Mesh:
    """Thin arrows from the origin along +x, +y and +z, colored by `colors` (three RGBA)."""
    shaft, head, head_length = 0.05, 0.16, 0.7
    arrow = _tube(np.array([(0.0, shaft), (length - head_length, shaft), (length - head_length, head), (length, 0.01)]))
    # Turn the arrow along x onto each axis.
    turns = (np.eye(3), np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1]]), np.array([[0, 0, -1], [0, 1, 0], [1, 0, 0]]))
    return Mesh.join(*(Mesh(arrow.vertices @ turn.T, arrow.faces, np.tile(color, (len(arrow.faces), 1)))
                       for turn, color in zip(turns, colors)))


def _tube(sections: np.ndarray, around: int = 12) -> Mesh:
    """A closed round tube along x through (x, radius) cross-sections."""
    x, radius = sections.T
    circle = _circle(around)
    rings = np.stack([
        np.broadcast_to(x[:, None], (len(x), around)),
        radius[:, None] * circle[:, 0],
        radius[:, None] * circle[:, 1],
    ], axis=-1)

    j = np.arange(around)
    k = (j + 1) % around
    quads = [np.concatenate((np.column_stack((r * around + j, (r + 1) * around + k, (r + 1) * around + j)),
                             np.column_stack((r * around + j, r * around + k, (r + 1) * around + k))))
             for r in range(len(x) - 1)]
    tube = Mesh(rings.reshape(-1, 3), np.concatenate(quads))
    # Each end is closed by a fan of its own vertices, so the rim stays a sharp edge.
    caps = []
    for ring, flip in ((rings[0], True), (rings[-1], False)):
        fan = np.column_stack((np.zeros(around, int), 1 + j, 1 + k))
        caps.append(Mesh(np.vstack(((ring[0, 0], 0.0, 0.0), ring)), fan[:, ::-1] if flip else fan))
    return Mesh.join(tube, *caps)


def _circle(count: int) -> np.ndarray:
    angles = np.linspace(0, 2 * math.pi, count, endpoint=False)
    return np.column_stack((np.cos(angles), np.sin(angles)))


def _polygon(points, color) -> Mesh:
    """A flat convex polygon in the face's plane (z = 0), as a fan of triangles."""
    points = np.asarray(points, dtype=float)
    i = np.arange(1, len(points) - 1)
    faces = np.column_stack((np.zeros(len(i), int), i, i + 1))
    return Mesh(np.column_stack((points, np.zeros(len(points)))), faces, np.tile(color, (len(faces), 1)))


def _bar(clock_degrees: float, start: float, end: float, half_width: float, color) -> Mesh:
    """A straight mark from radius `start` to `end`, pointing at a clock position (0° is 12, 90° is 3)."""
    angle = math.radians(clock_degrees)
    along = np.array([math.sin(angle), math.cos(angle)])
    across = np.array([along[1], -along[0]])
    return _polygon([start * along - half_width * across, start * along + half_width * across,
                     end * along + half_width * across, end * along - half_width * across], color)
