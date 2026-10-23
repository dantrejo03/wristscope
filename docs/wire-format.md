# Wire format

Each message from the phone is a frame, big-endian: `UInt32 length | UInt32 seq | Float64 phone
time`. Its payload is little-endian: `"WRSC" | version 2 | UInt32 watch seq | record…`, and each
record is `tag | Float64 timestamp | Float64 value…`:

| tag | measurement              | values  |
| --- | ------------------------ | ------- |
| 1   | raw acceleration         | x y z   |
| 2   | user acceleration        | x y z   |
| 3   | raw rotation rate (gyro) | x y z   |
| 4   | rotation rate            | x y z   |
| 5   | attitude quaternion      | w x y z |
| 6   | gravity                  | x y z   |

One sensor event becomes several records with the same timestamp, which the receiver joins back
into one sample. The phone's seq counts the frames it sends; the watch seq counts the messages
WatchConnectivity took, so the status bar can tell where a message was lost.

[`wristscope/transport/wire.py`](../wristscope/transport/wire.py) must agree with `Motion.Sample` in
[`xcode/Shared/Motion/MotionTypes.swift`](../xcode/Shared/Motion/MotionTypes.swift),
`SampleFormatter.swift` beside it, and the phone's `ComputerFormatter`. The tests check against
bytes the Swift code wrote: after changing the format, rerun `tools/swift_fixtures/generate.sh`.
