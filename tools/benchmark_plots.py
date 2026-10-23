"""Draws the figures in docs/benchmark-report.md from the benchmark logs the watch sends.

    pip install matplotlib
    python tools/benchmark_plots.py --out docs/figures benchmarks/"Phase 0"/*.json benchmarks/"Phase 1"/*.json

Runs are grouped by flush interval. Each figure is written twice, for light and dark pages
(round-trips.png and round-trips-dark.png, and so on), and the report shows whichever matches the
reader's theme. The CPU and battery figure is drawn only when some of the logs have readings in
them, which logs from before the "resources" event was added don't.
"""

import argparse
import math
from dataclasses import dataclass
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

from wristscope.transport.benchmark_log import Summary, load, percentile, summarize  # noqa: E402

# Colors from a palette checked for colorblind readers in both themes. Series 1 and 2 are the only
# data colors; everything else is ink and chrome.
THEMES = {
    "light": {
        "surface": "#fcfcfb", "ink": "#0b0b0b", "secondary": "#52514e", "muted": "#898781",
        "grid": "#e1e0d9", "axis": "#c3c2b7", "series1": "#2a78d6", "series2": "#eb6834",
    },
    "dark": {
        "surface": "#1a1a19", "ink": "#f0efec", "secondary": "#c3c2b7", "muted": "#898781",
        "grid": "#2c2c2a", "axis": "#383835", "series1": "#3987e5", "series2": "#d95926",
    },
}

SLOW = 1.0  # seconds; a round trip over this counts towards a stall
STALL_GAP = 5.0  # seconds; slow messages sent closer together than this belong to one stall


@dataclass
class Run:
    path: Path
    summary: Summary
    sends: list[float]  # seconds from the first event, for each message that got a reply
    round_trips: list[float]  # seconds, in the same order as `sends`
    in_flight: list[tuple[float, int]]  # (time, messages waiting on a reply) after each change


@dataclass
class Stall:
    start: float  # when the first slow message was sent, from the first event
    end: float  # when the last slow message's reply came
    slow: int  # messages over SLOW
    worst: float  # the longest round trip, seconds
    most_in_flight: int  # the most messages waiting on a reply at once


def read(path: Path) -> Run:
    log = load(path)
    first = log.events[0].time if log.events else 0.0
    sends, trips, changes = [], [], []
    for event in log.events:
        if event.kind == "sent":
            changes.append((event.time - first, +1))
        elif event.kind == "delivered":
            trip = event.fields["roundTrip"]
            sends.append(event.time - first - trip)
            trips.append(trip)
            changes.append((event.time - first, -1))
        elif event.kind == "failed":
            changes.append((event.time - first, -1))
    waiting, in_flight = 0, []
    for time, change in sorted(changes):
        waiting += change
        in_flight.append((time, waiting))
    return Run(path, summarize(log), sends, trips, in_flight)


def stalls(run: Run) -> list[Stall]:
    found: list[Stall] = []
    for sent, trip in zip(run.sends, run.round_trips):
        if trip <= SLOW:
            continue
        if found and sent - found[-1].start <= (found[-1].end - found[-1].start) + STALL_GAP:
            stall = found[-1]
            stall.end, stall.slow, stall.worst = max(stall.end, sent + trip), stall.slow + 1, max(stall.worst, trip)
        else:
            found.append(Stall(sent, sent + trip, 1, trip, 0))
    for stall in found:
        stall.most_in_flight = max((n for t, n in run.in_flight if stall.start <= t <= stall.end), default=0)
    return found


def flush_label(seconds: float) -> str:
    return f"{seconds:g} s" if seconds >= 1 else f"{seconds * 1000:.0f} ms"


def by_flush(runs: list[Run]) -> dict[float, list[Run]]:
    groups: dict[float, list[Run]] = {}
    for run in sorted(runs, key=lambda r: (r.summary.flush_interval, r.path.name)):
        groups.setdefault(run.summary.flush_interval, []).append(run)
    return groups


# MARK: - Drawing


def style(theme: dict) -> None:
    plt.rcParams.update({
        "font.family": "sans-serif",
        "font.sans-serif": ["SF Pro Text", "Helvetica Neue", "Helvetica", "Arial", "DejaVu Sans"],
        "font.size": 10,
        "text.color": theme["ink"],
        "axes.facecolor": theme["surface"],
        "figure.facecolor": theme["surface"],
        "axes.edgecolor": theme["axis"],
        "axes.labelcolor": theme["secondary"],
        "xtick.color": theme["muted"],
        "ytick.color": theme["muted"],
        "xtick.labelcolor": theme["secondary"],
        "ytick.labelcolor": theme["secondary"],
        "axes.grid": True,
        "axes.grid.axis": "y",
        "grid.color": theme["grid"],
        "grid.linewidth": 0.8,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.spines.left": False,
        "axes.axisbelow": True,
        "legend.frameon": False,
        "legend.labelcolor": theme["secondary"],
    })


