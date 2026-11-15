// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkUI

/// diff-viewer "Incremental search".
@Suite struct PaneSearchTests {
    private let text = "TODO one\nfoo\nTODO two\nbar TODO\n"

    @Test func highlightsEveryMatchAndSelectsFirstAfterCursor() {
        var m = PaneSearchModel(text: text, query: "TODO")
        #expect(m.matches.map(\.location) == [0, 13, 26])
        let hit = m.incremental(anchor: 5, forward: true)
        #expect(hit == NSRange(location: 13, length: 4))
        #expect(m.currentHitRange == hit)
        #expect(m.foundRanges.map(\.location) == [0, 26])
    }

    @Test func nextAndPreviousStepAndStopAtEnds() {
        var m = PaneSearchModel(text: text, query: "TODO")
        #expect(m.next(anchor: 0)?.location == 0)
        #expect(m.next(anchor: 0)?.location == 13)
        #expect(m.next(anchor: 0)?.location == 26)
        #expect(m.next(anchor: 0) == nil)
        #expect(m.current == nil)
        var b = PaneSearchModel(text: text, query: "TODO")
        #expect(b.previous(anchor: text.utf16.count)?.location == 26)
        #expect(b.previous(anchor: 0)?.location == 13)
        #expect(b.previous(anchor: 0)?.location == 0)
        #expect(b.previous(anchor: 0) == nil)
    }

    @Test func caseSensitiveNonOverlapping() {
        let m = PaneSearchModel(text: "aaaa Aa", query: "aa")
        #expect(m.matches.map(\.location) == [0, 2])
        #expect(PaneSearchModel(text: "x", query: "").matches.isEmpty)
    }
}
