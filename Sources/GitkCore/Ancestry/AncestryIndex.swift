// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// One line of `git rev-list --parents` output: a commit and its parents.
/// Parsing happens off the main actor; the value crosses to the index's owner
/// (design D3).
public struct AncestryLine: Sendable, Equatable {
    public var id: ObjectID
    public var parents: [ObjectID]

    public init(id: ObjectID, parents: [ObjectID]) {
        self.id = id
        self.parents = parents
    }

    /// Splits `<id> <parent>...` on spaces (Tcl `lindex $line 0`,
    /// `lrange $line 1 end`). A line whose ids are not valid hex is dropped.
    public static func parse(_ record: Data) -> AncestryLine? {
        var ids: [ObjectID] = []
        for word in record.split(separator: 0x20, omittingEmptySubsequences: true) {
            guard let id = ObjectID(hex: String(decoding: word, as: UTF8.self)) else { return nil }
            ids.append(id)
        }
        guard let first = ids.first else { return nil }
        return AncestryLine(id: first, parents: Array(ids.dropFirst()))
    }
}

/// The `git rev-list` invocation `getallcommits` decides on.
public struct RevListCommand: Sendable, Equatable {
    /// Arguments after `git`.
    public var arguments: [String]
    /// Text for the command's standard input (gitk's `<<` redirection).
    public var stdin: Data?
}

/// What `finish(error:)` tells the owner (the tail of `getallclines`).
public struct AncestryFinish: Sendable, Equatable {
    /// `getallclines` hit an error while updating, dropped the cache and ran
    /// `getallcommits` again: the owner must call `beginLoad()` and stream
    /// the new command.
    public var restart = false
    /// Text for gitk's `error_popup` (without the `(err)` suffix, see
    /// `errorDetail`); nil when there is nothing to report.
    public var errorMessage: String?
    public var errorDetail: String?
    /// `run savecache` would have been queued (task 12.2 writes the cache).
    public var saveCache = false
}

/// The whole-repository ancestry index behind the "Branch:", "Follows:" and
/// "Precedes:" lines. Commits with one parent and one child are grouped into
/// "arcs" that join branch/merge points (BMPs): commits that do not have
/// exactly one parent or exactly one child.
///
/// Names follow gitk's globals (`arcnos` → `arcNos`, ...). Where gitk keys a
/// Tcl array by commit id, this class interns each id to a dense node index
/// (``CommitIndex`` used as a private index space; it is unrelated to a
/// view's ``CommitStore``) and keeps parallel arrays; `nil` stands for
/// "`info exists` is false".
///
/// - `arcNos[id]`: incoming arcs for a BMP, the arc we are on for other nodes.
/// - `arcOut[id]`: outgoing arcs for a BMP.
/// - `arcIDs[a]`: ids on arc `a`, including the end but not the start.
/// - `arcStart[a]`, `arcEnd[a]`: the BMPs at the two ends; `arcEnd` is nil
///   while the arc is still `growing`.
/// - `arcTags[a]`, `arcHeads[a]`: ids of `arcIDs` (excluding the end) that
///   have tags / heads.
///
/// The start of an arc is at the descendant end: "incoming" comes from
/// descendants, "outgoing" goes toward ancestors.
///
/// Not thread-safe and not `Sendable`: used from one actor only, like gitk's
/// single-threaded state. The building steps (`beginLoad`, `add`, `finish`)
/// are synchronous so that they can be tested without a process; ``load(runner:)``
/// is the thin asynchronous driver.
public final class AncestryIndex {
    /// gitk's `idheads`, `idtags`, `idotherrefs` and `tagobjid`. Replace it
    /// when the refs are re-read.
    public var refs: RefSet

    // MARK: id interning

    private var indexByID: [ObjectID: CommitIndex] = [:]
    private(set) var ids: [ObjectID] = []

    // MARK: per-commit state (gitk arrays keyed by id)

    /// `allparents`
    var allParents: [[CommitIndex]?] = []
    /// `allchildren`
    var allChildren: [[CommitIndex]?] = []
    /// `arcnos`
    var arcNos: [[Int]?] = []
    /// `arcout`
    var arcOut: [[Int]?] = []

    // MARK: per-arc state (gitk arrays keyed by arc number; index 0 unused)

