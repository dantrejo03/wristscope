//
//  TransferModels.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/20/26.
//

import Foundation


// MARK: - Benchmark log

/// What the watch sends with `transferFile` after a session with benchmarking on: what
/// happened to every live message, as JSON.
nonisolated struct BenchmarkLog: Codable, Sendable {
    /// Seconds between flushes, so between messages.
    let flushInterval: TimeInterval
    /// Readings per second from each sensor.
    let sampleRate: Int
    let entries: [Entry]

    /// The file transfer's metadata, so the phone can tell this file from others.
    static let metadata = ["kind": "benchmarkLog"]
}

extension BenchmarkLog {
    nonisolated struct Entry: Codable, Sendable {
        /// Seconds since the watch booted, the clock the samples' timestamps use.
        let time: TimeInterval
        let event: Event
    }

    nonisolated enum Event: Codable, Sendable {
        /// Handed to WatchConnectivity.
        case sent(sequence: UInt32, bytes: Int)
        /// The phone replied, `roundTrip` seconds after the message was handed over.
        case delivered(sequence: UInt32, roundTrip: TimeInterval)
        /// WatchConnectivity gave up on it. `code` is a `WCError.Code` raw value.
        case failed(sequence: UInt32, code: Int)
        /// Never handed to WatchConnectivity, so its sequence number went to the next message.
        /// `reason` names the `WatchSessionError`.
        case notSent(reason: String)
        /// Read every few seconds. `cpuTime` is the seconds of CPU this app has used since it
        /// launched, `battery` runs from 0 to 1 (-1 when unknown), and `thermalState` is a
        /// `ProcessInfo.ThermalState` raw value, from 0 (nominal) to 3 (critical).
        case resources(cpuTime: TimeInterval, battery: Float, charging: Bool, thermalState: Int)
    }
}

extension BenchmarkLog {
    /// Writes the JSON `JSONEncoder` makes of this log with sorted keys, one entry at a time.
    /// Encoding the whole log at once first builds a copy about 20 times its size, enough to get
    /// a watch app killed after a long session. This holds about one chunk however long it runs.
    ///
    /// The top-level keys are written by hand, so tools/swift_fixtures checks the output against
    /// `JSONEncoder`'s each time it runs.
    nonisolated func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        try Data().write(to: url)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }

        let chunkSize = 64 * 1024
        var chunk = Data()
        func append(_ data: Data) throws {
            chunk.append(data)
            if chunk.count >= chunkSize {
                try file.write(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }

        try append(Data(#"{"entries":["#.utf8))
        for (index, entry) in entries.enumerated() {
            if index > 0 { try append(Data(",".utf8)) }
            try append(encoder.encode(entry))
        }
        try append(Data(#"],"flushInterval":"#.utf8))
        try append(encoder.encode(flushInterval))
        try append(Data(#","sampleRate":"#.utf8))
        try append(encoder.encode(sampleRate))
        try append(Data("}".utf8))
        try file.write(contentsOf: chunk)
    }
}
