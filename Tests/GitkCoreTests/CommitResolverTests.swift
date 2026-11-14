// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct CommitResolverTests {
    private struct Runner: GitRunning {
        var response: Result<GitOutput, GitError>
        func run(_ args: [String], stdin: Data?, cwd: URL?) async throws -> GitOutput {
            #expect(args == ["rev-parse", "--verify", "topic^{commit}"] || args.last?.hasSuffix("^{commit}") == true)
            return try response.get()
        }
    }
    private var failure: Runner { Runner(response: .failure(GitError(args: [], status: 128, stderr: "unknown revision"))) }

    @Test func prefixResolutionAndAmbiguity() async throws {
        let a = try #require(ObjectID(hex: "abcdef0" + String(repeating: "1", count: 33)))
        let b = try #require(ObjectID(hex: "abcdef0" + String(repeating: "2", count: 33)))
        #expect(try await CommitResolver.resolve("abcdef01", inView: [a, b], runner: failure) == a)
        await #expect(throws: CommitResolutionError.ambiguous("abcdef0")) {
            try await CommitResolver.resolve("abcdef0", inView: [a, b], runner: failure)
        }
    }

    @Test func revisionAndFilteredRevision() async throws {
        let id = try #require(ObjectID(hex: String(repeating: "a", count: 40)))
        let runner = Runner(response: .success(GitOutput(stdout: Data((id.hex + "\n").utf8), stderr: Data(), status: 0)))
        #expect(try await CommitResolver.resolve("topic", inView: [id], runner: runner) == id)
        await #expect(throws: CommitResolutionError.notInView("topic")) {
            try await CommitResolver.resolve("topic", inView: [], runner: runner)
        }
        await #expect(throws: CommitResolutionError.unknownRevision("topic")) {
            try await CommitResolver.resolve("topic", inView: [], runner: failure)
        }
        await #expect(throws: CommitResolutionError.unknownCommit("deadbeef")) {
            try await CommitResolver.resolve("deadbeef", inView: [], runner: failure)
        }
    }
}
