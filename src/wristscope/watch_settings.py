"""How the watch is worn, mirroring the watch's Settings → General → Orientation.

This assumes CoreMotion's axes are fixed to the hardware (+x toward the Digital
Crown, +y toward the hardware's 12 o'clock, +z out of the display) whichever way
the watch is worn. That is why watchOS gives apps `wristLocation` and
`crownOrientation`. It still needs confirming against data from a real watch.
"""

from dataclasses import dataclass
from enum import Enum

import numpy as np


class Wrist(Enum):
    LEFT = "left"
    RIGHT = "right"


class Crown(Enum):
    RIGHT = "right"
    LEFT = "left"


@dataclass(frozen=True)
class WatchSettings:
    wrist: Wrist = Wrist.LEFT
    crown: Crown = Crown.RIGHT

    @property
    def display_flipped(self) -> bool:
        """With the crown on the left, watchOS turns the screen 180° so it reads the right way up."""
        return self.crown is Crown.LEFT

    @property
    def twelve_o_clock(self) -> np.ndarray:
        """The direction of the face's 12 o'clock, in the watch frame."""
        return np.array([0.0, -1.0 if self.display_flipped else 1.0, 0.0])

    @property
    def hand_side(self) -> float:
        """+1 if the hand is toward +x (the crown points at it), -1 if it is toward -x."""
        crown_toward_hand = (self.wrist is Wrist.LEFT) == (self.crown is Crown.RIGHT)
        return 1.0 if crown_toward_hand else -1.0
