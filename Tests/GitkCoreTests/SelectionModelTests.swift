// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct SelectionModelTests {
    private let ids = (0..<5).map { ObjectID(hex: String(repeating: String($0), count: 40))! }

    /// commit-list "Default selection" and cli-launch "Select a commit at startup".
    @Test func defaultSelection() {
        let model = SelectionModel()
        #expect(model.defaultID(rows: ids, head: ids[2], requested: nil) == ids[2])
        #expect(model.defaultID(rows: ids, head: ids[2], requested: ids[4]) == ids[4])
        #expect(model.defaultID(rows: ids, head: nil, requested: nil) == ids[0])
        let other = ObjectID(hex: String(repeating: "f", count: 40))!
        #expect(model.defaultID(rows: ids, head: other, requested: other) == ids[0])
        #expect(model.selecting(ids[3]).defaultID(rows: ids, head: ids[1], requested: nil) == ids[3])
        #expect(model.defaultID(rows: [], head: nil, requested: nil) == nil)
    }

    /// commit-list "Select a commit": selection is recorded in the history.
    @Test func selectingRecordsHistory() {
        let model = SelectionModel().selecting(ids[1]).selecting(ids[2])
        #expect(model.selectedID == ids[2])
        #expect(model.history.canGoBack)
        let unrecorded = model.selecting(ids[3], record: false)
        #expect(unrecorded.history.entries == model.history.entries)
        #expect(model.rowCounter(rows: ids) == "3 / 5")
        #expect(SelectionModel().rowCounter(rows: ids) == "0 / 5")
    }

    /// commit-list "Auto-copy": the abbreviated ID of the selection.
    @Test func clipboardText() {
        #expect(SelectionModel().selecting(ids[1]).clipboardText(copyLength: 7) == "1111111")
        #expect(SelectionModel().clipboardText(copyLength: 7) == nil)
    }

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