    /// `arcids`
    var arcIDs: [[CommitIndex]] = [[]]
    /// `arcstart`
    var arcStart: [CommitIndex?] = [nil]
    /// `arcend`
    var arcEnd: [CommitIndex?] = [nil]
    /// `arctags`
    var arcTags: [[CommitIndex]] = [[]]
    /// `archeads`
    var arcHeads: [[CommitIndex]] = [[]]
    /// `growing`
    var growing: Set<Int> = []

    // MARK: scalar state

    /// `nextarc`: the number of the last arc created.
    public internal(set) var nextArc = 0
    /// `seeds`: commits with no child (the tips), in the order they appeared.
    var seeds: [CommitIndex] = []
    /// `allcommits`: nil until `getallcommits` first ran (`info exists`),
    /// then the number of loads in progress.
    public internal(set) var allCommits: Int?
    /// `allcwait`: a cache is being read (task 12.2).
    var allCWait = false
    /// `cachedarcs`: number of arcs stored in the cache file (task 12.2).
    var cachedArcs = 0
    /// `allcupdate`: the running load only reads what is new.
    public internal(set) var allCUpdate = false
    /// Text of gitk's `puts "oops splitarc ..."` diagnostics.
    public internal(set) var diagnostics: [String] = []
    /// Incremented by every `add`. gitk's `getallclines` unsets
    /// `cached_dheads`, `cached_dtags` and `cached_atags` after every batch;
    /// the query caches of tasks 12.3/12.4 compare against this to do the
    /// same.
    public internal(set) var generation = 0

    public init(refs: RefSet = RefSet()) {
        self.refs = refs
    }

    // MARK: - Interning and accessors

    /// Returns the node index of `id`, creating empty state for new ids.
    @discardableResult
    func intern(_ id: ObjectID) -> CommitIndex {
        if let existing = indexByID[id] { return existing }
        let index = CommitIndex(ids.count)
        indexByID[id] = index
        ids.append(id)
        allParents.append(nil)
        allChildren.append(nil)
        arcNos.append(nil)
        arcOut.append(nil)
        return index
    }

    func index(of id: ObjectID) -> CommitIndex? { indexByID[id] }

    /// Grows the per-arc arrays so arc `a` can be addressed.
    func ensureArc(_ a: Int) {
        while arcIDs.count <= a {
            arcIDs.append([])
            arcStart.append(nil)
            arcEnd.append(nil)
            arcTags.append([])
            arcHeads.append([])
        }
    }

    /// Number of distinct commits seen.
    public var commitCount: Int { ids.count }

    public func allParents(of id: ObjectID) -> [ObjectID]? {
        index(of: id).flatMap { allParents[Int($0)] }?.map { ids[Int($0)] }
    }

    public func allChildren(of id: ObjectID) -> [ObjectID]? {
        index(of: id).flatMap { allChildren[Int($0)] }?.map { ids[Int($0)] }
    }

    public func arcNos(of id: ObjectID) -> [Int]? {
        index(of: id).flatMap { arcNos[Int($0)] }
    }

    public func arcOut(of id: ObjectID) -> [Int]? {
        index(of: id).flatMap { arcOut[Int($0)] }
    }

    public func arcStart(_ a: Int) -> ObjectID? {
        arcStart.indices.contains(a) ? arcStart[a].map { ids[Int($0)] } : nil
    }

    /// nil while the arc is growing.
    public func arcEnd(_ a: Int) -> ObjectID? {
        arcEnd.indices.contains(a) ? arcEnd[a].map { ids[Int($0)] } : nil
    }

    public func arcIDs(_ a: Int) -> [ObjectID] {
        arcIDs.indices.contains(a) ? arcIDs[a].map { ids[Int($0)] } : []
    }

    public func arcTags(_ a: Int) -> [ObjectID] {
        arcTags.indices.contains(a) ? arcTags[a].map { ids[Int($0)] } : []
    }

    public func arcHeads(_ a: Int) -> [ObjectID] {
        arcHeads.indices.contains(a) ? arcHeads[a].map { ids[Int($0)] } : []
    }

    public func isGrowing(_ a: Int) -> Bool { growing.contains(a) }

    public var seedIDs: [ObjectID] { seeds.map { ids[Int($0)] } }

    /// True when a full load has finished (`allcommits` is 0).
    public var isComplete: Bool { allCommits == 0 }

    /// `lappend allchildren($p) $id`
    private func lappendChild(_ p: CommitIndex, _ id: CommitIndex) {
        allChildren[Int(p), orEmpty: ()].append(id)
    }

