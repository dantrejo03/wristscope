"""The watch in 3D, as a widget that can be dropped into any window.

It turns a model of the watch with the attitude quaternion, over a floor with the
watch's shadow, with its x/y/z axes. Its own strip of controls sets how the watch
is worn and calibrates which way it faces. The calibration only changes what is
shown: attitudes passed in are never modified.
"""

import math
from dataclasses import dataclass

import numpy as np
import pyqtgraph as pg
import pyqtgraph.opengl as gl
from pyqtgraph.opengl import shaders
from pyqtgraph.opengl.GLGraphicsItem import GLGraphicsItem
from pyqtgraph.Qt import QtCore, QtGui, QtWidgets

from wristscope import quaternion as quat
from wristscope.calibration import CalibrationError, yaw_offset
from wristscope.style import AXIS_COLORS
from wristscope.watch_model import Mesh, axis_arrows, load_watch, watch_face
from wristscope.watch_settings import Crown, WatchSettings, Wrist

AXIS_LENGTH = 8.0
FLOOR_Z = -9.0
BACKGROUND = (22, 24, 29)
# Opaque, and drawn first just under the grid, so the grid shows through and overlapping
# triangles don't darken each other the way they would if it were translucent.
SHADOW_COLOR = (0.035, 0.04, 0.047, 1.0)


@dataclass(frozen=True)
class Material:
    color: tuple[float, float, float, float]
    ambient: float  # light that reaches every face
    diffuse: float  # light on faces turned toward the lamp
    specular: float  # brightness of the highlight
    shininess: float  # higher is a smaller, sharper highlight


MATERIALS = {
    "case": Material((0.72, 0.74, 0.77, 1.0), ambient=0.22, diffuse=0.5, specular=0.55, shininess=7),  # brushed metal
    "screen": Material((0.02, 0.025, 0.03, 1.0), ambient=1.0, diffuse=0.4, specular=1.0, shininess=150),  # glass
    "band": Material((0.14, 0.2, 0.36, 1.0), ambient=0.35, diffuse=0.7, specular=0.0, shininess=1),  # matte connectors
    "crown": Material((1.0, 0.55, 0.12, 1.0), ambient=0.4, diffuse=0.6, specular=0.5, shininess=30),
}

# pyqtgraph passes u_mvp and u_normal; extra uniforms arrive through ShaderProgram as
# float arrays, so the model-view matrix comes in as 16 floats, column by column.
_VERTEX_SHADER = """
uniform mat4 u_mvp;
uniform mat3 u_normal;
uniform float u_modelview[16];
attribute vec4 a_position;
attribute vec3 a_normal;
attribute vec4 a_color;
varying vec4 v_color;
varying vec3 v_normal;
varying vec3 v_to_eye;
void main() {
    mat4 modelview = mat4(%s);
    v_to_eye = -(modelview * a_position).xyz;
    v_normal = u_normal * a_normal;
    v_color = a_color;
    gl_Position = u_mvp * a_position;
}
""" % ", ".join(f"u_modelview[{i}]" for i in range(16))

# Blinn-Phong lighting in view space (x right, y up, z toward the viewer), with the
# lamp above and in front, a little to the left, so faces toward the camera are lit.
_FRAGMENT_SHADER = """
#ifdef GL_ES
precision mediump float;
#endif
uniform float u_ambient;
uniform float u_diffuse;
uniform float u_specular;
uniform float u_shininess;
varying vec4 v_color;
varying vec3 v_normal;
varying vec3 v_to_eye;
const vec3 TO_LIGHT = vec3(-0.35, 0.65, 0.7);
void main() {
    vec3 normal = normalize(v_normal);
    if (!gl_FrontFacing) normal = -normal;
    vec3 light = normalize(TO_LIGHT);
    vec3 halfway = normalize(light + normalize(v_to_eye));
    float diffuse = max(dot(normal, light), 0.0);
    float highlight = diffuse > 0.0 ? pow(max(dot(normal, halfway), 0.0), u_shininess) : 0.0;
    vec3 rgb = v_color.rgb * (u_ambient + u_diffuse * diffuse) + u_specular * highlight;
    gl_FragColor = vec4(rgb, v_color.a);
}
"""


