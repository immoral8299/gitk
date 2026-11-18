// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Foundation
import GitkCore
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

    @Test func nextAndPreviousStepAndWrapAtEnds() {
        var m = PaneSearchModel(text: text, query: "TODO")
        #expect(m.next(anchor: 0)?.location == 0)
        #expect(m.next(anchor: 0)?.location == 13)
        #expect(m.next(anchor: 0)?.location == 26)
        #expect(m.next(anchor: 0)?.location == 0)
        #expect(m.next(anchor: 0)?.location == 13)
        var b = PaneSearchModel(text: text, query: "TODO")
        #expect(b.previous(anchor: text.utf16.count)?.location == 26)
        #expect(b.previous(anchor: 0)?.location == 13)
        #expect(b.previous(anchor: 0)?.location == 0)
        #expect(b.previous(anchor: 0)?.location == 26)
        var none = PaneSearchModel(text: text, query: "nothing")
        #expect(none.next(anchor: 0) == nil)
        #expect(none.previous(anchor: 0) == nil)
    }

    @Test func caseSensitiveNonOverlapping() {
        let m = PaneSearchModel(text: "aaaa Aa", query: "aa")
        #expect(m.matches.map(\.location) == [0, 2])
        #expect(PaneSearchModel(text: "x", query: "").matches.isEmpty)
    }

    /// Return / ⌘-S scrolls the next hit into view and the counter follows it.
    @MainActor @Test func stepScrollsToHitAndCounts() throws {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        let lines = (0..<300).map { $0 == 5 || $0 == 250 ? "line \($0) MATCH" : "line \($0)" }
        textView.string = lines.joined(separator: "\n")
        textView.sizeToFit()
        let search = PaneSearch(textView: textView, settings: Settings())
        #expect(search.counterText == "")

        search.applySnapshotQuery("MATCH")
        #expect(search.counterText == "1 / 2")
        #expect(scroll.contentView.bounds.minY == 0)

        search.searchNext()
        #expect(search.counterText == "2 / 2")
        let hit = try #require(search.currentHit)
        #expect((textView.string as NSString).substring(with: hit) == "MATCH")
        #expect(textView.selectedRange() == NSRange(location: hit.location, length: 0))
        #expect(scroll.contentView.bounds.minY > 1000)

        search.searchPrevious()
        #expect(search.counterText == "1 / 2")
        #expect(scroll.contentView.bounds.minY < 100)

        // Past the last hit it wraps and keeps scrolling.
        search.searchNext()
        search.searchNext()
        #expect(search.counterText == "1 / 2")
        #expect(scroll.contentView.bounds.minY < 100)
        search.searchNext()
        #expect(search.counterText == "2 / 2")
        #expect(scroll.contentView.bounds.minY > 1000)
    }
}
