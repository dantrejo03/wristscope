"""A fake iPhone + watch for testing the desktop app without devices.

Runs the simulator, encodes its samples the way the watch does, wraps them the
way the phone does and sends a frame every 100 ms. Like the phone app, it listens
on port 9000 and the desktop app connects to it; run that with
`wristscope --phone localhost`.

    python tools/fake_phone.py                       # clean stream on localhost:9000
    python tools/fake_phone.py --lose-on-phone 0.1   # phone drops 10% of frames (phone sequence gaps)
    python tools/fake_phone.py --lose-in-transit 0.1 # WatchConnectivity loses 10% (watch sequence gaps)
    python tools/fake_phone.py --lose-on-watch 0.1   # watch out of range for 10% (only timestamp gaps show it)
    python tools/fake_phone.py --reorder 0.1         # swaps 10% of frames with the next one
    python tools/fake_phone.py --restart-every 15    # watch and phone app restart every 15 s
"""

import argparse
import random
import socket
import time

from wristscope.feeds.simulator import MOTIONS, Simulator
from wristscope.transport.wire import encode_frame, encode_payload

FRAME_INTERVAL = 0.1


def probability(text: str) -> float:
    value = float(text)
    if not 0 <= value <= 1:
        raise argparse.ArgumentTypeError("must be between 0 and 1")
    return value


def listen(host: str, port: int) -> socket.socket:
    server = socket.create_server((host, port))
    server.setblocking(False)  # so checking for the receiver never stops the frames
    print(f"listening on {host}:{port}")
    return server


def accept(server: socket.socket) -> socket.socket | None:
    """The receiver's connection, if it has connected since the last check. The newest wins, as on the phone."""
    try:
        sock, address = server.accept()
    except BlockingIOError:
        return None
    sock.setblocking(True)
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    print(f"receiver connected from {address[0]}")
    return sock


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=9000)
    parser.add_argument("--motion", choices=MOTIONS, default="wander")
    parser.add_argument("--rate", type=float, default=100.0)
    parser.add_argument("--lose-on-phone", type=probability, default=0.0, metavar="P")
    parser.add_argument("--lose-in-transit", type=probability, default=0.0, metavar="P")
    parser.add_argument("--lose-on-watch", type=probability, default=0.0, metavar="P")
    parser.add_argument("--reorder", type=probability, default=0.0, metavar="P")
    parser.add_argument("--restart-every", type=float, default=0.0, metavar="SECONDS")
    args = parser.parse_args()

    def new_watch() -> Simulator:
        return Simulator(MOTIONS[args.motion], rate=args.rate, seed=random.randrange(1 << 30))

    watch = new_watch()
    server = listen(args.host, args.port)
    sock: socket.socket | None = None
    seq = 0  # the phone's, one per frame
    watch_seq = 0  # the watch's, one per message WatchConnectivity takes
    started = time.monotonic()
    held: bytes | None = None  # a frame being delayed past its successor
    next_send = time.monotonic()
    try:
        while True:
            next_send += FRAME_INTERVAL
            time.sleep(max(0.0, next_send - time.monotonic()))
            if args.restart_every and time.monotonic() - started > args.restart_every:
                watch, seq, watch_seq, started, held = new_watch(), 0, 0, time.monotonic(), None
                print("restarted")

            newest = accept(server)
            if newest is not None:
                if sock is not None:
                    sock.close()
                sock = newest

            samples = watch.poll()
            if not samples or random.random() < args.lose_on_watch:
                continue  # out of range: the watch never sent it, so it used no number
            payload = encode_payload(samples, watch_seq)
            watch_seq += 1
            if random.random() < args.lose_in_transit:
                continue  # WatchConnectivity took it but never delivered it, so the phone never numbers it
            frame = encode_frame(payload, seq, time.time())
            seq += 1
            if sock is None or random.random() < args.lose_on_phone:
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
                sock = None
    except KeyboardInterrupt:
        pass
    finally:
        server.close()


if __name__ == "__main__":
    main()
