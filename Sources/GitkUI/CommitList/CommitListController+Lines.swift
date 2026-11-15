// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Line hover, line click and arrow jump (commit-graph "Click a line",
/// "Arrow jump"). The hit-testing is `LineHitTest` in GitkCore.
extension CommitListController {
    func configureLineInteraction(_ cell: GraphCellView) {
        cell.lineTooltip = { [weak self] parent in
            guard let self else { return nil }
            return LineDetails.tooltip(parent: parent, session: session)
        }
        cell.onLineClick = { [weak self] parent in self?.lineClicked(parent) }
        cell.onArrowClick = { [weak self] row in self?.arrowJump(to: row) }
    }

    /// Port of gitk proc `lineclick` (gitk/gitk 9068–9120): unselect, draw the
    /// line thicker, and hand the parent and children to the details sidebar.
    func lineClicked(_ parent: CommitIndex) {
        guard let details = LineDetails.build(parent: parent, session: session, dateFormat: dateFormat) else { return }
        tableView.deselectAll(nil)
        setThickLine(parent)
        onLineDetails?(details)
    }

    /// Port of gitk procs `normalline` and `drawlines` for the thicker line.
    func setThickLine(_ parent: CommitIndex?) {
        guard thickLine != parent else { return }
        thickLine = parent
        let visible = tableView.rows(in: scrollView.contentView.documentVisibleRect)
        guard visible.length > 0 else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)),
                             columnIndexes: IndexSet(integer: 0))
    }

    /// Port of gitk proc `arrowjump` (gitk/gitk 9051–9066): centre the row at
    /// the other end of the arrow.
    func arrowJump(to row: Int) {
        guard row >= 0, row < tableView.numberOfRows else { return }
        let clip = scrollView.contentView
        let rect = tableView.rect(ofRow: row)
        let top = clip.contentInsets.top
        let offset = LineHitTest.arrowJumpOffset(
            row: row, rowHeight: Double(rect.height), viewportHeight: Double(clip.bounds.height - top - clip.contentInsets.bottom),
            contentHeight: Double(tableView.frame.height))
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: CGFloat(offset) - top))
        scrollView.reflectScrolledClipView(clip)
    }
}
