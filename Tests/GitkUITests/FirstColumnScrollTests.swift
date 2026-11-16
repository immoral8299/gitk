// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

/// The first column scrolls horizontally, but the graph lanes stay visible and
/// the whole headline is drawn (not just the part inside the column width).
@MainActor
@Suite struct FirstColumnScrollTests {
    private func makeCell(labels: [GraphRowGeometry.RefLabel]) -> GraphCellView {
        let geometry = GraphRowGeometry(
            row: 0, commit: 0, segments: [], dotColumn: 0, dotStyle: .normal, arrows: [],
            textX: labels.isEmpty ? 80 : 140, labels: labels, hasNotes: false)
        let cell = GraphCellView()
        cell.frame = NSRect(x: 0, y: 0, width: 300, height: 20)
        cell.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        cell.geometry = geometry
        let headline = String(repeating: "a long commit subject ", count: 20)
        cell.attributedHeadline = NSAttributedString(
            string: headline, attributes: [.font: cell.font])
        return cell
    }

    private var headLabel: GraphRowGeometry.RefLabel {
        GraphRowGeometry.RefLabel(name: "main", text: "main", kind: .head, isBold: true,
                                  remotePrefix: nil, x: 100, width: 40, tagCount: 0)
    }

    @Test func scrollingMovesTextButKeepsTheGraphFixed() {
        let cell = makeCell(labels: [headLabel])
        #expect(cell.graphContentStart == 100)
        #expect(cell.contentClipRect.minX == 100)
        #expect(cell.textDrawRect.minX == 140)

        cell.contentOffset = 60
        #expect(cell.graphContentStart == 100)
        #expect(cell.contentClipRect.minX == 100)
        #expect(cell.textDrawRect.minX == 80)
    }

    @Test func longHeadlineIsDrawnWiderThanTheColumn() {
        let cell = makeCell(labels: [headLabel])
        let full = cell.attributedHeadline.size().width
        #expect(cell.textDrawRect.width >= full)
        #expect(cell.textDrawRect.width > cell.bounds.width)
    }

    @Test func withoutLabelsTheContentStartsAfterTheGraph() {
        let cell = makeCell(labels: [])
        #expect(cell.graphContentStart == 80)
        #expect(cell.contentClipRect.minX == 80)
        #expect(cell.textDrawRect.minX == 80)
    }
}
