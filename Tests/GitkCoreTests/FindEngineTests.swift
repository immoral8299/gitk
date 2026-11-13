// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct FindEngineTests {
    private func allIDs(_ repo: URL) async throws -> [ObjectID] {
        let out = try await GitRunner(cwd: repo).run(["rev-list", "--all"])
        return String(decoding: out.stdout, as: UTF8.self)
            .split(separator: "\n").compactMap { ObjectID(hex: String($0)) }
    }

    private func logHashes(_ repo: URL, _ extra: [String]) async throws -> Set<ObjectID> {
        let out = try await GitRunner(cwd: repo).run(["log", "--all", "--format=%H"] + extra)
        return Set(String(decoding: out.stdout, as: UTF8.self)
            .split(separator: "\n").compactMap { ObjectID(hex: String($0)) })
    }

    private func collect(_ s: AsyncThrowingStream<ObjectID, Error>) async throws -> Set<ObjectID> {
        var r = Set<ObjectID>()
        for try await id in s { r.insert(id) }
        return r
    }

    @Test func argumentsForEachType() {
        #expect(FindEngine.arguments(for: FindQuery(type: .addingRemovingString, pattern: "foo"), cdup: "")
            == ["diff-tree", "-r", "-s", "--stdin", "-Sfoo"])
        #expect(FindEngine.arguments(for: FindQuery(type: .changingLinesMatching, pattern: "a.b"), cdup: "")
            == ["diff-tree", "-r", "-s", "--stdin", "-Ga.b"])
        #expect(FindEngine.arguments(for: FindQuery(type: .touchingPaths, pattern: "a b/c"), cdup: "../")
            == ["diff-tree", "-r", "-s", "--stdin", "--", "../a", "../b/c"])
        #expect(FindEngine.arguments(for: FindQuery(type: .touchingPaths, matchMode: .exact, pattern: "d\\e"), cdup: "")
            == ["diff-tree", "-r", "-s", "--stdin", "--", "d/e"])
        #expect(FindEngine.arguments(for: FindQuery(type: .containing, pattern: "x"), cdup: "") == nil)
        #expect(FindEngine.arguments(for: FindQuery(type: .touchingPaths, pattern: "'oops"), cdup: "") == nil)
    }

    @Test func pickaxeMatchesGitLog() async throws {
        let repo = try FixtureRepo.make("linear")
        let ids = try await allIDs(repo)
        let engine = FindEngine(runner: GitRunner(cwd: repo))
        let got = try await collect(engine.start(
            query: FindQuery(type: .addingRemovingString, pattern: "file 5"), commitIDs: ids))
        let expected = try await logHashes(repo, ["-Sfile 5"])
        #expect(!expected.isEmpty)
        #expect(got == expected)
    }

    @Test func changingLinesMatchesGitLog() async throws {
        let repo = try FixtureRepo.make("linear")
        let ids = try await allIDs(repo)
        let engine = FindEngine(runner: GitRunner(cwd: repo))
        let got = try await collect(engine.start(
            query: FindQuery(type: .changingLinesMatching, pattern: "file [3-4]"), commitIDs: ids))
        let expected = try await logHashes(repo, ["-Gfile [3-4]"])
        #expect(!expected.isEmpty)
        #expect(got == expected)
    }

    @Test func touchingPathsOnRenames() async throws {
        let repo = try FixtureRepo.make("renames")
        let ids = try await allIDs(repo)
        let engine = FindEngine(runner: GitRunner(cwd: repo))
        let got = try await collect(engine.start(
            query: FindQuery(type: .touchingPaths, pattern: "gadget.c"), commitIDs: ids))
        let expected = try await logHashes(repo, ["--", "gadget.c"])
        #expect(!expected.isEmpty)
        #expect(got == expected)
    }

    @Test func idsNotRequestedAreNotReported() async throws {
        let repo = try FixtureRepo.make("linear")
        let ids = try await allIDs(repo)
        let engine = FindEngine(runner: GitRunner(cwd: repo))
        let subset = Array(ids.prefix(2))
        let got = try await collect(engine.start(
            query: FindQuery(type: .addingRemovingString, pattern: "file"), commitIDs: subset))
        #expect(got.isSubset(of: Set(subset)))
    }

    @Test func containingRunsNothing() async throws {
        let repo = try FixtureRepo.make("linear")
        let engine = FindEngine(runner: GitRunner(cwd: repo))
        let ids = try await allIDs(repo)
        let got = try await collect(engine.start(
            query: FindQuery(type: .containing, pattern: "x"), commitIDs: ids))
        #expect(got.isEmpty)
    }

    @Test func cancelStopsProcess() async throws {
        let repo = try FixtureRepo.make("linear")
        let ids = try await allIDs(repo)
        let engine = FindEngine(runner: GitRunner(cwd: repo))
        let stream = engine.start(
            query: FindQuery(type: .addingRemovingString, pattern: "file"), commitIDs: ids)
        engine.cancel()
        for try await _ in stream {}
        let deadline = Date().addingTimeInterval(2)
        while engine.isRunning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!engine.isRunning)
    }
}
