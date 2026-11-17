// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// UI-free geometry in lane units. Y is normalized within a table row:
/// 0 at its top, 0.5 at its centre and 1 at its bottom.
public struct GraphRowGeometry: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public var column: Double
        public var y: Double
    }
    public struct Segment: Sendable, Equatable {
        public var id: CommitIndex
        public var from: Point
        public var to: Point
        public var colorIndex: Int
        public var thick: Bool
    }
    public enum DotStyle: Sendable {
        case normal, boundary, mainHead, unstaged, staged, negative, left, right
    }
    public struct Arrow: Sendable, Equatable {
        public enum Direction: Sendable { case up, down }
        public var id: CommitIndex
        public var column: Int
        public var direction: Direction
        public var targetRow: Int
        public var colorIndex: Int
    }
    public struct RefLabel: Sendable, Equatable {
        public enum Kind: Sendable { case tag, collapsedTags, head, remote, other }
        public var name: String
        public var text: String
        public var kind: Kind
        public var isBold: Bool
        public var remotePrefix: String?
        public var x: Double
        public var width: Double
        public var tagCount: Int
    }

    public var row: Int
    public var commit: CommitIndex
    public var segments: [Segment]
    public var dotColumn: Int
    public var dotStyle: DotStyle
    public var arrows: [Arrow]
    public var textX: Double
    public var labels: [RefLabel]
    public var hasNotes: Bool

    /// Port of gitk procs `drawlineseg`, `drawparentlinks`, `drawcmittext`
    /// (6074–6417), and `xc`/`yc`/`linewidth` (5998–6016). Segments are
    /// clipped at table-row boundaries so cells can draw independently.
    public static func make(
        row: Int, layout: GraphLayout, colors: GraphColors, refs: RefSet = RefSet(),
        columnWidth: Double = 800, maxWidth: Int = 16, maxGraphPct: Int = 50,
        lineSpacing: Double = 18, thickLine: CommitIndex? = nil
    ) -> GraphRowGeometry? {
        guard let id = layout.ordering.commitOnRow(row) else { return nil }
        layout.ensureLaid(visibleRows: row..<(row + 1))
        let ordering = layout.ordering
        let list = layout.ids(on: row)
        guard let column = list.firstIndex(of: id) else { return nil }
        var segments: [Segment] = []
        func addPath(_ path: [Point], id: CommitIndex) {
            for (a, b) in zip(path, path.dropFirst()) {
                var from = a, to = b
                let low = Double(row) - 0.5, high = Double(row) + 0.5
                if max(a.y, b.y) < low || min(a.y, b.y) > high { continue }
                if a.y != b.y {
                    let lower = max(0, min(1, (low - a.y) / (b.y - a.y)))
                    let upper = max(0, min(1, (high - a.y) / (b.y - a.y)))
                    let t0 = min(lower, upper), t1 = max(lower, upper)
                    from = Point(column: a.column + (b.column - a.column) * t0, y: a.y + (b.y - a.y) * t0)
                    to = Point(column: a.column + (b.column - a.column) * t1, y: a.y + (b.y - a.y) * t1)
                }
                if from == to { continue }
                from.y -= low
                to.y -= low
                segments.append(Segment(id: id, from: from, to: to, colorIndex: colors.color(of: id), thick: thickLine == id))
            }
        }
        for r in max(0, row - 1)...row {
            guard let child = layout.commit(r) else { continue }
            let current = layout.ids(on: r), next = layout.ids(on: r + 1)
            for line in current.compactMap({ $0 }) where line != child {
                if let a = current.firstIndex(of: line), let b = next.firstIndex(of: line) {
                    addPath([Point(column: Double(a), y: Double(r)), Point(column: Double(b), y: Double(r + 1))], id: line)
                }
            }
            guard let source = current.firstIndex(of: child) else { continue }
            for parent in layout.parents(r) {
                guard let target = next.firstIndex(of: parent) else { continue }
                let previous = current.firstIndex(of: parent)
                var path = [Point(column: Double(source), y: Double(r))]
                if target != source {
                    let vertical = previous == target || (previous == nil && layout.ids(on: r + 2).firstIndex(of: parent) == target)
                    if vertical {
                        path.append(Point(column: Double(target) + (target < source ? 0.5 : -0.5), y: Double(r)))
                        path.append(Point(column: Double(target), y: Double(r) + 0.5))
                    } else if let previous, target < source && target < previous {
                        path.append(Point(column: Double(previous), y: Double(r)))
                        addPath(path, id: parent)
                        continue
                    } else if abs(target - source) > 1 {
                        path.append(Point(column: Double(target + (target < source ? 1 : -1)), y: Double(r)))
                    }
                }
                path.append(Point(column: Double(target), y: Double(r + 1)))
                addPath(path, id: parent)
            }
        }
        var arrows: [Arrow] = []
        for line in list.compactMap({ $0 }) {
            let ranges = layout.rowRanges(line)
            for i in stride(from: 0, to: ranges.count - ranges.count % 2, by: 2) {
                let start = ranges[i], end = ranges[i + 1]
                if row == start && i > 0, let c = list.firstIndex(of: line) {
                    arrows.append(Arrow(id: line, column: c, direction: .up, targetRow: ranges[i - 1], colorIndex: colors.color(of: line)))
                }
                if row == end && i + 2 < ranges.count, let c = list.firstIndex(of: line) {
                    arrows.append(Arrow(id: line, column: c, direction: .down, targetRow: ranges[i + 2], colorIndex: colors.color(of: line)))
                }
            }
        }
        let oid = ordering.store.id(at: id)
        let style: DotStyle
        if oid == ordering.nullID { style = .unstaged }
        else if oid == ordering.nullID2 { style = .staged }
        else if oid == refs.mainHeadID { style = .mainHead }
        else {
            switch ordering.cmitListed[id] ?? 1 {
            case 0: style = .boundary
            case 2: style = .negative
            case 3: style = .left
            case 4: style = .right
            default: style = .normal
            }
        }
        // gitk keeps the text on a parent's lane when the merge line opens a new
        // lane at `list.count`, so the line runs into the text and the graph
        // clip cuts it in half. Start the text one lane past any parent lane.
        var rightmost = list.count
        for parent in layout.parents(row) {
            if let target = layout.ids(on: row + 1).firstIndex(of: parent) {
                rightmost = max(rightmost, target + 1)
            }
        }
        let origin = floor(3 + 0.5 * lineSpacing)
        let width = max(0, min(Double(maxWidth) * lineSpacing, columnWidth * Double(maxGraphPct) / 100))
        let textX = min(origin + Double(rightmost) * lineSpacing, origin + width)
        return GraphRowGeometry(row: row, commit: id, segments: segments, dotColumn: column,
            dotStyle: style, arrows: arrows, textX: textX, labels: [], hasNotes: ordering.store.hasNotes(id))
    }

    /// Port of gitk procs `drawtags` and `drawnotesign` (6753–6880).
    /// The measuring closure is supplied by the UI's actual font metrics.
    /// `tagPadding` widens tag labels beyond gitk's size (0 keeps gitk's).
    public func addingRefLabels(
        refs: RefSet, store: CommitStore, columnWidth: Double,
        lineSpacing: Double = 18, lineThickness: Double = 1, tagPadding: Double = 0,
        measure: (String, Bool) -> Double
    ) -> GraphRowGeometry {
        var result = self
        let oid = store.id(at: commit)
        let tags = refs.tags(of: oid)
        let delta = floor(0.5 * (lineSpacing - lineThickness))
        let extra = delta + lineThickness + lineSpacing / 2
        let collapse = tags.count > 3 || tags.reduce(0) { $0 + measure($1, false) + extra } > columnWidth * 0.25
        var labels: [(String, String, RefLabel.Kind, Int)] = []
        if collapse && !tags.isEmpty {
            labels.append((tags.joined(separator: "\n"), tags.count == 1 ? "tag..." : "\(tags.count) tags...", .collapsedTags, tags.count))
        } else {
            labels += tags.map { ($0, $0, .tag, 1) }
        }
        labels += refs.heads(of: oid).map { ($0, $0, $0.hasPrefix("remotes/") ? .remote : .head, 0) }
        labels += refs.otherRefs(of: oid).map { ($0, $0, .other, 0) }
        var x = textX
        result.labels = labels.map { name, text, kind, count in
            let bold = (kind == .head || kind == .remote) && name == refs.mainHeadName
            let isTag = kind == .tag || kind == .collapsedTags
            let width = measure(text, bold) + extra + (isTag ? tagPadding : 0)
            let prefix: String?
            if kind == .remote {
                let parts = name.split(separator: "/", omittingEmptySubsequences: false)
                prefix = parts.count >= 3 ? parts.prefix(2).joined(separator: "/") + "/" : "remotes/"
            } else { prefix = nil }
            defer { x += width }
            return RefLabel(name: name, text: text, kind: kind, isBold: bold, remotePrefix: prefix, x: x, width: width, tagCount: count)
        }
        if hasNotes { x += lineSpacing }
        result.textX = x
        return result
    }
}
