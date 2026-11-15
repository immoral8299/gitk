// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// The list of views behind the View menu: "All files" (view 0), "Command line"
/// when the app was launched with arguments, then the user's views. gitk keeps
/// this in the arrays `viewname`, `viewargs`, ... and the globals `curview`,
/// `nextviewnum`; the menu is rebuilt from `entries`.
public struct ViewManager: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var number: Int
        public var spec: ViewSpec
        /// "All files" and "Command line" carry gitk's own names, which the UI translates.
        public var isBuiltIn: Bool
    }

    /// What `showView` hands back: the view to load and the commit to keep selected.
    public struct Switch: Sendable, Equatable {
        public var number: Int
        public var view: ViewSpec
        /// The commit that was selected before the switch (gitk's `selid`).
        public var requestedID: ObjectID?
    }

    public static let allFilesNumber = 0
    public static let allFilesName = "All files"
    public static let commandLineName = "Command line"

    public private(set) var entries: [Entry]
    public private(set) var current: Int
    private var nextViewNumber: Int

    /// - Parameters:
    ///   - commandLine: The view built from the launch arguments, nil for none.
    ///   - remembered: Views loaded from the settings (task 15.5 persists them),
    ///     added after the built-in ones.
    public init(commandLine: ViewSpec? = nil, remembered: [ViewSpec] = []) {
        entries = [Entry(number: 0, spec: ViewSpec(name: Self.allFilesName), isBuiltIn: true)]
        nextViewNumber = 1
        if var commandLine {
            commandLine.name = Self.commandLineName
            entries.append(Entry(number: 1, spec: commandLine, isBuiltIn: true))
            nextViewNumber = 2
        }
        current = entries.last?.number ?? 0
        for var view in remembered {
            view.perm = true
            add(view)
        }
    }

    public var currentEntry: Entry { entry(current) ?? entries[0] }
    public var currentView: ViewSpec { currentEntry.spec }

    public func entry(_ number: Int) -> Entry? { entries.first { $0.number == number } }

    /// Edit view and Delete view are disabled on "All files"
    /// (gitk proc `showview`, gitk/gitk 4693–4694).
    public var canEdit: Bool { current != 0 }
    public var canDelete: Bool { current != 0 }

    /// The number gitk prefills in the new view's name, "View N"
    /// (gitk proc `newview`, gitk/gitk 4286–4303); the caller translates "View".
    public var nextNumber: Int { nextViewNumber }

    /// The views to save in `Settings.views`: user views with "Remember this view" set.
    public var rememberedViews: [ViewSpec] {
        entries.filter { !$0.isBuiltIn && $0.spec.perm }.map(\.spec)
    }

    /// Adds a view to the end of the list (gitk procs `newviewok`, `addviewmenu`) and
    /// returns its number. It does not become current; call `switchTo`.
    @discardableResult
    public mutating func add(_ view: ViewSpec) -> Int {
        let number = nextViewNumber
        nextViewNumber += 1
        entries.append(Entry(number: number, spec: view, isBuiltIn: false))
        return number
    }

    /// Replaces the definition of an existing user view (the edit case of `newviewok`).
    public mutating func replace(_ number: Int, with view: ViewSpec) {
        guard let index = entries.firstIndex(where: { $0.number == number }), !entries[index].isBuiltIn else { return }
        entries[index].spec = view
    }

    /// Port of gitk proc `showview` (gitk/gitk 4668–4765), the view-list part:
    /// makes `number` current and asks to keep the selected commit. Nil when it
    /// is already current or unknown (`if {$n == $curview} return`).
    public mutating func switchTo(_ number: Int, selected: ObjectID?) -> Switch? {
        guard number != current, let entry = entry(number) else { return nil }
        current = number
        return Switch(number: number, view: entry.spec, requestedID: selected)
    }

    /// Port of gitk proc `delview` (gitk/gitk 4634–4647, with `allviewmenus`): removes
    /// the current view and switches to "All files". The removed view is returned
    /// so the caller can forget it if it was remembered (`viewperm = 0`).
    public mutating func deleteCurrent(selected: ObjectID?) -> (removed: ViewSpec, switched: Switch)? {
        guard canDelete, let index = entries.firstIndex(where: { $0.number == current }) else { return nil }
        let removed = entries.remove(at: index).spec
        current = 0
        return (removed, Switch(number: 0, view: entries[0].spec, requestedID: selected))
    }

    /// Port of the tail of gitk proc `showview` (gitk/gitk 4735–4762): after the switch
    /// the previous selection stays if it is in the new view, otherwise the first row.
    public static func selection(after previous: ObjectID?, rows: [ObjectID]) -> ObjectID? {
        if let previous, rows.contains(previous) { return previous }
        return rows.first
    }
}
