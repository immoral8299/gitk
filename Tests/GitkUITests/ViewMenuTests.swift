// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
import GitkCore
@testable import GitkUI

@MainActor
@Suite struct ViewMenuTests {
    private func id(_ n: Int) -> ObjectID {
        ObjectID(hex: String(repeating: String(n), count: 40))!
    }

    @Test func noArgumentsDisablesEditAndDelete() throws {
        let manager = ViewManager()
        #expect(manager.entries.map(\.spec.name) == ["All files"])
        #expect(manager.current == 0)
        #expect(!manager.canEdit && !manager.canDelete)
        let menu = MainMenu(
            dispatch: { _ in },
            isEnabled: { command in
                switch command {
                case .editView: return manager.canEdit
                case .deleteView: return manager.canDelete
                default: return true
                }
            })
        menu.isChecked = { command in
            if case .showView(let n) = command { return n == manager.current }
            return nil
        }
        menu.setViews(manager.entries.map { ($0.number, $0.spec.name) })
        let items = menu.viewMenu.items
        #expect(!menu.validateMenuItem(items[1]))
        #expect(!menu.validateMenuItem(items[2]))
        #expect(menu.validateMenuItem(items[0]))
        #expect(menu.validateMenuItem(items[4]))
        #expect(items[4].title == "All files")
        #expect(items[4].state == .on)
    }

    @Test func commandLineViewIsInitialAndEditable() {
        let manager = ViewManager(commandLine: ViewSpec(name: "x", args: ["main"]))
        #expect(manager.entries.map(\.spec.name) == ["All files", "Command line"])
        #expect(manager.current == 1)
        #expect(manager.currentView.args == ["main"])
        #expect(manager.canEdit && manager.canDelete)
    }

    @Test func menuRebuildReplacesViewEntries() {
        var manager = ViewManager()
        let menu = MainMenu(dispatch: { _ in }, isEnabled: { _ in true })
        let n = manager.add(ViewSpec(name: "Alice", args: ["--author=alice"]))
        menu.setViews(manager.entries.map { ($0.number, $0.spec.name) })
        let titles = menu.viewMenu.items.map { $0.isSeparatorItem ? "-" : $0.title }
        #expect(titles.suffix(5) == ["-", "All files", "Alice", "-", L("Details Sidebar")])
        #expect(n == 1)
    }

    @Test func switchKeepsSelectionWhenInNewView() {
        var manager = ViewManager()
        let n = manager.add(ViewSpec(name: "V"))
        let change = manager.switchTo(n, selected: id(2))
        #expect(change?.requestedID == id(2))
        #expect(change?.view.name == "V")
        #expect(manager.current == n)
        #expect(ViewManager.selection(after: id(2), rows: [id(1), id(2)]) == id(2))
        #expect(ViewManager.selection(after: id(3), rows: [id(1), id(2)]) == id(1))
        #expect(ViewManager.selection(after: nil, rows: []) == nil)
        #expect(manager.switchTo(n, selected: nil) == nil)
    }

    @Test func deleteSwitchesToAllFilesAndForgetsRemembered() {
        var manager = ViewManager()
        let n = manager.add(ViewSpec(name: "R", perm: true))
        _ = manager.switchTo(n, selected: nil)
        #expect(manager.rememberedViews.map(\.name) == ["R"])
        let result = manager.deleteCurrent(selected: id(1))
        #expect(result?.removed.name == "R")
        #expect(result?.switched.number == 0)
        #expect(result?.switched.requestedID == id(1))
        #expect(manager.current == 0)
        #expect(manager.rememberedViews.isEmpty)
        #expect(manager.deleteCurrent(selected: nil) == nil)
    }

    @Test func replaceEditsUserViewOnly() {
        var manager = ViewManager(commandLine: ViewSpec(name: "c", args: ["a"]))
        let n = manager.add(ViewSpec(name: "U"))
        manager.replace(n, with: ViewSpec(name: "U2", args: ["--all"]))
        manager.replace(1, with: ViewSpec(name: "bad"))
        #expect(manager.entry(n)?.spec.args == ["--all"])
        #expect(manager.entry(1)?.spec.name == "Command line")
        #expect(manager.nextNumber == 3)
    }
}
