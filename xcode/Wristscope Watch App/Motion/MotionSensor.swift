//
//  MotionSensor.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import CoreMotion
import os


extension Motion {
    nonisolated final class Sensor {
        
        private let manager = CMMotionManager()

        /// CMMotionManager only delivers to an OperationQueue. This one runs its operations on
        /// the queue passed to `init`.
        private let handlerQueue = OperationQueue()

        init(deliveringOn queue: DispatchSerialQueue) {
            handlerQueue.name = "com.wristscope.motion.handlers"
            handlerQueue.maxConcurrentOperationCount = 1
            handlerQueue.underlyingQueue = queue
        }

        deinit {
            manager.stopAccelerometerUpdates()
            manager.stopGyroUpdates()
            manager.stopDeviceMotionUpdates()
        }
        
        static func supports(_ frame: CMAttitudeReferenceFrame) -> Bool {
            return CMMotionManager.availableAttitudeReferenceFrames()
                .contains(frame)
        }

        // The handlers are `@Sendable` so a closure written in main-actor code isn't inferred
        // @MainActor; they run on the queue passed to `init`.

        /// Returns whether the updates are running afterwards.
        func startAccelerometer(
            updateInterval: Double,
            handler: @escaping @Sendable (Motion.Reading?, (any Error)?) -> Void
        ) -> Bool {
            guard manager.isAccelerometerAvailable else { return false }
            guard !manager.isAccelerometerActive else {
                AppLog.motion.info("Accelerometer is already running, so the new handler wasn't installed")
                return true
            }

            manager.accelerometerUpdateInterval = updateInterval
            manager.startAccelerometerUpdates(to: handlerQueue) { data, error in
                if let data {
                    handler(.accelerometer(AccelerometerReading(from: data)), error)
                } else {
                    handler(nil, error)
                }
            }
            
            return true
        }

        /// Returns whether the updates are running afterwards.
        func startGyroscope(
            updateInterval: Double,
            handler: @escaping @Sendable (Motion.Reading?, (any Error)?) -> Void
        ) -> Bool {
            guard manager.isGyroAvailable else { return false }
            guard !manager.isGyroActive else {
                AppLog.motion.info("Gyroscope is already running, so the new handler wasn't installed")
                return true
            }

            manager.gyroUpdateInterval = updateInterval
            manager.startGyroUpdates(to: handlerQueue) { data, error in
                if let data {
                    handler(.gyro(GyroReading(from: data)), error)
                } else {
                    handler(nil, error)
                }
            }
            return true
        }

        /// Returns whether the updates are running afterwards.
        func startDeviceMotion(
            updateInterval: Double,
            referenceFrame: CMAttitudeReferenceFrame,
            handler: @escaping @Sendable (Motion.Reading?, (any Error)?) -> Void
        ) -> Bool {
            guard manager.isDeviceMotionAvailable else { return false }
            guard !manager.isDeviceMotionActive else {
                AppLog.motion.info("Device motion is already running, so the new handler wasn't installed")
                return true
            }

            manager.deviceMotionUpdateInterval = updateInterval
            manager.startDeviceMotionUpdates(using: referenceFrame, to: handlerQueue) { motion, error in
                if let motion {
                    handler(.deviceMotion(DeviceMotionReading(from: motion)), error)
                } else {
                    handler(nil, error)
                }
            }
            return true
        }

        func stopAccelerometer() { manager.stopAccelerometerUpdates() }
        func stopGyroscope() { manager.stopGyroUpdates() }
        func stopDeviceMotion() { manager.stopDeviceMotionUpdates() }
    }
}

extension Motion.Sensor {
    nonisolated struct Availability {
        let accelerometer: Bool
        let gyro: Bool
        let deviceMotion: Bool
    }
}

