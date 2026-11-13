// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// A startup check that failed. `message` is gitk's exact English text.
public enum StartupError: Error, Sendable, Equatable {
    /// `git version` is below 2.20. Shown as a fatal error titled "gitk: fatal error".
    case gitTooOld(found: String)
    /// `git version` printed nothing we can read.
    case gitVersionUnreadable(String)
    /// gitk: "Cannot find a git repository here."
    case notARepository
    /// Written to stderr; exit status 1.
    case unknownHashAlgorithm(String)

    public static let fatalErrorTitle = "gitk: fatal error"

    public var message: String {
        switch self {
        case .gitTooOld(let found):
            return "The git executable found is too old.\n"
                + "The minimum required version is \(GitVersion.minimumSupported).\n"
                + "The version of git found is \(found)."
        case .gitVersionUnreadable(let output):
            return "Cannot read the version of git from: \(output)"
        case .notARepository:
            return "Cannot find a git repository here."
        case .unknownHashAlgorithm(let name):
            return "Unknown hash algorithm: \(name)"
        }
    }
}

/// What the startup checks learned.
public struct StartupContext: Sendable, Equatable {
    public var gitVersion: GitVersion
    public var repo: RepoContext
}

/// Runs the checks gitk does before it opens a window.
public struct StartupChecks: Sendable {
    public var cwd: URL
    public var environment: [String: String]
    public var runner: (any GitRunning)?

    public init(
        cwd: URL, environment: [String: String] = ProcessInfo.processInfo.environment,
        runner: (any GitRunning)? = nil
    ) {
        self.cwd = cwd
        self.environment = environment
        self.runner = runner
    }

    /// Port of gitk/gitk 20–34 (git version), 12601–12610 (hash algorithm) and
    /// 12828–12831 (repository).
    ///
    /// Order: git version, repository, hash algorithm. gitk reads the hash algorithm
    /// (line 12601) before it checks for a repository (12828), but outside a
    /// repository `git rev-parse --show-object-format` fails, which in gitk is an
    /// uncaught Tcl error. Checking the repository first gives the user the
    /// intended "Cannot find a git repository here." message; both checks are in
    /// `RepoContext.discover`, which tests the repository before the hash algorithm.
    public func run() async throws -> StartupContext {
        let git: any GitRunning = runner ?? GitRunner(cwd: cwd, baseEnvironment: environment)

        let output: GitOutput
        do {
            output = try await git.run(["version"], stdin: nil, cwd: nil)
        } catch let e as GitError {
            throw StartupError.gitVersionUnreadable(e.stderr)
        }
        let text = String(decoding: output.stdout, as: UTF8.self)
        // regexp {^git version ([\d.]*\d)} [exec git version] _ git_version
        guard let version = GitVersion(versionOutput: text),
              let match = text.firstMatch(of: /^git version ([\d.]*\d)/) else {
            throw StartupError.gitVersionUnreadable(text.trimmingCharacters(in: .newlines))
        }
        guard version.isSupported else {
            throw StartupError.gitTooOld(found: String(match.1))
        }

        do {
            let repo = try await RepoContext.discover(cwd: cwd, environment: environment, runner: git)
            return StartupContext(gitVersion: version, repo: repo)
        } catch RepoContextError.notARepository {
            throw StartupError.notARepository
        } catch RepoContextError.unknownHashAlgorithm(let name) {
            throw StartupError.unknownHashAlgorithm(name)
        }
    }
}
