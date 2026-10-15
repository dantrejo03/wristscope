//
//  MotionSampleBuffer.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import Dispatch
import Foundation
import os


// MARK: - Isolation
//
// `queue` is this actor's executor, so actor-isolated code runs on it. The CoreMotion
// handlers (via an OperationQueue backed by `queue`) and the flush timer also run on it,
// but outside Swift concurrency, so they enter the actor with `assumeIsolated`, which
// traps at runtime if they are not actually on `queue`.

extension Motion {
    actor SampleBuffer {
        
        private let connectivity: WatchConnectivityManager
        
        nonisolated let queue = DispatchSerialQueue(label: "com.wristscope.motion", qos: .userInitiated)

        nonisolated var unownedExecutor: UnownedSerialExecutor {
            queue.asUnownedSerialExecutor()
        }

        private let flushInterval: DispatchTimeInterval = .milliseconds(100)

        private var storage = ContiguousArray<UInt8>()
        private var flushTimer: (any DispatchSourceTimer)?

        init(connectivity: WatchConnectivityManager) {
            self.connectivity = connectivity
            // Covers about 190ms of data
            storage.reserveCapacity(4096)
        }

        deinit {
            flushTimer?.cancel()
        }

        func append(_ record: some WireEncodable) {
            record.write(into: &storage)
        }


        // MARK: Flushing

        /// Callable from any thread. Runs on `queue` in call order with `stopFlushing()`.
        nonisolated func startFlushing() {
            queue.async { self.assumeIsolated { $0.startTimer() } }
        }

        /// Callable from any thread. Stops the timer, then flushes whatever is left.
        nonisolated func stopFlushing() {
            queue.async { self.assumeIsolated { $0.stopTimer() } }
        }

        private func startTimer() {
            guard flushTimer == nil else { return }

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval, leeway: .milliseconds(10))
            timer.setEventHandler { [weak self] in
                self?.assumeIsolated { $0.flush() }
            }
            timer.activate()
            flushTimer = timer
        }

        private func stopTimer() {
            flushTimer?.cancel()
            flushTimer = nil
            flush()
        }

        private func flush() {
            guard !storage.isEmpty else { return }
            
            // Every frame carries the stream header (magic + version), so the receiver can
            // refuse a format it doesn't understand instead of plotting wrong numbers.
            var header = ContiguousArray<UInt8>()
            Format.writeStreamHeader(into: &header)
            var message = Data(capacity: header.count + storage.count)
            message.append(contentsOf: header)
            message.append(contentsOf: storage)
            storage.removeAll(keepingCapacity: true)
            
            let _ = connectivity.sendFrame(message) { error in
                AppLog.connectivity.error("Frame send failed: \(error.localizedDescription)")
            }
        }
    }
}