    /// `lappend arcnos($p) $a`
    private func lappendArcNo(_ p: CommitIndex, _ a: Int) {
        arcNos[Int(p), orEmpty: ()].append(a)
    }

    private func hasTag(_ id: CommitIndex) -> Bool { refs.idTags[ids[Int(id)]] != nil }
    private func hasHead(_ id: CommitIndex) -> Bool { refs.idHeads[ids[Int(id)]] != nil }

    // MARK: - getallcommits

    /// Port of the first half of gitk proc `getallcommits` (gitk/gitk
    /// 10414–10475): first-call initialisation and choosing the
    /// `git rev-list` command.
    ///
    /// Returns nil when there is nothing to run: a cache is being read
    /// (`allcwait`), or an update finds no new refs (gitk then just calls
    /// `dispneartags 0`). Otherwise `allcommits` has been incremented and the
    /// caller streams the command's lines into ``add(_:)``, then calls
    /// ``finish(error:)``.
    ///
    /// Deviation: gitk tries `readcache`/`getcache` on the first call; the
    /// cache is task 12.2, which hooks in where the comment says.
    public func beginLoad() -> RevListCommand? {
        if allCommits == nil {
            nextArc = 0
            allCommits = 0
            seeds = []
            allCWait = false
            cachedArcs = 0
            // 12.2: read <gitdir>/gitk-swift.cache here; on success `return`.
        }

        if allCWait {
            return nil
        }
        allCUpdate = !seeds.isEmpty
        let command: RevListCommand
        if !allCUpdate {
            command = RevListCommand(arguments: ["rev-list", "--parents", "--all"], stdin: nil)
        } else {
            var refIDs = Set<ObjectID>()
            refIDs.formUnion(refs.idHeads.keys)
            refIDs.formUnion(refs.idTags.keys)
            refIDs.formUnion(refs.idOtherRefs.keys)
            let tagObjs = Set(refs.tagObjectIDs.values)
            var lines: [String] = []
            // `lsort -unique`: ASCII order of the hex text.
            for hex in refIDs.map(\.hex).sorted() {
                guard let id = ObjectID(hex: hex) else { continue }
                let seen = index(of: id).map { allParents[Int($0)] != nil } ?? false
                if !seen && !tagObjs.contains(id) { lines.append(hex) }
            }
            if lines.isEmpty { return nil }
            for seed in seeds { lines.append("^" + ids[Int(seed)].hex) }
            lines.append("--")
            command = RevListCommand(
                arguments: ["rev-list", "--parents", "--stdin"],
                stdin: Data((lines.joined(separator: "\n") + "\n").utf8))
        }
        allCommits = (allCommits ?? 0) + 1
        return command
    }

    // MARK: - getallclines

    /// Port of the line loop of gitk proc `getallclines` (gitk/gitk
    /// 10497–10574). One call handles one `rev-list --parents` line. gitk
    /// reads 1000 lines per event; the batching is the caller's business.
    public func add(_ line: AncestryLine) {
        generation += 1
        let id = intern(line.id)
        let i = Int(id)
        if allParents[i] != nil {
            // seen it already
            return
        }
        cachedArcs = 0
        let olds = line.parents.map { intern($0) }
        allParents[i] = olds
        if allChildren[i] == nil {
            allChildren[i] = []
            arcNos[i] = []
            seeds.append(id)
        } else {
            let arcs = arcNos[i] ?? []
            if olds.count == 1 && arcs.count == 1 {
                let a = arcs[0]
                let p = olds[0]
                arcIDs[a].append(id)
                if hasTag(id) { arcTags[a].append(id) }
                if hasHead(id) { arcHeads[a].append(id) }
                if allParents[Int(p)] != nil {
                    // seen parent already
                    if arcOut[Int(p)] == nil {
                        splitArc(p)
                    }
                    arcIDs[a].append(p)
                    arcEnd[a] = p
                    growing.remove(a)
                }
                lappendChild(p, id)
                lappendArcNo(p, a)
                return
            }
        }
        for a in arcNos[i] ?? [] {
            arcIDs[a].append(id)
            arcEnd[a] = id
            growing.remove(a)
        }

        var ao: [Int] = []
        for p in olds {
            lappendChild(p, id)
            nextArc += 1
            let a = nextArc
            ensureArc(a)
            arcStart[a] = id
            arcHeads[a] = []
            arcTags[a] = []
            arcIDs[a] = []
            ao.append(a)
            growing.insert(a)
            if allParents[Int(p)] != nil {
                // seen it already, may need to make a new branch
                if arcOut[Int(p)] == nil {
                    splitArc(p)
                }
                arcIDs[a].append(p)
                arcEnd[a] = p
                growing.remove(a)
            }
            lappendArcNo(p, a)
        }
        arcOut[i] = ao
    }

