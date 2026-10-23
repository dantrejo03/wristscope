//
//  ConnectivityBenchmark.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/20/26.
//

import Foundation
import Synchronization
import WatchKit
import os


/// Logs what happened to every live message, for picking the flush interval and finding how far
/// the watch can be from the phone. Every few seconds it also notes the app's CPU time, the
/// battery level and the thermal state, for what streaming costs the watch. Only made when
/// benchmarking is on in debug settings.
///
/// The log stays in memory until `finish()` writes it to a file and sends that to the phone.
/// WatchConnectivity calls the reply and error handlers on its own queue, so the log sits behind
/// a lock instead of on an actor: nothing waits for a hop, so the round trips don't include one.
nonisolated final class ConnectivityBenchmark: Sendable {

    private let connectivity: WatchConnectivityManager
    private let flushInterval: TimeInterval
    private let sampleRate: Int

    private let entries = Mutex<[BenchmarkLog.Entry]>([])

    /// Notes CPU time, battery and thermal state until `finish()` cancels it.
    private let resourceMonitor = Mutex<Task<Void, Never>?>(nil)

    init(connectivity: WatchConnectivityManager, flushInterval: TimeInterval, sampleRate: Int) {
        self.connectivity = connectivity
        self.flushInterval = flushInterval
        self.sampleRate = sampleRate
        startMonitoringResources()
    }

    /// Seconds since the watch booted. CoreMotion stamps readings with this clock, so the log's
    /// times line up with the samples'.
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func record(_ event: BenchmarkLog.Event, at time: TimeInterval = ConnectivityBenchmark.now) {
        entries.withLock { $0.append(BenchmarkLog.Entry(time: time, event: event)) }
    }
}


// MARK: - Logging

extension ConnectivityBenchmark {

    /// Logs a message WatchConnectivity took.
    nonisolated func sent(_ sequence: UInt32, bytes: Int) {
        record(.sent(sequence: sequence, bytes: bytes))
    }

    /// Logs a message `sendMessage` refused before trying.
    nonisolated func notSent(_ error: any Error) {
        record(.notSent(reason: String(describing: error)))
    }

    /// Make this just before sending: the round trip is timed from here.
    nonisolated func replyHandler(for sequence: UInt32) -> @Sendable (Data) -> Void {
        let sentAt = Self.now
        return { [self] _ in
            let now = Self.now
            record(.delivered(sequence: sequence, roundTrip: now - sentAt), at: now)
        }
    }

    nonisolated func errorHandler(for sequence: UInt32) -> @Sendable (any Error) -> Void {
        return { [self] error in
            record(.failed(sequence: sequence, code: (error as NSError).code))
        }
    }
}


// MARK: - CPU, battery and heat

extension ConnectivityBenchmark {

    /// How often CPU time, battery and thermal state are noted.
    nonisolated private static let resourceInterval: Duration = .seconds(5)

    /// Notes the app's CPU time, the battery level and the thermal state now and then every
    /// `resourceInterval`, until `finish()` or until nothing holds the benchmark any more.
    ///
    /// The battery level moves in coarse steps, so a run needs 30 minutes or more off the charger
    /// for it to say much. The CPU time is this app's alone: the WatchConnectivity and Bluetooth
    /// work happens in system processes, which only the battery level sees.
    nonisolated private func startMonitoringResources() {
        let task = Task { @MainActor [weak self] in
            let device = WKInterfaceDevice.current()
            device.isBatteryMonitoringEnabled = true
            while !Task.isCancelled, let self {
                self.record(.resources(
                    cpuTime: ConnectivityBenchmark.cpuTime,
                    battery: device.batteryLevel,
                    charging: device.batteryState == .charging || device.batteryState == .full,
                    thermalState: ProcessInfo.processInfo.thermalState.rawValue
                ))
                try? await Task.sleep(for: ConnectivityBenchmark.resourceInterval)
            }
        }
        resourceMonitor.withLock { $0 = task }
    }

    /// User plus system CPU time this process has used since it launched, in seconds.
    nonisolated private static var cpuTime: TimeInterval {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ time: timeval) -> TimeInterval {
            TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000
        }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }
}


// MARK: - Sending the log

extension ConnectivityBenchmark {

    /// Stops the CPU and battery readings, writes the log to a file and queues it for the phone.
    /// A message still waiting on its reply when this runs shows up as sent, with no outcome.
    nonisolated func finish() {
        resourceMonitor.withLock { $0?.cancel(); $0 = nil }
        let log = BenchmarkLog(
            flushInterval: flushInterval,
            sampleRate: sampleRate,
            entries: entries.withLock { $0 }
        )
        let name = "benchmark-\(Int(Date.now.timeIntervalSince1970)).json"
        let url = URL.temporaryDirectory.appending(path: name)
        do {
            try log.write(to: url)
            try connectivity.transferFile(url, metadata: BenchmarkLog.metadata)
        } catch {
            AppLog.connectivity.error("Sending the benchmark log failed: \(error.localizedDescription)")
        }
    }
}
