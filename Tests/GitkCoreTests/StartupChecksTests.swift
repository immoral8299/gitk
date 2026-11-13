// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

/// Answers `git <args>` from a table; anything else fails like git outside a repo.
private struct StubGit: GitRunning {
    var answers: [[String]: String]

    func run(_ args: [String], stdin: Data?, cwd: URL?) async throws -> GitOutput {
        if let text = answers[args] {
            return GitOutput(stdout: Data((text + "\n").utf8), stderr: Data(), status: 0)
        }
        throw GitError(args: args, status: 128, stderr: "fatal: stubbed failure")
    }
}

private func stubbedRepo(version: String, objectFormat: String) -> StubGit {
    StubGit(answers: [
        ["version"]: version,
        ["rev-parse", "--git-dir"]: ".git",
        ["rev-parse", "--show-object-format"]: objectFormat,
        ["rev-parse", "--is-bare-repository"]: "false",
        ["rev-parse", "--is-inside-git-dir"]: "false",
        ["rev-parse", "--is-inside-work-tree"]: "true",
        ["rev-parse", "--show-cdup"]: "",
        ["rev-parse", "--show-toplevel"]: "/repo",
    ])
}

@Suite struct StartupChecksTests {
    private let cwd = FileManager.default.temporaryDirectory

    @Test func gitTooOld() async throws {
        let checks = StartupChecks(cwd: cwd, runner: stubbedRepo(version: "git version 2.19.1", objectFormat: "sha1"))
        do {
            _ = try await checks.run()
            Issue.record("expected an error")
        } catch let e as StartupError {
            #expect(e == .gitTooOld(found: "2.19.1"))
            #expect(e.message == """
                The git executable found is too old.
                The minimum required version is 2.20.0.
                The version of git found is 2.19.1.
                """)
        }
    }

    @Test func unknownHashAlgorithm() async throws {
        let checks = StartupChecks(cwd: cwd, runner: stubbedRepo(version: "git version 2.45.0", objectFormat: "md5"))
        do {
            _ = try await checks.run()
            Issue.record("expected an error")
        } catch let e as StartupError {
            #expect(e == .unknownHashAlgorithm("md5"))
            #expect(e.message == "Unknown hash algorithm: md5")
        }
    }

    @Test func notARepository() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitk-swift-startup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let env = isolatedGitEnvironment(["GIT_CEILING_DIRECTORIES": dir.deletingLastPathComponent().path])
        do {
            _ = try await StartupChecks(cwd: dir, environment: env).run()
            Issue.record("expected an error")
        } catch let e as StartupError {
            #expect(e == .notARepository)
            #expect(e.message == "Cannot find a git repository here.")
        }
    }

    @Test func notARepositoryBeatsHashCheck() async throws {
        // Outside a repository --show-object-format fails too; the repository error wins.
        var stub = stubbedRepo(version: "git version 2.45.0", objectFormat: "sha1")
        stub.answers[["rev-parse", "--git-dir"]] = nil
        stub.answers[["rev-parse", "--show-object-format"]] = nil
        await #expect(throws: StartupError.notARepository) {
            _ = try await StartupChecks(cwd: cwd, runner: stub).run()
        }
    }

    @Test func realGitSucceedsOnLinear() async throws {
        let repo = try FixtureRepo.make("linear")
        let ctx = try await StartupChecks(cwd: repo, environment: isolatedGitEnvironment()).run()
        #expect(ctx.gitVersion.isSupported)
        #expect(ctx.repo.hashLength == 40)
    }

    @Test func sha256Repository() async throws {
        let repo = try FixtureRepo.make("sha256")
        let ctx = try await StartupChecks(cwd: repo, environment: isolatedGitEnvironment()).run()
        #expect(ctx.repo.hashAlgorithm == "sha256")
        #expect(ctx.repo.hashLength == 64)
    }

    @Test func stubbedSuccess() async throws {
        let ctx = try await StartupChecks(
            cwd: cwd, runner: stubbedRepo(version: "git version 2.20.0", objectFormat: "sha256")).run()
        #expect(ctx.gitVersion == GitVersion(2, 20, 0))
        #expect(ctx.repo.hashLength == 64)
    }
}