    /// Parses `record` (one output line) and adds it. Malformed lines are
    /// skipped.
    public func add(line record: Data) {
        if let line = AncestryLine.parse(record) { add(line) }
    }

    /// Port of the end-of-file half of gitk proc `getallclines` (gitk/gitk
    /// 10575–10612). `error` is the text of the failed `close` (git's
    /// stderr), nil when `git rev-list` exited cleanly.
    public func finish(error: String?) -> AncestryFinish {
        var result = AncestryFinish()
        var cacheOK = true
        if let error {
            // got an error reading the list of commits
            // if we were updating, try rereading the whole thing again
            if allCUpdate {
                allCommits = (allCommits ?? 0) - 1
                dropCache()
                result.restart = true
                return result
            }
            result.errorMessage = Self.topologyErrorMessage
            result.errorDetail = error
            cacheOK = false
        }
        allCommits = (allCommits ?? 0) - 1
        if allCommits == 0 {
            // notbusy allcommits
            if cacheOK { result.saveCache = true }
        }
        return result
    }

    /// gitk's English text for the failed-read popup (the translation key, with
    /// the Tcl line continuations collapsed to single spaces). The popup shows
    /// it followed by "\n(<detail>)".
    public static let topologyErrorMessage =
        "Error reading commit topology information; branch and preceding/following tag information will be incomplete."

    /// Port of gitk proc `dropcache` (gitk/gitk 10792–10806) minus the final
    /// `getallcommits` call (the owner calls ``beginLoad()`` again, see
    /// `AncestryFinish.restart`).
    func dropCache() {
        // unset arcnos arcout arcids arcstart arcend growing arctags archeads
        // allparents allchildren
        for i in 0..<ids.count {
            allParents[i] = nil
            allChildren[i] = nil
            arcNos[i] = nil
            arcOut[i] = nil
        }
        arcIDs = [[]]
        arcStart = [nil]
        arcEnd = [nil]
        arcTags = [[]]
        arcHeads = [[]]
        growing = []
        allCWait = false
        nextArc = 0
        cachedArcs = 0
        seeds = []
    }

    // MARK: - recalcarc, splitarc, addnewchild

    /// Port of gitk proc `recalcarc` (gitk/gitk 10614–10628).
    func recalcArc(_ a: Int) {
        var at: [CommitIndex] = []
        var ah: [CommitIndex] = []
        for id in arcIDs[a].dropLast() {
            if hasTag(id) { at.append(id) }
            if hasHead(id) { ah.append(id) }
        }
        arcTags[a] = at
        arcHeads[a] = ah
    }

    /// Tcl `lreplace $l $j $j $x`: replaces the element at `j`; with `j` of -1
    /// (not found) the new element is inserted at the front, as Tcl does.
    private static func replacing(_ list: [Int], at j: Int, with x: Int) -> [Int] {
        var out = list
        if j >= 0 && j < out.count {
            out[j] = x
        } else {
            out.insert(x, at: 0)
        }
        return out
    }

