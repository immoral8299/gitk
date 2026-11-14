// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct FindQueryTests {
    private func oid(_ n: Int) -> ObjectID {
        let text = String(n, radix: 16)
        return ObjectID(hex: String(repeating: "0", count: 40 - text.count) + text)!
    }

    private func store(id: ObjectID? = nil) -> (CommitStore, CommitIndex) {
        let store = CommitStore()
        let c = ParsedCommit(
            id: id ?? oid(1), parents: [], isBoundary: false, isUninteresting: false,
            side: nil, tree: oid(0xFFFF), authorName: Data("Alice Smith".utf8),
            authorEmail: Data("alice@example.com".utf8), authorEpoch: 1_577_836_800,
            authorTZ: "+0000", committerName: Data("Carol".utf8),
            committerEmail: Data("carol@example.com".utf8), committerEpoch: 1_577_836_900,
            committerTZ: "+0000", encoding: nil, headline: Data("Fix the widget".utf8),
            message: Data("Fix the widget\n\nLong body mentions gadget".utf8), notes: nil)
        return (store, store.insert(c))
    }

    @Test func ignoreCaseAuthor() {
        let (s, i) = store()
        let q = FindQuery(matchMode: .ignoreCase, field: .author, pattern: "ALICE")
        #expect(q.matches(commit: i, in: s))
        let exact = FindQuery(matchMode: .exact, field: .author, pattern: "ALICE")
        #expect(!exact.matches(commit: i, in: s))
        let wrongField = FindQuery(matchMode: .ignoreCase, field: .committer, pattern: "ALICE")
        #expect(!wrongField.matches(commit: i, in: s))
    }

    @Test(arguments: [40, 64])
    func allFieldsIncludesFullAndShortCommitIDs(length: Int) throws {
        let hex = "abcdef1234567" + String(repeating: "0", count: length - 13)
        let id = try #require(ObjectID(hex: hex))
        let (s, i) = store(id: id)
        for pattern in [hex, String(hex.prefix(7))] {
            #expect(FindQuery(pattern: pattern).matches(commit: i, in: s))
        }
        #expect(FindQuery(matchMode: .ignoreCase, pattern: "ABCDEF1").matches(commit: i, in: s))
        #expect(FindQuery(matchMode: .regexp, pattern: "^abcdef[0-9]+").matches(commit: i, in: s))
        #expect(!FindQuery(pattern: "fedcba").matches(commit: i, in: s))
        #expect(!FindQuery(field: .headline, pattern: hex).matches(commit: i, in: s))
        #expect(!FindQuery(type: .touchingPaths, pattern: hex).matches(commit: i, in: s))
    }

    @Test func invalidRegexpMatchesNothing() {
        let (s, i) = store()
        let q = FindQuery(matchMode: .regexp, pattern: "(unclosed[")
        #expect(!q.doesMatch("(unclosed["))
        #expect(!q.matches(commit: i, in: s))
        #expect(q.matches(in: "(unclosed[").isEmpty)
    }

    @Test func fieldSelection() {
        let (s, i) = store()
        func hit(_ f: FindQuery.Field, _ p: String) -> Bool {
            FindQuery(field: f, pattern: p).matches(commit: i, in: s)
        }
        #expect(hit(.headline, "widget"))
        #expect(!hit(.headline, "gadget"))
        #expect(hit(.comments, "gadget"))
        #expect(hit(.allFields, "gadget"))
        #expect(hit(.committer, "carol@example"))
        #expect(hit(.allFields, "alice@example.com"))
        #expect(!hit(.allFields, "2020"))  // dates are not searched
    }

    @Test func globMetacharactersAreLiteralInExact() {
        let q = FindQuery(pattern: "a*b?[c]\\")
        #expect(q.findPattern == "*a\\*b\\?\\[c]\\\\*")
        #expect(q.doesMatch("xx a*b?[c]\\ yy"))
        #expect(!q.doesMatch("aXXb?[c]\\"))
    }

    @Test func regexpAndRanges() {
        let q = FindQuery(matchMode: .regexp, pattern: "w.dg")
        #expect(q.doesMatch("a widget"))
        let text = "widget wodget"
        let r = q.matches(in: text)
        #expect(r.map { String(text[$0]) } == ["widg", "wodg"])
    }

    @Test func literalRangesAreNonOverlapping() {
        let text = "aaaa Aa"
        let q = FindQuery(matchMode: .ignoreCase, pattern: "aa")
        #expect(q.matches(in: text).map { text.distance(from: text.startIndex, to: $0.lowerBound) } == [0, 2, 5])
        let e = FindQuery(matchMode: .exact, pattern: "aa")
        #expect(e.matches(in: text).count == 2)
    }

    @Test func emptyPatternAndOtherTypesMatchNothing() {
        #expect(!FindQuery(pattern: "").doesMatch("anything"))
        #expect(!FindQuery(type: .touchingPaths, pattern: "a").doesMatch("a"))
        #expect(FindQuery(type: .touchingPaths, pattern: "a").matches(in: "a").isEmpty)
    }

    @Test func mutatingRecompiles() {
        var q = FindQuery(pattern: "x")
        #expect(q.doesMatch("axb"))
        q.pattern = "y"
        #expect(!q.doesMatch("axb"))
        q.matchMode = .regexp
        q.pattern = "[xy]"
        #expect(q.doesMatch("axb"))
    }
}
