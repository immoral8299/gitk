// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// One line of gitk's comparison report, as structured data. The UI layer
/// turns each case into gitk's message text with short-ID links.
public enum PatchIDReportLine: Sendable, Equatable {
    /// "Skipping merge commit <id>"
    case skippingMerge(ObjectID)
    /// "Commit <a> == <b>  <head>" (equal headlines) or
    /// "Commit <a>  <heada>" / " is the same patch as <b>  <headb>".
    case samePatch(a: ObjectID, b: ObjectID, headA: String, headB: String)
    /// "Error getting patch ID for <id> - stopping"
    case patchIDError(ObjectID)
    /// "\nCommit <a>  <heada>\n differs from <b>  <headb>\nDiff of commits:\n\n";
    /// gitk then diffs the two commits and stops.
    case differs(a: ObjectID, b: ObjectID, headA: String, headB: String)
    /// "Commit <id> has <n> children - stopping"; `leadingBlank` is set for
    /// the `a` side, which gitk precedes with an empty line.
    case tooManyChildren(ObjectID, count: Int, leadingBlank: Bool)
}

/// What `PatchIDCompare` needs to know about the commit graph of the view.
public struct PatchIDGraph {
    public var parentCount: @MainActor (ObjectID) -> Int
    public var realChildren: @MainActor (ObjectID) -> [ObjectID]
    public var headline: @MainActor (ObjectID) -> String

    public init(parentCount: @escaping @MainActor (ObjectID) -> Int,
                realChildren: @escaping @MainActor (ObjectID) -> [ObjectID],
                headline: @escaping @MainActor (ObjectID) -> String) {
        self.parentCount = parentCount
        self.realChildren = realChildren
        self.headline = headline
    }
}

extension PatchIDGraph {
    /// The graph of `session`'s current view (gitk's `parents($curview,$id)`,
    /// `real_children` and `commitinfo`).
    @MainActor public init(session: ViewSession) {
        self.init(
            parentCount: { id in
                session.store.index(of: id).map { session.ordering.parents[$0]?.count ?? 0 } ?? 0
            },
            realChildren: { id in
                guard let index = session.store.index(of: id) else { return [] }
                return session.ordering.realChildren(index).map { session.store.id(at: $0) }
            },
            headline: { id in
                session.store.index(of: id).map { session.store.headline(at: $0) } ?? ""
            })
    }
}

/// Compares two commits' series by patch ID. Port of gitk procs
/// `compare_commits`, `getpatchid` and `do_cmp_commits` (gitk/gitk 9241–9343).
@MainActor
public final class PatchIDCompare {
    public let runner: GitRunner
    public let graph: PatchIDGraph
    /// gitk's `patchids` array: patch ID per commit, `"error"` when it failed.
    public private(set) var patchIDs: [ObjectID: String] = [:]

    public init(runner: GitRunner, graph: PatchIDGraph) {
        self.runner = runner
        self.graph = graph
    }

    /// Port of gitk proc `getpatchid` (gitk/gitk 9250–9263).
    public func getPatchID(_ id: ObjectID) async -> String {
        if let known = patchIDs[id] { return known }
        let value: String
        do { value = try await RepoActions(runner: runner).patchID(of: id.hex) }
        catch { value = "error" }
        patchIDs[id] = value
        return value
    }

    /// Port of gitk proc `do_cmp_commits` (gitk/gitk 9265–9343): walks `a` and
    /// `b` forward, one real child at a time (at most 100 steps), while their
    /// patch IDs agree, and returns the report lines. `a` is the marked
    /// commit and `b` the one the menu was opened on.
    public func compare(_ startA: ObjectID, _ startB: ObjectID) async throws -> [PatchIDReportLine] {
        var a = startA
        var b = startB
        var report: [PatchIDReportLine] = []
        for _ in 0..<100 {
            try Task.checkCancellation()
            var skipA = false
            var skipB = false
            var patchA = ""
            var patchB = ""
            if graph.parentCount(a) > 1 {
                report.append(.skippingMerge(a))
                skipA = true
            } else {
                patchA = await getPatchID(a)
            }
            if graph.parentCount(b) > 1 {
                report.append(.skippingMerge(b))
                skipB = true
            } else {
                patchB = await getPatchID(b)
            }
            if !skipA && !skipB {
                let headA = graph.headline(a)
                let headB = graph.headline(b)
                if patchA == "error" { report.append(.patchIDError(a)); break }
                if patchB == "error" { report.append(.patchIDError(b)); break }
                if patchA == patchB {
                    report.append(.samePatch(a: a, b: b, headA: headA, headB: headB))
                    skipA = true
                    skipB = true
                } else {
                    report.append(.differs(a: a, b: b, headA: headA, headB: headB))
                    return report
                }
            }
            if skipA {
                let kids = graph.realChildren(a)
                if kids.count != 1 {
                    report.append(.tooManyChildren(a, count: kids.count, leadingBlank: true))
                    break
                }
                a = kids[0]
            }
            if skipB {
                let kids = graph.realChildren(b)
                if kids.count != 1 {
                    report.append(.tooManyChildren(b, count: kids.count, leadingBlank: false))
                    break
                }
                b = kids[0]
            }
        }
        return report
    }
}
