// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct HistoryLoaderTests {
    @Test func streamsEveryCommitAndTagsBatches() async throws {
        let repo = try FixtureRepo.make("merge-simple")
        let runner = GitRunner(cwd: repo)
        let loader = HistoryLoader(runner: runner)
        let stream = try await loader.start(view: ViewSpec(name: "all", args: ["--all"]), hashLength: 40)
        var ids: [ObjectID] = []
        var generations: Set<UInt64> = []
        for try await batch in stream {
            #expect(batch.commits.count <= 2_000)
            ids += batch.commits.map(\.id)
            generations.insert(batch.generation)
        }
        let expected = try await runner.run(["rev-list", "--all"])
        let hashes = String(decoding: expected.stdout, as: UTF8.self).split(separator: "\n").map(String.init)
        #expect(Set(ids.map(\.hex)) == Set(hashes))
        #expect(ids.count == hashes.count)
        #expect(generations.count == 1)
        #expect(await !loader.isRunning)
    }

    @Test func cancellationStopsChildAndFurtherBatches() async throws {
        let repo = try FixtureRepo.make("long-lines")
        let loader = HistoryLoader(runner: GitRunner(cwd: repo))
        let stream = try await loader.start(view: ViewSpec(name: "all", args: ["--all"]), hashLength: 40)
        await loader.cancel()
        do { for try await _ in stream {} } catch is CancellationError {}
        #expect(await !loader.isRunning)
        let next = try await loader.start(view: ViewSpec(name: "one", args: ["-1"]), hashLength: 40)
        var count = 0
        for try await batch in next { count += batch.commits.filter { !$0.isBoundary }.count }
        #expect(count == 1)
    }

    @Test func gitFailureSurfacesStderr() async throws {
        let repo = try FixtureRepo.make("linear")
        let loader = HistoryLoader(runner: GitRunner(cwd: repo))
        let stream = try await loader.start(view: ViewSpec(name: "bad", args: ["--invalid-gitk-option"]), hashLength: 40)
        do {
            for try await _ in stream {}
            Issue.record("git log should fail")
        } catch let error as GitError {
            #expect(error.stderr.contains("invalid-gitk-option"))
        }
    }

    @Test func repositoryEncodingIsUsedWithoutForcingLogEncoding() async throws {
        let repo = try FixtureRepo.make("encodings")
        let context = try await RepoContext.discover(cwd: repo)
        let loader = HistoryLoader(runner: GitRunner(cwd: repo))
        let stream = try await loader.start(view: ViewSpec(name: "all", args: ["--all"]), hashLength: 40)
        var authors: [String] = []
        for try await batch in stream {
            authors += batch.commits.map { $0.authorNameString(fallbackEncoding: context.gitEncoding) }
        }
        #expect(authors.contains { $0.contains("é") || $0.contains("ü") })
    }
}
