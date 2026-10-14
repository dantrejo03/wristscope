"""Rolling history of samples: the data behind the scope's traces."""

import math

import numpy as np

from wristscope.channels import CHANNELS, Source, channels_for
from wristscope.samples import Sample


class SourceBuffer:
    """The most recent `capacity` samples from one source, as numpy arrays.

    Each channel is a column. A channel missing from a sample is stored as NaN,
    which plotting libraries draw as a gap.
    """

    def __init__(self, source: Source, capacity: int) -> None:
        self.source = source
        self.capacity = capacity
        self._columns = {channel.id: i for i, channel in enumerate(channels_for(source))}
        self._timestamps = np.empty(capacity)
        self._values = np.empty((capacity, len(self._columns)))
        self._next = 0  # row the next sample is written to
        self._count = 0

    def __len__(self) -> int:
        return self._count

    def append(self, sample: Sample) -> None:
        if sample.source is not self.source:
            raise ValueError(f"{sample.source.name} sample appended to {self.source.name} buffer")
        row = self._next
        self._timestamps[row] = sample.timestamp
        self._values[row] = np.nan
        for channel_id, value in sample.values.items():
            self._values[row, self._columns[channel_id]] = value
        self._next = (row + 1) % self.capacity
        self._count = min(self._count + 1, self.capacity)

    def timestamps(self) -> np.ndarray:
        """Timestamps, oldest first."""
        return self._in_order(self._timestamps)

    def values(self, channel_id: str) -> np.ndarray:
        """One channel's readings, oldest first, aligned with `timestamps()`."""
        return self._in_order(self._values[:, self._columns[channel_id]])

    def latest(self, channel_id: str) -> float:
        """The newest reading of one channel, or NaN if there isn't one."""
        if not self._count:
            return math.nan
        return float(self._values[self._next - 1, self._columns[channel_id]])

    def latest_timestamp(self) -> float:
        """The newest timestamp, or NaN before the first sample."""
        return float(self._timestamps[self._next - 1]) if self._count else math.nan

    def rate(self, window: float = 1.0) -> float:
        """Samples per second over the last `window` seconds."""
        timestamps = self.timestamps()
        if len(timestamps) < 2:
            return 0.0
        recent = timestamps[timestamps >= timestamps[-1] - window]
        if len(recent) < 2:
            return 0.0
        return (len(recent) - 1) / (recent[-1] - recent[0])

    def _in_order(self, array: np.ndarray) -> np.ndarray:
        if self._count < self.capacity:
            return array[: self._count].copy()
        return np.concatenate((array[self._next :], array[: self._next]))


GAP_FACTOR = 5  # a jump this many times a source's usual spacing means samples were lost
RESTART_JUMP = 1.0  # seconds backward that means the watch restarted rather than a late sample
_SPACING_SAMPLES = 3  # spacings to see before trusting the usual spacing


class MotionStore:
    """One buffer per source; each sample is routed to its source's buffer.

    Samples must arrive in order within each source. Three things can break that,
    and the store handles them so nothing downstream has to:

    - A jump well past the usual spacing: samples were lost. A blank row is stored
      so traces show a gap instead of a line straight across it.
    - A timestamp older than the source's newest: dropped and counted.
    - A jump backward of more than RESTART_JUMP: the watch restarted or was swapped,
      so every buffer is cleared.
    """

    def __init__(self, capacity: int = 4096) -> None:
        self._capacity = capacity
        self.out_of_order = 0
        self.gaps = 0
        self.restarts = 0
        self._reset()

    def _reset(self) -> None:
        self._buffers = {source: SourceBuffer(source, self._capacity) for source in Source}
        self._spacing = {source: 0.0 for source in Source}  # smoothed time between samples
        self._spacings_seen = {source: 0 for source in Source}

    def add(self, sample: Sample) -> None:
        source = sample.source
        buffer = self._buffers[source]
        if len(buffer):
            newest = buffer.latest_timestamp()
            step = sample.timestamp - newest
            if step < -RESTART_JUMP:
                self.restarts += 1
                self._reset()
                buffer = self._buffers[source]
            elif step < 0:
                self.out_of_order += 1
                return
            else:
                self._note_spacing(source, step, buffer, sample)
        buffer.append(sample)

    def _note_spacing(self, source: Source, step: float, buffer: SourceBuffer, sample: Sample) -> None:
        usual = self._spacing[source]
        if self._spacings_seen[source] >= _SPACING_SAMPLES and step > GAP_FACTOR * usual:
            self.gaps += 1
            buffer.append(Sample(source, buffer.latest_timestamp() + usual, {}))
            return  # the jump says nothing about the usual spacing
        seen = self._spacings_seen[source]
        self._spacing[source] = step if seen == 0 else 0.9 * usual + 0.1 * step
        self._spacings_seen[source] = seen + 1

    def buffer(self, source: Source) -> SourceBuffer:
        return self._buffers[source]

    def series(self, channel_id: str) -> tuple[np.ndarray, np.ndarray]:
        """(timestamps, values) for one channel, oldest first."""
        buffer = self._buffers[CHANNELS[channel_id].source]
        return buffer.timestamps(), buffer.values(channel_id)

    def latest(self, channel_id: str) -> float:
        return self._buffers[CHANNELS[channel_id].source].latest(channel_id)

    def latest_timestamp(self) -> float:
        """The newest timestamp from any source, or NaN before the first sample."""
        return max((buffer.latest_timestamp() for buffer in self._buffers.values() if len(buffer)), default=math.nan)
