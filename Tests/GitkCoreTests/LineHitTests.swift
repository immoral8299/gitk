// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct LineHitTests {
    private func geometry(segments: [GraphRowGeometry.Segment] = [], arrows: [GraphRowGeometry.Arrow] = [])
        -> GraphRowGeometry {
        GraphRowGeometry(row: 0, commit: 0, segments: segments, dotColumn: 0, dotStyle: .normal, arrows: arrows,
                         textX: 100, labels: [], hasNotes: false)
    }
    private func seg(_ id: CommitIndex, _ a: (Double, Double), _ b: (Double, Double)) -> GraphRowGeometry.Segment {
        .init(id: id, from: .init(column: a.0, y: a.1), to: .init(column: b.0, y: b.1), colorIndex: 0, thick: false)
    }

    @Test func clickOnVerticalLineBelowDotHitsItsParent() {
        let g = geometry(segments: [seg(7, (0, 0.5), (0, 1))])
        // rowHeight 18: origin x = floor(3 + 9) = 12
        #expect(LineHitTest.hit(in: g, x: 13, y: 17.5, rowHeight: 18) == .line(7))
        #expect(LineHitTest.hit(in: g, x: 20, y: 17.5, rowHeight: 18) == nil)
    }

    @Test func dotAndTextAreAreNotLines() {
        let g = geometry(segments: [seg(7, (0, 0), (0, 1))])
        #expect(LineHitTest.hit(in: g, x: 12, y: 9, rowHeight: 18) == nil)
        #expect(LineHitTest.hit(in: g, x: 150, y: 3, rowHeight: 18) == nil)
    }

    @Test func diagonalToleranceIsLineThicknessPlusTwo() {
        let g = geometry(segments: [seg(3, (0, 0.5), (1, 1))])
        #expect(LineHitTest.hit(in: g, x: 21, y: 13.5, rowHeight: 18) == .line(3))
        #expect(LineHitTest.hit(in: g, x: 12, y: 18, rowHeight: 18, lineThickness: 1) == nil)
    }

    @Test func clickNearArrowReturnsArrow() {
        let arrow = GraphRowGeometry.Arrow(id: 4, column: 0, direction: .down, targetRow: 90, colorIndex: 0)
        let g = geometry(segments: [seg(4, (0, 0), (0, 0.5))], arrows: [arrow])
        #expect(LineHitTest.hit(in: g, x: 12, y: 9, rowHeight: 18) == .arrow(arrow))
        // More than 2 * thickness + 6 above the row centre it is the plain line.
        #expect(LineHitTest.hit(in: g, x: 12, y: 0.5, rowHeight: 18) == .line(4))
    }

    @Test func arrowThresholdMatchesGitk() {
        #expect(LineHitTest.arrowThreshold() == 8)
        #expect(LineHitTest.arrowThreshold(lineThickness: 2) == 10)
    }

    @Test func arrowJumpCentresTargetAndClamps() {
        #expect(LineHitTest.arrowJumpOffset(row: 100, rowHeight: 18, viewportHeight: 360, contentHeight: 18000) == 100 * 18 + 9 - 180)
        #expect(LineHitTest.arrowJumpOffset(row: 2, rowHeight: 18, viewportHeight: 360, contentHeight: 18000) == 0)
        #expect(LineHitTest.arrowJumpOffset(row: 999, rowHeight: 18, viewportHeight: 360, contentHeight: 18000) == 18000 - 360)
    }

    @Test func realArrowsAreHitAtTheirColumn() async throws {
        let layout = try await LayoutTestSupport.graph("long-lines")
        let colors = GraphColors(layout: layout)
        for row in stride(from: 0, to: layout.ordering.commitIdx, by: 50) { layout.ensureLaid(visibleRows: row..<(row + 50)) }
        var checked = 0
        for row in 0..<layout.ordering.commitIdx {
            let g = try #require(GraphRowGeometry.make(row: row, layout: layout, colors: colors))
            for arrow in g.arrows {
                #expect(LineHitTest.hit(in: g, x: 12 + Double(arrow.column) * 18, y: 9, rowHeight: 18) == .arrow(arrow))
                #expect(arrow.targetRow != row)
                checked += 1
            }
        }
        #expect(checked > 0)
    }
}