def heading(fig, title: str, subtitle: str, theme: dict) -> None:
    fig.text(0.012, 0.985, title, ha="left", va="top", fontsize=13, weight="semibold", color=theme["ink"])
    fig.text(0.012, 0.935, subtitle, ha="left", va="top", fontsize=10, color=theme["secondary"])


def round_trips(groups: dict[float, list[Run]], theme: dict):
    """One bar per run: the middle 90% of its round trips, with a dot at the median."""
    fig, ax = plt.subplots(figsize=(8, 4.2))
    fig.subplots_adjust(left=0.09, right=0.98, top=0.8, bottom=0.16)
    ticks, labels, x, top = [], [], 0.0, 0.0
    for flush, runs in groups.items():
        positions = [x + i * 0.45 for i in range(len(runs))]
        for pos, run in zip(positions, runs):
            ms = [t * 1000 for t in run.round_trips]
            low, mid, high = percentile(ms, 0.05), percentile(ms, 0.5), percentile(ms, 0.95)
            top = max(top, high)
            ax.vlines(pos, low, high, color=theme["series1"], linewidth=5, capstyle="round", alpha=0.35)
            ax.scatter([pos], [mid], s=46, color=theme["series1"], edgecolors=theme["surface"], linewidths=2, zorder=3)
        ticks.append(sum(positions) / len(positions))
        runs_note = f"\n{len(runs)} runs" if len(runs) > 1 else ""
        labels.append(flush_label(flush) + runs_note)
        x = positions[-1] + 1.0
    ax.set_xticks(ticks, labels)
    ax.tick_params(axis="x", length=0, pad=8)
    ax.tick_params(axis="y", length=0)
    ax.set_xlim(-0.6, x - 0.4)
    ax.set_ylim(0, math.ceil((top + 50) / 100) * 100)
    ax.set_ylabel("Round trip (ms)")
    ax.set_xlabel("Flush interval", labelpad=8)
    heading(fig, "The typical round trip barely changes with the flush interval",
            "Dot: median. Bar: the middle 90% of round trips. One bar per 10-minute run.", theme)
    return fig


def sample_age(groups: dict[float, list[Run]], theme: dict):
    """How old a sample is when it reaches the phone, split into waiting and sending."""
    fig, ax = plt.subplots(figsize=(8, 4.2))
    fig.subplots_adjust(left=0.09, right=0.8, top=0.8, bottom=0.16)
    xs = list(range(len(groups)))
    waits, sends = [], []
    for flush, runs in groups.items():
        pooled = [t for run in runs for t in run.round_trips]
        waits.append(flush / 2 * 1000)  # a sample waits half an interval for the flush, on average
        sends.append(percentile(pooled, 0.5) / 2 * 1000)  # about half the median round trip
    width = 0.42
    ax.bar(xs, waits, width, color=theme["series1"], edgecolor=theme["surface"], linewidth=2,
           label="Waiting for the next flush")
    ax.bar(xs, sends, width, bottom=waits, color=theme["series2"], edgecolor=theme["surface"], linewidth=2,
           label="Getting to the phone")
    for x, wait, send in zip(xs, waits, sends):
        ax.text(x, wait + send + 12, f"~{wait + send:.0f} ms", ha="center", va="bottom", fontsize=10,
                color=theme["ink"])
    last = xs[-1]
    ax.text(last + width / 2 + 0.08, waits[-1] / 2, "Waiting for\nthe next flush", va="center", fontsize=9,
            color=theme["secondary"])
    ax.text(last + width / 2 + 0.08, waits[-1] + sends[-1] / 2, "Getting to\nthe phone", va="center", fontsize=9,
            color=theme["secondary"])
    ax.set_xticks(xs, [flush_label(f) for f in groups])
    ax.tick_params(axis="x", length=0, pad=8)
    ax.tick_params(axis="y", length=0)
    ax.set_ylim(0, math.ceil((max(w + s for w, s in zip(waits, sends)) + 80) / 100) * 100)
    ax.set_ylabel("Age when it reaches the phone (ms)")
    ax.set_xlabel("Flush interval", labelpad=8)
    ax.legend(loc="upper left", fontsize=9)
    heading(fig, "Above 200 ms, waiting for the flush is most of the delay",
            "Estimated: half the flush interval, plus half the median round trip.", theme)
    return fig


