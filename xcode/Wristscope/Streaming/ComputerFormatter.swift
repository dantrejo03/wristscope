//
//  ComputerFormatter.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/19/26.
//

import Foundation


/// The header the computer reads at the start of each payload: "WRSC", the format version, then
/// the watch's sequence number. They must match `MAGIC`, `VERSION` and `_PAYLOAD_HEADER` in
/// wristscope/transport/wire.py.
nonisolated enum ComputerFormatter {
    static let magic = Data("WRSC".utf8)
    static let version: UInt8 = 2

    /// The watch's records with the header in front, ready for `MotionStreamer.send`. The
    /// sequence number is little-endian like the records; only the frame `MotionStreamer` wraps
    /// this in is big-endian.
    static func payload(watchSequence: UInt32, records: Data) -> Data {
        var payload = Data(capacity: magic.count + 1 + MemoryLayout<UInt32>.size + records.count)
        payload.append(magic)
        payload.append(version)
        withUnsafeBytes(of: watchSequence.littleEndian) { payload.append(contentsOf: $0) }
        payload.append(records)
        return payload
    }
}
