// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Lazy lane layout for one view. Padding is represented by nil, matching
/// gitk's empty entries in rowidlist. Owned by the view's main-actor session.
public final class GraphLayout {
    public let ordering: VarcOrdering
    public internal(set) var rowIDList: [[CommitIndex?]] = []
    var rowIsOpt: [Bool] = []
    var rowFinal: [Bool] = []
    public var viewComplete = true
    public var upArrowLen = 5
    public var downArrowLen = 5
    public var minGapLen = 100
    public internal(set) var needRedisplay = false
    var drawnIDs: Set<CommitIndex> = []
    var onDraw: ((Int, Int) -> Void)?

    public init(ordering: VarcOrdering) {
        self.ordering = ordering
        ordering.undoLayout = { [weak self] row in self?.undoLayout(row) }
    }

    /// Port of gitk proc `ordertoken` (gitk/gitk 5306–5351).
    func orderToken(_ original: CommitIndex?) -> String {
        guard let original else { return "" }
        if let token = ordering.orderTok[original] { return token }
        var id = original
        var todo: [(CommitIndex, String)] = []
        var token: String
        while true {
            let p: CommitIndex
            if let arc = ordering.varcID[id], let start = ordering.varcStart[arc] {
                p = start
            } else if let child = ordering.children[id]?.first {
                p = child
            } else {
                return ""
            }
            if let cached = ordering.orderTok[p] {
                token = cached
                break
            }
            guard let child = ordering.firstRealChild(p) else {
                token = ordering.varcTok[ordering.varcID[p] ?? 0]
                break
            }
            id = child
            let parents = ordering.parents[child] ?? []
            todo.append((p, parents.count == 1 ? "" : strrep(parents.firstIndex(of: p) ?? -1)))
        }
        for (p, suffix) in todo.reversed() {
            token += suffix
            ordering.orderTok[p] = token
        }
        ordering.orderTok[original] = token
        return token
    }

    /// Port of gitk proc `idcol` (gitk/gitk 5355–5376).
    func idCol(_ list: [CommitIndex?], _ id: CommitIndex, _ start: Int = 0) -> Int {
        let token = orderToken(id)
        var i = max(0, start)
        if i >= list.count || token < orderToken(list[i]) {
            i = min(i, list.count) - 1
            while i >= 0 && token < orderToken(list[i]) { i -= 1 }
            i += 1
        } else if token > orderToken(list[i]) {
            i += 1
            while i < list.count && token >= orderToken(list[i]) { i += 1 }
        }
        return i
    }

    /// Port of gitk proc `initlayout` (gitk/gitk 5378–5395). Commit storage
    /// stays with the ordering; the session resets it when beginning a load.
    public func reset() {
        rowIDList = []
        rowIsOpt = []
        rowFinal = []
        ordering.orderTok = [:]
        needRedisplay = false
        drawnIDs = []
    }

    /// Port of gitk proc `setcanvscroll` (gitk/gitk 5397–5409), geometry only.
    public func scrollHeight(lineSpacing: Double, originY: Double = 3) -> Double {
        originY + (Double(ordering.commitIdx) - 0.5) * lineSpacing + 2
    }

    /// Port of gitk proc `nextuse` (gitk/gitk 5604–5620).
    func nextUse(_ id: CommitIndex, _ row: Int) -> Int {
        for child in ordering.children[id] ?? [] {
            guard ordering.commitInView(child) else { return -1 }
            if let r = ordering.rowOfCommit(child), r > row { return r }
        }
        return ordering.rowOfCommit(id) ?? -1
    }

    /// Port of gitk proc `prevuse` (gitk/gitk 5622–5636).
    func prevUse(_ id: CommitIndex, _ row: Int) -> Int {
        var result = -1
        for child in ordering.children[id] ?? [] {
            guard ordering.commitInView(child) else { break }
            if let r = ordering.rowOfCommit(child), r < row { result = r }
        }
        return result
    }

    func ids(on row: Int) -> [CommitIndex?] {
        rowIDList.indices.contains(row) ? rowIDList[row] : []
    }

    func commit(_ row: Int) -> CommitIndex? {
        ordering.displayOrder.indices.contains(row) ? ordering.displayOrder[row] : nil
    }

    func parents(_ row: Int) -> [CommitIndex] {
        ordering.parentList.indices.contains(row) ? ordering.parentList[row] : []
    }

