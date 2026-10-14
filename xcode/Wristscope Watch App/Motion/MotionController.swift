//
//  MotionController.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import CoreMotion
import Foundation


extension Motion {
    final class Controller {
        
        /// Needs to be nonisolated so that it can be accessed in `deinit`.
        nonisolated(unsafe) private let motionManager = CMMotionManager()

        private let buffer = SampleBuffer(connectivity: WatchConnectivityManager.shared)
        /// CMMotionManager only delivers to an OperationQueue. This one runs its operations on
        /// `buffer.queue`, so the handlers can enter the buffer's isolation.
        private let handlerQueue = OperationQueue()

        private let updateInterval: TimeInterval = 0.01     // 100 Hz
        private let deviceMotionReferenceFrame: CMAttitudeReferenceFrame = .xArbitraryZVertical

        init() {
            handlerQueue.name = "com.wristscope.motion.handlers"
            handlerQueue.maxConcurrentOperationCount = 1
            handlerQueue.underlyingQueue = buffer.queue
        }

        deinit {
            motionManager.stopAccelerometerUpdates()
            motionManager.stopGyroUpdates()
            motionManager.stopDeviceMotionUpdates()
            buffer.stopFlushing()
        }

        /// Returns the sources that are running afterwards. A source is left out when this
        /// device doesn't have it.
        @discardableResult
        func startSensors() -> Set<Source> {
            buffer.startFlushing()
            var active: Set<Source> = []
            if startDeviceMotion() { active.insert(.deviceMotion) }
            if startAccelerometer() { active.insert(.accelerometer) }
            if startGyro() { active.insert(.gyro) }
            return active
        }

        func stopSensors() {
            motionManager.stopAccelerometerUpdates()
            motionManager.stopGyroUpdates()
            motionManager.stopDeviceMotionUpdates()
            buffer.stopFlushing()
        }
        
        /// Returns whether the updates are running afterwards.
        private func startDeviceMotion() -> Bool {
            guard motionManager.isDeviceMotionAvailable else { return false }
            guard !motionManager.isDeviceMotionActive else { return true }
            
            motionManager.deviceMotionUpdateInterval = updateInterval
            // The handlers are `@Sendable` so they aren't inferred @MainActor; they run on `buffer.queue`.
            motionManager.startDeviceMotionUpdates(
                using: deviceMotionReferenceFrame, to: handlerQueue
            ) { @Sendable [buffer] motion, error in
                guard let motion else { return }
                let sample = DeviceMotionSample(from: motion)
                buffer.assumeIsolated { $0.append(sample) }
            }
            return true
        }

        /// Returns whether the updates are running afterwards.
        private func startAccelerometer() -> Bool {
            guard motionManager.isAccelerometerAvailable else { return false }
            guard !motionManager.isAccelerometerActive else { return true }

            motionManager.accelerometerUpdateInterval = updateInterval
            motionManager.startAccelerometerUpdates(to: handlerQueue) { @Sendable [buffer] data, error in
                guard let data else { return }
                let sample = AccelerometerSample(from: data)
                buffer.assumeIsolated { $0.append(sample) }
            }
            return true
        }

        /// Returns whether the updates are running afterwards.
        private func startGyro() -> Bool {
            guard motionManager.isGyroAvailable else { return false }
            guard !motionManager.isGyroActive else { return true }

            motionManager.gyroUpdateInterval = updateInterval
            motionManager.startGyroUpdates(to: handlerQueue) { @Sendable [buffer] data, error in
                guard let data else { return }
                let sample = GyroSample(from: data)
                buffer.assumeIsolated { $0.append(sample) }
            }
            return true
        }
    }
}
