// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Why a repository action failed, in the cases the UI branches on.
public enum RepoActionError: Error, Sendable, Equatable {
    /// Cherry-pick or revert refused because local changes would be overwritten.
    case localChanges(files: [String], output: String)
    /// Cherry-pick or revert stopped on a merge conflict.
    case conflict(output: String)
    /// Checking out `remotes/<r>/<name>` as a new branch, but `<name>` exists.
    case localBranchExists(String)
    /// Any other git failure; carries git's stderr.
    case git(GitError)
}

extension RepoActionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .localChanges(_, let output), .conflict(let output): return output
        case .localBranchExists(let name): return "A local branch named \(name) exists already"
        case .git(let e): return e.errorDescription
        }
    }
}

/// Result of a successful cherry-pick or revert.
public enum PickOutcome: Sendable, Equatable {
    /// A new commit was made on top of `oldHead`.
    case committed(oldHead: String, newHead: String)
    /// git succeeded but HEAD did not move ("No changes committed").
    case noChanges
}

public enum ResetType: String, Sendable, CaseIterable {
    case soft, mixed, hard
}

/// The git commands behind gitk's repository-changing menu actions. No UI,
/// no view updates: each function runs the command gitk runs and returns a
/// typed result or throws `RepoActionError`.
public struct RepoActions: Sendable {
    public var runner: GitRunner

    public init(runner: GitRunner) { self.runner = runner }

    public init(repo: URL) { self.runner = GitRunner(cwd: repo) }

    // MARK: Branches

    /// Port of the command in gitk proc `mkbrgo` (gitk/gitk 9772–9816):
    /// `git branch [-f] <name> <id>`; `force` is used when overwriting.
    public func createBranch(name: String, at id: String, force: Bool = false) async throws {
        _ = try await run(["branch"] + (force ? ["-f"] : []) + [name, id])
    }

    /// Port of the command in gitk proc `mvbrgo` (gitk/gitk 9818–9856): `git branch -m <old> <new>`.
    public func renameBranch(from old: String, to new: String) async throws {
        _ = try await run(["branch", "-m", old, new])
    }

    /// Port of the command in gitk proc `rmbranch` (gitk/gitk 10176–10206): `git branch -D <name>`.
    public func deleteBranch(_ name: String) async throws {
        _ = try await run(["branch", "-D", name])
    }

    // MARK: Tags

    /// Port of the command in gitk proc `domktag` (gitk/gitk 9554–9586).
    /// An empty `message` makes a lightweight tag (`git tag <tag> <id>`),
    /// otherwise `git tag -a -m <message> <tag> <id>`.
    public func createTag(name: String, at id: String, message: String = "") async throws {
        if message.isEmpty {
            _ = try await run(["tag", name, id])
        } else {
            _ = try await run(["tag", "-a", "-m", message, name, id])
        }
    }

    // MARK: Checkout and reset

    /// Port of gitk proc `cobranch` (gitk/gitk 10105–10139). `head` is the
    /// label text; `remotes/<remote>/<name>` becomes
    /// `git checkout -b <name> --track remotes/<remote>/<name>`, and fails with
    /// `.localBranchExists` when `localHeads` already has `<name>`. stderr is
    /// merged into the failure text as gitk's `2>@1` does. Returns the
    /// local branch name that is now checked out.
    @discardableResult
    public func checkout(head: String, localHeads: Set<String> = []) async throws -> String {
        var args = ["checkout"]
        var newHead = head
        if head.hasPrefix("remotes/") {
            if let slash = head.lastIndex(of: "/") {
                newHead = String(head[head.index(after: slash)...])
            }
            if localHeads.contains(newHead) { throw RepoActionError.localBranchExists(newHead) }
            args += ["-b", newHead, "--track", head]
        } else {
            args.append(head)
        }
        let out = try await runMerged(args)
        if out.status != 0 {
            throw RepoActionError.git(GitError(args: args, status: out.status, stderr: out.text))
        }
        return newHead
    }

    /// Port of the command in gitk proc `resethead` (gitk/gitk 10008–10048):
    /// `git reset --<type> <id>` with stderr merged. Progress is not parsed.
    /// Returns git's combined output.
    @discardableResult
    public func reset(to id: String, type: ResetType) async throws -> String {
        let args = ["reset", "--\(type.rawValue)", id]
        let out = try await runMerged(args)
        if out.status != 0 {
            throw RepoActionError.git(GitError(args: args, status: out.status, stderr: out.text))
        }
        return out.text
    }

    // MARK: Cherry-pick and revert

    /// Port of the command and error handling in gitk proc `cherrypick`
    /// (gitk/gitk 9884–9945): `git cherry-pick -r <id>` with stderr merged.
    /// Throws `.localChanges` or `.conflict` per gitk's regexps, else `.git`.
    public func cherryPick(_ id: String) async throws -> PickOutcome {
        try await pick(["cherry-pick", "-r", id], isRevert: false)
    }

