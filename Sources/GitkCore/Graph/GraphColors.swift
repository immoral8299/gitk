// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// gitk's palette assignment and the drawing order that determines it.
public final class GraphColors {
    public let layout: GraphLayout
    public var palette: [String]
    public private(set) var colorMap: [CommitIndex: Int] = [:]
    var nextColor = 0
    var lineSegments: [CommitIndex: [Range<Int>]] = [:]
    var maxLineLen = 200

    public init(layout: GraphLayout, palette: [String] = ["#00ff00", "red", "blue", "magenta", "darkgrey", "brown", "orange"]) {
        self.layout = layout
        self.palette = palette.isEmpty ? ["black"] : palette
        layout.onDraw = { [weak self] first, last in self?.draw(first, last) }
    }

    public func reset() {
        colorMap = [:]
        nextColor = 0
        lineSegments = [:]
        layout.drawnIDs = []
    }

    public func color(of id: CommitIndex) -> Int { colorMap[id] ?? 0 }

    /// Port of gitk proc `findcrossings` (gitk/gitk 6633–6673).
    func findCrossings(_ id: CommitIndex) -> [CommitIndex?] {
        var cross: [CommitIndex] = []
        var corner: [CommitIndex] = []
        let ranges = layout.rowRanges(id)
        for i in stride(from: 0, to: ranges.count - ranges.count % 2, by: 2) {
            let start = ranges[i]
            let end = min(ranges[i + 1], layout.ordering.commitIdx - 1)
            if end <= start { continue }
            for row in stride(from: end - 1, through: start, by: -1) {
                guard let x = layout.ids(on: row).firstIndex(of: id) else { break }
                guard let kid = layout.commit(row), let kidx = layout.ids(on: row).firstIndex(of: kid) else { continue }
                let next = layout.ids(on: row + 1)
                for p in layout.parents(row) {
                    guard let px = next.firstIndex(of: p) else { continue }
                    if (kidx < x && x < px) || (px < x && x < kidx) {
                        if corner.contains(p) { continue }
                        if x == px + (kidx < px ? -1 : 1) {
                            corner.append(p)
                        } else if !cross.contains(p) {
                            cross.append(p)
                        }
                    }
                }
            }
        }
        return corner.map { Optional($0) } + [nil] + cross.map { Optional($0) }
    }

    /// Port of gitk proc `assigncolor` (gitk/gitk 6675–6731). The final
    /// lsearch is intentionally used as a Tcl boolean: only index zero is false.
    func assignColor(_ id: CommitIndex) {
        if colorMap[id] != nil { return }
        let ordering = layout.ordering
        let kids = ordering.children[id] ?? []
        if kids.count == 1, let child = kids.first, let color = colorMap[child], ordering.parents[child]?.count == 1 {
            colorMap[id] = color
            return
        }
        let count = palette.count
        var bad: [String] = []
        var original: [String] = []
        func addColor(_ id: CommitIndex) {
            if let color = colorMap[id], !bad.contains(palette[color]) { bad.append(palette[color]) }
        }
        for crossing in findCrossings(id) {
            if let crossing {
                addColor(crossing)
            } else {
                if bad.count >= count - 1 { break }
                original = bad
            }
        }
        if bad.count >= count { bad = original }
        original = bad
        if bad.count < count - 1 {
            for child in kids {
                addColor(child)
                for parent in ordering.parents[child] ?? [] { addColor(parent) }
            }
            if bad.count >= count { bad = original }
        }
        var selected = 0
        for _ in 0...count {
            selected = nextColor
            nextColor = (nextColor + 1) % count
            if bad.firstIndex(of: palette[selected]) != 0 { break }
        }
        colorMap[id] = selected
    }

    /// Port of the stateful portion of gitk proc `drawlineseg` (6074–6245).
    /// Canvas coordinates do not affect whether a new segment gets a colour.
    @discardableResult
    func drawLineSegment(_ id: CommitIndex, _ row: Int, _ end: Int) -> Int {
        var le = row + 1
        while true {
            if !layout.ids(on: le).contains(id) { le -= 1; break }
            let commit = layout.commit(le)
            if commit == id { break }
            if commit.map({ layout.drawnIDs.contains($0) }) == true || le == end { break }
            le += 1
        }
        if le <= row { return row }
        var lines = lineSegments[id] ?? []
        var i = 0
        var joinHigh = false
        for line in lines {
            if line.lowerBound > row {
                if line.lowerBound == le && line.upperBound - 1 - row <= maxLineLen { joinHigh = true }
                break
            }
            i += 1
        }
        let joinLow = i > 0 && lines[i - 1].upperBound - 1 == row && le - lines[i - 1].lowerBound <= maxLineLen
        if !joinLow {
            if !joinHigh {
                assignColor(id)
                lines.insert(row..<(le + 1), at: i)
            } else {
                lines[i] = row..<lines[i].upperBound
            }
        } else if !joinHigh {
            lines[i - 1] = lines[i - 1].lowerBound..<(le + 1)
        } else {
            let joined = lines[i - 1].lowerBound..<lines[i].upperBound
            lines.replaceSubrange((i - 1)...i, with: [joined])
        }
        lineSegments[id] = lines
        return le
    }

    /// Port of gitk proc `drawcommits` (gitk/gitk 6497–6538), invoking the
    /// colour-affecting parts of drawcmitrow, drawparentlinks and drawlineseg.
    func draw(_ first: Int, _ last: Int) {
        if layout.needRedisplay || layout.drawnIDs.count > 2000 {
            layout.drawnIDs = []
            lineSegments = [:]
            layout.needRedisplay = false
        }
        var row = first
        if let prior = layout.commit(first - 1), layout.drawnIDs.contains(prior) { row -= 1 }
        var end = last
        if let next = layout.commit(last + 1), layout.drawnIDs.contains(next) { end += 1 }
        var lineEnd: [CommitIndex: Int] = [:]
        while row <= end {
            defer { row += 1 }
            guard let id = layout.commit(row) else { continue }
            let wasDrawn = layout.drawnIDs.contains(id)
            if !wasDrawn && layout.ids(on: row).contains(id) {
                assignColor(id)
                layout.drawnIDs.insert(id)
            }
            if row == end { break }
            if wasDrawn, let next = layout.commit(row + 1), layout.drawnIDs.contains(next) { continue }
            let rowIDs = layout.ids(on: row)
            for parent in layout.parents(row) {
                if layout.ids(on: row + 1).contains(parent) && rowIDs.contains(parent) { assignColor(parent) }
            }
            for lineID in rowIDs.compactMap({ $0 }) {
                if let end = lineEnd[lineID], end > row { continue }
                if lineID == id {
                    for parent in layout.parents(row) where !rowIDs.contains(parent) {
                        lineEnd[parent] = drawLineSegment(parent, row, end)
                    }
                } else {
                    lineEnd[lineID] = drawLineSegment(lineID, row, end)
                }
            }
        }
    }
}
