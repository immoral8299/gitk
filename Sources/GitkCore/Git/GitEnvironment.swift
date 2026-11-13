// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Environment handling for child processes (design D2).
enum GitEnvironment {
    /// The child environment: the parent's, minus `GIT_TRACE` (it would write
    /// trace output into the stderr we capture). `LC_ALL`/`LANG` are left alone.
    static func childEnvironment(
        from base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        env["GIT_TRACE"] = nil
        return env
    }

    /// Searches `path` (a colon separated list) for an executable file called `name`.
    static func resolveExecutable(named name: String, path: String?) -> URL? {
        for dir in (path ?? "").split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(dir), isDirectory: true)
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// `git`, found on the parent's PATH once; `/usr/bin/git` if PATH has none.
    static let gitURL: URL =
        resolveExecutable(named: "git", path: ProcessInfo.processInfo.environment["PATH"])
        ?? URL(fileURLWithPath: "/usr/bin/git")
}
