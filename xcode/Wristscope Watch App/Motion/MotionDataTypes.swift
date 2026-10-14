//
//  MotionDataTypes.swift
//  Wristscope Watch App
//
//  Created by Daniel Trejo on 10/14/26.
//

import CoreMotion
import Foundation


enum Motion {}


// MARK: - Wire format
//
// Stream:  magic (4 bytes "WRSC") | version (UInt8) | record*
// Record:  Source tag (UInt8)     | payload (Source.payloadByteCount bytes)
// Payload: consecutive little-endian Doubles, in each sample type's field order.

extension Motion {
    nonisolated enum Format {
        static let magic: [UInt8] = Array("WRSC".utf8)
        static let version: UInt8 = 1
        static let recordHeaderByteCount = 1
        static var streamHeaderByteCount: Int { magic.count + 1 }
        
        enum DecodeError: Error, Equatable {
            case badMagic
            case unsupportedVersion(UInt8)
            case unknownSource(UInt8)
            case truncatedRecord
        }
        
        static func writeStreamHeader(into bytes: inout ContiguousArray<UInt8>) {
            bytes.append(contentsOf: magic)
            bytes.append(version)
        }

        static func encode(_ samples: [Sample]) -> ContiguousArray<UInt8> {
            var bytes = ContiguousArray<UInt8>()
            writeStreamHeader(into: &bytes)
            for sample in samples { sample.write(into: &bytes) }
            return bytes
        }
        
        static func decode(_ bytes: [UInt8]) throws -> [Sample] {
            guard bytes.count >= streamHeaderByteCount,
                  Array(bytes[0..<magic.count]) == magic else { throw DecodeError.badMagic }
            let fileVersion = bytes[magic.count]
            guard fileVersion == version else { throw DecodeError.unsupportedVersion(fileVersion) }
            
            var reader = ByteReader(bytes: bytes, offset: streamHeaderByteCount)
            var samples: [Sample] = []
            while !reader.isAtEnd {
                let tag = reader.byte()
                guard let source = Source(rawValue: tag) else { throw DecodeError.unknownSource(tag) }
                guard reader.remaining >= source.payloadByteCount else { throw DecodeError.truncatedRecord }
                samples.append(Sample(source: source, reader: &reader))
            }
            return samples
        }
    }
}

nonisolated struct ByteReader {
    let bytes: [UInt8]
    var offset = 0
    
    var remaining: Int { bytes.count - offset }
    var isAtEnd: Bool { remaining == 0 }
    
    mutating func byte() -> UInt8 {
        defer { offset += 1 }
        return bytes[offset]
    }
    
    mutating func double() -> Double {
        var bits: UInt64 = 0
        for i in 0..<8 { bits |= UInt64(bytes[offset + i]) << UInt64(8 * i) }
        offset += 8
        return Double(bitPattern: bits)
    }
}

/// Appends its wire bytes straight onto the caller's buffer, so encoding never builds an
/// intermediate array.
nonisolated protocol WireEncodable {
    func write(into bytes: inout ContiguousArray<UInt8>)
}

extension ContiguousArray where Element == UInt8 {
    /// Appends `value` as 8 little-endian bytes.
    nonisolated mutating func append(_ value: Double) {
        Swift.withUnsafeBytes(of: value.bitPattern.littleEndian) { append(contentsOf: $0) }
    }
}


// MARK: - Source and Sample

nonisolated protocol MotionSampleType: WireEncodable, Sendable {
    static var source: Motion.Source { get }
    /// Number of Doubles in the payload, including the timestamp.
    static var fieldCount: Int { get }

    /// Appends the payload only (no source tag).
    func writePayload(into bytes: inout ContiguousArray<UInt8>)
    init(reader: inout ByteReader)
}

extension MotionSampleType {
    nonisolated static var payloadByteCount: Int { fieldCount * 8 }

    /// Appends one record: the source tag, then the payload.
    nonisolated func write(into bytes: inout ContiguousArray<UInt8>) {
        bytes.append(Self.source.rawValue)
        writePayload(into: &bytes)
    }
}

extension Motion {
    nonisolated enum Source: UInt8, CaseIterable, Sendable {
        case accelerometer = 1
        case gyro = 2
        case deviceMotion = 3
        
        /// The only switch to extend when adding a source (plus the `Sample` cases).
        var sampleType: any MotionSampleType.Type {
            switch self {
            case .accelerometer: return AccelerometerSample.self
            case .gyro: return GyroSample.self
            case .deviceMotion: return DeviceMotionSample.self
            }
        }
        
        var payloadByteCount: Int { sampleType.payloadByteCount }
    }
}