class _LitMesh(gl.GLMeshItem):
    """A mesh lit by the shader above with one material."""

    def __init__(self, mesh: Mesh, name: str, material: Material) -> None:
        # Each item gets its own program, because a program holds one set of material values.
        shader = shaders.ShaderProgram(
            f"wristscope-{name}",
            [shaders.VertexShader(_VERTEX_SHADER), shaders.FragmentShader(_FRAGMENT_SHADER)],
            uniforms={
                "u_ambient": [material.ambient],
                "u_diffuse": [material.diffuse],
                "u_specular": [material.specular],
                "u_shininess": [material.shininess],
            },
        )
        super().__init__(vertexes=mesh.vertices, faces=mesh.faces, color=material.color, smooth=True, shader=shader)

    def paint(self) -> None:
        self.shader()["u_modelview"] = self.modelViewMatrix().data()
        super().paint()


def _flat_mesh(mesh: Mesh, color=None) -> gl.GLMeshItem:
    """A mesh drawn in flat colors, without lighting."""
    return gl.GLMeshItem(vertexes=mesh.vertices, faces=mesh.faces, faceColors=mesh.face_colors, color=color,
                         smooth=False, computeNormals=False)


def _rotation(attitude: np.ndarray) -> QtGui.QMatrix4x4:
    transform = QtGui.QMatrix4x4()
    transform.rotate(QtGui.QQuaternion(*attitude))
    return transform


def calibration_pose(settings: WatchSettings) -> str:
    wrist = settings.wrist.value
    other = "right" if settings.wrist is Wrist.LEFT else "left"
    return (f"Rest your {wrist} forearm on the desk as if checking the time: display up, "
            f"forearm parallel to the screen, 12 o'clock pointing at the screen. "
            f"Then click Calibrate with your {other} hand, or press C.")


