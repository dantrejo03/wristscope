//
//  MotionSampleSink.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/17/26.
//

import Foundation
import os


extension Motion {

    @Motion.Actor
    protocol SampleSink: AnyObject, Sendable {
        /// Called when the sensors start. A few samples can arrive just before it.
        func start()
        /// Called when the sensors stop.
        func stop()
        func receive(_ sample: AccelerometerSample)
        func receive(_ sample: GyroSample)
        func receive(_ sample: DeviceMotionSample)
    }
}


extension Motion {

    @Motion.Actor
    final class LiveSink: SampleSink {

        private var buffer: ContiguousArray<UInt8>

        private let connectivity: WatchConnectivityManager

        private var flushCount: UInt32 = 0

        /// Seconds between flushes, whatever the sample rate.
        private let flushInterval: TimeInterval

        /// Fires on `Motion.queue` while the sensors run. Nil when stopped.
        private var timer: DispatchSourceTimer?

        /// `nonisolated` so the main actor can create one without awaiting.
        nonisolated init(
            connectivity: WatchConnectivityManager,
            flushInterval: TimeInterval = 0.1
        ) {
            self.connectivity = connectivity
            self.flushInterval = flushInterval

            // Room for 4 intervals at the fastest rate, so a late tick doesn't drop samples.
            var buffer = ContiguousArray<UInt8>()
            buffer.reserveCapacity(
                Int((Double(SampleFormatter.maxBytesPerSecond) * flushInterval * 4).rounded(.up))
            )
            self.buffer = buffer
        }

        deinit {
            timer?.cancel()
        }

        func start() {
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: Motion.queue)
            // The leeway lets watchOS line this wakeup up with others, which saves battery.
            timer.schedule(
                deadline: .now() + flushInterval, repeating: flushInterval, leeway: .milliseconds(10)
            )
            // `@Sendable` so it isn't inferred `@Motion.Actor`; it runs on `Motion.queue`.
            timer.setEventHandler { @Sendable [weak self] in
                guard let self else { return }
                Motion.Actor.assumeIsolated { self.flush() }
            }
            timer.resume()
            self.timer = timer
        }

        /// Sends whatever is left, so the last partial interval isn't lost.
        func stop() {
            timer?.cancel()
            timer = nil
            flush()
        }

        func receive(_ sample: AccelerometerSample) {
            SampleFormatter.append(sample, to: &buffer)
        }

        func receive(_ sample: GyroSample) {
            SampleFormatter.append(sample, to: &buffer)
        }

        func receive(_ sample: DeviceMotionSample) {
            SampleFormatter.append(sample, to: &buffer)
        }

        private func flush() {
            // Nothing arrived this interval. Skipping leaves no gap in `flushCount`.
            guard !buffer.isEmpty else { return }

            var data = Data()
            data.reserveCapacity(MemoryLayout<UInt32>.size + buffer.count)

            withUnsafeBytes(of: flushCount.littleEndian) { data.append(contentsOf: $0) }
            data.append(contentsOf: buffer)

            connectivity.sendLive(data, kind: .live) { error in
                AppLog.connectivity.error("Frame send failed: \(error.localizedDescription, privacy: .public)")
            }
            buffer.removeAll(keepingCapacity: true)
            flushCount &+= 1
        }

    }
}
