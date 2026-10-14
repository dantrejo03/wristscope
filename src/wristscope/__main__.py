"""Run the scope with `wristscope` or `python -m wristscope`."""

import argparse
import math

import pyqtgraph as pg

from wristscope.receiver import PORT, WatchFeed
from wristscope.simulator import MOTIONS, Simulator
from wristscope.window import ScopeWindow


def main() -> None:
    parser = argparse.ArgumentParser(description="Real-time oscilloscope for Apple Watch motion data.")
    parser.add_argument("--simulate", action="store_true",
                        help="run a simulated watch instead of listening for the iPhone app")
    parser.add_argument("--port", type=int, default=PORT, help=f"port to listen on (default: {PORT})")
    parser.add_argument("--delay", type=float, default=0.15, metavar="SECONDS",
                        help="how far the traces trail the watch, for smooth scrolling (default: 0.15)")
    parser.add_argument("--motion", choices=MOTIONS, default="wander", help="with --simulate: motion (default: wander)")
    parser.add_argument("--rate", type=float, default=100.0, help="with --simulate: samples per second per source")
    parser.add_argument("--drift", type=float, nargs="?", const=3.0, default=0.0, metavar="DEG_PER_S",
                        help="with --simulate: let the simulated attitude drift about the vertical (default when given: 3°/s), "
                             "to see why recalibrating helps")
    args = parser.parse_args()

    app = pg.mkQApp("Wristscope")
    if args.simulate:
        feed = Simulator(MOTIONS[args.motion], rate=args.rate, drift=math.radians(args.drift))
    else:
        feed = WatchFeed(port=args.port)
        print(f"Waiting for the iPhone app. Type this address into it, or use Find automatically: {feed.ip}:{feed.port}")
    window = ScopeWindow(feed, delay=args.delay)
    window.show()
    app.exec()


if __name__ == "__main__":
    main()
