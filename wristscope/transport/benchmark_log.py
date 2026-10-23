"""Reads the benchmark logs the watch sends after a session with benchmarking on, and sums them up.

The watch writes them with Swift's JSONEncoder from `BenchmarkLog` in
xcode/Shared/WatchConnectivity/TransferModels.swift, so the keys here are that type's property and
case names. Each event is an object with one key, its case name, holding the case's values:

    {"time": 5321.07, "event": {"delivered": {"sequence": 0, "roundTrip": 0.031}}}

Times are seconds since the watch booted, the clock the samples' timestamps use.
tests/fixtures/benchmark_log.json was written by that Swift type, to catch drift.
"""

import json
import math
from dataclasses import dataclass
from pathlib import Path

# WCError.Code raw values, from WatchConnectivity's WCError.h
ERROR_NAMES = {
    7001: "genericError",
    7002: "sessionNotSupported",
    7003: "sessionMissingDelegate",
    7004: "sessionNotActivated",
    7005: "deviceNotPaired",
    7006: "watchAppNotInstalled",
    7007: "notReachable",
    7008: "invalidParameter",
    7009: "payloadTooLarge",
    7010: "payloadUnsupportedTypes",
    7011: "messageReplyFailed",
    7012: "messageReplyTimedOut",
    7013: "fileAccessDenied",
    7014: "deliveryFailed",
    7015: "insufficientSpace",
    7016: "sessionInactive",
    7017: "transferTimedOut",
    7018: "companionAppNotInstalled",
    7019: "watchOnlyApp",
}

# ProcessInfo.ThermalState raw values
THERMAL_NAMES = {0: "nominal", 1: "fair", 2: "serious", 3: "critical"}


@dataclass(frozen=True)
class Event:
    time: float
    kind: str  # the Swift case: "sent", "delivered", "failed", "notSent" or "resources"
    fields: dict  # the case's values, such as {"sequence": 0, "roundTrip": 0.031}


@dataclass(frozen=True)
class BenchmarkLog:
    flush_interval: float  # seconds between messages
    sample_rate: int  # readings per second from each sensor
    events: list[Event]


def load(path: str | Path) -> BenchmarkLog:
    data = json.loads(Path(path).read_text())
    events = []
    for entry in data["entries"]:
        [(kind, fields)] = entry["event"].items()  # exactly one key, so this fails loudly otherwise
        events.append(Event(entry["time"], kind, fields))
    return BenchmarkLog(data["flushInterval"], data["sampleRate"], events)


@dataclass(frozen=True)
class Summary:
    flush_interval: float
    sample_rate: int
    duration: float  # seconds from the first event to the last
    sent: int  # messages WatchConnectivity took
    delivered: int  # of those, the ones the phone replied to
    failures: dict[int, int]  # WCError code -> how many messages WatchConnectivity gave up on with it
    unanswered: int  # sent, but neither replied to nor failed, such as one still in flight at the end
    not_sent: int  # flushes refused before sending, because the phone couldn't be reached
    round_trips: list[float]  # seconds, in the order the replies came
    sizes: list[int]  # bytes of each message sent
    out_of_range: list[tuple[float, float]]  # (start, length) in seconds; start counts from the first event
    cpu_load: float  # this app's CPU time over the time between the first and last reading; 0.05 is 5% of one core
    battery_levels: tuple[float, float] | None  # (first, last) level read, 0 to 1; None if unknown or ever charging
    battery_per_hour: float  # percentage points of battery used per hour; NaN when battery_levels is None
    thermal_max: int | None  # the hottest ProcessInfo.ThermalState read; None in logs without readings

    @property
    def failed(self) -> int:
        return sum(self.failures.values())


def summarize(log: BenchmarkLog) -> Summary:
    sizes: dict[int, int] = {}  # sequence -> bytes
    answered: set[int] = set()
    failures: dict[int, int] = {}
    round_trips: list[float] = []
    out_of_range: list[tuple[float, float]] = []
    not_sent = 0
    readings: list[Event] = []  # the "resources" events
    first = log.events[0].time if log.events else 0.0
    stretch: tuple[float, float] | None = None  # (first, last) refusal of the stretch under way

    def end_stretch() -> None:
        # Refusals come once per flush, so the last one stands for a whole flush interval.
        if stretch is not None:
            start, last = stretch
            out_of_range.append((start - first, last - start + log.flush_interval))

    for event in log.events:
        if event.kind == "notSent":
            not_sent += 1
            stretch = (event.time if stretch is None else stretch[0], event.time)
            continue
        if event.kind == "sent":
            end_stretch()  # only a send ends a stretch; a late reply to an earlier message doesn't
            stretch = None
            sizes[event.fields["sequence"]] = event.fields["bytes"]
        elif event.kind == "delivered":
            answered.add(event.fields["sequence"])
            round_trips.append(event.fields["roundTrip"])
        elif event.kind == "failed":
            answered.add(event.fields["sequence"])
            code = event.fields["code"]
            failures[code] = failures.get(code, 0) + 1
        elif event.kind == "resources":
            readings.append(event)
    end_stretch()
    cpu_load, battery_levels, battery_per_hour, thermal_max = _resources(readings)

    return Summary(
        flush_interval=log.flush_interval,
        sample_rate=log.sample_rate,
        duration=log.events[-1].time - first if log.events else 0.0,
        sent=len(sizes),
        delivered=len(round_trips),
        failures=failures,
        unanswered=len(sizes.keys() - answered),
        not_sent=not_sent,
        round_trips=round_trips,
        sizes=list(sizes.values()),
        out_of_range=out_of_range,
        cpu_load=cpu_load,
        battery_levels=battery_levels,
        battery_per_hour=battery_per_hour,
        thermal_max=thermal_max,
    )


def _resources(readings: list[Event]) -> tuple[float, tuple[float, float] | None, float, int | None]:
    """CPU load, battery levels, battery used per hour and the hottest thermal state, from the
    "resources" readings. CPU load and battery use need two readings some time apart, and battery
    use means nothing if the watch was on its charger at any point."""
    if not readings:
        return math.nan, None, math.nan, None
    first, last = readings[0], readings[-1]
    span = last.time - first.time
    cpu_load = (last.fields["cpuTime"] - first.fields["cpuTime"]) / span if span > 0 else math.nan

    known = [r for r in readings if r.fields["battery"] >= 0]  # -1 means the watch didn't say
    charging = any(r.fields["charging"] for r in readings)
    levels = None if charging or not known else (known[0].fields["battery"], known[-1].fields["battery"])
    hours = (known[-1].time - known[0].time) / 3600 if known else 0.0
    per_hour = (levels[0] - levels[1]) * 100 / hours if levels is not None and hours > 0 else math.nan

    return cpu_load, levels, per_hour, max(r.fields["thermalState"] for r in readings)


def percentile(values: list[float], fraction: float) -> float:
    """The value `fraction` of the way through `values` once sorted (nearest rank), or NaN if
    there are none. A fraction of 0.5 gives the median, or the lower middle value of an even count."""
    if not values:
        return math.nan
    ordered = sorted(values)
    return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]
