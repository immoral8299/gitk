// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Runs "containing:" searches over a ``SearchIndex`` off the main actor
/// (design D3): a debounce, prefix narrowing, field pruning, parallel chunk
/// scans, visible rows first, and generation cancellation.
///
/// Each ``search(_:priority:debounce:)`` supersedes the previous one. The old
/// stream stops delivering at once and finishes as soon as its scan has
/// stopped; a superseded search never delivers a result.
public final class SearchScanner: @unchecked Sendable {
    // @unchecked Sendable: `generation` and `last` are only touched under `lock`.

    /// One batch of results. `matches` are new ids only (not cumulative).
    public struct Update: Sendable {
        public let matches: [ObjectID]
        /// True on the last update of a search that ran to completion.
        public let isFinal: Bool
    }

    /// What a finished search covered, for prefix narrowing.
    private struct Completed {
        let query: FindQuery
        let matched: [Int]
        let covered: Int
    }

    private let index: SearchIndex
    private let lock = NSLock()
    private var generation = 0
    private var last: Completed?
    /// Chunks scanned by the most recent search (for tests).
    private var scannedCount = 0
    private let chunkSlice = 256

    public init(index: SearchIndex) {
        self.index = index
    }

    /// Number of commits the latest search looked at (for tests).
    public var lastScanned: Int {
        lock.lock()
        defer { lock.unlock() }
        return scannedCount
    }

    /// Stops the running search, if any.
    public func cancel() {
        lock.lock()
        generation += 1
        lock.unlock()
    }

    private func isCurrent(_ g: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == g
    }

    /// Starts a search and supersedes any earlier one. `priority` lists the
    /// ids of the visible rows, which are scanned and delivered first.
    /// `debounce` is the wait before scanning; a newer search cancels it.
    public func search(_ query: FindQuery, priority: [ObjectID] = [],
                       debounce: Duration = .zero) -> AsyncStream<Update> {
        lock.lock()
        generation += 1
        let g = generation
        let previous = last
        lock.unlock()
        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) { [self] in
                await run(query, priority: priority, debounce: debounce, generation: g,
                          previous: previous, continuation: continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ query: FindQuery, priority: [ObjectID], debounce: Duration,
                     generation g: Int, previous: Completed?,
                     continuation: AsyncStream<Update>.Continuation) async {
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
        }
        guard isCurrent(g), !Task.isCancelled else { return }
        guard let matcher = Matcher(query) else {
            continuation.yield(Update(matches: [], isFinal: true))
            return
        }
        let snapshot = index.snapshot
        guard !snapshot.chunks.isEmpty else {
            store(Completed(query: query, matched: [], covered: 0), g)
            continuation.yield(Update(matches: [], isFinal: true))
            return
        }

        // Prefix narrowing: when the pattern extends the previous one, every
        // match is among the previous matches plus commits indexed since.
        var candidates: [Int]?
        if let previous, Self.narrows(previous.query, to: query) {
            candidates = previous.matched + Array(previous.covered..<max(previous.covered, snapshot.count))
        }

        var found: [Int] = []
        let started = candidates?.count ?? snapshot.count
        // Visible rows first.
        if candidates == nil, !priority.isEmpty {
            var positions = priority.compactMap { index.position(of: $0) }.filter { $0 < snapshot.count }
            positions.sort()
            let hits = scan(positions, in: snapshot, matcher: matcher, generation: g)
            guard let hits else { return }
            found += hits.positions
            // Always sent, even when empty: it tells the caller the visible rows are done.
            continuation.yield(Update(matches: hits.ids, isFinal: false))
        }
        guard isCurrent(g) else { return }

        // The rest, one task per chunk with bounded parallelism.
        let groups = Self.group(candidates, in: snapshot)
        let limit = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        var aborted = false
        await withTaskGroup(of: (positions: [Int], ids: [ObjectID])?.self) { group in
            var next = 0
            var running = 0
            func addNext() {
                let work = groups[next]
                next += 1
                running += 1
                group.addTask { [self] in
                    scan(work, in: snapshot, matcher: matcher, generation: g)
                }
            }
            while next < groups.count, running < limit { addNext() }
            while let result = await group.next() {
                running -= 1
                guard let result, isCurrent(g), !Task.isCancelled else {
                    aborted = true
                    group.cancelAll()
                    continue
                }
                found += result.positions
                if !result.ids.isEmpty { continuation.yield(Update(matches: result.ids, isFinal: false)) }
                if !aborted, next < groups.count { addNext() }
            }
        }
        guard !aborted, isCurrent(g), !Task.isCancelled else { return }

        let unique = Array(Set(found)).sorted()
        lock.withLock {
            scannedCount = started
            last = Completed(query: query, matched: unique, covered: snapshot.count)
        }
        continuation.yield(Update(matches: [], isFinal: true))
    }

    private func store(_ completed: Completed, _ g: Int) {
        lock.withLock { if generation == g { last = completed } }
    }

