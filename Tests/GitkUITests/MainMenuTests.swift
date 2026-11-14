// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
import GitkCore
@testable import GitkUI

@MainActor
@Suite struct MainMenuTests {
    @Test func menuTreeAndShortcuts() throws {
        let menu = MainMenu(dispatch: { _ in }, isEnabled: { $0 != .editView && $0 != .deleteView })
        #expect(menu.menu.items.map(\.title) == ["gitk-swift", L("File"), L("Edit"), L("View"), L("Help")])
        let app = try #require(menu.menu.items[0].submenu)
        #expect(app.items.filter { !$0.isSeparatorItem }.map(\.keyEquivalent) == ["", ",", "q"])
        let file = try #require(menu.menu.items[1].submenu)
        #expect(file.items.filter { !$0.isSeparatorItem }.map(\.title) == [
            L("Update"), L("Reload"), L("Reread references"), L("List references"), L("Start git gui"), L("Close"),
        ])
        #expect(file.items[0].keyEquivalentModifierMask.isEmpty)
        #expect(file.items[1].keyEquivalentModifierMask == .shift)
        #expect(!menu.validateMenuItem(menu.viewMenu.items[1]))
        #expect(!menu.validateMenuItem(menu.viewMenu.items[2]))
        #expect(menu.viewMenu.items[4].state == .on)
    }

    @Test func menuDispatchesSameCommandAsKeyBindings() throws {
        var received: AppCommand?
        let menu = MainMenu(dispatch: { received = $0 }, isEnabled: { _ in true })
        let file = try #require(menu.menu.items[1].submenu)
        let update = file.items[0]
        #expect(update.target?.perform(update.action, with: update) != nil)
        #expect(received == .update)
    }
}
