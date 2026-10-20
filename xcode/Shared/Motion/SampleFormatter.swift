//
//  SampleFormatter.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/19/26.
//

import Foundation
import CoreMotion


extension Motion {
    nonisolated enum SampleFormatter {
        
        static let version: UInt8 = 1
        
        
        
        
        

        
       
    }
}

// MARK: - Motion Samples

extension Motion.SampleFormatter {
    
    /// 8 bytes for each Double: the timestamp and the sample's values.
    nonisolated static func byteSize(from tag: Motion.SampleTag) -> Int {
        let doubles = switch tag {
        case .accelerometer: 4
        case .gyro: 4
        case .deviceMotion: 14
        }
        return doubles * MemoryLayout<Double>.size
    }
    
    nonisolated static func hasRoom(
        in buffer: ContiguousArray<UInt8>,
        for sample: Motion.SampleTag
    ) -> Int {
        let needed = 1 + byteSize(from: sample) // the 1 is for the tag
        let remaining = buffer.capacity - buffer.count
        return remaining - needed
    }
    
    nonisolated static func unsafePackageBytes(
        from sample: any Motion.Sample, to buffer: inout ContiguousArray<UInt8>
    ) {
        // The tag fixes the type, so these casts can't fail.
        switch sample.tag {
        case .accelerometer: unsafePackageBytes(from: sample as! AccelerometerSample, to: &buffer)
        case .gyro: unsafePackageBytes(from: sample as! GyroSample, to: &buffer)
        case .deviceMotion: unsafePackageBytes(from: sample as! DeviceMotionSample, to: &buffer)
        }
    }
    
    nonisolated static func unsafePackageBytes(
        from sample: AccelerometerSample, to buffer: inout ContiguousArray<UInt8>
    ) {
        buffer.append(Motion.SampleTag.accelerometer.rawValue)
        append(sample.timestamp, to: &buffer)
        append(sample.x, to: &buffer)
        append(sample.y, to: &buffer)
        append(sample.z, to: &buffer)
    }
    
    nonisolated static func unsafePackageBytes(
        from sample: GyroSample, to buffer: inout ContiguousArray<UInt8>
    ) {
        buffer.append(Motion.SampleTag.gyro.rawValue)
        append(sample.timestamp, to: &buffer)
        append(sample.x, to: &buffer)
        append(sample.y, to: &buffer)
        append(sample.z, to: &buffer)
    }
    
    nonisolated static func unsafePackageBytes(
        from sample: DeviceMotionSample, to buffer: inout ContiguousArray<UInt8>
    ) {
        buffer.append(Motion.SampleTag.deviceMotion.rawValue)
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
    }
    
    nonisolated private static func append(_ value: Double, to buffer: inout ContiguousArray<UInt8>) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { buffer.append(contentsOf: $0) }
    }
}

// MARK: - Watch extensions

#if os(watchOS)
extension Motion.SampleFormatter {
    nonisolated static func sample(from reading: Motion.Reading) -> any Motion.Sample {
        switch reading {
        case .accelerometer(let reading): sample(from: reading)
        case .gyro(let reading): sample(from: reading)
        case .deviceMotion(let reading): sample(from: reading)
        }
    }
    
    nonisolated static func sample(from reading: Motion.AccelerometerReading) -> AccelerometerSample {
        AccelerometerSample(
            timestamp: reading.timestamp,
            x: reading.acceleration.x,
            y: reading.acceleration.y,
            z: reading.acceleration.z
        )
    }
    
    nonisolated static func sample(from reading: Motion.GyroReading) -> GyroSample {
        GyroSample(
            timestamp: reading.timestamp,
            x: reading.rotationRate.x,
            y: reading.rotationRate.y,
            z: reading.rotationRate.z
        )
    }
    
    nonisolated static func sample(from reading: Motion.DeviceMotionReading) -> DeviceMotionSample {
        DeviceMotionSample(
            timestamp: reading.timestamp,
            attW: reading.attitude.w,
            attX: reading.attitude.x,
            attY: reading.attitude.y,
            attZ: reading.attitude.z,
            accX: reading.userAcceleration.x,
            accY: reading.userAcceleration.y,
            accZ: reading.userAcceleration.z,
            rotX: reading.rotationRate.x,
            rotY: reading.rotationRate.y,
            rotZ: reading.rotationRate.z,
            gX: reading.gravity.x,
            gY: reading.gravity.y,
            gZ: reading.gravity.z
        )
    }
}
#endif



