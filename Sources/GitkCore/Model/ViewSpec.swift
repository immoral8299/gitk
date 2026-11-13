// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// A view as the user defined it (gitk's `viewname`, `viewargs`, `viewfiles`,
/// `viewargscmd` and `viewperm` arrays, for one view).
public struct ViewSpec: Sendable, Equatable {
    public var name: String
    public var args: [String]
    public var files: [String]
    /// The `--argscmd` shell command, run with `sh -c` on every load.
    public var argsCmd: String?
    public var perm: Bool

    public init(
        name: String, args: [String] = [], files: [String] = [],
        argsCmd: String? = nil, perm: Bool = false
    ) {
        self.name = name
        self.args = args
        self.files = files
        self.argsCmd = argsCmd
        self.perm = perm
    }
}

/// A failure gitk reports with `error_popup`. `prefix` is gitk's msgid
/// (untranslated; the UI passes it through `L()`), `detail` the text gitk
/// appends after a space, empty when the msgid is the whole message.
public struct ViewArgsError: Error, Sendable, Equatable, CustomStringConvertible {
    public var prefix: String
    public var detail: String

    public init(prefix: String, detail: String) {
        self.prefix = prefix
        self.detail = detail
    }

    public var message: String { detail.isEmpty ? prefix : "\(prefix) \(detail)" }
    public var description: String { message }
}

/// The per-view results of gitk's `parseviewargs` (the globals `vdatemode`,
/// `vmergeonly`, `vinlinediff`, `vdflags`, `vflags`, `vrevs`, `vfiltered`,
/// `vorigargs`, plus its return value as `canOpt`, stored by gitk as `vcanopt`).
public struct ResolvedViewArgs: Sendable, Equatable {
    public var dateMode = false
    public var mergeOnly = false
    public var inlineDiff = false
    public var diffFlags: [String] = []
    public var flags: [String] = []
    public var revs: [String] = []
    public var filtered = false
    public var origArgs: [String] = []
    /// Every option was recognized, so `git log` can be given `flags` and `revs`.
    public var canOpt = true
    /// gitk sets the `worddiff` global to this msgid ("Color words" or
    /// "Markup words") when a word-diff option is seen.
    public var wordDiff: String?
    /// gitk sets `env(GIT_NO_REPLACE_OBJECTS)=1` when `--no-replace-objects` is seen.
    public var noReplaceObjects = false
}

/// What `parseviewrevs` computes: the revision list for `git log --stdin`
/// and the view's `vposids` and `vnegids`.
public struct ParsedViewRevs: Sendable, Equatable {
    public var revs: [String] = []
    public var posIDs: [String] = []
    public var negIDs: [String] = []
}

/// The part of `start_rev_list` (603–641) that works out what to hand to `git log`.
public struct ResolvedView: Sendable, Equatable {
    public var parsed: ResolvedViewArgs
    /// `vfilelimit`.
    public var fileLimit: [String]
    /// `$revs` (empty when `parsed.canOpt` is false).
    public var revs: [String]
    /// `$args` for `git log`: `vflags`, or `vorigargs` when `canOpt` is false.
    public var logArgs: [String]
    public var posIDs: [String]
    public var negIDs: [String]
}

