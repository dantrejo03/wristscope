# What works today

Wristscope is still being built. This page lists what each app does now, and what isn't built yet
or is hidden until it is.

## Apple Watch app

| feature                                                                               | status        | notes                                                                                  |
| ------------------------------------------------------------------------------------- | ------------- | -------------------------------------------------------------------------------------- |
| Live session: stream motion data to the iPhone                                        | works         |                                                                                        |
| Accelerometer and device motion (attitude, user acceleration, rotation rate, gravity) | works         |                                                                                        |
| Raw gyroscope                                                                         | not available | Apple Watch doesn't offer it, so none is sent; device motion's rotation rate covers it |
| Sample rates from 10 to 100 Hz                                                        | works         |                                                                                        |
| Arbitrary reference frame                                                             | works         |                                                                                        |
| Corrected, magnetic north and true north reference frames                             | not yet       | hidden in Settings                                                                     |
| Keep streaming with the wrist down                                                    | works         | through a HealthKit workout, saved to Health at the end                                |
| Heart rate, active energy and elapsed time                                            | works         |                                                                                        |
| Rep session: a short recording to upload for review                                   | not yet       | hidden in Settings; no motion data is saved                                            |
| Workout session: a long recording saved on the watch                                  | not yet       | hidden in Settings; no motion data is saved                                            |
| Connection benchmark                                                                  | works         | debug and beta builds only; see [benchmarking](benchmarking.md)                        |

## iPhone app

| feature                                               | status  | notes |
| ----------------------------------------------------- | ------- | ----- |
| Relay the live stream to the computer over USB        | works   |       |
| Show whether the watch and the computer are connected | works   |       |
| Save benchmark logs from the watch in the Files app   | works   |       |
| Receive rep and workout recordings from the watch     | not yet |       |

## Computer app

| feature                                                  | status  | notes                                                       |
| -------------------------------------------------------- | ------- | ----------------------------------------------------------- |
| Live plots of every channel, each one shown or hidden    | works   |                                                             |
| 3D view of the watch, with Calibrate                     | works   |                                                             |
| Simulated watch, no devices needed                       | works   | `wristscope --simulate`                                     |
| Messages lost, gaps and watch restarts in the status bar | works   |                                                             |
| Benchmark tables and figures                             | works   | `tools/benchmark_report.py` and `tools/benchmark_plots.py`  |
| Save a live stream to a file                             | not yet |                                                             |
| Open recordings made on the watch                        | not yet |                                                             |
| Derived signals and filters                              | not yet | the data is in Python, but the app has no place to add them |
| Machine-learning models                                  | not yet | the same                                                    |
