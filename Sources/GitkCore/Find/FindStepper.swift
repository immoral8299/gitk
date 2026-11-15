// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public enum FindStepper {
    /// Port of gitk procs `dofind`, `findmore` (gitk/gitk 6964–7128), row stepping.
    public static func nextRow(current: Int?, rowCount: Int, matchingRows: Set<Int>, forward: Bool, wrap: Bool) -> Int? {
        guard rowCount > 0, !matchingRows.isEmpty else { return nil }
        let start = current ?? (forward ? -1 : rowCount)
        for distance in 1...rowCount {
            var row = start + (forward ? distance : -distance)
            if !wrap && !(0..<rowCount).contains(row) { return nil }
            row = ((row % rowCount) + rowCount) % rowCount
            if matchingRows.contains(row) { return row }
        }
        return nil
    }

    /// The occurrence drawn in the current-match colour inside the selected
    /// row: the first one in display order. `counts` holds the number of
    /// occurrences in each searched field in display order (list headline,
    /// list author; or the sidebar message). Every other occurrence uses the
    /// found colour. Port of gitk proc `findselectline` and `markmatches`
    /// (gitk/gitk 7130–7172), where the selected row's boxes are raised.
    public static func currentOccurrence(counts: [Int]) -> (field: Int, index: Int)? {
        counts.firstIndex { $0 > 0 }.map { ($0, 0) }
    }
}
