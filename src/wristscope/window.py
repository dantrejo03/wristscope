"""The scope window: live traces for each channel group beside the 3D watch."""

import math

import numpy as np
import pyqtgraph as pg
from pyqtgraph.Qt import QtCore, QtGui, QtWidgets

from wristscope.channels import Channel, Source, channel_groups
from wristscope.playback import PlaybackClock
from wristscope.samples import Feed
from wristscope.store import MotionStore
from wristscope.style import AXIS_COLORS, DEFAULT_COLOR
from wristscope.watch_view import WatchView

QUATERNION = [f"motion.quaternion.{axis}" for axis in "wxyz"]
# Plotted when the window opens; the rest can be ticked on in the sidebar.
DEFAULT_GROUPS = {"Raw acceleration", "Raw rotation rate", "Quaternion"}


class ScopeWindow(QtWidgets.QMainWindow):
    def __init__(
        self,
        feed: Feed,
        window_seconds: float = 10.0,
        settings: QtCore.QSettings | None = None,
        delay: float = 0.15,
    ) -> None:
        """`settings` is where preferences are remembered (by default, the user's wristscope settings).
        `delay` is how many seconds behind the watch the traces run, which keeps them scrolling smoothly."""
        super().__init__()
        self.setWindowTitle("Wristscope")
        self.feed = feed
        self.store = MotionStore()
        self.playback = PlaybackClock(delay)
        self._restarts_seen = 0
        self.window_seconds = window_seconds
        self._groups = channel_groups()
        self._plots: dict[str, pg.PlotWidget] = {}
        self._curves: dict[str, pg.PlotDataItem] = {}

        sidebar = QtWidgets.QWidget()
        sidebar_layout = QtWidgets.QVBoxLayout(sidebar)
        traces = QtWidgets.QWidget()
        traces_layout = QtWidgets.QVBoxLayout(traces)
        for group, channels in self._groups.items():
            plot = self._make_plot(group, channels)
            traces_layout.addWidget(plot)
            checkbox = QtWidgets.QCheckBox(group)
            shown = group in DEFAULT_GROUPS
            checkbox.setChecked(shown)
            plot.setVisible(shown)
            checkbox.toggled.connect(plot.setVisible)
            sidebar_layout.addWidget(checkbox)
        sidebar_layout.addStretch()

        self.watch = WatchView(settings)
        self.watch.message.connect(lambda text: self.statusBar().showMessage(text, 8000))
        calibrate = QtGui.QShortcut(QtGui.QKeySequence("C"), self)
        calibrate.activated.connect(self.watch.calibrate)
        splitter = QtWidgets.QSplitter()
        splitter.addWidget(sidebar)
        splitter.addWidget(traces)
        splitter.addWidget(self.watch)
        splitter.setSizes([170, 760, 490])
        self.setCentralWidget(splitter)
        self.resize(1420, 860)
        # Feed status and rates sit at the right of the status bar, leaving the rest for messages.
        self._feed_status = QtWidgets.QLabel()
        self._rates = QtWidgets.QLabel()
        self.statusBar().addPermanentWidget(self._feed_status)
        self.statusBar().addPermanentWidget(self._rates)

        self._frame_timer = QtCore.QTimer(self)
        self._frame_timer.timeout.connect(self._refresh)
        self._frame_timer.start(16)
        self._rate_timer = QtCore.QTimer(self)
        self._rate_timer.timeout.connect(self._show_rates)
        self._rate_timer.start(500)
        self._show_rates()

    def closeEvent(self, event) -> None:
        self.feed.close()
        super().closeEvent(event)

    def _make_plot(self, group: str, channels: tuple[Channel, ...]) -> pg.PlotWidget:
        plot = pg.PlotWidget(title=group)
        plot.setLabel("left", channels[0].unit)
        plot.setLabel("bottom", "seconds")
        plot.showGrid(x=True, y=True, alpha=0.2)
        plot.setXRange(-self.window_seconds, 0, padding=0)
        plot.setClipToView(True)
        plot.setAutoVisible(y=True)  # fit y to the data in view, not the whole buffer
        if len(channels) > 1:
            plot.addLegend(offset=(5, 5), colCount=len(channels))
        for channel in channels:
            axis = channel.id.rsplit(".", 1)[-1]
            pen = pg.mkPen(AXIS_COLORS.get(axis, DEFAULT_COLOR))
            self._curves[channel.id] = plot.plot(pen=pen, name=axis.upper())
        if self._plots:
            plot.setXLink(next(iter(self._plots.values())))
        self._plots[group] = plot
        return plot

    def _refresh(self) -> None:
        samples = self.feed.poll()
        for sample in samples:
            self.store.add(sample)
        if self.store.restarts != self._restarts_seen:  # the watch's timeline started over
            self._restarts_seen = self.store.restarts
            self.playback.reset()
        if samples:
            self.playback.observe(max(sample.timestamp for sample in samples))
        now = self.playback.now()
        if math.isnan(now):
            return

        # Like a scope in roll mode: the playback time sits at 0 and older samples scroll left.
        # It trails the newest sample by the delay, so newer ones are off the right edge.
        for group, channels in self._groups.items():
            if not self._plots[group].isVisible():
                continue
            for channel in channels:
                timestamps, values = self.store.series(channel.id)
                self._curves[channel.id].setData(timestamps - now, values, connect="finite")

        attitude = np.array([self.store.latest(channel_id) for channel_id in QUATERNION])
        if np.isfinite(attitude).all():
            self.watch.set_attitude(attitude)

    def _show_rates(self) -> None:
        rates = (f"{source.value} {self.store.buffer(source).rate():.0f} Hz" for source in Source)
        self._rates.setText("    ".join(rates))
        status = self.feed.status()
        for count, what in ((self.store.gaps, "gaps"), (self.store.out_of_order, "out of order"),
                            (self.store.restarts, "restarts")):
            if count:
                status += f" · {count} {what}"
        self._feed_status.setText(status)