    /// Port of gitk proc `splitarc` (gitk/gitk 10630–10682): splits the arc
    /// `p` lies on into two at `p`, making `p` a branch point.
    func splitArc(_ p: CommitIndex) {
        let pi = Int(p)
        let current = arcNos[pi] ?? []
        if current.count != 1 {
            diagnostics.append("oops splitarc called but \(current.count) arcs already")
            return
        }
        let a = current[0]
        guard let i = arcIDs[a].firstIndex(of: p) else {
            diagnostics.append("oops splitarc \(ids[pi].hex) not in arc \(a)")
            return
        }
        nextArc += 1
        let na = nextArc
        ensureArc(na)
        if let end = arcEnd[a] {
            arcEnd[na] = end
        } else {
            let last = arcIDs[a][arcIDs[a].count - 1]
            if let l = (allParents[Int(last)] ?? []).first {
                let li = Int(l)
                let nos = arcNos[li] ?? []
                let j = nos.firstIndex(of: a) ?? -1
                arcNos[li] = Self.replacing(nos, at: j, with: na)
            }
        }
        let tail = Array(arcIDs[a][(i + 1)...])
        arcIDs[a] = Array(arcIDs[a][0...i])
        arcEnd[a] = p
        arcStart[na] = p
        arcOut[pi] = [na]
        arcIDs[na] = tail
        if growing.contains(a) {
            growing.insert(na)
            growing.remove(a)
        }

        for id in tail {
            let ii = Int(id)
            let nos = arcNos[ii] ?? []
            if nos.count == 1 {
                arcNos[ii] = [na]
            } else {
                let j = nos.firstIndex(of: a) ?? -1
                arcNos[ii] = Self.replacing(nos, at: j, with: na)
            }
        }

        // reconstruct tags and heads lists
        if !arcTags[a].isEmpty || !arcHeads[a].isEmpty {
            recalcArc(a)
            recalcArc(na)
        } else {
            arcTags[na] = []
            arcHeads[na] = []
        }
    }

    /// Port of gitk proc `addnewchild` (gitk/gitk 10684–10701): records a new
    /// commit `id` that is a child of the existing commit `p` (used when
    /// cherry-picking).
    public func addNewChild(_ id: ObjectID, parent p: ObjectID) {
        guard allCommits != nil, let pIndex = index(of: p), arcNos[Int(pIndex)] != nil else { return }
        let n = intern(id)
        allParents[Int(n)] = [pIndex]
        allChildren[Int(n)] = []
        arcNos[Int(n)] = []
        seeds.append(n)
        lappendChild(pIndex, n)
        nextArc += 1
        let a = nextArc
        ensureArc(a)
        arcStart[a] = n
        arcHeads[a] = []
        arcTags[a] = []
        arcIDs[a] = [pIndex]
        arcEnd[a] = pIndex
        if arcOut[Int(pIndex)] == nil {
            splitArc(pIndex)
        }
        lappendArcNo(pIndex, a)
        arcOut[Int(n)] = [a]
    }

    // MARK: - Driver

    /// Runs `getallcommits` to completion: starts `git rev-list`, parses its
    /// lines off the main actor in batches (2,000 lines or 50 ms, as in
    /// design D3), adds them here, and finishes. Restarts once with the full
    /// command when an update fails (`AncestryFinish.restart`).
    ///
    /// Returns the result of the last ``finish(error:)``; its `errorMessage`
    /// is for the owner to show. Cancelling the task stops git and throws
    /// `CancellationError` without calling `finish`.
    @MainActor
    public func load(runner: GitRunner) async throws -> AncestryFinish {
        while true {
            guard let command = beginLoad() else { return AncestryFinish() }
            let process = runner.stream(command.arguments, stdin: command.stdin)
            let batches = Self.parsedBatches(process.records(separator: 0x0A))
            var failure: String?
            do {
                for try await batch in batches {
                    for line in batch { add(line) }
                }
            } catch is CancellationError {
                process.cancel()
                throw CancellationError()
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            }
            try Task.checkCancellation()
            let result = finish(error: failure)
            if !result.restart { return result }
        }
    }

    /// Parses records into batches of at most 2,000 lines, flushing early when
    /// 50 ms have passed since the last batch (checked as records arrive).
    static func parsedBatches(
        _ records: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<[AncestryLine], Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                var batch: [AncestryLine] = []
                var lastFlush = ContinuousClock.now
                do {
                    for try await record in records {
                        if let line = AncestryLine.parse(record) { batch.append(line) }
                        let now = ContinuousClock.now
                        if batch.count >= 2000 || (!batch.isEmpty && now - lastFlush >= .milliseconds(50)) {
                            continuation.yield(batch)
                            batch.removeAll(keepingCapacity: true)
                            lastFlush = now
                        }
                    }
                    if !batch.isEmpty { continuation.yield(batch) }
                    continuation.finish()
                } catch {
                    if !batch.isEmpty { continuation.yield(batch) }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private extension Array {
    /// A list slot that may be unset: reading gives `[]` for nil, writing
    /// stores the list (Tcl `lappend` creating the variable).
    subscript<T>(index: Int, orEmpty _: Void) -> [T] where Element == [T]? {
        get { self[index] ?? [] }
        set { self[index] = newValue }
    }
}
