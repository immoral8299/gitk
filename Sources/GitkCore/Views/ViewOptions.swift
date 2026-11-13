// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// One entry of gitk's `known_view_options` table.
public struct ViewOption: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// `b`
        case checkbox
        /// `l`
        case label
        /// `tN`: label and entry side by side.
        case text(width: Int)
        /// `tN=`: label above a full-width entry.
        case textStacked(width: Int)
        /// `rN`: radio button with value N.
        case radio(value: Int)
        /// `path`: the multi-line paths box.
        case path
    }

    /// gitk's layout flag: where the option's row starts.
    public enum Layout: String, Sendable, Equatable {
        /// `.`: same row as the previous option.
        case same = "."
        /// `+`: new row.
        case newRow = "+"
        /// `..`: new row, indented.
        case newRowIndented = ".."
        /// `*`: new row, expanding.
        case newRowExpanding = "*"
        /// `*.`: new row, indented and expanding.
        case newRowIndentedExpanding = "*."
    }

    public let id: String
    public let kind: Kind
    public let layout: Layout
    /// Tcl glob patterns; the first is used to encode.
    public let patterns: [String]
    /// gitk's English `mc` text (the localization key).
    public let title: String

    /// For radio buttons, the shared variable name: gitk's `^(.*_)` applied to
    /// the id (so `pickaxe_t` gives `pickaxe_`). Nil for other kinds.
    public var radioGroup: String? {
        guard case .radio = kind, let us = id.lastIndex(of: "_") else { return nil }
        return String(id[...us])
    }
}

/// The value of one option in `ViewOptionValues` (gitk's `newviewopts($n,$id)`).
public enum ViewOptionValue: Sendable, Equatable {
    case bool(Bool)
    case text(String)
    case radio(Int)
}

/// gitk's `newviewname($n)` and `newviewopts($n,*)` for one view. Radio
/// groups are keyed by `ViewOption.radioGroup`.
public struct ViewOptionValues: Sendable, Equatable {
    public var name: String
    public var values: [String: ViewOptionValue]

    public init(name: String = "", values: [String: ViewOptionValue] = [:]) {
        self.name = name
        self.values = values
    }

    public func bool(_ id: String) -> Bool {
        if case .bool(let b)? = values[id] { return b }
        return false
    }

    public func text(_ id: String) -> String {
        if case .text(let s)? = values[id] { return s }
        return ""
    }

    public func radio(_ id: String) -> Int {
        if case .radio(let n)? = values[id] { return n }
        return 0
    }

    /// `newviewopts($n,perm)`: "Remember this view".
    public var perm: Bool {
        get { bool("perm") }
        set { values["perm"] = .bool(newValue) }
    }
}

public enum ViewOptions {
    private static func o(
        _ id: String, _ kind: ViewOption.Kind, _ layout: ViewOption.Layout,
        _ patterns: [String], _ title: String
    ) -> ViewOption {
        ViewOption(id: id, kind: kind, layout: layout, patterns: patterns, title: title)
    }

    /// gitk variable `known_view_options` (gitk/gitk 4303–4335), in gitk's order.
    public static let known: [ViewOption] = [
        o("perm", .checkbox, .same, [], "Remember this view"),
        o("reflabel", .label, .newRow, [], "References (space separated list):"),
        o("refs", .text(width: 15), .newRowIndented, [], "Branches & tags:"),
        o("allrefs", .checkbox, .newRowIndentedExpanding, ["--all"], "All refs"),
        o("branches", .checkbox, .same, ["--branches"], "All (local) branches"),
        o("tags", .checkbox, .same, ["--tags"], "All tags"),
        o("remotes", .checkbox, .same, ["--remotes"], "All remote-tracking branches"),
        o("commitlbl", .label, .newRow, [], "Commit Info (regular expressions):"),
        o("author", .text(width: 15), .newRowIndented, ["--author=*"], "Author:"),
        o("committer", .text(width: 15), .same, ["--committer=*"], "Committer:"),
        o("loginfo", .text(width: 15), .newRowIndented, ["--grep=*"], "Commit Message:"),
        o("allmatch", .checkbox, .newRowIndented, ["--all-match"], "Matches all Commit Info criteria"),
        o("igrep", .checkbox, .newRowIndented, ["--invert-grep"], "Matches no Commit Info criteria"),
        o("changes_l", .label, .newRow, [], "Changes to Files:"),
        o("pickaxe_s", .radio(value: 0), .same, [], "Fixed String"),
        o("pickaxe_t", .radio(value: 1), .same, ["--pickaxe-regex"], "Regular Expression"),
        o("pickaxe", .text(width: 15), .newRowIndented, ["-S*"], "Search string:"),
        o("datelabel", .label, .newRow, [],
          "Commit Dates (\"2 weeks ago\", \"2009-03-17 15:27:38\", \"March 17, 2009 15:27:38\"):"),
        o("since", .text(width: 15), .newRowIndented, ["--since=*", "--after=*"], "Since:"),
        o("until", .text(width: 15), .same, ["--until=*", "--before=*"], "Until:"),
        o("limit_lbl", .label, .newRow, [],
          "Limit and/or skip a number of revisions (positive integer):"),
        o("limit", .text(width: 10), .newRowIndentedExpanding, ["--max-count=*"], "Number to show:"),
        o("skip", .text(width: 10), .same, ["--skip=*"], "Number to skip:"),
        o("misc_lbl", .label, .newRow, [], "Miscellaneous options:"),
        o("dorder", .checkbox, .newRowIndentedExpanding, ["--date-order", "-d"], "Strictly sort by date"),
        o("lright", .checkbox, .same, ["--left-right"], "Mark branch sides"),
        o("first", .checkbox, .same, ["--first-parent"], "Limit to first parent"),
        o("smplhst", .checkbox, .same, ["--simplify-by-decoration"], "Simple history"),
        o("args", .text(width: 50), .newRowIndentedExpanding, [], "Additional arguments to git log:"),
        o("allpaths", .path, .newRow, [],
          "Enter files and directories to include, one per line:"),
        o("cmd", .textStacked(width: 50), .newRow, [], "Command to generate more commits to include:"),
    ]
}
