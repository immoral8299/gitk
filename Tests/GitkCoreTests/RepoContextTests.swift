// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

/// Parent environment without user/system git config and without repo overrides.
func isolatedGitEnvironment(_ extra: [String: String] = [:]) -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    for k in ["GIT_DIR", "GIT_WORK_TREE", "GIT_TRACE"] { env[k] = nil }
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CONFIG_GLOBAL"] = "/dev/null"
    for (k, v) in extra { env[k] = v }
    return env
}

func runGit(_ args: [String], in dir: URL, env: [String: String] = isolatedGitEnvironment()) async throws {
    _ = try await GitRunner(cwd: dir, baseEnvironment: env).run(args)
}

@Suite struct RepoContextTests {
    @Test func linear() async throws {
        let repo = try FixtureRepo.make("linear")
        let ctx = try await RepoContext.discover(cwd: repo, environment: isolatedGitEnvironment())
        #expect(ctx.gitDir == ".git")
        #expect(ctx.hasWorktree)
        #expect(!ctx.isBare)
        #expect(ctx.cdup == "")
        #expect(ctx.hashAlgorithm == "sha1")
        #expect(ctx.hashLength == 40)
        #expect(ctx.logShowRoot)
        #expect(ctx.gitEncoding == "utf-8")
        #expect(ctx.guiEncoding == "utf-8")
        #expect(URL(fileURLWithPath: ctx.worktree).resolvingSymlinksInPath().path
            == repo.resolvingSymlinksInPath().path)
    }

    @Test func sha256() async throws {
        let repo = try FixtureRepo.make("sha256")
        let ctx = try await RepoContext.discover(cwd: repo, environment: isolatedGitEnvironment())
        #expect(ctx.hashAlgorithm == "sha256")
        #expect(ctx.hashLength == 64)
    }

    @Test func bareClone() async throws {
        let source = try FixtureRepo.make("linear")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitk-swift-bare-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await runGit(["clone", "--bare", "-q", source.path, "bare.git"], in: dir)
        let bare = dir.appendingPathComponent("bare.git")
        let ctx = try await RepoContext.discover(cwd: bare, environment: isolatedGitEnvironment())
        #expect(ctx.isBare)
        #expect(!ctx.hasWorktree)
        #expect(ctx.cdup == "")
        #expect(ctx.gitDir == ".")
        #expect(URL(fileURLWithPath: ctx.worktree).resolvingSymlinksInPath().path
            == bare.resolvingSymlinksInPath().path)
    }

    @Test func subdirectoryHasCdup() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let sub = repo.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let ctx = try await RepoContext.discover(cwd: sub, environment: isolatedGitEnvironment())
        #expect(ctx.cdup == "../")
        #expect(ctx.hasWorktree)
        #expect(URL(fileURLWithPath: ctx.worktree).resolvingSymlinksInPath().path
            == repo.resolvingSymlinksInPath().path)
    }

    @Test func notARepository() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitk-swift-norepo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Stop upward discovery so a repository above $TMPDIR cannot be found.
        let env = isolatedGitEnvironment(["GIT_CEILING_DIRECTORIES": dir.deletingLastPathComponent().path])
        await #expect(throws: RepoContextError.notARepository) {
            _ = try await RepoContext.discover(cwd: dir, environment: env)
        }
    }

    @Test func gitDirFromEnvironment() async throws {
        let repo = try FixtureRepo.make("linear")
        let elsewhere = FileManager.default.temporaryDirectory
        let env = isolatedGitEnvironment([
            "GIT_DIR": repo.appendingPathComponent(".git").path,
            "GIT_WORK_TREE": repo.path,
        ])
        let ctx = try await RepoContext.discover(cwd: elsewhere, environment: env)
        #expect(ctx.gitDir == repo.appendingPathComponent(".git").path)
        #expect(ctx.hashLength == 40)
        #expect(URL(fileURLWithPath: ctx.worktree).resolvingSymlinksInPath().path
            == repo.resolvingSymlinksInPath().path)
    }

    @Test func configOptions() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let env = isolatedGitEnvironment()
        try await runGit(["config", "log.showroot", "false"], in: repo, env: env)
        try await runGit(["config", "i18n.commitencoding", "iso-8859-1"], in: repo, env: env)
        try await runGit(["config", "gui.encoding", "euc-jp"], in: repo, env: env)
        var ctx = try await RepoContext.discover(cwd: repo, environment: env)
        #expect(!ctx.logShowRoot)
        #expect(ctx.gitEncoding == "iso-8859-1")
        #expect(ctx.guiEncoding == "euc-jp")

        try await runGit(["config", "i18n.logoutputencoding", "shift_jis"], in: repo, env: env)
        ctx = try await RepoContext.discover(cwd: repo, environment: env)
        #expect(ctx.gitEncoding == "shift_jis")
    }
}
