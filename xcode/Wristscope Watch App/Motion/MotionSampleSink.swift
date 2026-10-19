//
//  MotionSampleSink.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/17/26.
//

import Foundation


extension Motion {

    @Motion.Actor
    protocol SampleSink: AnyObject, Sendable {
        
        func openTap()
        func closeTap()
        
        func receive(_ sample: AccelerometerReading)
        func receive(_ sample: GyroReading)
        func receive(_ sample: DeviceMotionReading)
    }
}


extension Motion {

    @Motion.Actor
    final class LiveSink: SampleSink {
        private enum State {
            case open(DispatchSourceTimer)
            case closed
        }
        
        private var state: State = .closed

        private var buffer: ContiguousArray<UInt8>

        private let connectivity: WatchConnectivityManager

        /// Seconds between flushes, whatever the sample rate.
        private let flushInterval: TimeInterval

        /// `nonisolated` so the main actor can create one without awaiting.
        nonisolated init(
            connectivity: WatchConnectivityManager,
            flushInterval: TimeInterval,
            capacity: Int
        ) {
            self.connectivity = connectivity
            self.flushInterval = flushInterval

            var buffer = ContiguousArray<UInt8>()
            buffer.reserveCapacity(capacity)
            self.buffer = buffer
        }

        deinit {
            if case .open(let timer) = state {
                timer.cancel()
            }
        }
        
        func openTap() {
            guard case .closed = state else { return }
            let timer = createTimer()
            state = .open(timer)
        }
        
        func closeTap() {
            guard case .open(let timer) = state else { return }
            timer.cancel()
            state = .closed
            flush()
        }

        func receive(_ sample: AccelerometerReading) {
            
        }

        func receive(_ sample: GyroReading) {
            
        }

        func receive(_ sample: DeviceMotionReading) {
            
        }

        private func flush() {
            guard !buffer.isEmpty else { return }
            connectivity.sendLive(Data(buffer), kind: .live)
            buffer.removeAll(keepingCapacity: true)
        }
        
        
        private func createTimer() -> DispatchSourceTimer {
            let timer = DispatchSource.makeTimerSource(queue: Motion.queue)
            
            // The leeway lets watchOS line this wakeup up with others, which saves battery.
            timer.schedule(
                deadline: .now() + flushInterval,
                repeating: flushInterval,
                leeway: .milliseconds(10)
            )
            
            // `@Sendable` so it isn't inferred `@Motion.Actor`; it runs on `Motion.queue`.
            timer.setEventHandler { @Sendable [weak self] in
                guard let self else { return }
                Motion.Actor.assumeIsolated { self.flush() }
            }
            
            return timer
        }
    }
}
