import pytest

from wristscope.watch3d.watch_settings import Crown, WatchSettings, Wrist


def test_defaults_match_the_watch():
    assert WatchSettings() == WatchSettings(Wrist.LEFT, Crown.RIGHT)


@pytest.mark.parametrize(
    "wrist, crown, hand_side, flipped",
    [
        (Wrist.LEFT, Crown.RIGHT, 1, False),
        (Wrist.LEFT, Crown.LEFT, -1, True),
        (Wrist.RIGHT, Crown.RIGHT, -1, False),
        (Wrist.RIGHT, Crown.LEFT, 1, True),
    ],
)
def test_orientation_follows_wrist_and_crown(wrist, crown, hand_side, flipped):
    settings = WatchSettings(wrist, crown)
    assert settings.hand_side == hand_side
    assert settings.display_flipped is flipped
    assert settings.twelve_o_clock == pytest.approx([0, -1 if flipped else 1, 0])
