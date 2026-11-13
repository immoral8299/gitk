// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct CommitStoreTests {
    private func oid(_ n: Int) -> ObjectID {
        let text = String(n, radix: 16)
        return ObjectID(hex: String(repeating: "0", count: 40 - text.count) + text)!
    }

    private func commit(_ n: Int, parents: [Int] = [], name: Data = Data("Alice".utf8),
                        encoding: String? = nil, headline: String = "subject",
                        notes: String? = nil) -> ParsedCommit {
        ParsedCommit(
            id: oid(n), parents: parents.map(oid), isBoundary: false, isUninteresting: false,
            side: nil, tree: oid(0xFFFF), authorName: name, authorEmail: Data("a@example.com".utf8),
            authorEpoch: 1_577_836_800 + Int64(n), authorTZ: "+0100",
            committerName: Data("Carol".utf8), committerEmail: Data("c@example.com".utf8),
            committerEpoch: 1_577_836_900, committerTZ: "-0530", encoding: encoding,
            headline: Data(headline.utf8), message: Data((headline + "\n\nbody").utf8),
            notes: notes.map { Data($0.utf8) })
    }

    @Test func internIsIdempotent() {
        let store = CommitStore()
        let a = store.intern(oid(1))
        let b = store.intern(oid(2))
        #expect(a == 0)
        #expect(b == 1)
        #expect(store.intern(oid(1)) == a)
        #expect(store.count == 2)
        #expect(store.index(of: oid(2)) == b)
        #expect(store.index(of: oid(3)) == nil)
        #expect(store.id(at: b) == oid(2))
        #expect(!store.isLoaded(a))
    }

    @Test func insertInternsParentsAndIsIdempotent() {
        let store = CommitStore()
        let child = store.insert(commit(2, parents: [1, 3]))
        #expect(store.count == 3)
        #expect(store.parents(of: child).map { store.id(at: $0) } == [oid(1), oid(3)])
        #expect(store.isLoaded(child))
        let parent = store.index(of: oid(1))!
        #expect(!store.isLoaded(parent))
        // Parent arrives later: same index, now loaded.
        #expect(store.insert(commit(1)) == parent)
        #expect(store.isLoaded(parent))
        #expect(store.insert(commit(2, parents: [1, 3])) == child)
        #expect(store.count == 3)
        #expect(store.authorEpoch(of: child) == 1_577_836_802)
        #expect(store.authorTZOffset(of: child) == 3600)
        #expect(store.committerTZOffset(of: child) == -(5 * 3600 + 1800))
        #expect(store.tree(of: child) == oid(0xFFFF))
    }

    @Test func flagsAreKept() {
        let store = CommitStore()
        var c = commit(1)
        c.isBoundary = true
        c.side = .right
        let i = store.insert(c)
        #expect(store.isBoundary(i))
        #expect(store.side(of: i) == .right)
        #expect(!store.isUninteresting(i))
        #expect(store.side(of: store.insert(commit(2))) == nil)
    }

    @Test func textIsDecodedOnFirstAccessAndCached() {
        let store = CommitStore()
        let i = store.insert(commit(1, notes: "Notes:\nhello"))
        #expect(store.decodeCount == 0)
        #expect(store.headline(at: i) == "subject")
        #expect(store.decodeCount == 1)
        #expect(store.headline(at: i) == "subject")
        #expect(store.decodeCount == 1)
        #expect(store.author(at: i) == "Alice <a@example.com>")
        #expect(store.committer(at: i) == "Carol <c@example.com>")
        #expect(store.message(at: i) == "subject\n\nbody")
        #expect(store.notes(at: i) == "Notes:\nhello")
        #expect(store.decodeCount == 5)
        _ = store.text(at: i)
        #expect(store.decodeCount == 5)
        #expect(store.hasNotes(i))
        let j = store.insert(commit(2))
        #expect(store.notes(at: j) == nil)
        #expect(store.notes(at: j) == nil)
        #expect(store.decodeCount == 5)
    }

    @Test func usesCommitEncodingThenFallback() {
        let latin1 = Data([0x4A, 0x6F, 0x73, 0xE9])  // "José" in ISO-8859-1
        let store = CommitStore(fallbackEncoding: "ISO-8859-1")
        let own = store.insert(commit(1, name: latin1, encoding: "ISO-8859-1"))
        let viaFallback = store.insert(commit(2, name: latin1))
        #expect(store.author(at: own) == "José <a@example.com>")
        #expect(store.author(at: viaFallback) == "José <a@example.com>")
        store.fallbackEncoding = nil
        let utf8 = store.insert(commit(3, name: latin1))
        // Invalid UTF-8 is shown, not dropped.
        #expect(store.author(at: utf8) == "José <a@example.com>")
    }

    @Test func insertDropsStaleCachedText() {
        let store = CommitStore()
        let i = store.insert(commit(1, headline: "old"))
        #expect(store.headline(at: i) == "old")
        store.insert(commit(1, headline: "new"))
        #expect(store.headline(at: i) == "new")
    }

    @Test func hundredThousandInsertsAreFast() {
        let n = 100_000
        var commits = [ParsedCommit]()
        commits.reserveCapacity(n)
        for k in 1...n { commits.append(commit(k, parents: k > 1 ? [k - 1] : [])) }
        let store = CommitStore()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for c in commits { store.insert(c) }
        }
        #expect(store.count == n)
        #expect(store.index(of: oid(n)) == CommitIndex(n - 1))
        #if !DEBUG
        #expect(elapsed < .milliseconds(500), "100k inserts took \(elapsed)")
        #endif
        _ = elapsed
    }
}
