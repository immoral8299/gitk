// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct SearchScannerTests {
    static func id(_ n: Int) -> ObjectID {
        ObjectID(hex: String(repeating: "0", count: 32) + String(format: "%08x", n))!
    }

    /// `count` commits: even ones say "fix bug", every 10th "fix bug in parser",
    /// others "add feature"; the author is alice or bob.
    static func index(count: Int = 3000) -> SearchIndex {
        let index = SearchIndex()
        var sources: [SearchSource] = []
        for n in 0..<count {
            let headline = n % 10 == 0 ? "fix bug in parser" : (n % 2 == 0 ? "fix bug" : "add feature")
            sources.append(SearchSource(
                id: id(n), headline: Data(headline.utf8),
                author: Data((n % 3 == 0 ? "Alice <a@x.org>" : "Bob <b@x.org>").utf8),
                committer: Data("Carol <c@x.org>".utf8),
                message: Data((headline + "\n\nBody \(n) Zebra").utf8)))
            if sources.count == 700 { index.append(sources); sources = [] }
        }
        if !sources.isEmpty { index.append(sources) }
        return index
    }

    static func run(_ scanner: SearchScanner, _ query: FindQuery, priority: [ObjectID] = [],
                    debounce: Duration = .zero) async -> (ids: [ObjectID], updates: Int, final: Bool) {
        var ids: [ObjectID] = [], updates = 0, final = false
        for await u in scanner.search(query, priority: priority, debounce: debounce) {
            ids += u.matches
            updates += 1
            if u.isFinal { final = true }
        }
        return (ids, updates, final)
    }

    @Test func matchesAgreeWithFindQuery() async {
        let index = Self.index()
        let scanner = SearchScanner(index: index)
        let cases: [FindQuery] = [
            FindQuery(matchMode: .exact, field: .headline, pattern: "fix bug"),
            FindQuery(matchMode: .ignoreCase, field: .allFields, pattern: "zEbRa"),
            FindQuery(matchMode: .exact, field: .allFields, pattern: "zEbRa"),
            FindQuery(matchMode: .exact, field: .author, pattern: "alice"),
            FindQuery(matchMode: .ignoreCase, field: .author, pattern: "alice"),
            FindQuery(matchMode: .regexp, field: .headline, pattern: "^fix.*parser$"),
            FindQuery(matchMode: .exact, field: .committer, pattern: "c@x"),
            FindQuery(matchMode: .exact, field: .commitID, pattern: "00000a"),
        ]
        for q in cases {
            let got = Set(await Self.run(scanner, q).ids)
            var expected = Set<ObjectID>()
            let snap = index.snapshot
            for chunk in snap.chunks {
                for i in 0..<chunk.count {
                    let fields: [(FindQuery.Field, String)] = [
                        (.commitID, chunk.hexes[i]), (.headline, chunk.headlines[i]),
                        (.author, chunk.authors[i]), (.committer, chunk.committers[i]),
                        (.comments, chunk.messages[i])]
                    if fields.contains(where: { (q.field == .allFields || q.field == $0.0) && q.doesMatch($0.1) }) {
                        expected.insert(chunk.ids[i])
                    }
                }
            }
            #expect(got == expected, "\(q.pattern) \(q.matchMode) \(q.field)")
            #expect(!got.isEmpty || q.matchMode == .exact && q.pattern != q.pattern.lowercased() || q.pattern == "alice")
        }
    }

    @Test func fieldPruningOnlyReadsTheSelectedField() async {
        let scanner = SearchScanner(index: Self.index())
        // "Zebra" is only in the comments: a headline search must not see it.
        let headline = await Self.run(scanner, FindQuery(field: .headline, pattern: "Zebra"))
        let comments = await Self.run(scanner, FindQuery(field: .comments, pattern: "Zebra"))
        #expect(headline.ids.isEmpty)
        #expect(comments.ids.count == 3000)
    }

    @Test func prefixNarrowingScansOnlyPreviousMatches() async {
        let index = Self.index()
        let scanner = SearchScanner(index: index)
        let first = await Self.run(scanner, FindQuery(field: .headline, pattern: "fix"))
        #expect(first.final)
        #expect(first.ids.count == 1500)
        #expect(scanner.lastScanned == 3000)

        let second = await Self.run(scanner, FindQuery(field: .headline, pattern: "fix bug in"))
        #expect(second.ids.count == 300)
        #expect(scanner.lastScanned == 1500)
        // The narrowed result equals a from-scratch scan.
        let fresh = await Self.run(SearchScanner(index: index), FindQuery(field: .headline, pattern: "fix bug in"))
        #expect(Set(second.ids) == Set(fresh.ids))

        // Narrow again from the narrowed result.
        let third = await Self.run(scanner, FindQuery(field: .headline, pattern: "fix bug in parser"))
        #expect(third.ids.count == 300)
        #expect(scanner.lastScanned == 300)
    }

    @Test func narrowingAlsoScansCommitsIndexedSince() async {
        let index = SearchIndex()
        index.append((0..<100).map { n in
            SearchSource(id: Self.id(n), headline: Data((n % 2 == 0 ? "fix a" : "other").utf8),
                         author: Data(), committer: Data(), message: Data())
        })
        let scanner = SearchScanner(index: index)
        _ = await Self.run(scanner, FindQuery(field: .headline, pattern: "fi"))
        index.append((100..<200).map { n in
            SearchSource(id: Self.id(n), headline: Data("fix b".utf8),
                         author: Data(), committer: Data(), message: Data())
        })
        let r = await Self.run(scanner, FindQuery(field: .headline, pattern: "fix"))
        #expect(r.ids.count == 50 + 100)
        #expect(scanner.lastScanned == 50 + 100)
    }

    @Test func narrowingIsNotUsedWhenItWouldBeWrong() async {
        let scanner = SearchScanner(index: Self.index())
        _ = await Self.run(scanner, FindQuery(matchMode: .regexp, field: .headline, pattern: "fix"))
        // Regexp: "fix|add" extends "fix" textually but matches more.
        let r = await Self.run(scanner, FindQuery(matchMode: .regexp, field: .headline, pattern: "fix|add"))
        #expect(r.ids.count == 3000)
        #expect(scanner.lastScanned == 3000)
        // A different field or mode is a full scan too.
        _ = await Self.run(scanner, FindQuery(field: .headline, pattern: "fix"))
        _ = await Self.run(scanner, FindQuery(field: .comments, pattern: "fix b"))
        #expect(scanner.lastScanned == 3000)
        #expect(SearchScanner.narrows(FindQuery(pattern: "a"), to: FindQuery(pattern: "ab")))
        #expect(!SearchScanner.narrows(FindQuery(pattern: "ab"), to: FindQuery(pattern: "a")))
        #expect(!SearchScanner.narrows(FindQuery(pattern: ""), to: FindQuery(pattern: "a")))
    }

    @Test func supersededSearchDeliversNothing() async {
        let scanner = SearchScanner(index: Self.index())
        // A is still in its debounce when B starts; it must never deliver.
        let a = scanner.search(FindQuery(field: .headline, pattern: "fix"), debounce: .milliseconds(200))
        let b = scanner.search(FindQuery(field: .headline, pattern: "add"))
        var aUpdates = 0
        for await _ in a { aUpdates += 1 }
        var bIDs: [ObjectID] = []
        var bFinal = false
        for await u in b { bIDs += u.matches; bFinal = bFinal || u.isFinal }
        #expect(aUpdates == 0)
        #expect(bFinal)
        #expect(bIDs.count == 1500)
    }

    @Test func cancelStopsDelivery() async {
        let scanner = SearchScanner(index: Self.index(count: 20_000))
        let stream = scanner.search(FindQuery(field: .comments, pattern: "Zebra"))
        scanner.cancel()
        var final = false
        for await u in stream where u.isFinal { final = true }
        #expect(!final)
    }

    @Test func debounceWaitsBeforeScanning() async {
        let scanner = SearchScanner(index: Self.index())
        let start = ContinuousClock.now
        let r = await Self.run(scanner, FindQuery(field: .headline, pattern: "fix"), debounce: .milliseconds(100))
        let elapsed = start.duration(to: .now)
        #expect(elapsed >= .milliseconds(95))
        #expect(r.ids.count == 1500)
    }

    @Test func rapidTypingScansOnlyTheLastPattern() async {
        let scanner = SearchScanner(index: Self.index())
        var streams: [AsyncStream<SearchScanner.Update>] = []
        for text in ["f", "fi", "fix", "fix b"] {
            streams.append(scanner.search(FindQuery(field: .headline, pattern: text), debounce: .milliseconds(100)))
        }
        var counts: [Int] = []
        for s in streams {
            var n = 0
            for await u in s { n += u.matches.count }
            counts.append(n)
        }
        #expect(counts.dropLast().allSatisfy { $0 == 0 })
        #expect(counts.last == 1500)
    }

    @Test func visibleRowsAreDeliveredFirst() async {
        let scanner = SearchScanner(index: Self.index())
        let visible = (2000..<2010).map { Self.id($0) }
        var first: [ObjectID]?
        for await u in scanner.search(FindQuery(field: .headline, pattern: "fix"), priority: visible) {
            if first == nil { first = u.matches }
        }
        #expect(first == (2000..<2010).filter { $0 % 2 == 0 }.map { Self.id($0) })
    }

    @Test @MainActor func indexSyncTakesLoadedCommitsFromTheStore() async throws {
        let fixture = try FixtureRepo.make("linear")
        let repo = try await RepoContext.discover(cwd: fixture)
        let session = ViewSession(repo: repo, runner: GitRunner(cwd: fixture), view: ViewSpec(name: "All files", args: ["--all"]))
        session.showLocalChanges = false
        await session.load()
        let index = SearchIndex()
        await index.sync(with: session.store, slice: 3)
        #expect(index.count == 10)
        let first = index.snapshot.chunks[0]
        #expect(first.count == 3)
        let i = try #require(session.store.index(of: first.ids[0]))
        #expect(first.headlines[0] == session.store.headline(at: i))
        #expect(first.messages[0] == session.store.message(at: i))
        #expect(index.position(of: first.ids[0]) == 0)
    }
}
