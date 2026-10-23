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
        
        func openTap()
        func closeTap()
        
        func receive(_ reading: Motion.Reading)
    }
}


extension Motion {

    @Motion.Actor
    final class LiveSink: SampleSink {
        typealias Formatter = Motion.SampleFormatter
        
        private enum State {
            case open(DispatchSourceTimer)
            case closed
        }
        
        private var state: State = .closed

        private var buffer: ContiguousArray<UInt8>

        private let connectivity: WatchConnectivityManager

        /// Seconds between flushes, whatever the sample rate.
        private let flushInterval: TimeInterval
        
        /// The next message's. Goes up only once WatchConnectivity takes a message, so a gap the
        /// phone sees is a message that was sent and lost.
        private var sequenceNumber: UInt32 = 0

        /// Nil unless benchmarking is on. Supplies the reply and error handlers when it isn't.
        private let benchmark: ConnectivityBenchmark?

        /// `nonisolated` so the main actor can create one without awaiting.
        nonisolated init(
            connectivity: WatchConnectivityManager,
            flushInterval: TimeInterval,
            capacity: Int,
            benchmark: ConnectivityBenchmark?
        ) {
            self.connectivity = connectivity
            self.flushInterval = flushInterval
            self.benchmark = benchmark

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
        
        func receive(_ reading: Motion.Reading) {
            let record = Formatter.record(from: reading)

            let difference = Formatter.hasRoom(in: buffer, for: record)
            if difference >= 0 {
                Formatter.unsafeAppend(record, to: &buffer)
            } else {
                AppLog.motion.error("Buffer full, dropping a record (\(-difference) bytes short)")
            }
        }

        private func flush() {
            guard !buffer.isEmpty else { return }
            var data = MessageFormatter.liveHeader(sequenceNumber)
            data.append(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)

            do {
                try connectivity.sendMessage(
                    data,
                    onReply: benchmark?.replyHandler(for: sequenceNumber),
                    onError: benchmark?.errorHandler(for: sequenceNumber)
                )
            } catch {
                // Never sent, so the next message reuses this number.
                benchmark?.notSent(error)
                return
            }
            benchmark?.sent(sequenceNumber, bytes: data.count)
            sequenceNumber &+= 1
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

            // Timers start inactive. One that's never activated never fires, and releasing it
            // crashes.
            timer.activate()
            return timer
        }
    }
}
