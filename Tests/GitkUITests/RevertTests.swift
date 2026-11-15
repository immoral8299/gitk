// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct RevertTests {
    /// Makes `target` at HEAD~1 with a copy of `source`'s change under a new commit ID, so
    /// `source` is not in its history but reverts cleanly. The empty commit gives the copy
    /// a different parent, hence a different ID.
    private func checkoutTargetWithSameChange(_ repo: ActionTestRepo, source: ObjectID) async throws {
        _ = try await repo.runner.run(["checkout", "-b", "target", "HEAD~1"])
        _ = try await repo.runner.run(["commit", "--allow-empty", "-m", "elsewhere"])
        _ = try await repo.runner.run(["cherry-pick", source.hex])
        await repo.session.reload()
    }

    @Test func successfulRevertSelectsNewHead() async throws {
        let repo = try await ActionTestRepo.make()
        let old = try await repo.resolve()
        var selected: ObjectID?
        repo.actions.onSelect = { selected = $0 }
        #expect(await repo.actions.pick(old, revert: true))
        let head = try await repo.resolve()
        #expect(head != old)
        #expect(selected == head)
        #expect(repo.session.refs.mainHeadID == head)
        await repo.cleanup()
    }

    @Test func successAddsRowOnTopAndMovesLabel() async throws {
        let repo = try await ActionTestRepo.make()
        let old = try await repo.resolve()
        #expect(await repo.actions.pick(old, revert: true))
        let head = try await repo.resolve()
        #expect(repo.session.row(of: head) == 0)
        #expect(repo.session.row(of: old) == 1)
        let branch = try #require(repo.session.refs.mainHeadName)
        #expect(repo.session.refs.headIDs[branch] == head)
        #expect(!repo.actions.isBusy)
        await repo.cleanup()
    }

    @Test func notIncludedConfirmationDeclinedLeavesHead() async throws {
        let repo = try await ActionTestRepo.make(confirm: "no")
        let source = try await repo.resolve()
        try await checkoutTargetWithSameChange(repo, source: source)
        let before = try await repo.resolve()
        #expect(!(await repo.actions.pick(source, revert: true)))
        #expect(repo.messages.contains { $0.contains("is not included in branch") && $0.contains("really revert it") && $0.contains(source.abbreviated(8)) })
        #expect(try await repo.resolve() == before)
        #expect(!repo.actions.isBusy)
        await repo.cleanup()
    }

    @Test func notIncludedConfirmationAcceptedRevertsOntoHead() async throws {
        let repo = try await ActionTestRepo.make(confirm: "yes")
        let source = try await repo.resolve()
        try await checkoutTargetWithSameChange(repo, source: source)
        let before = try await repo.resolve()
        var selected: ObjectID?
        repo.actions.onSelect = { selected = $0 }
        #expect(await repo.actions.pick(source, revert: true))
        let head = try await repo.resolve()
        #expect(head != before)
        #expect(try await repo.resolve("HEAD^") == before)
        #expect(selected == head)
        #expect(repo.session.refs.mainHeadID == head)
        await repo.cleanup()
    }

    @Test func localChangesNameTheFile() async throws {
        let repo = try await ActionTestRepo.make()
        let source = try await repo.resolve()
        try await checkoutTargetWithSameChange(repo, source: source)
        let before = try await repo.resolve()
        let path = URL(fileURLWithPath: repo.session.repo.worktree).appendingPathComponent("file.txt")
        try Data("uncommitted local edit\n".utf8).write(to: path)
        #expect(!(await repo.actions.pick(source, revert: true)))
        #expect(repo.messages.contains { $0.contains("local changes") && $0.contains("file.txt") })
        #expect(try await repo.resolve() == before)
        #expect(!repo.actions.isBusy)
        await repo.cleanup()
    }

    @Test func conflictAcceptedRunsCitoolWithAuthorOfCommit() async throws {
        let repo = try await ActionTestRepo.make(confirm: "yes")
        let source = try await repo.resolve()
        try await checkoutTargetWithSameChange(repo, source: source)
        let path = URL(fileURLWithPath: repo.session.repo.worktree).appendingPathComponent("file.txt")
        try Data("conflicting content\n".utf8).write(to: path)
        _ = try await repo.runner.run(["add", "file.txt"])
        _ = try await repo.runner.run(["commit", "-m", "conflicting edit"])
        await repo.session.reload()
        var launched: [([String], ObjectID?)] = []
        repo.actions.toolLauncher = { launched.append(($0, $1)) }
        #expect(!(await repo.actions.pick(source, revert: true)))
        #expect(repo.messages.contains { $0.contains("Revert failed because of merge conflict") && $0.contains("git citool") })
        #expect(launched.count == 1)
        #expect(launched.first?.0 == ["citool"])
        #expect(launched.first?.1 == source)
        #expect(!repo.actions.isBusy)
        await repo.cleanup()
    }

    @Test func noOpRevertShowsNoChangesCommitted() async throws {
        let repo = try await ActionTestRepo.make()
        _ = try await repo.runner.run(["commit", "--allow-empty", "-m", "empty"])
        await repo.session.reload()
        let empty = try await repo.resolve()
        #expect(!(await repo.actions.pick(empty, revert: true)))
        #expect(repo.messages.contains { $0.contains("No changes committed") })
        #expect(try await repo.resolve() == empty)
        #expect(!repo.actions.isBusy)
        await repo.cleanup()
    }
}
