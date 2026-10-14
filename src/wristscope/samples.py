from collections.abc import Mapping
from dataclasses import dataclass
from typing import Protocol

from wristscope.channels import CHANNELS, Source


@dataclass(frozen=True)
class Sample:
    """One handler callback's worth of readings from one source.

    `timestamp` is CoreMotion's own (seconds since the watch booted). All three
    sources use that clock, so their samples line up on one time axis.
    `values` maps channel id to reading and holds only the channels that arrived.
    """

    source: Source
    timestamp: float
    values: Mapping[str, float]

    def __post_init__(self) -> None:
        for channel_id in self.values:
            channel = CHANNELS.get(channel_id)
            if channel is None or channel.source is not self.source:
                raise ValueError(f"{channel_id!r} is not a {self.source.name} channel")


class Feed(Protocol):
    """Anything that delivers samples: the simulator or the watch connection."""

    def poll(self) -> list[Sample]:
        """Samples that arrived since the last call."""
        ...

    def status(self) -> str:
        """A short line for the status bar."""
        ...

    def close(self) -> None:
        """Release anything held, such as a listening socket."""
        ...
