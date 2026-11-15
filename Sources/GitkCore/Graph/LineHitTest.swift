// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// What a click in a graph cell landed on.
public enum LineHit: Sendable, Equatable {
    case line(CommitIndex)
    case arrow(GraphRowGeometry.Arrow)
}

/// Hit-testing of graph lines and arrows on a row's geometry, in cell points
/// (x from the cell's left edge, y from its top, `rowHeight` = gitk's `linespc`).
public enum LineHitTest {
    /// Port of the threshold in gitk proc `clickisonarrow` (gitk/gitk 9037–9049).
    public static func arrowThreshold(lineThickness: Double = 1) -> Double { 2 * lineThickness + 6 }

    /// How close a click must be to a segment to count as on the line.
    public static func lineTolerance(lineThickness: Double = 1) -> Double { lineThickness + 2 }

    /// Port of the hit part of gitk procs `lineclick` and `clickisonarrow`
    /// (gitk/gitk 9037–9101). A click near the row centre on a line that has an
    /// arrow in this row is an arrow click; the dot and the text area are not
    /// part of any line.
    public static func hit(
        in geometry: GraphRowGeometry, x: Double, y: Double, rowHeight: Double, lineThickness: Double = 1
    ) -> LineHit? {
        let originX = floor(3 + 0.5 * rowHeight)
        let middle = rowHeight / 2
        let nearMiddle = abs(middle - y) < arrowThreshold(lineThickness: lineThickness)
        if let arrow = geometry.arrows.first(where: {
            abs(originX + Double($0.column) * rowHeight - x) < 6 && nearMiddle
        }) { return .arrow(arrow) }
        guard x < geometry.textX else { return nil }
        let dotX = originX + Double(geometry.dotColumn) * rowHeight
        if hypot(x - dotX, y - middle) <= rowHeight / 3 + 2 { return nil }
        let tolerance = lineTolerance(lineThickness: lineThickness)
        for segment in geometry.segments {
            let a = (x: originX + segment.from.column * rowHeight, y: segment.from.y * rowHeight)
            let b = (x: originX + segment.to.column * rowHeight, y: segment.to.y * rowHeight)
            guard distance(x: x, y: y, from: a, to: b) < tolerance else { continue }
            if nearMiddle, let arrow = geometry.arrows.first(where: { $0.id == segment.id }) { return .arrow(arrow) }
            return .line(segment.id)
        }
        return nil
    }

    /// Port of the scroll maths of gitk proc `arrowjump` (gitk/gitk 9051–9066):
    /// the top of the view that centres `row`, never above the first row and
    /// never past the end of the content.
    public static func arrowJumpOffset(row: Int, rowHeight: Double, viewportHeight: Double, contentHeight: Double) -> Double {
        let centre = (Double(row) + 0.5) * rowHeight
        return max(0, min(centre - viewportHeight / 2, max(0, contentHeight - viewportHeight)))
    }

    static func distance(x: Double, y: Double, from a: (x: Double, y: Double), to b: (x: Double, y: Double)) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let t = length > 0 ? max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / length)) : 0
        return hypot(x - a.x - t * dx, y - a.y - t * dy)
    }
}
