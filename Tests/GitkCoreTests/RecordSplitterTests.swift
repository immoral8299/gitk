// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct RecordSplitterTests {
    private func run(_ chunks: [[UInt8]], separator: UInt8 = 0) -> [[UInt8]] {
        var s = RecordSplitter(separator: separator)
        var out: [[UInt8]] = []
        for c in chunks { out += s.feed(Data(c)).map { [UInt8]($0) } }
        if let last = s.finish() { out.append([UInt8](last)) }
        return out
    }

    @Test func splitsAcrossChunkBoundaries() {
        // "ab" 0 "cde" 0 "f" 0, cut at every awkward place.
        let all: [UInt8] = [97, 98, 0, 99, 100, 101, 0, 102, 0]
        for cut in 0...all.count {
            let got = run([Array(all[..<cut]), Array(all[cut...])])
            #expect(got == [[97, 98], [99, 100, 101], [102]])
        }
        #expect(run(all.map { [$0] }) == [[97, 98], [99, 100, 101], [102]])
    }

    @Test func trailingRecordWithoutSeparatorIsEmittedAtEOF() {
        #expect(run([[97, 0, 98, 99]]) == [[97], [98, 99]])
    }

    @Test func trailingSeparatorAddsNoEmptyRecord() {
        #expect(run([[97, 0]]) == [[97]])
    }

    @Test func emptyRecordsAreKept() {
        #expect(run([[0, 0, 97, 0, 0]]) == [[], [], [97], []])
        #expect(run([[0], [0], [97], [0]]) == [[], [], [97]])
    }

    @Test func emptyInputGivesNothing() {
        #expect(run([]).isEmpty)
        #expect(run([[]]).isEmpty)
    }

    @Test func newlineSeparator() {
        #expect(run([Array("one\ntw".utf8), Array("o\n\nthree".utf8)], separator: 0x0A)
            == [Array("one".utf8), Array("two".utf8), [], Array("three".utf8)])
    }

    @Test func slicedDataWithNonZeroStartIndexWorks() {
        let base = Data([9, 9, 97, 0, 98, 9])
        var s = RecordSplitter(separator: 0)
        let got = s.feed(base[2..<5])
        #expect(got == [Data([97])])
        #expect(s.finish() == Data([98]))
    }
}