//extension Motion {
//
//    final class SampleFormatter {
//
//        // Each function appends one record straight onto `buffer`: a 1-byte tag
//        // (1 = accelerometer, 2 = gyro, 3 = device motion), then the sample's
//        // fields in declaration order, each a Double as 8 bytes, little-endian.
//        // The buffer is never grown: if the record doesn't fit in the capacity
//        // that's left, it's logged and dropped.
//
//        /// Bytes in the largest record: device motion's tag and 18 Doubles.
//        nonisolated static let largestRecordBytes = 1 + 18 * 8
//
//        /// Bytes one second of records takes with all three sensors at 100 Hz, the fastest
//        /// `SampleRate`. One record from each is 33 + 33 + 145 = 211 bytes.
//        nonisolated static let maxBytesPerSecond = 100 * (2 * (1 + 4 * 8) + largestRecordBytes)
//
//        @Motion.Actor
//        static func append(
//            _ sample: AccelerometerSample, to buffer: inout ContiguousArray<UInt8>
//        ) {
//            guard hasRoom(for: 4, in: buffer, name: "accelerometer") else { return }
//            buffer.append(1)
//            append(sample.timestamp, to: &buffer)
//            append(sample.x, to: &buffer)
//            append(sample.y, to: &buffer)
//            append(sample.z, to: &buffer)
//        }
//
//        @Motion.Actor
//        static func append(
//            _ sample: GyroSample, to buffer: inout ContiguousArray<UInt8>
//        ) {
//            guard hasRoom(for: 4, in: buffer, name: "gyro") else { return }
//            buffer.append(2)
//            append(sample.timestamp, to: &buffer)
//            append(sample.x, to: &buffer)
//            append(sample.y, to: &buffer)
//            append(sample.z, to: &buffer)
//        }
//
//        @Motion.Actor
//        static func append(
//            _ sample: DeviceMotionSample, to buffer: inout ContiguousArray<UInt8>
//        ) {
//            guard hasRoom(for: 18, in: buffer, name: "device motion") else { return }
//            buffer.append(3)
//            append(sample.timestamp, to: &buffer)
//            append(sample.attW, to: &buffer)
//            append(sample.attX, to: &buffer)
//            append(sample.attY, to: &buffer)
//            append(sample.attZ, to: &buffer)
//            append(sample.accX, to: &buffer)
//            append(sample.accY, to: &buffer)
//            append(sample.accZ, to: &buffer)
//            append(sample.rotX, to: &buffer)
//            append(sample.rotY, to: &buffer)
//            append(sample.rotZ, to: &buffer)
//            append(sample.gX, to: &buffer)
//            append(sample.gY, to: &buffer)
//            append(sample.gZ, to: &buffer)
//            append(sample.magX, to: &buffer)
//            append(sample.magY, to: &buffer)
//            append(sample.magZ, to: &buffer)
//            append(sample.heading, to: &buffer)
//        }
//
//        /// `doubleCount` fields of 8 bytes, plus the 1-byte tag.
//        @Motion.Actor
//        private static func hasRoom(
//            for doubleCount: Int, in buffer: ContiguousArray<UInt8>, name: String
//        ) -> Bool {
//            let needed = 1 + doubleCount * MemoryLayout<Double>.size
//            let remaining = buffer.capacity - buffer.count
//            guard remaining >= needed else {
//                AppLog.motion.error("Buffer full, dropping \(name) sample (need \(needed) bytes, have \(remaining))")
//                return false
//            }
//            return true
//        }
//
//        @Motion.Actor
//        private static func append(_ value: Double, to buffer: inout ContiguousArray<UInt8>) {
//            withUnsafeBytes(of: value.bitPattern.littleEndian) { buffer.append(contentsOf: $0) }
//        }
//    }
//}