extension Motion {
    nonisolated enum Sample: WireEncodable, Sendable {
        case accelerometer(AccelerometerSample)
        case gyro(GyroSample)
        case deviceMotion(DeviceMotionSample)
        
        var source: Source {
            switch self {
            case .accelerometer: return .accelerometer
            case .gyro: return .gyro
            case .deviceMotion: return .deviceMotion
            }
        }
        
        /// Appends the source tag followed by the payload.
        func write(into bytes: inout ContiguousArray<UInt8>) {
            switch self {
            case .accelerometer(let s): s.write(into: &bytes)
            case .gyro(let s): s.write(into: &bytes)
            case .deviceMotion(let s): s.write(into: &bytes)
            }
        }
        
        /// Reads one payload (the tag has already been consumed).
        init(source: Source, reader: inout ByteReader) {
            switch source {
            case .accelerometer: self = .accelerometer(AccelerometerSample(reader: &reader))
            case .gyro: self = .gyro(GyroSample(reader: &reader))
            case .deviceMotion: self = .deviceMotion(DeviceMotionSample(reader: &reader))
            }
        }
    }
}


// MARK: - Sample types

nonisolated struct AccelerometerSample: MotionSampleType {
    static let source = Motion.Source.accelerometer
    static let fieldCount = 4
    
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let z: Double
    
    init(from data: CMAccelerometerData) {
        timestamp = data.timestamp
        x = data.acceleration.x
        y = data.acceleration.y
        z = data.acceleration.z
    }
    
    init(reader: inout ByteReader) {
        timestamp = reader.double()
        x = reader.double()
        y = reader.double()
        z = reader.double()
    }
    
    func writePayload(into bytes: inout ContiguousArray<UInt8>) {
        bytes.append(timestamp)
        bytes.append(x)
        bytes.append(y)
        bytes.append(z)
    }
}

nonisolated struct GyroSample: MotionSampleType {
    static let source = Motion.Source.gyro
    static let fieldCount = 4
    
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let z: Double
    
    init(from data: CMGyroData) {
        timestamp = data.timestamp
        x = data.rotationRate.x
        y = data.rotationRate.y
        z = data.rotationRate.z
    }
    
    init(reader: inout ByteReader) {
        timestamp = reader.double()
        x = reader.double()
        y = reader.double()
        z = reader.double()
    }
    
    func writePayload(into bytes: inout ContiguousArray<UInt8>) {
        bytes.append(timestamp)
        bytes.append(x)
        bytes.append(y)
        bytes.append(z)
    }
}

nonisolated struct DeviceMotionSample: MotionSampleType {
    static let source = Motion.Source.deviceMotion
    static let fieldCount = 18
    
    let timestamp: TimeInterval
    
    let attW: Double
    let attX: Double
    let attY: Double
    let attZ: Double

    let rotX: Double
    let rotY: Double
    let rotZ: Double

    let uAccX: Double
    let uAccY: Double
    let uAccZ: Double

    let gX: Double
    let gY: Double
    let gZ: Double
    
    let mX: Double
    let mY: Double
    let mZ: Double
    
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
        
        uAccX = motion.userAcceleration.x
        uAccY = motion.userAcceleration.y
        uAccZ = motion.userAcceleration.z
        
        gX = motion.gravity.x
        gY = motion.gravity.y
        gZ = motion.gravity.z
        
        mX = motion.magneticField.field.x
        mY = motion.magneticField.field.y
        mZ = motion.magneticField.field.z
        
        heading = motion.heading
    }
    
    init(reader: inout ByteReader) {
        timestamp = reader.double()
        attW = reader.double()
        attX = reader.double()
        attY = reader.double()
        attZ = reader.double()
        rotX = reader.double()
        rotY = reader.double()
        rotZ = reader.double()
        uAccX = reader.double()
        uAccY = reader.double()
        uAccZ = reader.double()
        gX = reader.double()
        gY = reader.double()
        gZ = reader.double()
        mX = reader.double()
        mY = reader.double()
        mZ = reader.double()
        heading = reader.double()
    }
    
    func writePayload(into bytes: inout ContiguousArray<UInt8>) {
        bytes.append(timestamp)
        bytes.append(attW)
        bytes.append(attX)
        bytes.append(attY)
        bytes.append(attZ)
        bytes.append(rotX)
        bytes.append(rotY)
        bytes.append(rotZ)
        bytes.append(uAccX)
        bytes.append(uAccY)
        bytes.append(uAccZ)
        bytes.append(gX)
        bytes.append(gY)
        bytes.append(gZ)
        bytes.append(mX)
        bytes.append(mY)
        bytes.append(mZ)
        bytes.append(heading)
    }
}
