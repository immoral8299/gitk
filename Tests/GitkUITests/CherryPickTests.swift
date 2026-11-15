// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct CherryPickTests {
    @Test func successRefreshesRefsAndSelectsNewCommit() async throws {
        let repo = try await ActionTestRepo.make()
        let source = try await repo.resolve()
        _ = try await repo.runner.run(["checkout", "-b", "target", "HEAD~1"])
        await repo.session.reload()
        var selected: ObjectID?
        repo.actions.onSelect = { selected = $0 }
        #expect(await repo.actions.pick(source))
        let result = try await repo.resolve()
        #expect(selected == result)
        #expect(repo.session.refs.mainHeadID == result)
        #expect(repo.session.row(of: result) != nil)
        #expect(!repo.actions.isBusy)
        await repo.cleanup()
    }

    @Test func noOpAndConflictMessages() async throws {
        let repo = try await ActionTestRepo.make(confirm: "no")
        let source = try await repo.resolve()
        // Refusing the already-included confirmation leaves HEAD untouched.
        #expect(!(await repo.actions.pick(source)))
        #expect(try await repo.resolve() == source)
        _ = try await repo.runner.run(["checkout", "-b", "target", "HEAD~1"])
        let path = URL(fileURLWithPath: repo.session.repo.worktree).appendingPathComponent("file.txt")
        try Data("conflicting content\n".utf8).write(to: path)
        _ = try await repo.runner.run(["add", "file.txt"])
        _ = try await repo.runner.run(["commit", "-m", "conflicting edit"])
        await repo.session.reload()
        #expect(!(await repo.actions.pick(source)))
        #expect(repo.messages.contains { $0.contains("merge conflict") })
        #expect(!repo.actions.isBusy)
        await repo.cleanup()
    }

    @Test func emptyPickShowsNoChanges() async throws {
        let repo = try await ActionTestRepo.make()
        let source = try await repo.resolve()
        #expect(!(await repo.actions.pick(source)))
        #expect(repo.messages.contains { $0.contains("No changes committed") })
        await repo.cleanup()
    }

    @Test func localChangesNameTheFile() async throws {
        let repo = try await ActionTestRepo.make()
        let source = try await repo.resolve()
        _ = try await repo.runner.run(["checkout", "-b", "target", "HEAD~1"])
        await repo.session.reload()
        let path = URL(fileURLWithPath: repo.session.repo.worktree).appendingPathComponent("file.txt")
        try Data("uncommitted local edit\n".utf8).write(to: path)
        #expect(!(await repo.actions.pick(source)))
        #expect(repo.messages.contains { $0.contains("local changes") && $0.contains("file.txt") })
        #expect(!repo.actions.isBusy)
        await repo.cleanup()
    }

    @Test func conflictAcceptedRunsCitoolWithAuthorOfCommit() async throws {
        let repo = try await ActionTestRepo.make(confirm: "yes")
        let source = try await repo.resolve()
        _ = try await repo.runner.run(["checkout", "-b", "target", "HEAD~1"])
        let path = URL(fileURLWithPath: repo.session.repo.worktree).appendingPathComponent("file.txt")
        try Data("conflicting content\n".utf8).write(to: path)
        _ = try await repo.runner.run(["add", "file.txt"])
        _ = try await repo.runner.run(["commit", "-m", "conflicting edit"])
        await repo.session.reload()
        var launched: [([String], ObjectID?)] = []
        repo.actions.toolLauncher = { launched.append(($0, $1)) }
        #expect(!(await repo.actions.pick(source)))
        #expect(repo.messages.contains { $0.contains("git citool") })
        #expect(launched.count == 1)
        #expect(launched.first?.0 == ["citool"])
        #expect(launched.first?.1 == source)
        await repo.cleanup()
    }

    @Test func reapplyConfirmationNamesCommitAndBranch() async throws {
        let repo = try await ActionTestRepo.make(confirm: "no")
        let source = try await repo.resolve()
        #expect(!(await repo.actions.pick(source)))
        #expect(repo.messages.contains { $0.contains("already included") && $0.contains(source.abbreviated(8)) })
        await repo.cleanup()
    }
}
