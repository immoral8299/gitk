// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public struct LocalChanges: Sendable, Equatable {
    public var staged: Bool
    public var unstaged: Bool

    public init(staged: Bool = false, unstaged: Bool = false) {
        self.staged = staged
        self.unstaged = unstaged
    }

    /// Port of gitk procs `dodiffindex`, `readdiffindex`, `readdifffiles`
    /// (gitk/gitk 5508–5604). Dirty submodules are ignored in both checks.
    public static func read(repo: RepoContext, files: [String], runner: GitRunner) async throws -> LocalChanges {
        guard repo.hasWorktree else { return LocalChanges() }
        let limit = files.isEmpty ? [] : ["--"] + files
        let index = try await runner.run(["diff-index", "--cached", "--ignore-submodules=dirty", "HEAD"] + limit)
        let worktree = try await runner.run(["diff-files", "--ignore-submodules=dirty"] + limit)
        return LocalChanges(staged: !index.stdout.isEmpty, unstaged: !worktree.stdout.isEmpty)
    }

    public func commits(head: ObjectID, tree: ObjectID, hashLength: Int) -> [ParsedCommit] {
        guard let indexID = ObjectID.localStaged(hashLength: hashLength),
              let worktreeID = ObjectID.localUnstaged(hashLength: hashLength) else { return [] }
        func make(_ id: ObjectID, parent: ObjectID, title: String) -> ParsedCommit {
            ParsedCommit(id: id, parents: [parent], isBoundary: false, isUninteresting: false,
                         side: nil, tree: tree, authorName: Data(), authorEmail: Data(),
                         authorEpoch: 0, authorTZ: "+0000", committerName: Data(),
                         committerEmail: Data(), committerEpoch: 0, committerTZ: "+0000",
                         encoding: nil, headline: Data(title.utf8), message: Data(title.utf8), notes: nil)
        }
        var result: [ParsedCommit] = []
        if staged {
            result.append(make(indexID, parent: head,
                               title: "Local changes checked in to index but not committed"))
        }
        if unstaged {
            result.append(make(worktreeID, parent: staged ? indexID : head,
                               title: "Local uncommitted changes, not checked in to index"))
        }
        return result
    }
}
