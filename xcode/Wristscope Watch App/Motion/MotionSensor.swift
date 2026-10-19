//
//  MotionSensor.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import Foundation
import CoreMotion
import os


extension Motion {
    nonisolated final class Sensor {

        private let manager = CMMotionManager()

        /// CMMotionManager only delivers to an OperationQueue. This one runs its operations on
        /// `Motion.queue`, so the handlers can enter `Motion.Actor`.
        private let handlerQueue = OperationQueue()

        init() {
            handlerQueue.name = "com.wristscope.motion.handlers"
            handlerQueue.maxConcurrentOperationCount = 1
            handlerQueue.underlyingQueue = Motion.queue
        }

        deinit {
            manager.stopAccelerometerUpdates()
            manager.stopGyroUpdates()
            manager.stopDeviceMotionUpdates()
        }

        // The CoreMotion handlers are `@Sendable` so they aren't inferred @MainActor; they run
        // on `Motion.queue`.

        /// Returns whether the updates are running afterwards.
        @MainActor
        func startAccelerometer(
            updateInterval: Double,
            handler: @escaping @Motion.Actor (AccelerometerSample) -> Void
        ) -> Bool {
            guard manager.isAccelerometerAvailable else { return false }
            guard !manager.isAccelerometerActive else {
                AppLog.motion.info("Accelerometer is already running, so the new handler wasn't installed")
                return true
            }

            manager.accelerometerUpdateInterval = updateInterval
            manager.startAccelerometerUpdates(to: handlerQueue) { @Sendable data, error in
                guard let data else {
                    AppLog.motion.error("Accelerometer update failed: \(error?.localizedDescription ?? "no data")")
                    return
                }
                let sample = AccelerometerSample(from: data)
                Motion.Actor.assumeIsolated { handler(sample) }
            }

            return true
        }

        /// Returns whether the updates are running afterwards.
        @MainActor
        func startGyroscope(
            updateInterval: Double,
            handler: @escaping @Motion.Actor (GyroSample) -> Void
        ) -> Bool {
            guard manager.isGyroAvailable else { return false }
            guard !manager.isGyroActive else {
                AppLog.motion.info("Gyroscope is already running, so the new handler wasn't installed")
                return true
            }

            manager.gyroUpdateInterval = updateInterval
            manager.startGyroUpdates(to: handlerQueue) { @Sendable data, error in
                guard let data else {
                    AppLog.motion.error("Gyroscope update failed: \(error?.localizedDescription ?? "no data")")
                    return
                }
                let sample = GyroSample(from: data)
                Motion.Actor.assumeIsolated { handler(sample) }
            }

            return true
        }

        /// Returns whether the updates are running afterwards.
        @MainActor
        func startDeviceMotion(
            updateInterval: Double,
            referenceFrame: CMAttitudeReferenceFrame,
            handler: @escaping @Motion.Actor (DeviceMotionSample) -> Void
        ) -> Bool {
            guard manager.isDeviceMotionAvailable else { return false }
            guard !manager.isDeviceMotionActive else {
                AppLog.motion.info("Device motion is already running, so the new handler wasn't installed")
                return true
            }

            manager.deviceMotionUpdateInterval = updateInterval
            manager.startDeviceMotionUpdates(using: referenceFrame, to: handlerQueue) { @Sendable data, error in
                guard let data else {
                    AppLog.motion.error("Device motion update failed: \(error?.localizedDescription ?? "no data")")
                    return
                }
                let sample = DeviceMotionSample(from: data)
                Motion.Actor.assumeIsolated { handler(sample) }
            }

            return true
        }

        @MainActor
        func stopAccelerometer() { manager.stopAccelerometerUpdates() }
        @MainActor
        func stopGyroscope() { manager.stopGyroUpdates() }
        @MainActor
        func stopDeviceMotion() { manager.stopDeviceMotionUpdates() }
    }
}
