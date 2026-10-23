//
//  SampleFormatterTests.swift
//  Wristscope Watch AppTests
//
//  Created by Daniel Trejo on 10/23/26.
//

import Testing
@testable import Wristscope_Watch_App


/// The bytes the watch writes for each sample. The phone passes them on to the computer
/// untouched, so this is the layout docs/wire-format.md describes and tests/test_wire.py decodes.
struct SampleFormatterTests {
    typealias Formatter = Motion.SampleFormatter

    @Test func sampleSizeCountsTheTagTimestampAndValues() {
        #expect(Formatter.byteSize(of: Motion.Vector3.self) == 1 + 4 * 8)
        #expect(Formatter.byteSize(of: Motion.Vector4.self) == 1 + 5 * 8)
    }

    @Test func recordSizeRepeatsTheTimestampForEachSample() {
        let record = Motion.Record(timestamp: 1, samples: [
            .attitude(Motion.Vector4(w: 1, x: 0, y: 0, z: 0)),
            .gravity(Motion.Vector3(x: 0, y: 0, z: -1)),
        ])
        #expect(Formatter.byteSize(of: record) == 41 + 33)
    }

    @Test func sampleIsTagThenTimestampThenValuesLittleEndian() {
        let record = Motion.Record(timestamp: 1000.25, samples: [
            .rawAcceleration(Motion.Vector3(x: 0.1, y: -0.2, z: 9.81)),
        ])
        var buffer = ContiguousArray<UInt8>()
        Formatter.unsafeAppend(record, to: &buffer)

        #expect(buffer.count == 33)
        #expect(buffer[0] == 1)
        #expect(double(at: 1, in: buffer) == 1000.25)
        #expect(double(at: 9, in: buffer) == 0.1)
        #expect(double(at: 17, in: buffer) == -0.2)
        #expect(double(at: 25, in: buffer) == 9.81)
    }

    @Test func everySampleInARecordGetsItsOwnTagAndTheRecordTimestamp() {
        let record = Motion.Record(timestamp: 7.5, samples: [
            .attitude(Motion.Vector4(w: 1, x: 0, y: 0, z: 0)),
            .userAcceleration(Motion.Vector3(x: 0, y: 0, z: 0)),
            .rotationRate(Motion.Vector3(x: 0, y: 0, z: 0)),
            .gravity(Motion.Vector3(x: 0, y: 0, z: -1)),
        ])
        var buffer = ContiguousArray<UInt8>()
        Formatter.unsafeAppend(record, to: &buffer)

        let starts = [0, 41, 74, 107]
        #expect(buffer.count == 140)
        #expect(starts.map { buffer[$0] } == [5, 2, 4, 6])
        #expect(starts.map { double(at: $0 + 1, in: buffer) } == [7.5, 7.5, 7.5, 7.5])
    }

    @Test func hasRoomIsWhatsLeftAfterTheRecordAndNegativeWhenItDoesntFit() {
        let record = Motion.Record(timestamp: 0, samples: [
            .rawAcceleration(Motion.Vector3(x: 0, y: 0, z: 0)),
        ])
        #expect(Formatter.hasRoom(in: ContiguousArray(), for: record) == -33)

        // reserveCapacity can round up, so the room left comes from the capacity it got.
        var buffer = ContiguousArray<UInt8>()
        buffer.reserveCapacity(100)
        Formatter.unsafeAppend(record, to: &buffer)
        #expect(Formatter.hasRoom(in: buffer, for: record) == buffer.capacity - 33 - 33)
    }
}


/// The little-endian `Double` that starts at `offset`, read without the formatter's own code.
private func double(at offset: Int, in bytes: ContiguousArray<UInt8>) -> Double {
    var bits: UInt64 = 0
    for (index, byte) in bytes[offset..<offset + 8].enumerated() {
        bits |= UInt64(byte) << (8 * index)
    }
    return Double(bitPattern: bits)
}
