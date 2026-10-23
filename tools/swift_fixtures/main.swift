// Writes the test fixtures that pin the Python side to the Swift formats, using the real Swift
// types and formatters:
//
//     tests/fixtures/live_payload.bin    a payload as the phone sends it to the computer
//     tests/fixtures/benchmark_log.json  a benchmark log as the watch writes it
//
// Rerun after changing either format: tools/swift_fixtures/generate.sh
//
// tests/test_wire.py and tests/test_benchmark_log.py expect exactly these values, so change them
// together.

import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)


// MARK: - Live payload

// One sensor event from each sensor, in the order MotionReadingConversion.swift builds them.
let events = [
    Motion.Record(timestamp: 1000.25, samples: [
        .attitude(Vector4(w: 0.5, x: -0.5, y: 0.25, z: -0.25)),
        .userAcceleration(Vector3(x: 0.125, y: -0.125, z: 1.5)),
        .rotationRate(Vector3(x: 2.0, y: -2.0, z: 0.75)),
        .gravity(Vector3(x: 0.0, y: -0.5, z: -1.0)),
    ]),
    Motion.Record(timestamp: 1000.5, samples: [.rawAcceleration(Vector3(x: 0.1, y: 0.2, z: -0.98))]),
    Motion.Record(timestamp: 1000.75, samples: [.rawGyro(Vector3(x: -0.3, y: 0.4, z: 0.05))]),
]

// The watch, as `Motion.LiveSink.flush()` sends it.
var buffer = ContiguousArray<UInt8>()
for event in events {
    Motion.SampleFormatter.unsafeAppend(event, to: &buffer)
}
var message = MessageFormatter.liveHeader(41)
message.append(contentsOf: buffer)

// The phone, as `ViewModel.relay` passes it on.
let sequence = MessageFormatter.liveSequence(of: message)!
let payload = ComputerFormatter.payload(
    watchSequence: sequence,
    records: message.dropFirst(MessageFormatter.liveHeaderSize)
)
try payload.write(to: output.appending(path: "live_payload.bin"))


// MARK: - Benchmark log

// Message 1 is sent, then the phone goes out of reach for two flushes, and its reply times out
// later. Message 3 is still waiting on its reply when the log is written.
let log = BenchmarkLog(flushInterval: 0.1, sampleRate: 100, entries: [
    .init(time: 100.0, event: .sent(sequence: 0, bytes: 3480)),
    .init(time: 100.025, event: .delivered(sequence: 0, roundTrip: 0.025)),
    .init(time: 100.1, event: .sent(sequence: 1, bytes: 3480)),
    .init(time: 100.2, event: .notSent(reason: "phoneNotReachable")),
    .init(time: 100.3, event: .notSent(reason: "phoneNotReachable")),
    .init(time: 100.4, event: .sent(sequence: 2, bytes: 3512)),
    .init(time: 100.431, event: .delivered(sequence: 2, roundTrip: 0.031)),
    .init(time: 100.5, event: .sent(sequence: 3, bytes: 3480)),
    .init(time: 105.1, event: .failed(sequence: 1, code: 7012)),
])

// Written the way `ConnectivityBenchmark.finish()` writes it. `write(to:)` spells out the top-level
// keys itself, so check it still matches what JSONEncoder makes of the whole type.
let logURL = output.appending(path: "benchmark_log.json")
try log.write(to: logURL)
let encoder = JSONEncoder()
encoder.outputFormatting = .sortedKeys
guard try Data(contentsOf: logURL) == encoder.encode(log) else {
    FileHandle.standardError.write(Data("BenchmarkLog.write(to:) no longer matches JSONEncoder\n".utf8))
    exit(1)
}
