# Assets

## watch.npz

Watch model: ["Smart Watch - Apple"](https://sketchfab.com/3d-models/smart-watch-apple-765c09acb5bc4892be94bb3b37d12000) by James Gorman, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Re-oriented, scaled, split into parts, textures removed.

`tools/convert_watch_model.py` made this file from the glTF Binary download. In detail, it:

1. dropped the textures, texture coordinates and materials, keeping only the triangles;
2. merged vertices that the file split only for texture coordinates;
3. labelled each triangle as `case`, `screen`, `band` or `crown` (the original's four materials map to these, and the display glass was split off the body by position);
4. turned the model into the watch frame: Digital Crown toward +x, 12 o'clock toward +y, display toward +z;
5. centred it on the case and scaled it to centimetres, with the case 4.5 cm from 12 to 6 o'clock.

The model has no strap; the `band` part is the two band connectors.

Contents (numpy arrays):

| name | shape | meaning |
| --- | --- | --- |
| `vertices` | (n, 3) float32 | positions in the watch frame, in cm |
| `faces` | (m, 3) uint32 | three vertex indices per triangle |
| `parts` | (m,) uint8 | index into `part_names` for each triangle |
| `part_names` | (4,) str | `case`, `screen`, `band`, `crown` |

To rebuild it, download the model from Sketchfab as glTF Binary (`.glb`), then run:

```bash
.venv/bin/python tools/convert_watch_model.py tools/smart_watch_-_apple.glb
```
