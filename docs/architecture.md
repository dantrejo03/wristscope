# Repository layout

| path                                   | what                                                                                       |
| -------------------------------------- | ------------------------------------------------------------------------------------------ |
| [`wristscope/`](../wristscope)         | the desktop oscilloscope (Python)                                                          |
| [`tests/`](../tests)                   | tests for the Python app                                                                   |
| [`xcode/`](../xcode)                   | the Xcode project: iPhone app and Watch App that will stream CoreMotion data               |
| [`tools/`](../tools)                   | `fake_phone.py` (test stream), `benchmark_report.py` and `benchmark_plots.py` (benchmark tables and figures), `swift_fixtures/` (rebuilds the test fixtures from the Swift code) and `convert_watch_model.py` with the source `.glb` it reads |
| [`docs/`](.)                           | the documentation, including the connection benchmark report and its figures              |

See also the [wire format](wire-format.md) between the phone and the computer.
