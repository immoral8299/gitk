// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct ResetTests {
    @Test func mixedDefaultAndHardResetRefreshesChanges() async throws {
        let repo = try await ActionTestRepo.make()
        let target = try await repo.resolve("HEAD~1")
        _ = NSApplication.shared
        let dialog = ResetDialog(id: target, coordinator: repo.actions)
        #expect(dialog.resetType == .mixed)
        dialog.close()
        let file = URL(fileURLWithPath: repo.session.repo.worktree).appendingPathComponent("file.txt")
        try Data("local edit\n".utf8).write(to: file)
        #expect(await repo.actions.reset(to: target, type: .hard))
        #expect(repo.session.refs.mainHeadID == target)
        let status = try await repo.runner.run(["status", "--porcelain"])
        #expect(status.stdout.isEmpty)
        await repo.cleanup()
    }
}
