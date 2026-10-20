//
//  MessageDataKind.swift
//  Wristscope
//
//  Created by Daniel Trejo on 10/19/26.
//

/// The first byte of every message the watch sends with `sendMessageData`, so the phone knows
/// what follows it.
nonisolated enum MessageDataKind: UInt8 {
    /// Motion records from `Motion.SampleFormatter`, with nothing else added.
    case live = 1
}