class WatchView(QtWidgets.QWidget):
    """The watch and its axes over a floor in the reference frame (z up), with controls."""

    message = QtCore.Signal(str)  # something to tell the user, such as how calibrating went

    def __init__(self, store: QtCore.QSettings | None = None, parent: QtWidgets.QWidget | None = None) -> None:
        super().__init__(parent)
        self._store = store if store is not None else QtCore.QSettings("wristscope", "wristscope")
        self._settings = _load_settings(self._store)
        self._attitude: np.ndarray | None = None  # the latest attitude passed in, unmodified
        self._offset: np.ndarray | None = None  # the calibration, applied to what is shown

        self.view = gl.GLViewWidget()
        self.view.setBackgroundColor(BACKGROUND)
        # Behind the user, looking toward +y and down: after calibrating, 12 o'clock points away from the camera.
        self.view.setCameraPosition(pos=pg.Vector(0, 0, -2.5), distance=19, elevation=55, azimuth=-90)

        floor = gl.GLGridItem()
        floor.setSize(40, 40)
        floor.setSpacing(2, 2)
        floor.translate(0, 0, FLOOR_Z)
        self.view.addItem(floor)

        parts = load_watch()
        # The shadow is the watch squashed flat onto the floor, so it needs no per-frame work.
        self._shadow = _flat_mesh(Mesh.join(*parts.values()), SHADOW_COLOR)
        self._shadow.setDepthValue(-1)
        self.view.addItem(self._shadow)

        # Everything that turns with the watch hangs from one item, so one transform moves it all.
        self._body = GLGraphicsItem()
        self.view.addItem(self._body)
        for name, mesh in parts.items():
            _LitMesh(mesh, name, MATERIALS[name]).setParentItem(self._body)
        self._face = _flat_mesh(watch_face(parts["screen"], self._settings))
        self._face.setParentItem(self._body)
        self._screen = parts["screen"]

        # Thin arrows rather than GL lines, which macOS draws one device pixel wide.
        self._axes = _flat_mesh(axis_arrows(AXIS_LENGTH, [pg.mkColor(AXIS_COLORS[axis]).getRgbF() for axis in "xyz"]))
        self._axes.setParentItem(self._body)

        layout = QtWidgets.QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.view, stretch=1)
        layout.addLayout(self._make_controls())
        self._show_settings()
        self._show_attitude()

    @property
    def settings(self) -> WatchSettings:
        return self._settings

    def set_settings(self, settings: WatchSettings) -> None:
        """Change how the watch is worn; it's remembered for next time."""
        self._settings = settings
        self._store.setValue("watch/wrist", settings.wrist.value)
        self._store.setValue("watch/crown", settings.crown.value)
        self._show_settings()

    def set_attitude(self, attitude: np.ndarray) -> None:
        """Turn the watch to `attitude`, a [w, x, y, z] quaternion from the watch."""
        self._attitude = np.asarray(attitude, dtype=float)
        self._show_attitude()

    def displayed_attitude(self) -> np.ndarray | None:
        """The attitude as shown: the latest one passed in, turned by the calibration."""
        if self._attitude is None:
            return None
        return self._attitude if self._offset is None else quat.multiply(self._offset, self._attitude)

    def calibrate(self) -> bool:
        """Turn the shown watch so the face's 12 o'clock points into the screen. Tilt is kept."""
        if self._attitude is None:
            self.message.emit("Can't calibrate yet: no attitude from the watch.")
            return False
        try:
            self._offset = yaw_offset(self._attitude, self._settings)
        except CalibrationError as error:
            self.message.emit(f"Can't calibrate: {error}.")
            return False
        turn = math.degrees(2 * math.atan2(self._offset[3], self._offset[0]))
        self._calibration_label.setText(f"Calibrated (turned {turn:+.0f}°)")
        self.message.emit(f"Calibrated: turned the watch {turn:+.0f}° about the vertical, so 12 o'clock points into the screen.")
        self._show_attitude()
        return True

    def reset_calibration(self) -> None:
        self._offset = None
        self._calibration_label.setText("Not calibrated")
        self.message.emit("Calibration reset: showing the attitude as the watch reports it.")
        self._show_attitude()

    def _make_controls(self) -> QtWidgets.QLayout:
        self._wrist = QtWidgets.QComboBox()
        self._wrist.addItem("Left wrist", Wrist.LEFT.value)
        self._wrist.addItem("Right wrist", Wrist.RIGHT.value)
        self._crown = QtWidgets.QComboBox()
        self._crown.addItem("Crown right", Crown.RIGHT.value)
        self._crown.addItem("Crown left", Crown.LEFT.value)
        for combo in (self._wrist, self._crown):
            combo.setToolTip("As set on the watch in Settings → General → Orientation")
            combo.activated.connect(self._settings_chosen)

        axes = QtWidgets.QCheckBox("Axes")
        axes.setToolTip("The watch's x (crown), y (12 o'clock) and z (out of the display) axes")
        shown = self._store.value("watch/show_axes", True, type=bool)
        axes.setChecked(shown)
        self._axes.setVisible(shown)
        axes.toggled.connect(self._axes.setVisible)
        axes.toggled.connect(lambda checked: self._store.setValue("watch/show_axes", checked))

        self._calibrate_button = QtWidgets.QPushButton("Calibrate")
        self._calibrate_button.clicked.connect(self.calibrate)
        reset = QtWidgets.QPushButton("Reset")
        reset.setToolTip("Show the attitude as the watch reports it")
        reset.clicked.connect(self.reset_calibration)
        self._calibration_label = QtWidgets.QLabel("Not calibrated")

        top = QtWidgets.QHBoxLayout()
        for widget in (self._wrist, self._crown):
            top.addWidget(widget)
        top.addStretch()
        top.addWidget(axes)
        bottom = QtWidgets.QHBoxLayout()
        for widget in (self._calibrate_button, reset, self._calibration_label):
            bottom.addWidget(widget)
        bottom.addStretch()
        controls = QtWidgets.QVBoxLayout()
        controls.setContentsMargins(6, 4, 6, 6)
        controls.addLayout(top)
        controls.addLayout(bottom)
        return controls

    def _settings_chosen(self) -> None:
        self.set_settings(WatchSettings(Wrist(self._wrist.currentData()), Crown(self._crown.currentData())))

    def _show_settings(self) -> None:
        self._wrist.setCurrentIndex(self._wrist.findData(self._settings.wrist.value))
        self._crown.setCurrentIndex(self._crown.findData(self._settings.crown.value))
        face = watch_face(self._screen, self._settings)
        self._face.setMeshData(vertexes=face.vertices, faces=face.faces, faceColors=face.face_colors)
        pose = calibration_pose(self._settings)
        self._calibrate_button.setToolTip(pose)
        self._calibration_label.setToolTip(pose)

    def _show_attitude(self) -> None:
        attitude = self.displayed_attitude()
        rotation = _rotation(attitude if attitude is not None else np.array([1.0, 0.0, 0.0, 0.0]))
        self._body.setTransform(rotation)
        shadow = QtGui.QMatrix4x4()
        shadow.translate(0, 0, FLOOR_Z - 0.01)
        shadow.scale(1, 1, 0)
        self._shadow.setTransform(shadow * rotation)


def _load_settings(store: QtCore.QSettings) -> WatchSettings:
    try:
        return WatchSettings(Wrist(store.value("watch/wrist", "left")), Crown(store.value("watch/crown", "right")))
    except ValueError:
        return WatchSettings()