extension ViewSpec {
    /// Port of gitk proc `parseviewargs` (gitk/gitk 389–518). `arglist` is the
    /// view's args followed by any argscmd lines.
    public static func parseViewArgs(_ arglist: [String]) -> ResolvedViewArgs {
        var r = ResolvedViewArgs()
        var nextIsVal = false
        r.origArgs = arglist
        var i = -1
        for arg in arglist {
            i += 1
            if nextIsVal {
                r.flags.append(arg)
                nextIsVal = false
                continue
            }
            let chars = Array(arg)
            func pre(_ p: String) -> Bool { arg.hasPrefix(p) }

            if arg == "-d" || arg == "--date-order" {
                r.dateMode = true
                // remove from origargs in case we hit an unknown option
                if r.origArgs.indices.contains(i) { r.origArgs.remove(at: i) }
                i -= 1
            } else if (chars.count == 2 && chars[0] == "-" && "puabwcrRBMC".contains(chars[1]))
                        || ["--no-renames", "--full-index", "--binary", "--find-copies-harder",
                            "--ext-diff", "--no-ext-diff", "--no-prefix", "--text", "--full-diff",
                            "--ignore-space-at-eol", "--ignore-space-change"].contains(arg)
                        || pre("--abbrev=") || pre("-l") || pre("--src-prefix=") || pre("--dst-prefix=")
                        || pre("-O") || pre("-U") || pre("--unified=") {
                // These request or affect diff output, which we don't want.
                r.diffFlags.append(arg)
            } else if ["--raw", "--patch-with-raw", "--patch-with-stat", "--name-only",
                       "--name-status", "--color", "--log-size", "--decorate", "--abbrev-commit",
                       "--cc", "-z", "--header", "--parents", "--boundary", "--no-color", "-g",
                       "--walk-reflogs", "--no-walk", "--timestamp", "relative-date", "--stdin",
                       "--objects", "--objects-edge", "--reverse"].contains(arg)
                        || pre("--pretty=") || pre("--date=") {
                // These cause our parsing of git log's output to fail, or else
                // they're options we want to set ourselves, so ignore them.
            } else if pre("--color-words") || arg == "--word-diff=color" {
                r.wordDiff = "Color words"
            } else if pre("--word-diff") {
                r.wordDiff = "Markup words"
            } else if pre("--stat=") || ["--numstat", "--shortstat", "--summary", "--check",
                                         "--exit-code", "--quiet", "--topo-order", "--full-history",
                                         "--dense", "--sparse", "--follow", "--left-right"].contains(arg)
                        || pre("--encoding=") {
                // These are harmless, and some are even useful
                r.flags.append(arg)
            } else if pre("--diff-filter=") || ["--no-merges", "--unpacked"].contains(arg)
                        || pre("--max-count=") || pre("--skip=") || pre("--since=") || pre("--after=")
                        || pre("--until=") || pre("--before=") || pre("--max-age=") || pre("--min-age=")
                        || pre("--author=") || pre("--committer=") || pre("--grep=")
                        || arg == "-i" || arg == "-E"
                        || ["--remove-empty", "--first-parent", "--cherry-pick"].contains(arg)
                        || pre("-S") || pre("-G")
                        || ["--pickaxe-all", "--pickaxe-regex", "--simplify-by-decoration"].contains(arg) {
                // These mean that we get a subset of the commits
                r.filtered = true
                r.flags.append(arg)
            } else if pre("-L") {
                // Line-log with 'stuck' argument (unstuck form is not supported)
                r.filtered = true
                r.inlineDiff = true
                r.canOpt = false
                r.flags.append(arg)
            } else if arg == "-n" {
                // This appears to be the only one that has a value as a
                // separate word following it
                r.filtered = true
                nextIsVal = true
                r.flags.append(arg)
            } else if arg == "--not" || arg == "--all" {
                r.revs.append(arg)
            } else if arg == "--merge" {
                r.mergeOnly = true
                // git rev-parse doesn't understand --merge
                r.revs.append("--gitk-symmetric-diff-marker")
                r.revs.append("MERGE_HEAD...HEAD")
            } else if arg == "--no-replace-objects" {
                r.noReplaceObjects = true
            } else if pre("-") {
                // Other flag arguments including -<n>
                let rest = arg.unicodeScalars.dropFirst()
                if !rest.isEmpty, rest.allSatisfy({ $0.properties.generalCategory == .decimalNumber }) {
                    r.filtered = true
                } else {
                    // a flag argument that we don't recognize;
                    // that means we can't optimize
                    r.canOpt = false
                }
                r.flags.append(arg)
            } else {
                // Non-flag arguments specify commits or ranges of commits
                if arg.contains("...") {
                    r.revs.append("--gitk-symmetric-diff-marker")
                }
                r.revs.append(arg)
            }
        }
        return r
    }

