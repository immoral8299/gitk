// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import GitkCore

/// A diff between two chosen commits (row-menu "Diff this -> selected" and
/// friends): which commits, in which order, and the sidebar header text.
struct TwoCommitDiff: Equatable {
    var old: ObjectID
    var new: ObjectID

    /// The commits for a row-menu diff command. Port of the endpoint choice in
    /// gitk procs `diffvssel` and `diffvsmark` (gitk/gitk 9358–9381). `menuID`
    /// is the clicked row. Nil when the needed selection or mark is missing.
    static func make(command: AppCommand, menuID: ObjectID, selected: ObjectID?, marked: ObjectID?) -> TwoCommitDiff? {
        switch command {
        case .diffThisToSelected: selected.map { TwoCommitDiff(old: menuID, new: $0) }
        case .diffSelectedToThis: selected.map { TwoCommitDiff(old: $0, new: menuID) }
        case .diffThisToMarked: marked.map { TwoCommitDiff(old: menuID, new: $0) }
        case .diffMarkedToThis: marked.map { TwoCommitDiff(old: $0, new: menuID) }
        default: nil
        }
    }

    /// The `git diff-tree` command for the bottom pane.
    func command(options: DiffOptions) -> [String] {
        DiffCommandBuilder.blobDiff(ids: [old, new], options: options)
    }

    /// The header text and the ranges (UTF-16) of the two ID links. Port of the
    /// text built by gitk proc `doseldiff` (gitk/gitk 9407–9420).
    func header(oldHeadline: String, newHeadline: String) -> (text: String, oldRange: NSRange, newRange: NSRange) {
        let from = L("From") + " "
        let oldText = old.hex
        let middle = "\n     " + oldHeadline + "\n\n" + L("To") + "   "
        let newText = new.hex
        let text = from + oldText + middle + newText + "\n     " + newHeadline + "\n"
        let oldRange = NSRange(location: (from as NSString).length, length: (oldText as NSString).length)
        let newRange = NSRange(location: oldRange.upperBound + (middle as NSString).length, length: (newText as NSString).length)
        return (text, oldRange, newRange)
    }
}
