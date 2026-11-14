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
