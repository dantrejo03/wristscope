//
//  ComputerFormatter.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/19/26.
//

import Foundation


/// The header the computer reads at the start of each payload: "WRSC", then the format version.
/// Both must match `MAGIC` and `VERSION` in wristscope/transport/wire.py.
nonisolated enum ComputerFormatter {
    static let magic = Data("WRSC".utf8)
    static let version: UInt8 = 1

    /// The watch's records with the header in front, ready for `MotionStreamer.send`.
    static func payload(fromRecords records: Data) -> Data {
        var payload = Data(capacity: magic.count + 1 + records.count)
        payload.append(magic)
        payload.append(version)
        payload.append(records)
        return payload
    }
}