    /// Port of gitk proc `make_idlist` (gitk/gitk 5638–5706).
    func makeIDList(_ row: Int) -> [CommitIndex?] {
        var r = max(0, row - minGapLen - downArrowLen - 1)
        let ra = max(0, row - downArrowLen)
        let rb = min(row + upArrowLen, ordering.commitIdx)
        ordering.makeDisporder(r, rb + 1)
        var ids: Set<CommitIndex> = []
        while r < ra {
            let nextID = commit(r + 1)
            for p in parents(r) where p != nextID {
                let rn = nextUse(p, r)
                if rn >= row && rn <= r + downArrowLen + minGapLen + upArrowLen { ids.insert(p) }
            }
            r += 1
        }
        while r < row {
            let nextID = commit(r + 1)
            for p in parents(r) where p != nextID {
                let rn = nextUse(p, r)
                if rn < 0 || rn >= row { ids.insert(p) }
            }
            r += 1
        }
        if let id = commit(row) { ids.insert(id) }
        while r < rb {
            for p in parents(r) {
                if let first = ordering.children[p]?.first,
                   (ordering.rowOfCommit(first) ?? -1) < row { ids.insert(p) }
            }
            r += 1
            if let id = commit(r), let first = ordering.children[id]?.first,
               (ordering.rowOfCommit(first) ?? -1) < row { ids.insert(id) }
        }
        return ids.sorted {
            let a = orderToken($0), b = orderToken($1)
            return a == b ? ordering.store.id(at: $0) < ordering.store.id(at: $1) : a < b
        }.map { Optional($0) }
    }

    /// Port of gitk proc `rowsequal` (gitk/gitk 5708–5718).
    func rowsEqual(_ a: [CommitIndex?], _ b: [CommitIndex?]) -> Bool {
        a.compactMap { $0 } == b.compactMap { $0 }
    }

    /// Port of gitk proc `makeupline` (gitk/gitk 5720–5742).
    func makeUpLine(_ id: CommitIndex, _ row: Int, _ end: Int, _ column: Int) {
        var r = end
        var start: Int
        while true {
            start = prevUse(id, r)
            if start < 0 { return }
            if start < row { break }
            r = start
        }
        if start + upArrowLen + minGapLen + downArrowLen < end { start = end - upArrowLen - 1 }
        var col = column
        r = start + 1
        while r <= row {
            var list = ids(on: r)
            if !list.isEmpty && !list.contains(id) {
                col = idCol(list, id, col)
                list.insert(id, at: col)
                rowIDList[r] = list
                changedRow(r)
            }
            r += 1
        }
    }

    /// Port of gitk proc `layoutrows` (gitk/gitk 5744–5840).
    @discardableResult
    func layoutRows(_ start: Int, _ end: Int) -> Int {
        ordering.makeDisporder(start - 1, end + upArrowLen)
        var list: [CommitIndex?] = start > 0 ? ids(on: start - 1).compactMap { $0 } : []
        var final = start > 0 && rowFinal.indices.contains(start - 1) ? rowFinal[start - 1] : true
        var row = start
        while row < end {
            let previous = row - 1
            if previous < 0 || list.isEmpty {
                list = makeIDList(row)
                final = true
            } else {
                let previousID = commit(previous)
                // Tcl lreplace with -1 -1 leaves the list unchanged.
                var col = list.firstIndex(of: previousID) ?? -1
                if col >= 0 { list.remove(at: col) }
                for p in parents(previous) where !list.contains(p) {
                    col = idCol(list, p, col)
                    list.insert(p, at: col)
                    if previousID != ordering.children[p]?.first { makeUpLine(p, previous, row, col) }
                }
                if row > downArrowLen {
                    let term = row - downArrowLen - 1
                    for p in parents(term) {
                        guard let i = list.firstIndex(of: p) else { continue }
                        let nr = nextUse(p, term)
                        if nr < 0 || nr >= row + minGapLen + upArrowLen { list.remove(at: i) }
                    }
                }
                if let id = commit(row) {
                    col = list.firstIndex(of: id) ?? -1
                    if col < 0 {
                        col = idCol(list, id)
                        list.insert(id, at: col)
                        if !(ordering.children[id] ?? []).isEmpty { makeUpLine(id, previous, row, col) }
                    }
                }
                var r = row + upArrowLen - 1
                if r < ordering.commitIdx {
                    var x = col
                    for p in parents(r) where !list.contains(p) {
                        if let first = ordering.children[p]?.first,
                           (ordering.rowOfCommit(first) ?? -1) < row {
                            x = idCol(list, p, x)
                            list.insert(p, at: x)
                        }
                    }
                    r += 1
                    if r < ordering.commitIdx, let p = commit(r), !list.contains(p),
                       let first = ordering.children[p]?.first,
                       (ordering.rowOfCommit(first) ?? -1) < row {
                        x = idCol(list, p, x)
                        list.insert(p, at: x)
                    }
                }
            }
            if final && !viewComplete && row + upArrowLen + minGapLen + downArrowLen >= ordering.commitIdx {
                final = false
            }
            if row == rowIDList.count {
                rowIDList.append(list)
                rowIsOpt.append(false)
                rowFinal.append(final)
            } else if row < rowIDList.count {
                if !rowsEqual(list, rowIDList[row]) {
                    rowIDList[row] = list
                    changedRow(row)
                }
                rowFinal[row] = final
            } else {
                let pad = row - rowIDList.count
                rowIDList.append(contentsOf: Array(repeating: [], count: pad))
                rowIDList.append(list)
                rowFinal.append(contentsOf: Array(repeating: false, count: pad))
                rowFinal.append(final)
                rowIsOpt.append(contentsOf: Array(repeating: false, count: pad + 1))
            }
            row += 1
        }
        return row
    }

