// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

/// The commands behind the Changed Files context menu (gitk's `flist_menu`),
/// built without any UI so tests can check them.
public enum FileMenu {
    /// Port of gitk proc `flist_hl` (gitk/gitk 3700–3708): the touching-paths
    /// pattern after "Highlight this only" (`only`) or "Highlight this too".
    /// "Too" appends to the current pattern only while the search type is
    /// "touching paths:" and the pattern is not empty.
    public static func highlightPattern(path: String, only: Bool, currentPattern: String, currentIsTouchingPaths: Bool) -> String {
        let quoted = ShellWords.quote(path)
        if only || currentPattern.isEmpty || !currentIsTouchingPaths { return quoted }
        return currentPattern + " " + quoted
    }

    /// Port of the path handling of gitk proc `external_blame` (gitk/gitk 4003–4031):
    /// `file join $cdup $path`, which `git gui blame` needs relative to the
    /// current directory.
    public static func blamePath(path: String, cdup: String) -> String {
        guard !cdup.isEmpty else { return path }
        return cdup.hasSuffix("/") ? cdup + path : cdup + "/" + path
    }

    /// Arguments for `git gui blame <base> <path>` ("Blame parent commit");
    /// nil when there is no base commit or it is one of the local-change
    /// pseudo commits (gitk shows "No such commit").
    public static func blameArguments(base: ObjectID?, path: String, cdup: String, hashLength: Int) -> [String]? {
        guard let base, base != ObjectID.localUnstaged(hashLength: hashLength),
              base != ObjectID.localStaged(hashLength: hashLength) else { return nil }
        return LineOrigin.guiArguments(revision: base.hex, path: blamePath(path: path, cdup: cdup), line: nil)
    }
}
