"""A fake iPhone + watch for testing the desktop app without devices.

Runs the simulator, encodes its samples the way the watch does, wraps them the
way the phone does and sends a frame every 100 ms to the receiver.

    python tools/fake_phone.py                     # clean stream to localhost:9000
    python tools/fake_phone.py --lose-on-phone 0.1 # phone drops 10% of frames (sequence gaps)
    python tools/fake_phone.py --lose-on-watch 0.1 # watch drops 10% (only timestamp gaps show it)
    python tools/fake_phone.py --reorder 0.1       # swaps 10% of frames with the next one
    python tools/fake_phone.py --restart-every 15  # watch and phone app restart every 15 s
"""

import argparse
import random
import socket
import time

from wristscope.simulator import MOTIONS, Simulator
from wristscope.wire import encode_frame, encode_records

FRAME_INTERVAL = 0.1


def probability(text: str) -> float:
    value = float(text)
    if not 0 <= value <= 1:
        raise argparse.ArgumentTypeError("must be between 0 and 1")
    return value


def connect(host: str, port: int) -> socket.socket:
    while True:
        try:
            sock = socket.create_connection((host, port), timeout=2)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            print(f"connected to {host}:{port}")
            return sock
        except OSError as error:
            print(f"can't reach {host}:{port} ({error}), retrying")
            time.sleep(1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=9000)
    parser.add_argument("--motion", choices=MOTIONS, default="wander")
    parser.add_argument("--rate", type=float, default=100.0)
    parser.add_argument("--lose-on-phone", type=probability, default=0.0, metavar="P")
    parser.add_argument("--lose-on-watch", type=probability, default=0.0, metavar="P")
    parser.add_argument("--reorder", type=probability, default=0.0, metavar="P")
    parser.add_argument("--restart-every", type=float, default=0.0, metavar="SECONDS")
    args = parser.parse_args()

    def new_watch() -> Simulator:
        return Simulator(MOTIONS[args.motion], rate=args.rate, seed=random.randrange(1 << 30))

    watch = new_watch()
    sock = connect(args.host, args.port)
    seq = 0
    started = time.monotonic()
    held: bytes | None = None  # a frame being delayed past its successor
    next_send = time.monotonic()
    try:
        while True:
            next_send += FRAME_INTERVAL
            time.sleep(max(0.0, next_send - time.monotonic()))
            if args.restart_every and time.monotonic() - started > args.restart_every:
                watch, seq, started, held = new_watch(), 0, time.monotonic(), None
                print("restarted")

            samples = watch.poll()
            if not samples or random.random() < args.lose_on_watch:
                continue  # the watch never sent it, so the phone never numbers it
            frame = encode_frame(encode_records(samples), seq, time.time())
            seq += 1
            if random.random() < args.lose_on_phone:
                continue  # the phone numbered it, then dropped it
            if held is not None:
                out, held = [frame, held], None
            elif random.random() < args.reorder:
                held, out = frame, []
            else:
                out = [frame]
            try:
                for data in out:
                    sock.sendall(data)
            except OSError:
                print("connection lost")
                sock.close()
                sock = connect(args.host, args.port)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
