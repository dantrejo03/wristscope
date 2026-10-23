//
//  MotionReadingConversion.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/20/26.
//

import Foundation
import CoreMotion


// Watch only: the phone never sees a Reading. Each Reading becomes one Record, so every sample
// in it shares that reading's timestamp.

extension Motion.SampleFormatter {

    nonisolated static func record(from reading: Motion.Reading) -> Motion.Record {
        switch reading {
        case .accelerometer(let reading): record(from: reading)
        case .gyro(let reading): record(from: reading)
        case .deviceMotion(let reading): record(from: reading)
        }
    }

    nonisolated static func record(from reading: Motion.AccelerometerReading) -> Motion.Record {
        Motion.Record(
            timestamp: reading.timestamp,
            samples: [.rawAcceleration(vector(from: reading.acceleration))]
        )
    }

    nonisolated static func record(from reading: Motion.GyroReading) -> Motion.Record {
        Motion.Record(
            timestamp: reading.timestamp,
            samples: [.rawGyro(vector(from: reading.rotationRate))]
        )
    }

    nonisolated static func record(from reading: Motion.DeviceMotionReading) -> Motion.Record {
        Motion.Record(
            timestamp: reading.timestamp,
            samples: [
                .attitude(vector(from: reading.attitude)),
                .userAcceleration(vector(from: reading.userAcceleration)),
                .rotationRate(vector(from: reading.rotationRate)),
                .gravity(vector(from: reading.gravity)),
            ]
        )
    }

    /// Bytes for one record from each sensor. It mirrors the conversions above, so change them
    /// together.
    nonisolated static var bytesPerRound: Int {
        let vector3 = byteSize(of: Motion.Vector3.self)
        let vector4 = byteSize(of: Motion.Vector4.self)
        let accelerometer = vector3
        let gyro = vector3
        let deviceMotion = vector4 + 3 * vector3
        return accelerometer + gyro + deviceMotion
    }
}


// MARK: - CoreMotion values

extension Motion.SampleFormatter {
    nonisolated private static func vector(from acceleration: CMAcceleration) -> Motion.Vector3 {
        Motion.Vector3(x: acceleration.x, y: acceleration.y, z: acceleration.z)
    }

    nonisolated private static func vector(from rotationRate: CMRotationRate) -> Motion.Vector3 {
        Motion.Vector3(x: rotationRate.x, y: rotationRate.y, z: rotationRate.z)
    }

    nonisolated private static func vector(from quaternion: CMQuaternion) -> Motion.Vector4 {
        Motion.Vector4(w: quaternion.w, x: quaternion.x, y: quaternion.y, z: quaternion.z)
    }
}
