// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Lets `gitk-swift <path-to-repo>` open another repository (not in gitk, which
/// always uses the working directory).
///
/// The first argument names the repository when it comes before any `--`,
/// does not start with `-`, is a directory, and git finds a repository there;
/// and either that directory is the top level of its work tree (or a git
/// directory), or the working directory is not inside a repository. A
/// subdirectory of the current repository stays a path limit, as in
/// `gitk src/`.
public enum RepositoryArgument {
    public struct Result: Sendable, Equatable {
        /// The directory to run in: the repository, or the original `cwd`.
        public var cwd: URL
        /// The arguments with the repository removed.
        public var arguments: [String]
    }

    public static func extract(_ arguments: [String], cwd: URL, runner: any GitRunning = GitRunner()) async -> Result {
        let unchanged = Result(cwd: cwd, arguments: arguments)
        guard let first = arguments.first, first != "--", !first.hasPrefix("-") else { return unchanged }
        let expanded = (first as NSString).expandingTildeInPath
        let absolute = expanded.hasPrefix("/") ? expanded : (cwd.path as NSString).appendingPathComponent(expanded)
        let candidate = URL(fileURLWithPath: (absolute as NSString).standardizingPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return unchanged
        }
        func output(_ args: [String], in dir: URL) async -> String? {
            guard let result = try? await runner.run(args, stdin: nil, cwd: dir) else { return nil }
            return String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let gitDir = await output(["rev-parse", "--absolute-git-dir"], in: candidate) else { return unchanged }
        let top = await output(["rev-parse", "--show-toplevel"], in: candidate)
        let resolved = candidate.resolvingSymlinksInPath().path
        let isRoot = top.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path == resolved } ?? false
        let isGitDir = URL(fileURLWithPath: gitDir).resolvingSymlinksInPath().path == resolved
        let cwdInRepo = await output(["rev-parse", "--git-dir"], in: cwd) != nil
        guard isRoot || isGitDir || !cwdInRepo else { return unchanged }
        return Result(cwd: candidate, arguments: Array(arguments.dropFirst()))
    }
}