    /// Port of gitk proc `changedrow` (gitk/gitk 5842–5859).
    func changedRow(_ row: Int) {
        for r in row..<min(row + 3, rowIsOpt.count) { rowIsOpt[r] = false }
        if let id = commit(row), drawnIDs.contains(id) { needRedisplay = true }
    }

    /// Port of gitk proc `insert_pad` (gitk/gitk 5861–5875).
    func insertPad(_ row: Int, _ column: Int, _ count: Int) {
        let list = ids(on: row)
        let before = Array(list.prefix(max(0, column)))
        var after = Array(list.dropFirst(max(0, column)))
        if let i = after.firstIndex(of: nil), i > 0 { after.remove(at: i) }
        rowIDList[row] = before + Array(repeating: nil, count: count) + after
        changedRow(row)
    }

    /// Port of gitk proc `optimize_rows` (gitk/gitk 5877–5996).
    func optimizeRows(_ start: Int, _ column: Int, _ end: Int) {
        var row = max(1, start)
        var col = column
        while row < end {
            defer { row += 1; col = 0 }
            if rowIsOpt.indices.contains(row), rowIsOpt[row] { continue }
            var hasPad = false
            let y0 = row - 1, ym = row - 2
            var list = ids(on: row), previous = ids(on: y0)
            if list.isEmpty || previous.isEmpty { continue }
            var prior = ym >= 0 ? ids(on: ym) : []
            if ym >= 0 && prior.isEmpty { continue }
            var x0 = -1
            while col < list.count {
                defer { col += 1 }
                let id = list[col]
                if (previous.indices.contains(col) ? previous[col] : nil) == id { continue }
                guard let id else { hasPad = true; continue }
                x0 = previous.firstIndex(of: id) ?? -1
                if x0 < 0 { continue }
                var z = x0 - col
                var isArrow = false
                var z0: Int?
                if ym >= 0, let xm = prior.firstIndex(of: id) { z0 = xm - x0 }
                if z0 == nil && ordering.children[id]?.first != commit(y0) { isArrow = true }
                if !isArrow && id != commit(row) && !ids(on: row + 1).contains(id) { isArrow = true }
                if z < -1 || (z < 0 && isArrow) {
                    insertPad(y0, x0, -1 - z + (isArrow ? 1 : 0))
                    if y0 > 0 { optimizeRows(y0, x0, row) }
                    previous = ids(on: y0)
                    x0 = previous.firstIndex(of: id) ?? -1
                    z = x0 - col
                    if z0 != nil {
                        prior = ids(on: ym)
                        z0 = (prior.firstIndex(of: id) ?? -1) - x0
                    }
                } else if z > 1 || (z > 0 && isArrow) {
                    let count = z - 1 + (isArrow ? 1 : 0)
                    insertPad(row, col, count)
                    list = ids(on: row)
                    col += count
                    z = x0 - col
                    hasPad = true
                }
                if z0 == nil && !isArrow && ym >= 0, let child = commit(ym),
                   let xc = prior.firstIndex(of: child) { z0 = xc - x0 }
                if let z0, z < 0 && z0 > 0 {
                    insertPad(y0, x0, 1)
                    x0 += 1
                    optimizeRows(y0, x0, row)
                    previous = ids(on: y0)
                }
            }
            if !hasPad {
                col = list.count - 1
                while col >= 0 {
                    guard let id = list[col] else { break }
                    x0 = previous.firstIndex(of: id) ?? -1
                    if x0 < 0 {
                        let child = commit(y0)
                        if ordering.children[id]?.first == child { x0 = previous.firstIndex(of: child) ?? -1 }
                    }
                    if x0 <= col { break }
                    col -= 1
                }
                col += 1
                if x0 >= 0 && col < list.count {
                    list.insert(nil, at: col)
                    rowIDList[row] = list
                    changedRow(row)
                }
            }
        }
    }

