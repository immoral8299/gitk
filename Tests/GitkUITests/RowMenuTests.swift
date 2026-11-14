// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct RowMenuTests {
    @Test func orderAndMarkEnablement() throws {
        let a = try #require(ObjectID(hex: String(repeating: "a", count: 40)))
        let b = try #require(ObjectID(hex: String(repeating: "b", count: 40)))
        let menu = RowMenus.commitMenu(id: a, selected: b, marked: nil, refs: RefSet()) { _ in }
        #expect(menu.items.count == 16)
        #expect(menu.items[0].title == L("Diff this -> selected"))
        #expect(menu.items[15].title == L("Revert this commit"))
        for n in [10, 11, 12, 13, 14] { #expect(!menu.items[n].isEnabled) }
        let marked = RowMenus.commitMenu(id: a, selected: b, marked: b, refs: RefSet()) { _ in }
        for n in [10, 11, 12, 13, 14] { #expect(marked.items[n].isEnabled) }
    }

    @Test func fakeRowHasOnlyDiffAndPatch() throws {
        let a = try #require(ObjectID.localUnstaged(hashLength: 40))
        let menu = RowMenus.commitMenu(id: a, selected: nil, marked: nil, refs: RefSet()) { _ in }
        #expect(menu.items.count == 5)
        #expect(menu.items.compactMap { $0.representedObject as? AppCommand }
                == [.diffThisToSelected, .diffSelectedToThis, .makePatch, .diffThisToMarked, .diffMarkedToThis])
        #expect(menu.items.allSatisfy { !$0.isEnabled })
    }
}
