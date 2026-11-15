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
        await repo.session.refreshLocalChanges()
        let local = try #require(ObjectID.localUnstaged(hashLength: repo.session.repo.hashLength))
        func localRowShown() -> Bool {
            repo.session.store.index(of: local).map { repo.session.ordering.commitInView($0) } ?? false
        }
        #expect(localRowShown())
        #expect(await repo.actions.reset(to: target, type: .hard))
        #expect(!localRowShown())
        #expect(repo.session.refs.mainHeadID == target)
        let status = try await repo.runner.run(["status", "--porcelain"])
        #expect(status.stdout.isEmpty)
        await repo.cleanup()
    }

    @Test func softResetKeepsIndexAndMixedClearsIt() async throws {
        let repo = try await ActionTestRepo.make()
        let target = try await repo.resolve("HEAD~1")
        #expect(await repo.actions.reset(to: target, type: .soft))
        #expect(repo.session.refs.mainHeadID == target)
        var status = try await repo.runner.run(["status", "--porcelain"])
        #expect(!status.stdout.isEmpty)
        #expect(String(decoding: status.stdout, as: UTF8.self).first != " ")
        #expect(await repo.actions.reset(to: target, type: .mixed))
        status = try await repo.runner.run(["status", "--porcelain"])
        #expect(String(decoding: status.stdout, as: UTF8.self).first == " ")
        await repo.cleanup()
    }
}
