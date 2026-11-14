// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Port of gitk proc `makewindow` (menu definitions, gitk/gitk 2398–2442).
@MainActor
final class MainMenu: NSObject, NSMenuItemValidation {
    let menu = NSMenu()
    private(set) var viewMenu = NSMenu(title: L("View"))
    var dispatch: (AppCommand) -> Void
    var isEnabled: (AppCommand) -> Bool
    private var commands: [ObjectIdentifier: AppCommand] = [:]

    init(dispatch: @escaping (AppCommand) -> Void, isEnabled: @escaping (AppCommand) -> Bool) {
        self.dispatch = dispatch
        self.isEnabled = isEnabled
        super.init()
        let app = addMenu("gitk-swift")
        add(L("About gitk"), .about, to: app)
        app.addItem(.separator())
        add(L("Settings…"), .preferences, key: ",", to: app)
        app.addItem(.separator())
        add(L("Quit"), .quit, key: "q", to: app)
        let file = addMenu(L("File"))
        add(L("Update"), .update, key: functionKey(NSF5FunctionKey), modifiers: [], to: file)
        add(L("Reload"), .reload, key: functionKey(NSF5FunctionKey), modifiers: [.shift], to: file)
        add(L("Reread references"), .rereadRefs, to: file)
        add(L("List references"), .listRefs, key: functionKey(NSF2FunctionKey), modifiers: [], to: file)
        file.addItem(.separator())
        add(L("Start git gui"), .startGitGui, to: file)
        file.addItem(.separator())
        add(L("Close"), .closeWindow, key: "w", to: file)
        let edit = addMenu(L("Edit"))
        for (title, selector, key) in [
            (L("Copy"), #selector(NSText.copy(_:)), "c"),
            (L("Paste"), #selector(NSText.paste(_:)), "v"),
            (L("Select all"), #selector(NSText.selectAll(_:)), "a"),
        ] {
            edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        let viewItem = NSMenuItem(title: L("View"), action: nil, keyEquivalent: "")
        viewItem.submenu = viewMenu
        menu.addItem(viewItem)
        add(L("New view..."), .newView, key: functionKey(NSF4FunctionKey), modifiers: [.shift], to: viewMenu)
        add(L("Edit view..."), .editView, key: functionKey(NSF4FunctionKey), modifiers: [], to: viewMenu)
        add(L("Delete view"), .deleteView, to: viewMenu)
        viewMenu.addItem(.separator())
        let all = add(L("All files"), .showView(0), to: viewMenu)
        all.state = .on
        let help = addMenu(L("Help"))
        add(L("Key bindings"), .keyBindings, to: help)
    }

    private func functionKey(_ value: Int) -> String {
        UnicodeScalar(value).map(String.init) ?? ""
    }

    private func addMenu(_ title: String) -> NSMenu {
        let submenu = NSMenu(title: title)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
        return submenu
    }

    @discardableResult
    func add(_ title: String, _ command: AppCommand, key: String = "",
             modifiers: NSEvent.ModifierFlags = [.command], to parent: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        commands[ObjectIdentifier(item)] = command
        parent.addItem(item)
        return item
    }

    @objc private func invoke(_ sender: NSMenuItem) {
        if let command = commands[ObjectIdentifier(sender)] { dispatch(command) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = commands[ObjectIdentifier(menuItem)] else { return true }
        return isEnabled(command)
    }
}
