//
//  MessageFormatterTests.swift
//  Wristscope Watch AppTests
//
//  Created by Daniel Trejo on 10/23/26.
//

import Foundation
import Testing
@testable import Wristscope_Watch_App


/// The header the watch puts on every live message, and the phone's way of reading it back.
struct MessageFormatterTests {

    @Test func liveHeaderIsTheKindThenTheSequenceLittleEndian() {
        #expect(MessageFormatter.liveHeaderSize == 5)
        #expect(MessageFormatter.liveHeader(0x0102_0304) == Data([1, 0x04, 0x03, 0x02, 0x01]))
    }

    @Test(arguments: [0, 1, 0x0102_0304, UInt32.max] as [UInt32])
    func phoneReadsBackTheSequenceTheWatchWrote(sequence: UInt32) {
        let message = MessageFormatter.liveHeader(sequence) + Data([0xAA, 0xBB])
        #expect(MessageFormatter.liveSequence(of: message) == sequence)
    }

    @Test func sequenceNeedsAWholeHeader() {
        #expect(MessageFormatter.liveSequence(of: Data()) == nil)
        #expect(MessageFormatter.liveSequence(of: Data([1, 2, 3, 4])) == nil)
        #expect(MessageFormatter.liveSequence(of: MessageFormatter.liveHeader(7)) == 7)
    }

    /// A slice of `Data` keeps its parent's indices, so its first byte isn't at index 0.
    @Test func readsTheSequenceFromASlice() {
        let bytes = Data([0xFF, 0xFF]) + MessageFormatter.liveHeader(42)
        let slice = bytes.dropFirst(2)
        #expect(slice.startIndex == 2)
        #expect(MessageFormatter.liveSequence(of: slice) == 42)
    }
}
