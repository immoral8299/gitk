// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct NavigationCommandTests {
    @Test func linePageAndParentNavigation() throws {
        let ids = try (0..<6).map { try #require(ObjectID(hex: String(repeating: String($0), count: 40))) }
        let selection = SelectionModel().selecting(ids[2])
        #expect(selection.navigating(.selectNext, rows: ids, parents: [], pageSize: 2).selectedID == ids[3])
        #expect(selection.navigating(.selectPrev, rows: ids, parents: [], pageSize: 2).selectedID == ids[1])
        #expect(selection.navigating(.selectPageDown, rows: ids, parents: [], pageSize: 2).selectedID == ids[4])
        #expect(selection.navigating(.selectPageUp, rows: ids, parents: [], pageSize: 5).selectedID == ids[0])
        #expect(selection.navigating(.goToParent(2), rows: ids, parents: [ids[3], ids[5]], pageSize: 2).selectedID == ids[5])
        #expect(selection.navigating(.goToParent(3), rows: ids, parents: [ids[3]], pageSize: 2).selectedID == ids[2])
    }
}