def timelines(groups: dict[float, list[Run]], theme: dict):
    """Every message's round trip by when it was sent, one run per flush interval."""
    chosen = [runs[0] for runs in groups.values()]
    fig, axes = plt.subplots(len(chosen), 1, figsize=(8, 1.25 * len(chosen) + 1.3), sharex=True, sharey=True)
    axes = list(axes) if len(chosen) > 1 else [axes]
    fig.subplots_adjust(left=0.1, right=0.98, top=1 - 1.0 / (1.25 * len(chosen) + 1.3), bottom=0.09, hspace=0.35)
    worst_run, worst_stall = None, None
    for run in chosen:
        for stall in stalls(run):
            if worst_stall is None or stall.end - stall.start > worst_stall.end - worst_stall.start:
                worst_run, worst_stall = run, stall
    top = max(max(run.round_trips, default=0) for run in chosen)
    for ax, run in zip(axes, chosen):
        minutes = [t / 60 for t in run.sends]
        ax.plot(minutes, run.round_trips, color=theme["series1"], linewidth=1.1, solid_joinstyle="round")
        repeat = len(groups[run.summary.flush_interval])
        note = f" (run 1 of {repeat})" if repeat > 1 else ""
        ax.text(0.0, 1.04, flush_label(run.summary.flush_interval) + note, transform=ax.transAxes,
                ha="left", va="bottom", fontsize=9, weight="semibold", color=theme["ink"])
        ax.set_ylim(0, math.ceil(top + 0.5))
        ax.set_yticks([0, 5] if top > 6 else [0, math.ceil(top / 2)])
        ax.tick_params(length=0)
        if run is worst_run and worst_stall is not None:
            length = worst_stall.end - worst_stall.start
            ax.annotate(
                f"{length:.0f} s stall: {worst_stall.most_in_flight} messages waiting at once,\n"
                f"worst {worst_stall.worst:.1f} s, none lost",
                xy=(worst_stall.start / 60 + length / 120, worst_stall.worst),
                xytext=(0.52, 0.55), textcoords="axes fraction", fontsize=9, color=theme["ink"],
                arrowprops={"arrowstyle": "-", "color": theme["muted"], "linewidth": 0.8},
            )
    axes[len(axes) // 2].set_ylabel("Round trip (s)")
    axes[-1].set_xlabel("Minutes into the run")
    heading(fig, "Slow round trips come in stalls, not scattered jitter",
            "Each message's round trip, plotted at the time it was sent.", theme)
    return fig


def resources(groups: dict[float, list[Run]], theme: dict):
    """CPU and battery for the runs that have readings, as two charts side by side."""
    rows = [(flush, run) for flush, runs in groups.items() for run in runs if run.summary.thermal_max is not None]
    if not rows:
        return None
    fig, (cpu, battery) = plt.subplots(1, 2, figsize=(8, 3.8))
    fig.subplots_adjust(left=0.08, right=0.98, top=0.76, bottom=0.17, wspace=0.3)
    labels = [flush_label(flush) for flush, _ in rows]
    xs = list(range(len(rows)))
    for ax, values, unit, name in (
        (cpu, [run.summary.cpu_load * 100 for _, run in rows], "%", "App CPU (% of one core)"),
        (battery, [run.summary.battery_per_hour for _, run in rows], "%", "Battery used per hour (%)"),
    ):
        shown = [v if not math.isnan(v) else 0 for v in values]
        ax.bar(xs, shown, 0.42, color=theme["series1"])
        for x, value in zip(xs, values):
            text = "n/a" if math.isnan(value) else f"{value:.1f}{unit}"
            ax.text(x, (0 if math.isnan(value) else value), text, ha="center", va="bottom", fontsize=10,
                    color=theme["ink"])
        ax.set_xticks(xs, labels)
        ax.set_title(name, loc="left", fontsize=10, color=theme["secondary"])
        ax.tick_params(length=0)
        ax.set_ylim(0, max(shown) * 1.25 if max(shown) > 0 else 1)
        ax.set_xlabel("Flush interval", labelpad=6)
    heading(fig, "What streaming costs the watch",
            "Battery covers everything the watch does; CPU covers this app only, not the system's radio work.", theme)
    return fig


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logs", nargs="+", type=Path, metavar="LOG")
    parser.add_argument("--out", type=Path, default=Path("docs/figures"), help="where to write the PNGs")
    args = parser.parse_args()

    groups = by_flush([read(path) for path in args.logs])
    args.out.mkdir(parents=True, exist_ok=True)
    for name, theme in THEMES.items():
        style(theme)
        suffix = "" if name == "light" else "-dark"
        for stem, draw in (("round-trips", round_trips), ("sample-age", sample_age),
                           ("stalls", timelines), ("watch-cost", resources)):
            fig = draw(groups, theme)
            if fig is None:
                continue
            path = args.out / f"{stem}{suffix}.png"
            fig.savefig(path, dpi=200, facecolor=theme["surface"])
            plt.close(fig)
            print(f"wrote {path}")


if __name__ == "__main__":
    main()
