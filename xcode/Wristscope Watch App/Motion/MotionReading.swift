//
//  MotionReading.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/19/26.
//

import Foundation
import CoreMotion


// Copies of CoreMotion's data classes, which tests can't build. They carry every field and
// decide nothing about the wire format; the formatter picks what gets sent.
//
// Each `init(from:)` is in an extension so the memberwise init stays, for tests.

extension Motion {
    
    nonisolated enum Reading {
        case accelerometer(AccelerometerReading)
        case gyro(GyroReading)
        case deviceMotion(DeviceMotionReading)
    }

    nonisolated struct AccelerometerReading: Sendable {
        let timestamp: TimeInterval
        let acceleration: CMAcceleration
    }


    nonisolated struct GyroReading: Sendable {
        let timestamp: TimeInterval
        let rotationRate: CMRotationRate
    }


    nonisolated struct DeviceMotionReading: Sendable {
        let timestamp: TimeInterval
        /// Roll, pitch, yaw and the rotation matrix can all be worked out from the quaternion.
        let attitude: CMQuaternion
        let rotationRate: CMRotationRate
        let userAcceleration: CMAcceleration
        let gravity: CMAcceleration
        let magneticField: CMCalibratedMagneticField
        let heading: Double
        let sensorLocation: CMDeviceMotion.SensorLocation
    }
}


extension Motion.AccelerometerReading {
    nonisolated init(from data: CMAccelerometerData) {
        self.init(timestamp: data.timestamp, acceleration: data.acceleration)
    }
}


extension Motion.GyroReading {
    nonisolated init(from data: CMGyroData) {
        self.init(timestamp: data.timestamp, rotationRate: data.rotationRate)
    }
}


extension Motion.DeviceMotionReading {
    nonisolated init(from motion: CMDeviceMotion) {
        self.init(
            timestamp: motion.timestamp,
            attitude: motion.attitude.quaternion,
            rotationRate: motion.rotationRate,
            userAcceleration: motion.userAcceleration,
            gravity: motion.gravity,
            magneticField: motion.magneticField,
            heading: motion.heading,
            sensorLocation: motion.sensorLocation
        )
    }
}
