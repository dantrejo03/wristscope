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


