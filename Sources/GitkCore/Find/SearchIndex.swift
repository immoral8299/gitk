// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// The undecoded searchable fields of one commit (see
/// ``CommitStore/searchSource(at:)``). `Data` is copy-on-write, so building one
/// is cheap and the decoding can run anywhere.
public struct SearchSource: Sendable {
    public let id: ObjectID
    public let headline: Data
    public let author: Data
    public let committer: Data
    public let message: Data
    /// The commit's own encoding, else the store's fallback.
    public let encoding: String?

    public init(id: ObjectID, headline: Data, author: Data, committer: Data,
                message: Data, encoding: String? = nil) {
        self.id = id
        self.headline = headline
        self.author = author
        self.committer = committer
        self.message = message
        self.encoding = encoding
    }
}

/// One immutable run of decoded, searchable commit text. Chunks never change
/// after they are built, so scanners read them from any thread.
public final class SearchChunk: Sendable {
    /// Position of the first commit in the index.
    public let start: Int
    public let ids: [ObjectID]
    public let hexes: [String]
    public let headlines: [String]
    public let authors: [String]
    public let committers: [String]
    public let messages: [String]
    public var count: Int { ids.count }

    init(start: Int, sources: [SearchSource]) {
        self.start = start
        var ids: [ObjectID] = [], hexes: [String] = [], headlines: [String] = []
        var authors: [String] = [], committers: [String] = [], messages: [String] = []
        for s in sources {
            ids.append(s.id)
            hexes.append(s.id.hex)
            headlines.append(TextDecoder.decodeReporting(s.headline, encodingName: s.encoding).text)
            authors.append(TextDecoder.decodeReporting(s.author, encodingName: s.encoding).text)
            committers.append(TextDecoder.decodeReporting(s.committer, encodingName: s.encoding).text)
            messages.append(TextDecoder.decodeReporting(s.message, encodingName: s.encoding).text)
        }
        self.ids = ids
        self.hexes = hexes
        self.headlines = headlines
        self.authors = authors
        self.committers = committers
        self.messages = messages
    }
}

/// The searchable text of every loaded commit, kept as immutable chunks that
/// are decoded off the main actor and appended as history loads (design D3).
/// Positions are append order, so they never change while the index lives; make
/// a new index when the commit store is replaced.
public final class SearchIndex: @unchecked Sendable {
    // @unchecked Sendable: all mutable state is read and written under `lock`.
    private let lock = NSLock()
    private var chunks: [SearchChunk] = []
    private var total = 0
    private var positions: [ObjectID: Int] = [:]
    private var nextStoreIndex = 0
    private var pending: [CommitIndex] = []
    private var storeToken: ObjectIdentifier?

    public init() {}

    /// A frozen view of the chunks at one moment.
    public struct Snapshot: Sendable {
        public let chunks: [SearchChunk]
        public let count: Int

        /// The chunk holding `position`, by binary search.
        func chunkIndex(containing position: Int) -> Int {
            var lo = 0, hi = chunks.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if chunks[mid].start <= position { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }
    }

    public var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(chunks: chunks, count: total)
    }

    public var count: Int { snapshot.count }

    /// Position of `id` in the index, if indexed.
    public func position(of id: ObjectID) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return positions[id]
    }

    /// Appends one chunk built from `sources`. Used by tests; ``sync(with:slice:)``
    /// is the normal way in.
    public func append(_ sources: [SearchSource]) {
        install(SearchChunk(start: count, sources: sources))
    }

    private func install(_ chunk: SearchChunk) {
        lock.lock()
        defer { lock.unlock() }
        guard chunk.start == total, chunk.count > 0 else { return }
        chunks.append(chunk)
        for (i, id) in chunk.ids.enumerated() { positions[id] = chunk.start + i }
        total += chunk.count
    }

    /// Takes in every commit of `store` that is loaded and not yet indexed, a
    /// slice at a time. Only the cheap byte extraction runs on the main actor
    /// (one slice per hop); decoding runs on a background task. Call it from
    /// one task at a time, always with the same store.
    @MainActor
    public func sync(with store: CommitStore, slice: Int = 1000) async {
        let token = ObjectIdentifier(store)
        let same = lock.withLock {
            if storeToken == nil { storeToken = token }
            return storeToken == token
        }
        guard same else { return }
        while !Task.isCancelled {
            let sources = takeSlice(store: store, limit: slice)
            if sources.isEmpty { return }
            let start = count
            let chunk = await Task.detached(priority: .userInitiated) {
                SearchChunk(start: start, sources: sources)
            }.value
            install(chunk)
        }
    }

    @MainActor
    private func takeSlice(store: CommitStore, limit: Int) -> [SearchSource] {
        lock.lock()
        defer { lock.unlock() }
        var out: [SearchSource] = []
        var stillPending: [CommitIndex] = []
        for index in pending {
            if out.count < limit, let s = store.searchSource(at: index) { out.append(s) }
            else { stillPending.append(index) }
        }
        pending = stillPending
        while out.count < limit, nextStoreIndex < store.count {
            let index = CommitIndex(nextStoreIndex)
            nextStoreIndex += 1
            if let s = store.searchSource(at: index) { out.append(s) } else { pending.append(index) }
        }
        return out
    }
}
