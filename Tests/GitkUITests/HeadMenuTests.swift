// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

extension ActionTestRepo {
    func makeUnmergedBranch(_ name: String) async throws {
        let out = try await runner.run(["commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "unmerged"])
        let id = String(decoding: out.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await runner.run(["branch", name, id])
    }
}

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

    @Test func otherBranchMenuEnablesAllItems() async throws {
        let repo = try await ActionTestRepo.make()
        _ = try await repo.runner.run(["branch", "side", "HEAD~1"])
        await repo.session.readReferences()
        let menu = RowMenus.headMenu(name: "side", refs: repo.session.refs) { _ in }
        #expect(menu.items.map(\.title) == [L("Check out this branch"), L("Rename this branch"),
                                           L("Remove this branch"), L("Copy branch name")])
        #expect(menu.items.map(\.isEnabled) == [true, true, true, true])
        await repo.cleanup()
    }

    @Test func remoteLabelOnlyChecksOutWhenNoLocalHead() async throws {
        let repo = try await ActionTestRepo.make()
        let remote = RowMenus.headMenu(name: "remotes/origin/fresh", refs: repo.session.refs) { _ in }
        #expect(remote.items.map(\.isEnabled) == [true, false, false, true])
        let current = try #require(repo.session.refs.mainHeadName)
        let clash = RowMenus.headMenu(name: "remotes/origin/\(current)", refs: repo.session.refs) { _ in }
        #expect(clash.items.map(\.isEnabled) == [false, false, false, true])
        await repo.cleanup()
    }

    @Test func menuItemsPerformTheirCommands() async throws {
        let repo = try await ActionTestRepo.make()
        _ = try await repo.runner.run(["branch", "side", "HEAD~1"])
        await repo.session.readReferences()
        var seen: [AppCommand] = []
        let menu = RowMenus.headMenu(name: "side", refs: repo.session.refs) { seen.append($0) }
        for item in menu.items { _ = item.target?.perform(item.action, with: item) }
        #expect(seen == [.checkoutBranch, .renameBranch, .removeBranch, .copyBranchName])
        await repo.cleanup()
    }

    @Test func checkoutSwitchesHead() async throws {
        let repo = try await ActionTestRepo.make()
        _ = try await repo.runner.run(["branch", "side", "HEAD~1"])
        await repo.session.readReferences()
        #expect(await repo.actions.checkout("side"))
        #expect(repo.session.refs.mainHeadName == "side")
        await repo.cleanup()
    }

    @Test func removeUnmergedBranchConfirms() async throws {
        let declined = try await ActionTestRepo.make(confirm: "no")
        try await declined.makeUnmergedBranch("side")
        await declined.session.readReferences()
        #expect(!(await declined.actions.removeBranch("side")))
        #expect(declined.session.refs.headIDs["side"] != nil)
        await declined.cleanup()

        let accepted = try await ActionTestRepo.make(confirm: "yes")
        try await accepted.makeUnmergedBranch("side")
        await accepted.session.readReferences()
        #expect(await accepted.actions.removeBranch("side"))
        #expect(accepted.session.refs.headIDs["side"] == nil)
        await accepted.cleanup()
    }

    @Test func copyBranchNameUsesPasteboard() async throws {
        let repo = try await ActionTestRepo.make()
        let id = try await repo.resolve()
        repo.actions.perform(.copyBranchName, id: id, selected: nil, branchName: "side")
        #expect(NSPasteboard.general.string(forType: .string) == "side")
        await repo.cleanup()
    }
}
