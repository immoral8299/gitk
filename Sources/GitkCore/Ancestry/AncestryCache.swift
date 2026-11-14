// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// The gitk text arc format, prefixed with an app-specific version marker.
public enum AncestryCache {
    public static let filename = "gitk-swift.cache"
    private static let header = "gitk-swift-cache 1"

    /// Port of gitk procs `getcache` and `readcache` (gitk/gitk 10701–10790).
    /// Invalid files never expose partially restored state to the caller.
    public static func read(from url: URL, refs: RefSet = RefSet()) -> AncestryIndex? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 4, lines[0] == header,
              let version = try? TclList.split(lines[1]), version.count == 2,
              version[0] == "1", let count = Int(version[1]), count >= 0,
              count <= lines.count - 3, lines[count + 2] == "1",
              lines.dropFirst(count + 3).allSatisfy({ $0.isEmpty }) else { return nil }
        let index = AncestryIndex(refs: refs)
        index.allCommits = 0
        for a in 1..<(count + 1) {
            guard let fields = try? TclList.split(lines[a + 1]), fields.count == 3,
                  let startID = ObjectID(hex: fields[0]),
                  let words = try? TclList.split(fields[2]) else { return nil }
            let members = words.compactMap(ObjectID.init(hex:))
            guard members.count == words.count,
                  members.allSatisfy({ $0.hex.count == startID.hex.count }) else { return nil }
            let endID = fields[1].isEmpty ? nil : ObjectID(hex: fields[1])
            guard fields[1].isEmpty || (endID != nil && members.last == endID),
                  !members.contains(startID), Set(members).count == members.count else { return nil }
            index.ensureArc(a)
            let start = index.intern(startID)
            index.arcStart[a] = start
            index.arcIDs[a] = members.map { index.intern($0) }
            index.arcOut[Int(start), defaultEmpty: ()].append(a)
            if index.arcNos[Int(start)] == nil { index.arcNos[Int(start)] = [] }
            if let endID {
                let end = index.intern(endID)
                index.arcEnd[a] = end
                if index.arcOut[Int(end)] == nil { index.arcOut[Int(end)] = [] }
            } else {
                index.growing.insert(a)
            }
            var previous = start
            for id in index.arcIDs[a] {
                index.allParents[Int(previous), defaultEmpty: ()].append(id)
                index.allChildren[Int(id), defaultEmpty: ()].append(previous)
                index.arcNos[Int(id), defaultEmpty: ()].append(a)
                previous = id
            }
            if index.allParents[Int(previous)] == nil { index.allParents[Int(previous)] = [] }
        }
        // A syntactically valid file with cyclic arcs is still corrupt.
        var remaining = index.allParents.map { $0?.count ?? 0 }
        var ready = remaining.indices.filter { remaining[$0] == 0 }
        var visited = 0
        while visited < ready.count {
            let node = ready[visited]
            visited += 1
            for child in index.allChildren[node] ?? [] {
                remaining[Int(child)] -= 1
                if remaining[Int(child)] == 0 { ready.append(Int(child)) }
            }
        }
        guard visited == index.ids.count else { return nil }
        index.nextArc = count
        index.cachedArcs = count
        for (offset, _) in index.ids.enumerated() {
            if index.allChildren[offset] == nil { index.allChildren[offset] = [] }
            if index.allChildren[offset] == [], index.arcNos[offset] == [] {
                index.seeds.append(CommitIndex(offset))
            }
        }
        index.seeds.sort { index.ids[Int($0)] < index.ids[Int($1)] }
        for a in 1..<(count + 1) { index.recalcArc(a) }
        return index
    }

    /// Port of gitk procs `savecache` and `writecache` (gitk/gitk 10808–10864).
    public static func write(_ index: AncestryIndex, to url: URL) throws {
        var lines = [header, "1 \(index.nextArc)"]
        for a in 1..<(index.nextArc + 1) {
            guard let start = index.arcStart(a) else { continue }
            let end = index.arcEnd(a)?.hex ?? "{}"
            let members = index.arcIDs(a).map(\.hex).joined(separator: " ")
            lines.append("\(start.hex) \(end) {\(members)}")
        }
        lines.append("1")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }
}

private extension Array {
    subscript<T>(index: Int, defaultEmpty _: Void) -> [T] where Element == [T]? {
        get { self[index] ?? [] }
        set { self[index] = newValue }
    }
}
