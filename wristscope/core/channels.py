"""The fundamental CoreMotion channels the watch can send.

A channel is one scalar signal, such as gravity's x axis. Every channel belongs
to exactly one source (the CoreMotion handler that produced it) and is plotted
against that source's timestamps. Within a source, channels are listed in the
order the watch writes them.
"""

from dataclasses import dataclass
from enum import Enum


class Source(Enum):
    """A CoreMotion handler on the watch. Each one stamps its own samples."""

    ACCELEROMETER = "accel"
    GYRO = "gyro"
    DEVICE_MOTION = "motion"


@dataclass(frozen=True)
class Channel:
    id: str
    source: Source
    group: str  # channels in the same group (the axes of one vector) are plotted together
    label: str
    unit: str


def _axes(source: Source, prefix: str, group: str, unit: str, axes: str = "xyz") -> tuple[Channel, ...]:
    return tuple(Channel(f"{prefix}.{axis}", source, group, f"{group} {axis.upper()}", unit) for axis in axes)


FUNDAMENTAL_CHANNELS: tuple[Channel, ...] = (
    # CMAccelerometerData.acceleration
    *_axes(Source.ACCELEROMETER, "accel", "Raw acceleration", "g"),
    # CMGyroData.rotationRate
    *_axes(Source.GYRO, "gyro", "Raw rotation rate", "rad/s"),
    # CMDeviceMotion
    *_axes(Source.DEVICE_MOTION, "motion.quaternion", "Quaternion", "", axes="wxyz"),
    *_axes(Source.DEVICE_MOTION, "motion.user_accel", "User acceleration", "g"),
    *_axes(Source.DEVICE_MOTION, "motion.rotation_rate", "Rotation rate", "rad/s"),
    *_axes(Source.DEVICE_MOTION, "motion.gravity", "Gravity", "g"),
)

CHANNELS: dict[str, Channel] = {channel.id: channel for channel in FUNDAMENTAL_CHANNELS}


def channels_for(source: Source) -> tuple[Channel, ...]:
    return tuple(channel for channel in FUNDAMENTAL_CHANNELS if channel.source is source)


def channel_groups() -> dict[str, tuple[Channel, ...]]:
    groups: dict[str, list[Channel]] = {}
    for channel in FUNDAMENTAL_CHANNELS:
        groups.setdefault(channel.group, []).append(channel)
    return {group: tuple(channels) for group, channels in groups.items()}
