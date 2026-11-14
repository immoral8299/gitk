// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

extension AncestryIndex {
    /// Port of gitk proc `desctags` (gitk/gitk 11098–11246).
    public func descendantTags(of id: ObjectID) -> [ObjectID] {
        nearestTags(to: id, ancestors: false)
    }

    /// Port of gitk proc `anctags` (gitk/gitk 11248–11394).
    public func ancestorTags(of id: ObjectID) -> [ObjectID] {
        nearestTags(to: id, ancestors: true)
    }

    private func nearestTags(to argument: ObjectID, ancestors: Bool) -> [ObjectID] {
        guard var id = index(of: argument), allParents[Int(id)] != nil else { return [] }
        if let incoming = arcNos[Int(id)], incoming.count == 1, allParents[Int(id)]?.count == 1 {
            let a = incoming[0]
            validateArcTags(a)
            let i = arcIDs[a].firstIndex(of: id) ?? -1
            if ancestors {
                if let tag = arcTags[a].first(where: { (arcIDs[a].firstIndex(of: $0) ?? -1) > i }) {
                    return [ids[Int(tag)]]
                }
                guard let end = arcEnd[a] else { return [] }
                id = end
            } else {
                if let tag = arcTags[a].last(where: { (arcIDs[a].firstIndex(of: $0) ?? -1) < i }) {
                    return [ids[Int(tag)]]
                }
                guard let start = arcStart[a] else { return [] }
                id = start
            }
            if refs.idTags[ids[Int(id)]] != nil { return [ids[Int(id)]] }
        }
        let origin = id
        var todo = [id]
        var queued: Set<CommitIndex> = [id]
        var done = Set<CommitIndex>()
        var eclipsed = Set<CommitIndex>()
        var locations: [CommitIndex: [CommitIndex]] = [:]
        var remaining = 1
        var i = 0
        func arcs(_ node: CommitIndex) -> [Int] {
            (ancestors ? arcOut[Int(node)] : arcNos[Int(node)]) ?? []
        }
        func otherEnd(_ a: Int) -> CommitIndex? { ancestors ? arcEnd[a] : arcStart[a] }
        while i < todo.count && remaining > 0 {
            id = todo[i]
            done.insert(id)
            var tagged = eclipsed.contains(id)
            if !tagged { remaining -= 1 }
            if !tagged && i > 0, refs.idTags[ids[Int(id)]] != nil {
                locations[id] = [id]
                tagged = true
            }
            for a in arcs(id) {
                validateArcTags(a)
                if !tagged, let tag = ancestors ? arcTags[a].first : arcTags[a].last {
                    locations[id, default: []].append(tag)
                }
                guard let d = otherEnd(a) else { continue }
                if tagged || !arcTags[a].isEmpty {
                    var mark = [d]
                    var j = 0
                    while j < mark.count {
                        let dd = mark[j]
                        j += 1
                        if eclipsed.insert(dd).inserted {
                            if done.contains(dd) {
                                mark += arcs(dd).compactMap(otherEnd)
                                locations[dd] = nil
                            } else if queued.contains(dd) { remaining -= 1 }
                        }
                    }
                }
                if queued.insert(d).inserted {
                    todo.append(d)
                    if !eclipsed.contains(d) { remaining += 1 }
                }
            }
            i += 1
        }
        var tags: [CommitIndex] = []
        for node in locations.keys.sorted() where !eclipsed.contains(node) {
            for tag in locations[node] ?? [] where !tags.contains(tag) { tags.append(tag) }
        }
        let candidates = tags
        tags = candidates.filter { a in
            !candidates.contains { b in
                a != b && ancOrDesc(ids[Int(a)], ids[Int(b)]) == (ancestors ? 1 : -1)
            }
        }
        if !growing.isEmpty {
            tags = tags.filter { t in
                ancestors ? isCertain(descendant: ids[Int(origin)], ancestor: ids[Int(t)])
                    : isCertain(descendant: ids[Int(t)], ancestor: ids[Int(origin)])
            }
        }
        return tags.map { ids[Int($0)] }
    }

    /// Port of gitk proc `descheads` (gitk/gitk 11398–11452).
    public func descendantHeads(of argument: ObjectID) -> [ObjectID] {
        guard var id = index(of: argument), allParents[Int(id)] != nil else { return [] }
        var onArc: [CommitIndex] = []
        if arcOut[Int(id)] == nil, let a = arcNos[Int(id)]?.first {
            validateArcHeads(a)
            let i = arcIDs[a].firstIndex(of: id) ?? -1
            onArc = arcHeads[a].prefix { (arcIDs[a].firstIndex(of: $0) ?? -1) <= i }.map { $0 }
            guard let start = arcStart[a] else { return [] }
            id = start
        }
        var todo = [id]
        var seen: Set<CommitIndex> = [id]
        var result = Set<CommitIndex>()
        var i = 0
        while i < todo.count {
            id = todo[i]
            i += 1
            if refs.idHeads[ids[Int(id)]] != nil { result.insert(id) }
            for a in arcNos[Int(id)] ?? [] {
                validateArcHeads(a)
                result.formUnion(arcHeads[a])
                if let d = arcStart[a], seen.insert(d).inserted { todo.append(d) }
            }
        }
        return result.map { ids[Int($0)] }.sorted() + onArc.map { ids[Int($0)] }
    }
}

/// Names and commit links for one nearby-ref header line. UI localizes overflowKey.
public struct NearbyRefLine: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var name: String
        public var id: ObjectID
    }
    public var entries: [Entry]
    public var overflowKey: String?
    public var omittedCount: Int
}

public struct NearbyRefs: Sendable, Equatable {
    public var branches: NearbyRefLine
    public var follows: NearbyRefLine
    public var precedes: NearbyRefLine

    public init(id: ObjectID, index: AncestryIndex, maxRefs: Int, visibleRefs: [String]) {
        branches = Self.line(ids: index.descendantHeads(of: id), refs: index.refs, heads: true,
                             maximum: maxRefs, visible: visibleRefs)
        follows = Self.line(ids: index.ancestorTags(of: id), refs: index.refs, heads: false,
                            maximum: maxRefs, visible: visibleRefs)
        precedes = Self.line(ids: index.descendantTags(of: id), refs: index.refs, heads: false,
                             maximum: maxRefs, visible: visibleRefs)
    }

    /// Port of gitk proc `appendrefs` (gitk/gitk 7358–7421), without widget writes.
    public static func line(ids: [ObjectID], refs: RefSet, heads: Bool,
                            maximum: Int, visible: [String]) -> NearbyRefLine {
        let entries = ids.flatMap { id in
            (heads ? refs.heads(of: id) : refs.tags(of: id)).map { NearbyRefLine.Entry(name: $0, id: id) }
        }.sorted { $0.name > $1.name }
        let limit = max(0, maximum)
        guard entries.count > limit else {
            return NearbyRefLine(entries: entries, overflowKey: nil, omittedCount: 0)
        }
        let important = heads ? Array(entries.filter {
            visible.contains($0.name) || $0.id == refs.mainHeadID
        }.prefix(limit)) : []
        return NearbyRefLine(entries: important, overflowKey: important.isEmpty ? "many" : "and many more",
                             omittedCount: entries.count - important.count)
    }
}
