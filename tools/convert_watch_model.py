"""Convert the downloaded watch model into the mesh wristscope loads at runtime.

    .venv/bin/python tools/convert_watch_model.py tools/smart_watch_-_apple.glb

Reads "Smart Watch - Apple" by James Gorman (Sketchfab, CC BY 4.0), downloaded as glTF
Binary, prints what it contains, and writes src/wristscope/assets/watch.npz. Only this
script needs trimesh; the app reads the .npz with numpy alone.

CC BY asks that changes to the model be stated. This script makes these, in order:

1. Drops the textures, texture coordinates and materials. Only the triangles are kept.
2. Merges vertices that the file splits only for texture coordinates (same position and
   normal), so texture seams don't show in the shading. Vertices split for hard edges
   stay split.
3. Labels each triangle with a part (see PART_OF_MATERIAL). The display glass has no
   material of its own: it is the up-facing part of the body inside the bezel opening
   (SCREEN_OPENING). The model has no strap, only the band connectors.
4. Turns the model into the watch frame: crown toward +x, 12 o'clock toward +y, display
   toward +z. The file has the display toward +y, the crown toward -x and 12 o'clock
   toward +z, so a watch-frame point is (-x, z, y). This is a rotation, not a mirror.
5. Centers the model on the case and scales it to centimetres, so the case measures
   CASE_HEIGHT from 12 o'clock to 6 o'clock.
"""

import argparse
from pathlib import Path

import numpy as np
import trimesh

PART_NAMES = ("case", "screen", "band", "crown")
PART_OF_MATERIAL = {
    "Body_MAT": "case",  # the case, side button and display glass (split off below)
    "Bottom_MAT": "case",  # the sensor dome on the back
    "Bar_MAT": "band",  # the two band connectors at 12 and 6 o'clock
    "Dail_MAT": "crown",  # the Digital Crown
}
# Where the bezel's inner edge is, in the file's own coordinates (x and z, in metres).
# Measured from the model: the glass is the flat top inside this rectangle.
SCREEN_OPENING = ((-0.0324, 0.0383), (-0.0463, 0.0470))
# watch-frame point = TO_WATCH @ file point
TO_WATCH = np.array([[-1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, 1.0, 0.0]])
CASE_HEIGHT = 4.5  # cm, 12 o'clock to 6 o'clock, like a 45 mm watch
OUTPUT = Path(__file__).resolve().parent.parent / "src" / "wristscope" / "assets" / "watch.npz"


def load_triangles(path: Path):
    """Each mesh in the file as (material name, vertices, vertex normals, faces), placed in the scene."""
    scene = trimesh.load(path, force="scene", process=False)
    meshes = []
    for node in scene.graph.nodes_geometry:
        transform, geometry_name = scene.graph[node]
        geometry = scene.geometry[geometry_name]
        linear, offset = transform[:3, :3], transform[:3, 3]
        vertices = geometry.vertices @ linear.T + offset
        # Normals turn with the inverse transpose, which keeps them perpendicular to the surface.
        normals = geometry.vertex_normals @ np.linalg.inv(linear)
        normals /= np.linalg.norm(normals, axis=1, keepdims=True)
        meshes.append((geometry.visual.material.name, vertices, normals, np.asarray(geometry.faces)))
    return meshes


def merge_texture_seams(vertices, normals, faces):
    """Merge vertices with the same position and normal; return the merged vertices and faces."""
    keys = np.hstack((vertices.round(7), normals.round(3)))
    _, first, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    return vertices[first], inverse.ravel()[faces]


def screen_faces(vertices, faces) -> np.ndarray:
    """Which faces of the body are the display glass: up-facing and inside the bezel opening."""
    triangles = vertices[faces]
    normals = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    facing_up = normals[:, 1] > 0.99 * np.linalg.norm(normals, axis=1)
    (x_min, x_max), (z_min, z_max) = SCREEN_OPENING
    x, z = triangles[:, :, 0], triangles[:, :, 2]
    inside = ((x >= x_min) & (x <= x_max) & (z >= z_min) & (z <= z_max)).all(axis=1)
    return facing_up & inside


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("glb", type=Path, help="the model downloaded from Sketchfab as glTF Binary")
    args = parser.parse_args()

    vertex_blocks, face_blocks, part_blocks = [], [], []
    vertex_count = 0
    print(f"{args.glb.name}:")
    for material, vertices, normals, faces in load_triangles(args.glb):
        part = PART_OF_MATERIAL[material]
        print(f"  {material:<10} -> {part:<6} {len(faces):5d} triangles, {len(vertices):4d} vertices, "
              f"bounds {vertices.min(axis=0).round(4)} to {vertices.max(axis=0).round(4)} m")
        vertices, faces = merge_texture_seams(vertices, normals, faces)
        parts = np.full(len(faces), PART_NAMES.index(part))
        if material == "Body_MAT":
            screen = screen_faces(vertices, faces)
            parts[screen] = PART_NAMES.index("screen")
            print(f"  {'':<10} -> screen {screen.sum():5d} of those triangles are the display glass")
        vertex_blocks.append(vertices)
        face_blocks.append(faces + vertex_count)
        part_blocks.append(parts)
        vertex_count += len(vertices)

    vertices = np.concatenate(vertex_blocks) @ TO_WATCH.T
    faces = np.concatenate(face_blocks)
    parts = np.concatenate(part_blocks)
    assert np.linalg.det(TO_WATCH) > 0, "a mirror would turn the triangles inside out"

    case = np.unique(faces[np.isin(parts, [PART_NAMES.index("case"), PART_NAMES.index("screen")])])
    low, high = vertices[case].min(axis=0), vertices[case].max(axis=0)
    vertices = (vertices - (low + high) / 2) * (CASE_HEIGHT / (high[1] - low[1]))

    print(f"\nwatch frame, cm: {len(faces)} triangles, {len(vertices)} vertices")
    for index, name in enumerate(PART_NAMES):
        used = vertices[np.unique(faces[parts == index])]
        print(f"  {name:<6} {np.sum(parts == index):5d} triangles, bounds {used.min(axis=0).round(2)} to {used.max(axis=0).round(2)}")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        OUTPUT,
        vertices=vertices.astype(np.float32),
        faces=faces.astype(np.uint32),
        parts=parts.astype(np.uint8),
        part_names=np.array(PART_NAMES),
    )
    print(f"\nwrote {OUTPUT}")


if __name__ == "__main__":
    main()