    /// Port of gitk proc `parseviewrevs` (gitk/gitk 520–584). Throws
    /// `ViewArgsError` ("Error parsing revisions:") where gitk shows that
    /// popup and returns an empty list.
    public static func parseViewRevs(
        _ revsIn: [String], hashLength: Int, runner: GitRunner
    ) async throws -> ParsedViewRevs {
        var revs = revsIn
        if revs.isEmpty {
            revs = ["HEAD"]
        } else if revs.contains("--all") {
            revs.append("HEAD")
        }
        let out: GitOutput
        do {
            out = try await runner.runRaw(["rev-parse"] + revs)
        } catch let e as GitError {
            throw ViewArgsError(prefix: "Error parsing revisions:", detail: e.stderr)
        }
        let text = tclExecMessage(out)
        if out.status != 0 || !out.stderr.isEmpty {
            // we get stdout followed by stderr in $err
            // for an unknown rev, git rev-parse echoes it and then errors out
            var err = text
            let errLines = text.components(separatedBy: "\n")
            var badRev: [String] = []
            for (l, line) in errLines.enumerated() {
                let isHash = line.count == hashLength && line.allSatisfy { $0.isHexDigit }
                if !isHash {
                    if line.hasPrefix("fatal:") {
                        if line.hasPrefix("fatal: ambiguous argument") && !badRev.isEmpty {
                            if badRev.count == 1 {
                                err = "unknown revision \(badRev[0])"
                            } else {
                                err = "unknown revisions: \(badRev.joined(separator: ", "))"
                            }
                        } else {
                            err = errLines[l...].joined(separator: "\n")
                        }
                        break
                    }
                    badRev.append(line)
                }
            }
            throw ViewArgsError(prefix: "Error parsing revisions:", detail: err)
        }
        var result = ParsedViewRevs()
        var sdm = 0
        for id in text.components(separatedBy: "\n") {
            if id == "--gitk-symmetric-diff-marker" {
                sdm = 4
            } else if id.hasPrefix("^") {
                if sdm != 1 {
                    result.revs.append(id)
                    if sdm == 3 { sdm = 0 }
                }
                result.negIDs.append(String(id.dropFirst()))
            } else {
                if sdm != 2 {
                    result.revs.append(id)
                } else if !result.revs.isEmpty {
                    result.revs[result.revs.count - 1] = "\(id)...\(result.revs[result.revs.count - 1])"
                }
                result.posIDs.append(id)
            }
            sdm -= 1
        }
        return result
    }

    /// Port of gitk proc `unmerged_files` (gitk/gitk 363–387). Returns the
    /// unmerged file names within `files` (all of them when `files` is empty)
    /// and `nr_unmerged`, the number of distinct unmerged files before the
    /// file limit is applied.
    public static func unmergedFiles(
        _ files: [String], runner: GitRunner
    ) async throws -> (files: [String], nrUnmerged: Int) {
        var mlist: [String] = []
        var nrUnmerged = 0
        let out: GitOutput
        do {
            out = try await runner.run(["ls-files", "-u"])
        } catch let e as GitError {
            throw ViewArgsError(prefix: "Couldn't get list of unmerged files:", detail: e.stderr)
        }
        var worktree: String?
        for line in String(decoding: out.stdout, as: UTF8.self).components(separatedBy: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let fname = String(line[line.index(after: tab)...])
            if mlist.contains(fname) { continue }
            nrUnmerged += 1
            if files.isEmpty {
                mlist.append(fname)
            } else {
                if worktree == nil { worktree = await gitWorktree(runner) }
                if pathFilter(files, fname, worktree: worktree ?? "") { mlist.append(fname) }
            }
        }
        return (mlist, nrUnmerged)
    }

    /// Port of gitk proc `path_filter` (gitk/gitk 8040–8050): true if the
    /// normalized `name` (under the work tree) starts with any normalized
    /// filter path. gitk uses `string match "$fq_p*"`, so glob characters in a
    /// filter path would act as wildcards; here they are literal.
    static func pathFilter(_ filter: [String], _ name: String, worktree: String) -> Bool {
        let fqN = normalize(worktree + "/" + name, base: worktree)
        for p in filter where fqN.hasPrefix(normalize(p, base: worktree)) {
            return true
        }
        return false
    }

