//
//  SampleFormatter.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/19/26.
//

import Foundation


// A record is one sensor event, so its samples share a timestamp in memory. On the wire each
// sample stands alone: its 1-byte tag, the record's timestamp, then the measurement's values in
// order. Every number is a Double, 8 bytes, little-endian. Nothing gives a sample's length, so
// the reader looks it up from the tag.
//
// The phone forwards these bytes untouched, so `RECORDS` in wristscope/transport/wire.py must
// list the same tags and sizes as `Motion.Sample`.

extension Motion {
    nonisolated enum SampleFormatter {}
}


// MARK: - Sizes

extension Motion.SampleFormatter {

    /// Bytes one sample takes: the tag, the timestamp, and `valueCount` values.
    nonisolated static func byteSize(valueCount: Int) -> Int {
        1 + (1 + valueCount) * MemoryLayout<Double>.size
    }

    /// Bytes one sample holding an `M` takes, for sizing a buffer before any sample exists.
    nonisolated static func byteSize<M: Motion.Measurement>(of type: M.Type) -> Int {
        byteSize(valueCount: M.valueCount)
    }

    /// Bytes `record` takes. Each sample repeats the timestamp.
    nonisolated static func byteSize(of record: Motion.Record) -> Int {
        record.samples.reduce(0) { $0 + byteSize(valueCount: $1.measurement.values.count) }
    }

    /// The capacity left in `buffer` after appending `record`. Negative means it doesn't fit,
    /// by that many bytes.
    nonisolated static func hasRoom(in buffer: ContiguousArray<UInt8>, for record: Motion.Record) -> Int {
        let remaining = buffer.capacity - buffer.count
        return remaining - byteSize(of: record)
    }
}


// MARK: - Writing

extension Motion.SampleFormatter {

    /// Appends every sample in `record` without checking capacity: if the record doesn't fit,
    /// the buffer grows. Check `hasRoom(in:for:)` first.
    nonisolated static func unsafeAppend(_ record: Motion.Record, to buffer: inout ContiguousArray<UInt8>) {
        for sample in record.samples {
            append(sample, at: record.timestamp, to: &buffer)
        }
    }

    nonisolated private static func append(
        _ sample: Motion.Sample, at timestamp: Double, to buffer: inout ContiguousArray<UInt8>
    ) {
        let measurement = sample.measurement
        assert(measurement.values.count == type(of: measurement).valueCount)

        buffer.append(sample.tag)
        append(timestamp, to: &buffer)
        for value in measurement.values {
            append(value, to: &buffer)
        }
    }

    nonisolated private static func append(_ value: Double, to buffer: inout ContiguousArray<UInt8>) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { buffer.append(contentsOf: $0) }
    }
}
