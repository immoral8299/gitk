// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// The rows of the "Tags and heads" window.
public struct RefListModel: Sendable, Equatable {
    /// gitk's one-letter type: `H` local head, `R` remote head, `T` tag, `o` other.
    public enum Kind: String, Sendable { case head = "H", remote = "R", tag = "T", other = "o" }

    public struct Entry: Sendable, Equatable {
        public var name: String
        public var kind: Kind
        public var id: ObjectID
    }

    /// Glob pattern (gitk's `reflistfilter`).
    public var filter = "*"
    /// gitk's `sortrefsbytype`.
    public var sortByType = false

    public init(filter: String = "*", sortByType: Bool = false) {
        self.filter = filter
        self.sortByType = sortByType
    }

    /// Port of the list building in gitk proc `refill_reflist` (gitk/gitk 10321–10385).
    /// `inView` is `commitinview`; refs outside the view are left out.
    /// `upstreamOfRef` maps a local head to its upstream remote ref name.
    public func entries(refs: RefSet, inView: (ObjectID) -> Bool,
                        upstreamOfRef: [String: String] = [:]) -> [Entry] {
        func sorted(_ list: [Entry]) -> [Entry] {
            list.sorted { tclStringCompare($0.name, $1.name) < 0 }
        }
        func matches(_ n: String) -> Bool { TclGlob.matches(pattern: filter, n) }

        var local: [Entry] = []
        var tracked: [String: Entry] = [:]
        for (n, id) in refs.headIDs where !n.hasPrefix("remotes/") && matches(n) && inView(id) {
            local.append(Entry(name: n, kind: .head, id: id))
            if let up = upstreamOfRef[n], let upID = refs.headIDs[up], inView(upID) {
                tracked[up] = Entry(name: up, kind: .remote, id: upID)
            }
        }
        var remote: [Entry] = []
        for (n, id) in refs.headIDs where n.hasPrefix("remotes/") && matches(n) && inView(id) {
            if tracked[n] == nil { remote.append(Entry(name: n, kind: .remote, id: id)) }
        }
        var tags: [Entry] = []
        for (n, id) in refs.tagIDs where matches(n) && inView(id) {
            tags.append(Entry(name: n, kind: .tag, id: id))
        }
        var other: [Entry] = []
        for (n, id) in refs.otherRefIDs where matches(n) && inView(id) {
            other.append(Entry(name: n, kind: .other, id: id))
        }
        let all = sorted(local) + sorted(Array(tracked.values)) + sorted(remote) + sorted(tags) + sorted(other)
        return sortByType ? all : sorted(all)
    }
}
