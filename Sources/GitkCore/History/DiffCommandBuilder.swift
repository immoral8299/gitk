// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// gitk's "Line diff / Markup words / Color words" choice (`worddiff`).
public enum WordDiffMode: Sendable, Equatable {
    case line, markup, color
}

/// The settings `getblobdiffs` reads from globals.
public struct DiffOptions: Sendable, Equatable {
    /// `diffcontext`.
    public var context: Int
    /// `ignorespace`.
    public var ignoreSpace: Bool
    /// `worddiff`; anything but `.line` adds `--word-diff=porcelain`.
    public var wordDiff: WordDiffMode
    /// `log_showroot`.
    public var logShowRoot: Bool
    /// `vfilelimit($curview)` when `limitdiffs` is on; nil or empty adds no filter.
    public var limitPaths: [String]?
    /// Hex digits of an object id (40 or 64), used to build the pseudo ids.
    public var hashLength: Int

    public init(
        context: Int = 3, ignoreSpace: Bool = false, wordDiff: WordDiffMode = .line,
        logShowRoot: Bool = false, limitPaths: [String]? = nil, hashLength: Int = 40
    ) {
        self.context = context
        self.ignoreSpace = ignoreSpace
        self.wordDiff = wordDiff
        self.logShowRoot = logShowRoot
        self.limitPaths = limitPaths
        self.hashLength = hashLength
    }
}

/// Builds git argument arrays (without the leading `git`) for gitk's diffs.
public enum DiffCommandBuilder {
    /// Port of gitk proc `diffcmd` (gitk/gitk 8059–8103). `flags` are the
    /// already split flag words; the pseudo ids for local changes are derived
    /// from `hashLength`.
    static func diffCommand(
        ids: [ObjectID], flags: [String], logShowRoot: Bool, hashLength: Int
    ) -> [String] {
        let nullID = ObjectID.localUnstaged(hashLength: hashLength)
        let nullID2 = ObjectID.localStaged(hashLength: hashLength)
        let i = nullID.flatMap { ids.firstIndex(of: $0) } ?? -1
        let j = nullID2.flatMap { ids.firstIndex(of: $0) } ?? -1
        var flags = flags
        var cmd: [String]
        if i >= 0 {
            if ids.count > 1 && j < 0 {
                // comparing working directory with some specific revision
                cmd = ["diff-index"] + flags
                if i == 0 {
                    cmd += ["-R", ids[1].hex]
                } else {
                    cmd.append(ids[0].hex)
                }
            } else {
                // comparing working directory with index
                cmd = ["diff-files"] + flags
                if j == 1 { cmd.append("-R") }
            }
        } else if j >= 0 {
            flags.append("--ignore-submodules=dirty")
            cmd = ["diff-index", "--cached"] + flags
            if ids.count > 1 {
                // comparing index with specific revision
                if j == 0 {
                    cmd += ["-R", ids[1].hex]
                } else {
                    cmd.append(ids[0].hex)
                }
            } else {
                // comparing index with HEAD
                cmd.append("HEAD")
            }
        } else {
            if logShowRoot { flags.append("--root") }
            cmd = ["diff-tree", "-r"] + flags + ids.map(\.hex)
        }
        return cmd
    }

    /// Port of the command construction in gitk proc `getblobdiffs`
    /// (gitk/gitk 8203–8231). A merge commit (gitk `mergediff`, 7975–7988)
    /// passes its single id through the same path, so `--cc` applies.
    public static func blobDiff(ids: [ObjectID], options: DiffOptions) -> [String] {
        var cmd = diffCommand(
            ids: ids,
            flags: ["-p", "--textconv", "--submodule", "-C", "--cc", "--no-commit-id",
                    "-U\(options.context)"],
            logShowRoot: options.logShowRoot, hashLength: options.hashLength)
        if options.ignoreSpace { cmd.append("-w") }
        if options.wordDiff != .line { cmd.append("--word-diff=porcelain") }
        return appendLimit(cmd, options.limitPaths)
    }

    /// Port of the command construction in gitk proc `gettreediffs`
    /// (gitk/gitk 8103–8118), the file list diff.
    public static func treeDiff(
        ids: [ObjectID], logShowRoot: Bool = false, limitPaths: [String]? = nil,
        hashLength: Int = 40
    ) -> [String] {
        let cmd = diffCommand(
            ids: ids, flags: ["--no-commit-id"], logShowRoot: logShowRoot,
            hashLength: hashLength)
        return appendLimit(cmd, limitPaths)
    }

    private static func appendLimit(_ cmd: [String], _ paths: [String]?) -> [String] {
        guard let paths, !paths.isEmpty else { return cmd }
        return cmd + ["--"] + paths
    }
}
