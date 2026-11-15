// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct FindSteppingTests {
    @Test func wrapAndNoWrap() {
        #expect(FindStepper.nextRow(current: 4, rowCount: 5, matchingRows: [1, 3], forward: true, wrap: true) == 1)
        #expect(FindStepper.nextRow(current: 4, rowCount: 5, matchingRows: [1, 3], forward: true, wrap: false) == nil)
        #expect(FindStepper.nextRow(current: 0, rowCount: 5, matchingRows: [1, 3], forward: false, wrap: true) == 3)
        #expect(FindStepper.nextRow(current: 0, rowCount: 5, matchingRows: [1, 3], forward: false, wrap: false) == nil)
        #expect(FindStepper.nextRow(current: 1, rowCount: 5, matchingRows: [1], forward: true, wrap: true) == 1)
        #expect(FindStepper.nextRow(current: nil, rowCount: 0, matchingRows: [], forward: true, wrap: true) == nil)
    }

    @Test func currentOccurrenceIsFirstInDisplayOrder() {
        #expect(FindStepper.currentOccurrence(counts: [0, 2])?.field == 1)
        #expect(FindStepper.currentOccurrence(counts: [3, 1])?.field == 0)
        #expect(FindStepper.currentOccurrence(counts: [3, 1])?.index == 0)
        #expect(FindStepper.currentOccurrence(counts: [0, 0]) == nil)
        #expect(FindStepper.currentOccurrence(counts: []) == nil)
    }

    @Test func steppingWalksEveryMatchAndWrapsOnce() {
        let rows: Set<Int> = [1, 3, 4]
        var current: Int? = nil
        var seen: [Int] = []
        for _ in 0..<4 {
            current = FindStepper.nextRow(current: current, rowCount: 6, matchingRows: rows, forward: true, wrap: true)
            seen.append(current ?? -1)
        }
        #expect(seen == [1, 3, 4, 1])
        #expect(FindStepper.nextRow(current: 4, rowCount: 6, matchingRows: rows, forward: true, wrap: false) == nil)
    }
}
