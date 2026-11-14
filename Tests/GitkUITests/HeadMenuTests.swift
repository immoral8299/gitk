// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct HeadMenuTests {
    @Test func currentBranchCannotBeRemoved() async throws {
        let repo = try await ActionTestRepo.make()
        let current = try #require(repo.session.refs.mainHeadName)
        let menu = RowMenus.headMenu(name: current, refs: repo.session.refs) { _ in }
        #expect(!menu.items[0].isEnabled)
        #expect(!menu.items[2].isEnabled)
        #expect(!(await repo.actions.removeBranch(current)))
        #expect(repo.messages.contains { $0.contains("Cannot delete the currently checked-out branch") })
        await repo.cleanup()
    }

    @Test func checkoutFailurePreservesHeadAndLabels() async throws {
        let repo = try await ActionTestRepo.make()
        let old = try await repo.resolve()
        _ = try await repo.runner.run(["branch", "previous", "HEAD~1"])
        let file = URL(fileURLWithPath: repo.session.repo.worktree).appendingPathComponent("file.txt")
        try Data("uncommitted local edit\n".utf8).write(to: file)
        #expect(!(await repo.actions.checkout("previous")))
        #expect(repo.session.refs.mainHeadID == old)
        #expect(repo.session.refs.mainHeadName == "main")
        #expect(!repo.messages.isEmpty)
        await repo.cleanup()
    }
}