    /// True when every match of `new` must also match `old`: the same plain
    /// (non-regexp) containing search whose pattern extends the old one.
    static func narrows(_ old: FindQuery, to new: FindQuery) -> Bool {
        old.type == .containing && new.type == .containing
            && old.matchMode == new.matchMode && old.matchMode != .regexp
            && old.field == new.field && !old.pattern.isEmpty
            && Array(new.pattern.utf8).starts(with: Array(old.pattern.utf8))
    }

    /// Splits the work into one list per chunk: global positions to test, or
    /// nil for "the whole chunk".
    private static func group(_ candidates: [Int]?, in snapshot: SearchIndex.Snapshot) -> [Work] {
        guard let candidates else { return snapshot.chunks.indices.map { Work(chunk: $0, positions: nil) } }
        var out: [Work] = []
        for position in candidates.sorted() {
            let c = snapshot.chunkIndex(containing: position)
            if let lastWork = out.last, lastWork.chunk == c {
                out[out.count - 1].positions?.append(position)
            } else {
                out.append(Work(chunk: c, positions: [position]))
            }
        }
        return out
    }

    struct Work: Sendable {
        var chunk: Int
        var positions: [Int]?
    }

    /// Tests the given positions (all in `snapshot`), in order.
    private func scan(_ positions: [Int], in snapshot: SearchIndex.Snapshot, matcher: Matcher,
                      generation g: Int) -> (positions: [Int], ids: [ObjectID])? {
        var foundPositions: [Int] = [], foundIDs: [ObjectID] = []
        var tested = 0
        for position in positions {
            if tested % chunkSlice == 0, !isCurrent(g) { return nil }
            tested += 1
            let chunk = snapshot.chunks[snapshot.chunkIndex(containing: position)]
            let i = position - chunk.start
            if matcher.matches(chunk, i) {
                foundPositions.append(position)
                foundIDs.append(chunk.ids[i])
            }
        }
        return (foundPositions, foundIDs)
    }

    private func scan(_ work: Work, in snapshot: SearchIndex.Snapshot, matcher: Matcher,
                      generation g: Int) -> (positions: [Int], ids: [ObjectID])? {
        let chunk = snapshot.chunks[work.chunk]
        if let positions = work.positions {
            var foundPositions: [Int] = [], foundIDs: [ObjectID] = []
            for (n, position) in positions.enumerated() {
                if n % chunkSlice == 0, !isCurrent(g) { return nil }
                let i = position - chunk.start
                if matcher.matches(chunk, i) {
                    foundPositions.append(position)
                    foundIDs.append(chunk.ids[i])
                }
            }
            return (foundPositions, foundIDs)
        }
        var foundPositions: [Int] = [], foundIDs: [ObjectID] = []
        for i in 0..<chunk.count {
            if i % chunkSlice == 0, !isCurrent(g) { return nil }
            if matcher.matches(chunk, i) {
                foundPositions.append(chunk.start + i)
                foundIDs.append(chunk.ids[i])
            }
        }
        return (foundPositions, foundIDs)
    }
}

/// Tests one commit of a chunk. Plain Exact and IgnCase searches compare UTF-8
/// bytes (the glob `*text*` is a substring test); Regexp goes through
/// ``FindQuery/doesMatch(_:)``. Only the selected field is read (field pruning).
private struct Matcher: Sendable {
    private let query: FindQuery
    private let needle: [UInt8]?
    private let fold: Bool
    private let fields: [FindQuery.Field]

    init?(_ query: FindQuery) {
        guard query.findPattern != nil else { return nil }
        self.query = query
        fold = query.matchMode == .ignoreCase
        switch query.matchMode {
        case .regexp: needle = nil
        case .exact: needle = Array(query.pattern.utf8)
        case .ignoreCase: needle = Array(query.pattern.lowercased().utf8)
        }
        fields = query.field == .allFields
            ? [.commitID, .headline, .author, .committer, .comments] : [query.field]
    }

    func matches(_ chunk: SearchChunk, _ i: Int) -> Bool {
        for f in fields {
            let text: String
            switch f {
            case .commitID: text = chunk.hexes[i]
            case .headline: text = chunk.headlines[i]
            case .author: text = chunk.authors[i]
            case .committer: text = chunk.committers[i]
            case .comments: text = chunk.messages[i]
            case .allFields: continue
            }
            if test(text) { return true }
        }
        return false
    }

    private func test(_ text: String) -> Bool {
        guard let needle else { return query.doesMatch(text) }
        return Self.contains(fold ? text.lowercased() : text, needle)
    }

    private static func contains(_ text: String, _ needle: [UInt8]) -> Bool {
        var text = text
        return text.withUTF8 { hay in
            needle.withUnsafeBufferPointer { n in
                guard let h = hay.baseAddress, let p = n.baseAddress else { return false }
                return memmem(h, hay.count, p, n.count) != nil
            }
        }
    }
}
