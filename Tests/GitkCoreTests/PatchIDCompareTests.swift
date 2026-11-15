// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@MainActor @Suite struct PatchIDCompareTests {
    private func makeRepo() async throws -> (URL, ViewSession) {
        let repo = try FixtureRepo.makeCopy("linear")
        let runner = GitRunner(cwd: repo)
        _ = try await runner.run(["config", "user.name", "Compare Test"])
        _ = try await runner.run(["config", "user.email", "compare@example.com"])
        let context = try await RepoContext.discover(cwd: repo)
        let session = ViewSession(repo: context, runner: runner, view: ViewSpec(name: "All files", args: ["--all"]))
        return (repo, session)
    }

    private func resolve(_ rev: String, _ runner: GitRunner) async throws -> ObjectID {
        let output = try await runner.run(["rev-parse", rev])
        return try #require(ObjectID(hex: String(decoding: output.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    @Test func cherryPickedSeriesIsReportedEquivalent() async throws {
        let (repo, session) = try await makeRepo()
        defer { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        let runner = session.runner
        let first = try await resolve("HEAD~1", runner)
        let second = try await resolve("HEAD", runner)
        _ = try await runner.run(["checkout", "-b", "picked", "HEAD~2"])
        _ = try await runner.run(["cherry-pick", first.hex, second.hex])
        let pickedFirst = try await resolve("HEAD~1", runner)
        let pickedSecond = try await resolve("HEAD", runner)
        await session.load()
        let compare = PatchIDCompare(runner: runner, graph: PatchIDGraph(session: session))
        let lines = try await compare.compare(first, pickedFirst)
        let headFirst = session.store.index(of: first).map { session.store.headline(at: $0) } ?? ""
        let headSecond = session.store.index(of: second).map { session.store.headline(at: $0) } ?? ""
        #expect(lines == [
            .samePatch(a: first, b: pickedFirst, headA: headFirst, headB: headFirst),
            .samePatch(a: second, b: pickedSecond, headA: headSecond, headB: headSecond),
            .tooManyChildren(second, count: 0, leadingBlank: true),
        ])
        #expect(compare.patchIDs.count == 4)
    }

    @Test func differingPatchIsReportedAndStopsTheWalk() async throws {
        let (repo, session) = try await makeRepo()
        defer { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        let runner = session.runner
        let first = try await resolve("HEAD~1", runner)
        _ = try await runner.run(["checkout", "-b", "other", "HEAD~2"])
        try Data("different\n".utf8).write(to: repo.appendingPathComponent("extra"))
        _ = try await runner.run(["add", "extra"])
        _ = try await runner.run(["commit", "-m", "extra"])
        let extra = try await resolve("HEAD", runner)
        await session.load()
        let compare = PatchIDCompare(runner: runner, graph: PatchIDGraph(session: session))
        let lines = try await compare.compare(first, extra)
        guard case .differs(let a, let b, _, let headB)? = lines.last else {
            Issue.record("expected a differs line, got \(lines)")
            return
        }
        #expect(lines.count == 1)
        #expect(a == first && b == extra && headB == "extra")
    }

    @Test func mergeCommitsAreSkipped() async throws {
        let (repo, session) = try await makeRepo()
        defer { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        let runner = session.runner
        let head = try await resolve("HEAD", runner)
        await session.load()
        var graph = PatchIDGraph(session: session)
        graph.parentCount = { _ in 2 }
        let compare = PatchIDCompare(runner: runner, graph: graph)
        let lines = try await compare.compare(head, head)
        #expect(lines.first == .skippingMerge(head))
    }
}
