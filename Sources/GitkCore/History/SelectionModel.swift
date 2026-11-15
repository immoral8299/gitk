// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public struct SelectionModel: Sendable {
    public private(set) var selectedID: ObjectID?
    public var markedID: ObjectID?
    public var history = NavigationHistory()
    public init() {}

    /// Port of gitk proc `selectline` (gitk/gitk 7500–7666), selection state only.
    public func selecting(_ id: ObjectID, scrollPosition: Double = 0, record: Bool = true) -> SelectionModel {
        var result = self
        result.selectedID = id
        if record { result.history = history.adding(NavigationEntry(target: .commit(id)), saving: scrollPosition) }
        return result
    }

    public func defaultID(rows: [ObjectID], head: ObjectID?, requested: ObjectID?) -> ObjectID? {
        if let requested, rows.contains(requested) { return requested }
        if let selectedID, rows.contains(selectedID) { return selectedID }
        if let head, rows.contains(head) { return head }
        return rows.first
    }

    public func clipboardText(copyLength: Int) -> String? { selectedID?.abbreviated(copyLength) }
    public func rowCounter(rows: [ObjectID]) -> String {
        let row = selectedID.flatMap { rows.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
        return "\(row) / \(rows.count)"
    }

    /// Port of gitk procs `selnextline`, `selnextpage`, `go_to_parent`
    /// (gitk/gitk 7668–7726, 7824–7832).
    public func navigating(_ command: AppCommand, rows: [ObjectID], parents: [ObjectID], pageSize: Int) -> SelectionModel {
        guard !rows.isEmpty else { return self }
        let currentRow = selectedID.flatMap { rows.firstIndex(of: $0) } ?? 0
        let target: Int
        switch command {
        case .selectPrev: target = currentRow - 1
        case .selectNext: target = currentRow + 1
        case .selectFirst: target = 0
        case .selectLast: target = rows.count - 1
        case .selectPageUp: target = max(0, currentRow - max(1, pageSize))
        case .selectPageDown: target = min(rows.count - 1, currentRow + max(1, pageSize))
        case .goToParent(let n):
            guard n > 0, n <= parents.count, rows.contains(parents[n - 1]) else { return self }
            return selecting(parents[n - 1])
        default: return self
        }
        return rows.indices.contains(target) ? selecting(rows[target]) : self
    }
}

extension SelectionModel {
    /// Port of gitk proc `markhere` (gitk/gitk 9188–9193): the row-menu commit becomes the mark.
    public func marking(_ id: ObjectID) -> SelectionModel {
        var result = self
        result.markedID = id
        return result
    }

    /// Port of gitk proc `gotomark` (gitk/gitk 9195–9201): the mark, when there is one.
    public var markTarget: ObjectID? { markedID }
}

extension ViewSession {
    /// Port of gitk proc `replace_by_kids` (gitk/gitk 9203–9212).
    func replaceByKids(_ list: [Int], _ r: Int) -> [Int] {
        var l = Array(list.dropFirst())
        if let commit = ordering.commitOnRow(r) {
            for kid in ordering.children[commit] ?? [] {
                if let kidRow = ordering.rowOfCommit(kid) { l.append(kidRow) }
            }
        }
        // lsort -integer -decreasing -unique
        return Array(Set(l)).sorted(by: >)
    }

    /// Port of gitk proc `find_common_desc` (gitk/gitk 9214–9239). Returns the
    /// commit gitk would pass to `selectline`: the nearest common descendant of
    /// the mark and `menuID` in this view, or nil.
    public func findCommonDesc(marked: ObjectID?, menuID: ObjectID) -> ObjectID? {
        guard let marked else { return nil }
        guard let markedCommit = store.index(of: marked), let menuCommit = store.index(of: menuID),
              ordering.commitInView(markedCommit), ordering.commitInView(menuCommit),
              let markedRow = ordering.rowOfCommit(markedCommit),
              let menuRow = ordering.rowOfCommit(menuCommit) else { return nil }
        var l1 = [markedRow]
        var l2 = [menuRow]
        while true {
            guard let r1 = l1.first, let r2 = l2.first else { return nil }
            if r1 == r2 { return id(at: r1) }
            if r1 > r2 { l1 = replaceByKids(l1, r1) } else { l2 = replaceByKids(l2, r2) }
        }
    }
}
