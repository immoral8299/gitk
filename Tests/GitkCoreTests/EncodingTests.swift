// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite @MainActor struct EncodingTests {
    /// history-loading "Non-UTF-8 commit": the `encodings` fixture has a commit made
    /// with `i18n.commitEncoding=ISO-8859-1` and a Latin-1 author name.
    @Test func latin1CommitDecodesThroughViewSession() async throws {
        let repo = try FixtureRepo.make("encodings")
        let context = try await RepoContext.discover(cwd: repo)
        let session = ViewSession(repo: context, runner: GitRunner(cwd: repo),
                                  view: ViewSpec(name: "all", args: ["--all"]))
        session.showLocalChanges = false
        await session.load()
        #expect(session.errorMessage == nil)
        let rows = (0..<session.rowCount).compactMap { session.commit(at: $0) }
        let latin1 = try #require(rows.first { session.store.headline(at: $0).hasPrefix("Latin-1 message") })
        #expect(session.store.author(at: latin1).contains("José Muñoz"))
        #expect(session.store.headline(at: latin1) == "Latin-1 message: señor, façade")
        let utf8 = try #require(rows.first { session.store.headline(at: $0).hasPrefix("UTF-8 commit") })
        #expect(session.store.headline(at: utf8) == "UTF-8 commit: café")
    }

    /// A commit that still carries its own `encoding` header is decoded with it,
    /// ahead of the repository fallback.
    @Test func encodingHeaderWinsOverFallback() throws {
        let store = CommitStore(fallbackEncoding: "utf-8")
        let index = store.insert(commit(name: Data([0x4A, 0x6F, 0x73, 0xE9]), encoding: "ISO-8859-1"))
        #expect(store.author(at: index).hasPrefix("José"))
    }

    /// history-loading "Unsupported encoding": an unknown name falls back to UTF-8 and
    /// invalid bytes are shown (as U+00XX) rather than dropped.
    @Test func unsupportedEncodingFallsBackToUTF8KeepingBytes() throws {
        let store = CommitStore(fallbackEncoding: "x-no-such-charset")
        let index = store.insert(commit(name: Data([0x4A, 0x6F, 0x73, 0xE9]), encoding: nil))
        let author = store.author(at: index)
        #expect(author.hasPrefix("Jos\u{E9}"))
        #expect(TextDecoder.decodeReporting(Data("x".utf8), encodingName: "x-no-such-charset").unknownEncoding)
    }

    private func commit(name: Data, encoding: String?) -> ParsedCommit {
        let id = ObjectID(hex: String(repeating: "a", count: 40))!
        let tree = ObjectID(hex: String(repeating: "b", count: 40))!
        return ParsedCommit(
            id: id, parents: [], isBoundary: false, isUninteresting: false,
            side: nil, tree: tree, authorName: name, authorEmail: Data("j@example.com".utf8),
            authorEpoch: 1_577_836_800, authorTZ: "+0000",
            committerName: name, committerEmail: Data("j@example.com".utf8),
            committerEpoch: 1_577_836_800, committerTZ: "+0000", encoding: encoding,
            headline: Data("subject".utf8), message: Data("subject\n".utf8), notes: nil)
    }
}