    /// Port of the command and error handling in gitk proc `revert`
    /// (gitk/gitk 9947–10006): `git revert --no-edit <id>`.
    public func revert(_ id: String) async throws -> PickOutcome {
        try await pick(["revert", "--no-edit", id], isRevert: true)
    }

    private func pick(_ args: [String], isRevert: Bool) async throws -> PickOutcome {
        let oldHead = try await revParseHead()
        let out = try await runMerged(args)
        if out.status != 0 {
            let err = out.text
            if let files = Self.localChangeFiles(in: err, isRevert: isRevert) {
                throw RepoActionError.localChanges(files: files, output: err)
            }
            if Self.isConflict(err, isRevert: isRevert) {
                throw RepoActionError.conflict(output: err)
            }
            throw RepoActionError.git(GitError(args: args, status: out.status, stderr: err))
        }
        let newHead = try await revParseHead()
        return newHead == oldHead ? .noChanges : .committed(oldHead: oldHead, newHead: newHead)
    }

    /// Files named by a local-changes failure, or nil if `err` is not one.
    ///
    /// gitk's cherry-pick regexp is `Entry '(.*)' (would be overwritten by merge|not uptodate)`
    /// (one file); its revert regexp is `files would be overwritten by merge:(\n(( |\t)+[^\n]+\n)+)`
    /// (a list). Current git prints the list form for both, so both commands try both.
    static func localChangeFiles(in err: String, isRevert: Bool) -> [String]? {
        let entry = #"Entry '(.*)' (would be overwritten by merge|not uptodate)"#
        let list = #"files would be overwritten by merge:(\n(( |\t)+[^\n]+\n)+)"#
        if !isRevert, let m = match(entry, in: err, lines: true), m.count > 1 {
            return [m[1]]
        }
        if let m = match(list, in: err + "\n", lines: false), m.count > 1 {
            return m[1].split(separator: "\n").map {
                String($0.drop(while: { $0 == " " || $0 == "\t" }))
            }
        }
        if isRevert, let m = match(entry, in: err, lines: true), m.count > 1 {
            return [m[1]]
        }
        return nil
    }

    static func isConflict(_ err: String, isRevert: Bool) -> Bool {
        let pattern = isRevert
            ? #"error: could not revert"#
            : #"^(CONFLICT \(.*\):|Automatic cherry-pick failed|error: could not apply)"#
        return match(pattern, in: err, lines: true) != nil
    }

    private static func match(_ pattern: String, in text: String, lines: Bool) -> [String]? {
        guard let re = try? NSRegularExpression(
            pattern: pattern, options: lines ? [.anchorsMatchLines] : [])
        else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        return (0..<m.numberOfRanges).map {
            let r = m.range(at: $0)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    // MARK: Patches

    /// Port of gitk proc `getpatchid` (gitk/gitk 9250–9263): the diff of `id`
    /// (`git diff-tree -r -p --root <id>`) piped to `git patch-id`; returns the
    /// first word of its output ("" when git prints nothing, as `lindex` does).
    public func patchID(of id: String) async throws -> String {
        let diff = try await run(["diff-tree", "-r", "-p", "--root", id])
        let out = try await run(["patch-id"], stdin: diff.stdout)
        let text = String(decoding: out.stdout, as: UTF8.self)
        return text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first.map(String.init) ?? ""
    }

    /// Port of gitk proc `mkpatchgo` (gitk/gitk 9493–9505): the output of
    /// `git diff-tree -r -p <from> <to>`; `reverse` swaps the two IDs, which is
    /// what the dialog's Reverse button does.
    public func makePatch(from: String, to: String, reverse: Bool = false) async throws -> Data {
        let ids = reverse ? [to, from] : [from, to]
        return try await run(["diff-tree", "-r", "-p"] + ids).stdout
    }

    // MARK: Helpers

    private func run(_ args: [String], stdin: Data? = nil) async throws -> GitOutput {
        do {
            return try await runner.run(args, stdin: stdin)
        } catch let e as GitError {
            throw RepoActionError.git(e)
        }
    }

    private func revParseHead() async throws -> String {
        let out = try await run(["rev-parse", "HEAD"])
        return String(decoding: out.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs git with stderr merged into the text (stdout first, then stderr),
    /// standing in for gitk's `2>&1`. Does not throw on a non-zero exit.
    private func runMerged(_ args: [String]) async throws -> (status: Int32, text: String) {
        do {
            let out = try await ProcessRunner().run(
                executable: runner.gitURL, arguments: args, environment: runner.environment,
                cwd: runner.cwd)
            return (out.status, String(decoding: out.stdout + out.stderr, as: UTF8.self))
        } catch let e as ChildProcess.SpawnError {
            throw RepoActionError.git(GitError(args: args, status: -1, stderr: e.message))
        }
    }
}
