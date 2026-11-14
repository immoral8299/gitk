// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.
import Testing
@testable import GitkCore

@Suite struct NavigationHistoryTests {
    @Test func restoresPositionAndTruncatesForwardBranch() throws {
        let a = try #require(ObjectID(hex: String(repeating: "a", count: 40)))
        let b = try #require(ObjectID(hex: String(repeating: "b", count: 40)))
        var history = NavigationHistory().adding(.init(target: .commit(a)))
        history = history.adding(.init(target: .link(b)), saving: 42)
        #expect(history.canGoBack)
        history = history.stepping(forward: false, saving: 17)
        #expect(history.current?.scrollPosition == 42)
        #expect(history.canGoForward)
        history = history.adding(.init(target: .line(a, child: b)), saving: 50)
        #expect(!history.canGoForward)
        #expect(history.entries.count == 2)
    }
}

@Suite struct SelectionModelTests {
    @Test func defaultsCopiesCountsAndNavigates() throws {
        let ids = try (1...4).map { try #require(ObjectID(hex: String(repeating: String($0), count: 40))) }
        var model = SelectionModel()
        #expect(model.defaultID(rows: ids, head: ids[2], requested: nil) == ids[2])
        #expect(model.defaultID(rows: ids, head: ids[2], requested: ids[3]) == ids[3])
        model = model.selecting(ids[1])
        #expect(model.rowCounter(rows: ids) == "2 / 4")
        #expect(model.clipboardText(copyLength: 12) == String(repeating: "2", count: 12))
        model = model.navigating(.selectNext, rows: ids, parents: [], pageSize: 2)
        #expect(model.selectedID == ids[2])
        model = model.navigating(.goToParent(2), rows: ids, parents: [ids[0], ids[3]], pageSize: 2)
        #expect(model.selectedID == ids[3])
        #expect(model.navigating(.scrollList(.toStart), rows: ids, parents: [], pageSize: 2).selectedID == ids[3])
    }
}
