# wristscope

A real-time oscilloscope for Apple Watch CoreMotion data.

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
```

## Run

```bash
wristscope                  # listen for the iPhone app on port 9000 (the live watch)
wristscope --simulate       # a simulated watch instead
```

With `--simulate` you can also choose the motion and rate:

```bash
wristscope --simulate --motion swing   # also: wander (default), rest, spin
wristscope --simulate --rate 200       # samples per second per source
wristscope --simulate --drift          # let the attitude drift about the vertical (3°/s, or give a rate)
```

### Using the real watch

1. Start `wristscope`. It prints this computer's address (for example `192.168.1.20:9000`) and
   advertises itself over Bonjour. macOS will ask whether Python may accept incoming
   connections; allow it.
2. In the iPhone app, tap **Find automatically**, or type the address in.
3. The status bar shows `Streaming from …`, plus counts of dropped frames, gaps, out-of-order
   samples and watch restarts if any occur.

### Testing without devices

```bash
wristscope &                                  # in one terminal
python tools/fake_phone.py                    # in another: a fake watch + phone
python tools/fake_phone.py --lose-on-phone 0.1 --lose-on-watch 0.1 --reorder 0.1 --restart-every 15
```

### Wire format

Each message from the phone is a frame: `UInt32 length | UInt32 seq | Float64 phone time`
(big-endian) followed by the watch payload: `"WRSC" | version | (tag | little-endian
doubles)*`. Tag 1 is the accelerometer (4 doubles), 2 the gyro (4), 3 device motion (18);
the first double of each is the timestamp. `src/wristscope/wire.py` and
`Motion/MotionDataTypes.swift` must agree on these.

The 3D view on the right shows the watch turning with its attitude. Below it, set
the wrist and crown to match the watch's Settings → General → Orientation, and
toggle the x/y/z axes. Drag to orbit the camera and scroll to zoom.

**Calibrate** (or press `C`) turns the on-screen watch so it faces the same way as
the real one. Rest your forearm on the desk as if checking the time: display up,
forearm parallel to the computer screen, 12 o'clock pointing at the screen. Only
the facing direction changes, never the tilt, and the recorded data is untouched.
**Reset** undoes it.

## Building the iPhone and watch apps

1. Copy `xcode/Config/Local.xcconfig.template` to `xcode/Config/Local.xcconfig` (git ignores it).
2. Set `DEVELOPMENT_TEAM` to your Apple Developer team ID and `BUNDLE_ID_PREFIX` to something unique to you.
   The apps become `<prefix>.Wristscope` and `<prefix>.Wristscope.watchkitapp`.
3. Open `xcode/Wristscope.xcodeproj` in Xcode and run the Wristscope scheme on your iPhone.

The project targets the latest OS releases, so it needs a current Xcode. The watch app uses
HealthKit for its workout session; if your account can't sign that capability, the build will
fail at signing.

## Repository layout

| path | what |
| --- | --- |
| `src/wristscope/` | the desktop oscilloscope (Python) |
| `tests/` | tests for the Python app |
| `xcode/` | the Xcode project: iPhone app and Watch App that will stream CoreMotion data |
| `tools/` | `fake_phone.py` (test stream) and `convert_watch_model.py` with the source `.glb` it reads |

## Tests

```bash
pytest
```

## Credits

3D model: ["Smart Watch - Apple"](https://sketchfab.com/3d-models/smart-watch-apple-765c09acb5bc4892be94bb3b37d12000) by James Gorman, on Sketchfab, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Changes were made to the original: it was re-oriented, scaled, split into parts and stripped of its textures. See [src/wristscope/assets/README.md](src/wristscope/assets/README.md) for the details.
