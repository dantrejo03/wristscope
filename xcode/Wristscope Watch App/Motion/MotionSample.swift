//
//  MotionSample.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/16/26.
//

import Foundation
import CoreMotion
import os


// `nonisolated` so the CoreMotion handlers can build these on `Motion.queue`.

nonisolated struct AccelerometerSample: Sendable {
    let timestamp: Double
    
    let x: Double
    let y: Double
    let z: Double
    
    init(from data: CMAccelerometerData) {
        self.timestamp = data.timestamp
        self.x = data.acceleration.x
        self.y = data.acceleration.y
        self.z = data.acceleration.z
    }
}


nonisolated struct GyroSample: Sendable {
    let timestamp: Double
    
    let x: Double
    let y: Double
    let z: Double
    
    init(from data: CMGyroData) {
        self.timestamp = data.timestamp
        self.x = data.rotationRate.x
        self.y = data.rotationRate.y
        self.z = data.rotationRate.z
    }
}


nonisolated struct DeviceMotionSample: Sendable {
    let timestamp: Double
    
    let attW: Double
    let attX: Double
    let attY: Double
    let attZ: Double
    
    let accX: Double
    let accY: Double
    let accZ: Double
    
    let rotX: Double
    let rotY: Double
    let rotZ: Double
    
    let gX: Double
    let gY: Double
    let gZ: Double
    
    let magX: Double
    let magY: Double
    let magZ: Double
    
    let heading: Double
    
    init(from motion: CMDeviceMotion) {
        timestamp = motion.timestamp
        
        attW = motion.attitude.quaternion.w
        attX = motion.attitude.quaternion.x
        attY = motion.attitude.quaternion.y
        attZ = motion.attitude.quaternion.z
        
        rotX = motion.rotationRate.x
        rotY = motion.rotationRate.y
        rotZ = motion.rotationRate.z
        
        accX = motion.userAcceleration.x
        accY = motion.userAcceleration.y
        accZ = motion.userAcceleration.z
        
        gX = motion.gravity.x
        gY = motion.gravity.y
        gZ = motion.gravity.z
        
        magX = motion.magneticField.field.x
        magY = motion.magneticField.field.y
        magZ = motion.magneticField.field.z
        
        heading = motion.heading
    }
}


extension Motion {
    
    final class SampleFormatter {
        
        // Each function appends one record straight onto `buffer`: a 1-byte tag
        // (1 = accelerometer, 2 = gyro, 3 = device motion), then the sample's
        // fields in declaration order, each a Double as 8 bytes, little-endian.
        // The buffer is never grown: if the record doesn't fit in the capacity
        // that's left, it's logged and dropped.

        /// Bytes in the largest record: device motion's tag and 18 Doubles.
        nonisolated static let largestRecordBytes = 1 + 18 * 8

        /// Bytes one second of records takes with all three sensors at 100 Hz, the fastest
        /// `SampleRate`. One record from each is 33 + 33 + 145 = 211 bytes.
        nonisolated static let maxBytesPerSecond = 100 * (2 * (1 + 4 * 8) + largestRecordBytes)
        
        @Motion.Actor
        static func append(
            _ sample: AccelerometerSample, to buffer: inout ContiguousArray<UInt8>
        ) {
            guard hasRoom(for: 4, in: buffer, name: "accelerometer") else { return }
            buffer.append(1)
            append(sample.timestamp, to: &buffer)
            append(sample.x, to: &buffer)
            append(sample.y, to: &buffer)
            append(sample.z, to: &buffer)
        }
        
        @Motion.Actor
        static func append(
            _ sample: GyroSample, to buffer: inout ContiguousArray<UInt8>
        ) {
            guard hasRoom(for: 4, in: buffer, name: "gyro") else { return }
            buffer.append(2)
            append(sample.timestamp, to: &buffer)
            append(sample.x, to: &buffer)
            append(sample.y, to: &buffer)
            append(sample.z, to: &buffer)
        }
        
        @Motion.Actor
        static func append(
            _ sample: DeviceMotionSample, to buffer: inout ContiguousArray<UInt8>
        ) {
            guard hasRoom(for: 18, in: buffer, name: "device motion") else { return }
            buffer.append(3)
            append(sample.timestamp, to: &buffer)
            append(sample.attW, to: &buffer)
            append(sample.attX, to: &buffer)
            append(sample.attY, to: &buffer)
            append(sample.attZ, to: &buffer)
            append(sample.accX, to: &buffer)
            append(sample.accY, to: &buffer)
            append(sample.accZ, to: &buffer)
            append(sample.rotX, to: &buffer)
            append(sample.rotY, to: &buffer)
            append(sample.rotZ, to: &buffer)
            append(sample.gX, to: &buffer)
            append(sample.gY, to: &buffer)
            append(sample.gZ, to: &buffer)
            append(sample.magX, to: &buffer)
            append(sample.magY, to: &buffer)
            append(sample.magZ, to: &buffer)
            append(sample.heading, to: &buffer)
        }
        
        /// `doubleCount` fields of 8 bytes, plus the 1-byte tag.
        @Motion.Actor
        private static func hasRoom(
            for doubleCount: Int, in buffer: ContiguousArray<UInt8>, name: String
        ) -> Bool {
            let needed = 1 + doubleCount * MemoryLayout<Double>.size
            let remaining = buffer.capacity - buffer.count
            guard remaining >= needed else {
                AppLog.motion.error("Buffer full, dropping \(name) sample (need \(needed) bytes, have \(remaining))")
                return false
            }
            return true
        }
        
        @Motion.Actor
        private static func append(_ value: Double, to buffer: inout ContiguousArray<UInt8>) {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { buffer.append(contentsOf: $0) }
        }
    }
}
