// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class CommandMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, command: AppCommand, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        representedObject = command
        target = self
        isEnabled = enabled
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    @objc private func invoke() { handler() }
}

@MainActor
enum RowMenus {
    /// Port of gitk proc `rowmenu` and its menu definitions (gitk/gitk 2853–2882, 9151–9186).
    static func commitMenu(id: ObjectID, selected: ObjectID?, marked: ObjectID?, refs: RefSet,
                           perform: @escaping (AppCommand) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let local = id == ObjectID.localUnstaged(hashLength: id.hex.count)
            || id == ObjectID.localStaged(hashLength: id.hex.count)
        let items: [(String, AppCommand)] = [
            (L("Diff this -> selected"), .diffThisToSelected),
            (L("Diff selected -> this"), .diffSelectedToThis),
            (L("Make patch"), .makePatch),
            (L("Create tag"), .createTag),
            (L("Copy commit reference"), .copyCommitReference),
            (L("Write commit to file"), .writeCommitToFile),
            (L("Create new branch"), .createBranch),
            (L("Cherry-pick this commit"), .cherryPickCommit),
            (refs.mainHeadName.map { L("Reset %s branch to here", $0) } ?? L("Detached head: can't reset"), .resetHeadToHere),
            (L("Mark this commit"), .markCommit),
            (L("Return to mark"), .returnToMark),
            (L("Find descendant of this and mark"), .findDescendantAndMark),
            (L("Compare with marked commit"), .compareWithMarked),
            (L("Diff this -> marked commit"), .diffThisToMarked),
            (L("Diff marked commit -> this"), .diffMarkedToThis),
            (L("Revert this commit"), .revertCommit),
        ]
        let fakeCommands: Set<AppCommand> = [.diffThisToSelected, .diffSelectedToThis, .makePatch,
                                            .diffThisToMarked, .diffMarkedToThis]
        let selectionCommands: Set<AppCommand> = [.diffThisToSelected, .diffSelectedToThis, .makePatch]
        let markCommands: Set<AppCommand> = [.returnToMark, .findDescendantAndMark, .compareWithMarked,
                                            .diffThisToMarked, .diffMarkedToThis]
        for (title, command) in items where !local || fakeCommands.contains(command) {
            let enabled = (!selectionCommands.contains(command) || (selected != nil && selected != id))
                && (!markCommands.contains(command) || (marked != nil && marked != id))
                && (command != .resetHeadToHere || refs.mainHeadName != nil)
            menu.addItem(CommandMenuItem(title: title, command: command, enabled: enabled) { perform(command) })
        }
        return menu
    }

    /// Port of gitk proc `headmenu` (gitk/gitk 10082–10103).
    static func headMenu(name: String, refs: RefSet, perform: @escaping (AppCommand) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let remote = name.hasPrefix("remotes/")
        let current = name == refs.mainHeadName
        let localName = name.components(separatedBy: "/").last ?? name
        let checkoutEnabled = !current && (!remote || refs.headIDs[localName] == nil)
        let items: [(String, AppCommand, Bool)] = [
            (L("Check out this branch"), .checkoutBranch, checkoutEnabled),
            (L("Rename this branch"), .renameBranch, !remote),
            (L("Remove this branch"), .removeBranch, !remote && !current),
            (L("Copy branch name"), .copyBranchName, true),
        ]
        for (title, command, enabled) in items {
            menu.addItem(CommandMenuItem(title: title, command: command, enabled: enabled) { perform(command) })
        }
        return menu
    }
}
