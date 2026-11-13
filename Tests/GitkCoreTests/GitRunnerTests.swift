// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct GitRunnerTests {
    @Test func gitVersionSucceeds() async throws {
        let out = try await GitRunner().run(["--version"])
        #expect(out.status == 0)
        #expect(String(decoding: out.stdout, as: UTF8.self).hasPrefix("git version"))
    }

    @Test func unknownRevisionThrowsWithStderr() async throws {
        let repo = try FixtureRepo.make("linear")
        let runner = GitRunner(cwd: repo)
        do {
            _ = try await runner.run(["rev-parse", "nope"])
            Issue.record("expected GitError")
        } catch let e as GitError {
            #expect(e.stderr.contains("unknown revision"))
            #expect(e.args == ["rev-parse", "nope"])
            #expect(e.status != 0)
        }
    }

    @Test func gitTraceIsRemovedFromChildEnvironment() async throws {
        // Mutating the real parent environment would race with other tests, so
        // the "parent" environment is passed in explicitly.
        let env = GitEnvironment.childEnvironment(from: ["GIT_TRACE": "1", "KEEP_ME": "yes"])
        #expect(env["GIT_TRACE"] == nil)
        let out = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/env"), environment: env)
        let text = String(decoding: out.stdout, as: UTF8.self)
        #expect(!text.contains("GIT_TRACE"))
        #expect(text.contains("KEEP_ME=yes"))
    }

    @Test func gitRunnerStripsGitTraceFromBaseEnvironment() async throws {
        let runner = GitRunner(baseEnvironment: ["GIT_TRACE": "1", "PATH": "/usr/bin:/bin"])
        let out = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/env"), environment: runner.environment)
        #expect(!String(decoding: out.stdout, as: UTF8.self).contains("GIT_TRACE"))
    }

    @Test func stdinIsDeliveredAndLargeOutputDoesNotDeadlock() async throws {
        // 4 MB through cat: more than any pipe buffer in both directions.
        let big = Data(repeating: 0x61, count: 4_000_000)
        let out = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/bin/cat"), stdin: big)
        #expect(out.stdout == big)
        #expect(out.status == 0)
    }

    @Test func gitReadsStdin() async throws {
        let out = try await GitRunner().run(["hash-object", "--stdin"], stdin: Data("hello\n".utf8))
        #expect(String(decoding: out.stdout, as: UTF8.self)
            .hasPrefix("ce013625030ba8dba906f756967f9e9ca394464a"))
    }

    @Test func cwdIsHonoured() async throws {
        let dir = FileManager.default.temporaryDirectory
        let out = try await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/bin/pwd"), cwd: dir)
        let got = String(decoding: out.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(URL(fileURLWithPath: got).resolvingSymlinksInPath().path
            == dir.resolvingSymlinksInPath().path)
    }

    @Test func missingExecutableThrowsGitError() async throws {
        let runner = GitRunner(gitURL: URL(fileURLWithPath: "/nonexistent/git"))
        await #expect(throws: GitError.self) { try await runner.run(["status"]) }
    }
}
