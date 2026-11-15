// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite @MainActor struct MarkTests {
    private func loaded(_ name: String) async throws -> (ViewSession, URL) {
        let repo = try FixtureRepo.make(name)
        let context = try await RepoContext.discover(cwd: repo)
        let session = ViewSession(repo: context, runner: GitRunner(cwd: repo), view: ViewSpec(name: "all", args: ["--all"]))
        session.showLocalChanges = false
        await session.load()
        return (session, repo)
    }

    @Test func findCommonDescOnCrissCross() async throws {
        let (session, repo) = try await loaded("criss-cross")
        let runner = GitRunner(cwd: repo)
        let ids = (0..<session.rowCount).compactMap { session.id(at: $0) }
        #expect(ids.count == 10)
        for a in ids {
            for b in ids {
                let found = session.findCommonDesc(marked: a, menuID: b)
                let ab = (try? await runner.run(["merge-base", "--is-ancestor", a.hex, b.hex])) != nil
                let ba = (try? await runner.run(["merge-base", "--is-ancestor", b.hex, a.hex])) != nil
                if ab { #expect(found == b) } else if ba { #expect(found == a) }
                if let found {
                    for x in [a, b] {
                        let anc = (try? await runner.run(["merge-base", "--is-ancestor", x.hex, found.hex])) != nil
                        #expect(anc)
                    }
                }
            }
        }
        // The head merges everything, so every commit has the head as a common descendant.
        let head = try #require(ids.first)
        for a in ids { #expect(session.findCommonDesc(marked: a, menuID: head) == head) }
    }

    @Test func noMarkOrUnknownCommitFindsNothing() async throws {
        let (session, _) = try await loaded("criss-cross")
        let first = try #require(session.id(at: 0))
        #expect(session.findCommonDesc(marked: nil, menuID: first) == nil)
        let unknown = try #require(ObjectID(hex: String(repeating: "e", count: 40)))
        #expect(session.findCommonDesc(marked: unknown, menuID: first) == nil)
    }

    @Test func markAndReturn() throws {
        let id = try #require(ObjectID(hex: String(repeating: "a", count: 40)))
        let model = SelectionModel()
        #expect(model.markTarget == nil)
        let marked = model.marking(id)
        #expect(marked.markedID == id)
        #expect(marked.markTarget == id)
    }
}
