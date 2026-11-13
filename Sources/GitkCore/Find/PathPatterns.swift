// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

/// The "touching paths:" find type: a list of glob patterns built from the
/// paths the user typed, and a matcher that tests file names against them.
struct PathPatterns {
    /// The paths the user entered, after shell-style word splitting. These are
    /// relative to the repository root and are passed to `git diff-tree`.
    let paths: [String]

    /// The glob patterns produced from `paths`, in gitk's order: for each path,
    /// the path itself and `path/*`, or only `path*` when it ends in `/`.
    let patterns: [String]

    /// Compiled form of `patterns`, used by `matches(_:)`.
    private let matchers: [[TclGlob]]

    /// Port of the "touching paths:" branch of gitk proc `do_file_hl`
    /// (gitk/gitk 4989–5024). With Exact matching, backslashes are treated as
    /// forward slashes before the find string is split into words. Throws the
    /// `ShellWords` error for an unbalanced quote; gitk ignores that case, so
    /// the caller decides how to report it.
    init(findString: String, exact: Bool) throws {
        let text = exact
            ? String(findString.map { $0 == "\\" ? "/" : $0 })
            : findString
        self.init(paths: try ShellWords.split(text))
    }

    /// Builds the patterns for words that have already been split.
    init(paths: [String]) {
        self.paths = paths
        self.patterns = PathPatterns.makePatterns(paths)
        self.matchers = patterns.map { TclGlob.parse($0) }
    }

    /// True if `path` matches at least one pattern, using Tcl `string match`
    /// semantics (see `TclGlob`).
    func matches(_ path: String) -> Bool {
        let text = Array(path.unicodeScalars)
        return matchers.contains { TclGlob.match($0, text) }
    }

    /// Port of gitk proc `makepatterns` (gitk/gitk 4975–4989). The glob
    /// metacharacters `* ? [ \` are escaped, so each path is matched literally.
    static func makePatterns(_ l: [String]) -> [String] {
        var ret: [String] = []
        for e in l {
            var ee = ""
            for c in e {
                switch c {
                case "*", "?", "[", "\\": ee.append("\\")
                default: break
                }
                ee.append(c)
            }
            if ee.last == "/" {
                ret.append(ee + "*")
            } else {
                ret.append(ee)
                ret.append(ee + "/*")
            }
        }
        return ret
    }
}