    /// Port of gitk proc `rowranges` (gitk/gitk 6018–6072).
    public func rowRanges(_ id: CommitIndex) -> [Int] {
        let children = ordering.children[id] ?? []
        if children.isEmpty { return [] }
        var result: [Int] = []
        var previousRow: Int?
        for child in children + [id] {
            guard ordering.commitInView(child), let row = ordering.rowOfCommit(child) else { break }
            if let previous = previousRow {
                if row > previous + upArrowLen + downArrowLen && !ids(on: (row + previous) / 2).contains(id) {
                    var r = previous + downArrowLen
                    if !ids(on: r).contains(id) {
                        r -= 1
                        while r > previous && !ids(on: r).contains(id) { r -= 1 }
                    } else {
                        r += 1
                        while r <= row && ids(on: r).contains(id) { r += 1 }
                        r -= 1
                    }
                    result.append(r)
                    r = row - upArrowLen
                    if !ids(on: r).contains(id) {
                        r += 1
                        while r < row && !ids(on: r).contains(id) { r += 1 }
                    } else {
                        r -= 1
                        while r >= previous && ids(on: r).contains(id) { r -= 1 }
                        r += 1
                    }
                    result.append(r)
                }
            } else {
                result.append(row + 1)
            }
            if child == id { result.append(row) }
            previousRow = row
        }
        return result
    }

    /// Port of gitk proc `undolayout` (gitk/gitk 6540–6558).
    public func undoLayout(_ row: Int) {
        let keep = max(0, row - upArrowLen - minGapLen - downArrowLen)
        if rowIDList.count > keep {
            rowIDList = Array(rowIDList.prefix(keep))
            rowFinal = Array(rowFinal.prefix(keep))
            rowIsOpt = Array(rowIsOpt.prefix(keep))
            needRedisplay = true
        }
    }

    /// Port of the layout portion of gitk proc `drawcommits` (6459–6500).
    /// The range is inclusive, matching gitk's drawing loop.
    func drawCommits(_ first: Int, _ last: Int) {
        let first = max(0, first)
        let last = min(last, ordering.commitIdx - 1)
        if first > last { return }
        var lower = max(0, first - downArrowLen - 3)
        let optimizeStart = max(0, first - 3)
        let upper = min(last + upArrowLen + 3, ordering.commitIdx)
        for row in lower..<upper {
            if !ids(on: row).isEmpty && rowFinal[row] {
                if lower < row { layoutRows(lower, row) }
                lower = row + 1
            }
        }
        if lower < upper { layoutRows(lower, upper) }
        optimizeRows(optimizeStart, 0, upper)
        onDraw?(first, last)
    }

    /// Port of gitk proc `drawvisible` (gitk/gitk 6560–6612), expressed in
    /// table rows. The two-row leading margin and inclusive trailing row are
    /// the integer arithmetic of gitk's canvas viewport at 18 points per row.
    public func ensureLaid(visibleRows: Range<Int>) {
        guard !visibleRows.isEmpty && ordering.commitIdx > 0 else { return }
        ordering.updateArcrows()
        drawCommits(visibleRows.lowerBound - 2, visibleRows.upperBound)
    }
}