    /// Tcl `file normalize` without symlink resolution; relative paths are
    /// taken from `base` (gitk runs in the work tree top).
    private static func normalize(_ p: String, base: String) -> String {
        let abs = p.hasPrefix("/") ? p : base + "/" + p
        var parts: [Substring] = []
        for c in abs.split(separator: "/", omittingEmptySubsequences: true) {
            if c == "." { continue }
            if c == ".." { _ = parts.popLast(); continue }
            parts.append(c)
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Port of gitk proc `gitworktree` (gitk/gitk 259–276), `--show-toplevel`
    /// branch, falling back to the runner's cwd.
    private static func gitWorktree(_ runner: GitRunner) async -> String {
        if let out = try? await runner.run(["rev-parse", "--show-toplevel"]) {
            let s = String(decoding: out.stdout, as: UTF8.self)
            return s.hasSuffix("\n") ? String(s.dropLast()) : s
        }
        return runner.cwd?.path ?? FileManager.default.currentDirectoryPath
    }

    /// The `--argscmd` step of gitk proc `start_rev_list` (gitk/gitk 604–612):
    /// run the command with `sh -c` and split its output at newlines, as Tcl's
    /// `exec` (one trailing newline dropped) and `split` do.
    public static func runArgsCmd(_ command: String, runner: GitRunner) async throws -> [String] {
        let out: GitOutput
        do {
            out = try await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", command],
                environment: runner.environment, cwd: runner.cwd)
        } catch let e as ChildProcess.SpawnError {
            throw ViewArgsError(prefix: "Error executing --argscmd command:", detail: e.message)
        }
        let text = tclExecMessage(out)
        if out.status != 0 || !out.stderr.isEmpty {
            throw ViewArgsError(prefix: "Error executing --argscmd command:", detail: text)
        }
        return text.components(separatedBy: "\n")
    }

    /// Port of the front half of gitk proc `start_rev_list` (gitk/gitk 603–641).
    /// Throws `ViewArgsError` at each place gitk shows `error_popup` and returns 0.
    public func resolve(hashLength: Int, runner: GitRunner) async throws -> ResolvedView {
        var args = self.args
        if let cmd = argsCmd, !cmd.isEmpty {
            args += try await Self.runArgsCmd(cmd, runner: runner)
        }
        let parsed = Self.parseViewArgs(args)

        var files = self.files
        if parsed.mergeOnly {
            let u = try await Self.unmergedFiles(files, runner: runner)
            files = u.files
            if files.isEmpty {
                if u.nrUnmerged == 0 {
                    throw ViewArgsError(
                        prefix: "No files selected: --merge specified but no files are unmerged.",
                        detail: "")
                } else {
                    throw ViewArgsError(
                        prefix: "No files selected: --merge specified but no unmerged files are within file limit.",
                        detail: "")
                }
            }
        }

        var revs: [String] = []
        var pos: [String] = []
        var neg: [String] = []
        let logArgs: [String]
        if parsed.canOpt {
            let p = try await Self.parseViewRevs(parsed.revs, hashLength: hashLength, runner: runner)
            if p.revs.isEmpty {
                throw ViewArgsError(prefix: "Error parsing revisions:", detail: "")
            }
            revs = p.revs
            pos = p.posIDs
            neg = p.negIDs
            logArgs = parsed.flags
        } else {
            logArgs = parsed.origArgs
        }
        return ResolvedView(
            parsed: parsed, fileLimit: files, revs: revs, logArgs: logArgs, posIDs: pos, negIDs: neg)
    }

    /// Tcl `exec` error/return text: stdout followed by stderr, with one
    /// trailing newline removed.
    private static func tclExecMessage(_ out: GitOutput) -> String {
        var s = String(decoding: out.stdout, as: UTF8.self) + out.stderrText
        if s.hasSuffix("\n") { s.removeLast() }
        return s
    }
}

extension GitRunner {
    /// Like `run` but a non-zero exit is returned, not thrown (only a failure
    /// to start git throws `GitError`).
    func runRaw(_ args: [String]) async throws -> GitOutput {
        do {
            return try await ProcessRunner().run(
                executable: gitURL, arguments: args, environment: environment, cwd: cwd)
        } catch let e as ChildProcess.SpawnError {
            throw GitError(args: args, status: -1, stderr: e.message)
        }
    }
}
