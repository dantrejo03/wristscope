//
//  MessageFormatter.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/20/26.
//

import Foundation

nonisolated enum MessageKind: UInt8 {
    case live = 1
}

/// What the watch sends with `sendMessageData`: a header starting with a `MessageKind` byte,
/// then the body.
nonisolated enum MessageFormatter {
    /// Bytes `liveHeader` writes: the kind, then the sequence number.
    static let liveHeaderSize = 1 + MemoryLayout<UInt32>.size

    static func liveHeader(_ sequenceNum: UInt32) -> Data {
        var data = Data()
        data.append(MessageKind.live.rawValue)
        withUnsafeBytes(of: sequenceNum.littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    /// The phone's half: the sequence number `liveHeader` wrote, or nil if `message` is too
    /// short to hold one.
    static func liveSequence(of message: Data) -> UInt32? {
        guard message.count >= liveHeaderSize else { return nil }
        let raw = message.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 1, as: UInt32.self) }
        return UInt32(littleEndian: raw)
    }
}
