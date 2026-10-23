import math
from pathlib import Path

import pytest

from wristscope.transport.benchmark_log import BenchmarkLog, Event, load, percentile, summarize

# Written by the real Swift BenchmarkLog type (tools/swift_fixtures/main.swift)
LOG = Path(__file__).parent / "fixtures" / "benchmark_log.json"


def test_reads_what_the_swift_code_writes():
    log = load(LOG)
    assert (log.flush_interval, log.sample_rate) == (0.1, 100)
    assert [e.kind for e in log.events] == [
        "sent", "delivered", "sent", "notSent", "notSent", "sent", "delivered", "sent", "failed",
    ]
    assert log.events[0] == Event(100.0, "sent", {"sequence": 0, "bytes": 3480})
    assert log.events[1].fields == {"sequence": 0, "roundTrip": 0.025}
    assert log.events[3].fields == {"reason": "phoneNotReachable"}
    assert log.events[8].fields == {"sequence": 1, "code": 7012}


def test_summary():
    s = summarize(load(LOG))
    assert (s.sent, s.delivered, s.failed, s.unanswered, s.not_sent) == (4, 2, 1, 1, 2)
    assert s.failures == {7012: 1}
    assert s.round_trips == [0.025, 0.031]
    assert s.sizes == [3480, 3480, 3512, 3480]
    assert s.duration == pytest.approx(5.1)
    [(start, length)] = s.out_of_range
    assert (start, length) == (pytest.approx(0.2), pytest.approx(0.2))


def test_out_of_range_at_the_end_is_kept():
    log = BenchmarkLog(0.1, 100, [
        Event(1.0, "sent", {"sequence": 0, "bytes": 10}),
        Event(1.1, "notSent", {"reason": "phoneNotReachable"}),
        Event(1.15, "delivered", {"sequence": 0, "roundTrip": 0.15}),  # a late reply doesn't end it
        Event(1.2, "notSent", {"reason": "phoneNotReachable"}),
    ])
    [(start, length)] = summarize(log).out_of_range
    assert (start, length) == (pytest.approx(0.1), pytest.approx(0.2))


def test_empty_log():
    s = summarize(BenchmarkLog(0.1, 100, []))
    assert (s.sent, s.duration, s.out_of_range) == (0, 0.0, [])


def test_percentile_is_nearest_rank():
    assert percentile([3.0, 1.0, 2.0], 0.5) == 2.0
    assert percentile(list(range(1, 101)), 0.95) == 95
    assert math.isnan(percentile([], 0.5))


def resources(time, cpu, battery, charging=False, thermal=0):
    return Event(time, "resources", {"cpuTime": cpu, "battery": battery, "charging": charging, "thermalState": thermal})


def test_resources():
    log = BenchmarkLog(0.1, 100, [
        resources(0.0, 10.0, 0.90),
        Event(0.5, "sent", {"sequence": 0, "bytes": 10}),
        resources(1800.0, 100.0, 0.85, thermal=1),
        resources(3600.0, 190.0, 0.80),
    ])
    s = summarize(log)
    assert s.cpu_load == pytest.approx(0.05)  # 180 s of CPU over an hour
    assert s.battery_levels == pytest.approx((0.90, 0.80))
    assert s.battery_per_hour == pytest.approx(10.0)
    assert s.thermal_max == 1
    assert s.sent == 1  # readings aren't messages


def test_battery_means_nothing_while_charging():
    s = summarize(BenchmarkLog(0.1, 100, [
        resources(0.0, 1.0, 0.5, charging=True),
        resources(60.0, 2.0, 0.6, charging=True),
    ]))
    assert s.battery_levels is None and math.isnan(s.battery_per_hour)
    assert s.cpu_load == pytest.approx(1 / 60)


def test_unknown_battery_readings_are_skipped():
    s = summarize(BenchmarkLog(0.1, 100, [
        resources(0.0, 1.0, -1.0),
        resources(1800.0, 2.0, 0.95),
        resources(3600.0, 3.0, 0.90),
    ]))
    assert s.battery_levels == pytest.approx((0.95, 0.90))
    assert s.battery_per_hour == pytest.approx(10.0)  # 5 points over the half hour it was known


def test_logs_from_before_readings():
    s = summarize(load(LOG))
    assert math.isnan(s.cpu_load) and s.battery_levels is None and s.thermal_max is None
