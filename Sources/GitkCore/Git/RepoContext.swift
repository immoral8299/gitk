// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Why `RepoContext.discover` failed.
public enum RepoContextError: Error, Sendable, Equatable {
    /// `git rev-parse --git-dir` failed. gitk's message: "Cannot find a git repository here."
    case notARepository
    /// `git rev-parse --show-object-format` printed something other than sha1/sha256.
    case unknownHashAlgorithm(String)
}

/// Facts about the repository gitk runs in.
public struct RepoContext: Sendable, Equatable {
    /// Output of `git rev-parse --git-dir` (may be relative to the cwd, e.g. ".git").
    public var gitDir: String
    /// Port of gitk's `gitworktree`; for a bare repository without a work tree it is the cwd.
    public var worktree: String
    /// `git rev-parse --show-cdup` when inside a work tree, else "".
    public var cdup: String
    public var isBare: Bool
    public var hasWorktree: Bool
    /// "sha1" or "sha256".
    public var hashAlgorithm: String
    /// 40 or 64.
    public var hashLength: Int
    public var logShowRoot: Bool
    /// i18n.logoutputencoding > i18n.commitencoding > "utf-8" (IANA/git name).
    public var gitEncoding: String
    /// gui.encoding, or "utf-8" (the macOS system encoding) when unset or empty.
    public var guiEncoding: String

    /// Discovers the repository the way git does from `cwd`, honouring `GIT_DIR` and
    /// `GIT_WORK_TREE` in `environment`.
    ///
    /// Port of gitk lines 245–283 (`hasworktree`, `gitworktree`), 12572–12615
    /// (encodings, hash algorithm, `log.showroot`) and 12941–12952 (`cdup`).
    /// - Parameters:
    ///   - environment: the "parent" environment for git (and the source of `GIT_WORK_TREE`).
    ///   - runner: replaces the real git runner (tests).
    public static func discover(
        cwd: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runner: (any GitRunning)? = nil
    ) async throws -> RepoContext {
        let git: any GitRunning = runner ?? GitRunner(cwd: cwd, baseEnvironment: environment)

        // Like Tcl `exec`: a failure throws, one trailing newline is dropped.
        func exec(_ args: [String]) async throws -> String {
            let out = try await git.run(args, stdin: nil, cwd: nil)
            var text = String(decoding: out.stdout, as: UTF8.self)
            if text.hasSuffix("\n") { text.removeLast() }
            return text
        }

        // gitk 12828: "check that we can find a .git directory somewhere"
        let gitDir: String
        do { gitDir = try await exec(["rev-parse", "--git-dir"]) } catch is GitError {
            throw RepoContextError.notARepository
        }

        // 12572–12595: commitencoding, overwritten by logoutputencoding when that succeeds.
        var gitEncoding = ""
        if let v = try? await exec(["config", "--get", "i18n.commitencoding"]) { gitEncoding = v }
        if let v = try? await exec(["config", "--get", "i18n.logoutputencoding"]) { gitEncoding = v }
        if gitEncoding.isEmpty { gitEncoding = "utf-8" }

        var guiEncoding = "utf-8"
        if let v = try? await exec(["config", "--get", "gui.encoding"]), !v.isEmpty {
            guiEncoding = v
        }

        // 12598–12610
        let hashAlgorithm = try await exec(["rev-parse", "--show-object-format"])
        let hashLength: Int
        switch hashAlgorithm {
        case "sha1": hashLength = 40
        case "sha256": hashLength = 64
        default: throw RepoContextError.unknownHashAlgorithm(hashAlgorithm)
        }

        var logShowRoot = true
        if let v = try? await exec(["config", "--bool", "--get", "log.showroot"]) {
            logShowRoot = v == "true"
        }

        // 245–250 hasworktree
        let isBare = try await exec(["rev-parse", "--is-bare-repository"])
        let isInsideGitDir = try await exec(["rev-parse", "--is-inside-git-dir"])
        let hasWorktree = isBare == "false" && isInsideGitDir == "false"

        // 12941–12944
        var cdup = ""
        if try await exec(["rev-parse", "--is-inside-work-tree"]) == "true" {
            cdup = try await exec(["rev-parse", "--show-cdup"])
        }

        // 259–283 gitworktree
        let worktree: String
        if let top = try? await exec(["rev-parse", "--show-toplevel"]) {
            worktree = top
        } else if let w = environment["GIT_WORK_TREE"] {
            worktree = w
        } else if let c = try? await exec(["config", "--get", "core.worktree"]) {
            worktree = c
        } else {
            // file normalize ./$cdup
            worktree = URL(fileURLWithPath: "./" + cdup, relativeTo: cwd).standardizedFileURL.path
        }

        return RepoContext(
            gitDir: gitDir, worktree: worktree, cdup: cdup, isBare: isBare == "true",
            hasWorktree: hasWorktree, hashAlgorithm: hashAlgorithm, hashLength: hashLength,
            logShowRoot: logShowRoot, gitEncoding: gitEncoding, guiEncoding: guiEncoding)
    }
}
