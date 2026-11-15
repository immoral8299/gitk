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
    /// The checkmark of a checkable item (View→Details Sidebar); nil for others.
    var isChecked: (AppCommand) -> Bool? = { _ in nil }
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
        viewMenu.addItem(.separator())
        setViews([(0, L("All files"))])
        add(L("Details Sidebar"), .toggleDetailsSidebar, to: viewMenu)
        let help = addMenu(L("Help"))
        add(L("Key bindings"), .keyBindings, to: help)
    }

    /// Port of gitk proc `addviewmenu` (gitk/gitk 4649–4655): replaces the view
    /// entries (the items between the two separators after "Delete view") with one
    /// item per view; the checkmark comes from `isChecked(.showView(n))`.
    func setViews(_ views: [(number: Int, title: String)]) {
        let separators = viewMenu.items.indices.filter { viewMenu.items[$0].isSeparatorItem }
        let start = (separators.first ?? viewMenu.items.count - 1) + 1
        while start < viewMenu.items.count, !viewMenu.items[start].isSeparatorItem {
            let item = viewMenu.items[start]
            commands[ObjectIdentifier(item)] = nil
            viewMenu.removeItem(at: start)
        }
        for (offset, view) in views.enumerated() {
            let item = NSMenuItem(title: view.title, action: #selector(invoke(_:)), keyEquivalent: "")
            item.target = self
            commands[ObjectIdentifier(item)] = .showView(view.number)
            viewMenu.insertItem(item, at: start + offset)
        }
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
        if let checked = isChecked(command) { menuItem.state = checked ? .on : .off }
        return isEnabled(command)
    }
}
