# Benchmarking the watch connection

This page explains how to record and analyse a benchmark of the link between the watch and the
iPhone.

In a debug build of the watch app, Settings › Debug › Benchmark logs what happens to every live
message: when it was handed to WatchConnectivity, how long the phone took to reply, or why it
failed or wasn't sent. When the workout ends, the log goes to the iPhone, which saves it in
Files › On My iPhone › Wristscope. Copy the files to this computer (AirDrop works) and run:

```bash
python tools/benchmark_report.py benchmark-*.json            # one row per run, sorted by flush interval
python tools/benchmark_report.py --detail benchmark-*.json   # also failures and out-of-range stretches
```

The log also notes the app's CPU time, the battery level and the thermal state every 5 seconds,
which the report shows as `cpu %`, `batt %/h` and `heat`. Take the watch off its charger and run for
30 minutes or more, since the battery level moves in coarse steps.

To draw figures from the logs (matplotlib comes with the `dev` extras):

```bash
python tools/benchmark_plots.py --out figures benchmark-*.json
```
