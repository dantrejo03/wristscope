"""Which moment of the watch's timeline the scope shows right now.

Samples arrive in bursts (every 100 ms), but the screen redraws far more often.
Showing the newest sample would make traces sit still and then jump. Instead the
scope shows the watch's time minus a fixed delay, advancing with the Mac's own
clock, so traces scroll smoothly as long as no burst is later than the delay.

The watch's timestamps count from its boot, so they must be mapped onto the Mac's
clock. Each burst gives one measurement of `mac_time - watch_time`; the delay
through the network only ever adds to it, so the smallest recent value is the
best estimate.
"""

import math
import time
from collections import deque
from collections.abc import Callable

HORIZON = 10.0  # seconds of measurements the smallest is taken over
MAX_SLEW = 0.005  # the estimate moves at most 5 ms per second, so playback never visibly speeds up or slows down


class PlaybackClock:
    def __init__(self, delay: float = 0.15, clock: Callable[[], float] = time.monotonic) -> None:
        self.delay = delay
        self._clock = clock
        self.reset()

    def reset(self) -> None:
        """Forget the offset, for when the watch's timeline restarts."""
        self._measurements: deque[tuple[float, float]] = deque()  # (mac time, mac time - watch time)
        self._offset = math.nan
        self._last_update = math.nan

    def observe(self, newest_timestamp: float) -> None:
        """Note that a burst whose newest sample is stamped `newest_timestamp` has just arrived."""
        arrived = self._clock()
        self._measurements.append((arrived, arrived - newest_timestamp))
        while self._measurements[0][0] < arrived - HORIZON:
            self._measurements.popleft()

    def now(self) -> float:
        """The watch timestamp to show at the right edge, or NaN before any data has arrived."""
        if not self._measurements:
            return math.nan
        mac_now = self._clock()
        target = min(offset for _, offset in self._measurements)
        if math.isnan(self._offset):
            self._offset = target
        else:
            step = MAX_SLEW * (mac_now - self._last_update)
            self._offset += max(-step, min(step, target - self._offset))
        self._last_update = mac_now
        return mac_now - self._offset - self.delay
