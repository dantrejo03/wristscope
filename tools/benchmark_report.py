"""Sums up the benchmark logs the watch sends, one row per file, so runs line up.

Turn on Settings › Debug › Benchmark in a debug build of the watch app. When a workout ends, the
log goes to the iPhone, which keeps it in Files › On My iPhone › Wristscope. Copy the files to
this computer (AirDrop works) and run:

    python tools/benchmark_report.py benchmark-*.json
    python tools/benchmark_report.py --detail benchmark-*.json   # failures and out-of-range stretches too

Rows are sorted by flush interval. Round trips are from the watch handing a message over to the
phone's reply arriving, in milliseconds. "cpu %" is this app's share of one core, "batt %/h" is
battery used per hour (blank if the watch was charging) and "heat" is the hottest thermal state.
Logs from before these were recorded show "-" for all three.
"""

import argparse
import math
from pathlib import Path

from wristscope.transport.benchmark_log import ERROR_NAMES, THERMAL_NAMES, Summary, load, percentile, summarize

HEADER = ["file", "flush ms", "Hz", "minutes", "sent", "delivered", "failed", "no reply", "not sent",
          "rtt p50", "p95", "max", "bytes p50", "cpu %", "batt %/h", "heat"]


def row(path: Path, s: Summary) -> list[str]:
    def ms(seconds: float) -> str:
        return "-" if math.isnan(seconds) else f"{seconds * 1000:.0f}"

    def tenths(value: float) -> str:
        return "-" if math.isnan(value) else f"{value:.1f}"

    return [
        path.name,
        f"{s.flush_interval * 1000:.0f}",
        str(s.sample_rate),
        f"{s.duration / 60:.1f}",
        str(s.sent),
        f"{s.delivered / s.sent:.1%}" if s.sent else "-",
        str(s.failed),
        str(s.unanswered),
        str(s.not_sent),
        ms(percentile(s.round_trips, 0.5)),
        ms(percentile(s.round_trips, 0.95)),
        ms(max(s.round_trips, default=math.nan)),
        f"{percentile(s.sizes, 0.5):.0f}" if s.sizes else "-",
        tenths(s.cpu_load * 100),
        tenths(s.battery_per_hour),
        THERMAL_NAMES.get(s.thermal_max, "-") if s.thermal_max is not None else "-",
    ]


def print_table(rows: list[list[str]]) -> None:
    """The first column left-aligned, the numbers right-aligned."""
    widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
    for r in rows:
        cells = [r[0].ljust(widths[0])] + [cell.rjust(width) for cell, width in zip(r[1:], widths[1:])]
        print("  ".join(cells))


def print_detail(path: Path, s: Summary) -> None:
    print(f"\n{path.name}")
    for code, count in sorted(s.failures.items()):
        print(f"  failed: {ERROR_NAMES.get(code, 'unknown')} ({code}) ×{count}")
    if s.out_of_range:
        longest = max(length for _, length in s.out_of_range)
        print(f"  out of range: {len(s.out_of_range)} stretches, longest {longest:.1f} s")
        for start, length in s.out_of_range:
            print(f"    at {start:.1f} s for {length:.1f} s")
    if not s.failures and not s.out_of_range:
        print("  no failures, never out of range")
    if s.battery_levels is not None:
        start, end = s.battery_levels
        print(f"  battery: {start:.0%} to {end:.0%}")
    elif s.thermal_max is not None:
        print("  battery: unknown, or the watch was charging")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logs", nargs="+", type=Path, metavar="LOG")
    parser.add_argument("--detail", action="store_true", help="also list failures and out-of-range stretches")
    args = parser.parse_args()

    summaries = [(path, summarize(load(path))) for path in args.logs]
    summaries.sort(key=lambda item: (item[1].flush_interval, item[0].name))
    print_table([HEADER] + [row(path, s) for path, s in summaries])
    if args.detail:
        for path, s in summaries:
            print_detail(path, s)


if __name__ == "__main__":
    main()
