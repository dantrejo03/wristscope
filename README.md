# wristscope

[![CI](https://github.com/dantrejo03/wristscope/actions/workflows/ci.yml/badge.svg)](https://github.com/dantrejo03/wristscope/actions/workflows/ci.yml)

An oscilloscope for Apple Watch CoreMotion data.

![A watch rotating slowly on a wrist, next to the Wristscope window showing the plots and the 3D watch following it](docs/media/slow_rotation.gif)

Wristscope lets you see what your Apple Watch's sensors are doing. It records motion data on the watch, or streams it live through your iPhone to a computer running the Python visualizer. There you can view it as time-series signals or as a 3D model of the watch moving in real time. Because the data lands on your computer, you can go further: derive your own signals, apply filters, or plug in machine-learning models to experiment with what the sensors can tell you.


Not all of this is built yet. See [what works today](docs/status.md) for a chart of what's built and what isn't.

## What you need

- **An Apple Watch** paired with an iPhone. It is the sensor source.
- **An iPhone** running the Wristscope app. It relays the watch's data to your computer.
- **A computer with Python 3.11 or newer** that can reach the iPhone, over a USB cable.
- **A Mac with Xcode**, to build and install the watch and iPhone apps. You only need it for that
  step; the visualizer itself doesn't depend on it.

The apps target iOS and watchOS 26.5.

## Quick start

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"
wristscope --simulate       # a simulated watch, no devices needed
```

To use the real watch, [build the apps](docs/building-the-apps.md), then follow
[getting started](docs/getting-started.md).

## Documentation

| page                                           | what's in it                                                                  |
| ---------------------------------------------- | ----------------------------------------------------------------------------- |
| [What works today](docs/status.md)             | which features are built and which aren't yet                                 |
| [Getting started](docs/getting-started.md)     | install, run, simulate, use the real watch, test without devices, the 3D view |
| [Building the apps](docs/building-the-apps.md) | signing and installing the iPhone and watch apps with Xcode                   |
| [Benchmarking](docs/benchmarking.md)           | record and analyse your own connection benchmarks                             |
| [Wire format](docs/wire-format.md)             | the bytes sent from the iPhone to the computer                                |
| [Repository layout](docs/architecture.md)      | what lives where                                                              |

## Tests

```bash
pytest
```

## Credits

3D model: ["Smart Watch - Apple"](https://sketchfab.com/3d-models/smart-watch-apple-765c09acb5bc4892be94bb3b37d12000) by James Gorman, on Sketchfab, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Changes were made to the original: it was re-oriented, scaled, split into parts and stripped of its textures. See [wristscope/watch3d/assets/README.md](wristscope/watch3d/assets/README.md) for the details.
