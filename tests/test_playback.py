import math

import pytest

from wristscope.core.playback import HORIZON, MAX_SLEW, PlaybackClock


class FakeClock:
    def __init__(self) -> None:
        self.time = 500.0

    def __call__(self) -> float:
        return self.time


def make(delay: float = 0.15) -> tuple[PlaybackClock, FakeClock]:
    clock = FakeClock()
    return PlaybackClock(delay, clock), clock


def test_nan_before_any_data():
    playback, _ = make()
    assert math.isnan(playback.now())


def test_shows_watch_time_minus_delay():
    playback, clock = make(delay=0.15)
    playback.observe(1000.0)  # watch is at 1000 s when the Mac's clock reads 500
    assert playback.now() == pytest.approx(1000.0 - 0.15)
    clock.time += 0.5
    assert playback.now() == pytest.approx(1000.5 - 0.15)


def test_advances_smoothly_between_bursts():
    playback, clock = make()
    playback.observe(1000.0)
    shown = []
    for _ in range(6):  # six 16 ms redraws with no new data
        clock.time += 0.016
        shown.append(playback.now())
    steps = [b - a for a, b in zip(shown, shown[1:])]
    assert steps == pytest.approx([0.016] * 5)


def test_uses_the_least_delayed_burst():
    playback, clock = make()
    for transit in (0.08, 0.02, 0.05):  # the middle burst was fastest through the network
        clock.time += 0.1
        playback.observe(1000.0 + (clock.time - 500.0) - transit)
    assert playback.now() == pytest.approx(1000.0 + (clock.time - 500.0) - 0.02 - 0.15)


def test_estimate_moves_slowly():
    playback, clock = make()
    playback.observe(1000.0)
    playback.now()
    clock.time += 1.0
    playback.observe(1001.5)  # a burst that got through 0.5 s faster than any before
    jump = playback.now() - (1001.0 - 0.15)
    assert jump == pytest.approx(MAX_SLEW, abs=1e-9)  # not the full 0.5 s


def test_old_measurements_expire():
    playback, clock = make()
    playback.observe(1000.0 + 0.0)  # offset -500.0
    clock.time += HORIZON + 1
    playback.observe(clock.time - 500.0 + 1000.0 - 0.3)  # a burst 0.3 s slower than the first
    assert min(o for _, o in playback._measurements) == pytest.approx(-500.0 + 0.3)


def test_reset_forgets_the_offset():
    playback, clock = make()
    playback.observe(1000.0)
    playback.reset()
    assert math.isnan(playback.now())
    playback.observe(5.0)  # watch rebooted
    assert playback.now() == pytest.approx(5.0 - 0.15)
