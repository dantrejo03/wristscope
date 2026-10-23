# Getting started

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

## Run

```bash
wristscope                  # connect to the iPhone app over USB (the live watch)
wristscope --simulate       # a simulated watch instead
```

With `--simulate` you can also choose the motion and rate:

```bash
wristscope --simulate --motion swing   # also: wander (default), rest, spin
wristscope --simulate --rate 200       # samples per second per source
wristscope --simulate --drift          # let the attitude drift about the vertical (3°/s, or give a rate)
```

## Using the real watch

You need the iPhone and watch apps installed first: see [building the apps](building-the-apps.md).

1. Plug the iPhone into this computer with a cable. If it asks whether to trust the computer,
   tap **Trust**.
2. Open Wristscope on the iPhone, and start `wristscope`. Either can go first: `wristscope`
   keeps trying until the app answers, and the status bar says what it is waiting for.
3. The status bar shows `Streaming from iPhone over USB`, plus counts of messages lost between
   the watch and the iPhone or between the iPhone and the computer, gaps, out-of-order samples
   and watch restarts if any occur.

The iPhone app listens on port 9000 and `wristscope` connects to it through usbmuxd, the macOS
service Xcode and Finder use to reach a plugged-in iPhone
([`wristscope/transport/usbmux.py`](../wristscope/transport/usbmux.py)).
The watch still reaches the iPhone wirelessly; only the iPhone-to-computer hop is wired.

## Testing without devices

```bash
python tools/fake_phone.py &                  # in one terminal: a fake watch + phone on localhost:9000
wristscope --phone localhost                  # in another: connect to it over TCP instead of USB
python tools/fake_phone.py --lose-on-phone 0.1 --lose-in-transit 0.1 --lose-on-watch 0.1 --reorder 0.1 --restart-every 15
```

## The 3D view

The 3D view on the right shows the watch turning with its attitude. Below it, set
the wrist and crown to match the watch's Settings → General → Orientation, and
toggle the x/y/z axes. Drag to orbit the camera and scroll to zoom.

**Calibrate** (or press `C`) turns the on-screen watch so it faces the same way as
the real one. Rest your forearm on the desk as if checking the time: display up,
forearm parallel to the computer screen, 12 o'clock pointing at the screen. Only
the facing direction changes, never the tilt, and the recorded data is untouched.
**Reset** undoes it.
