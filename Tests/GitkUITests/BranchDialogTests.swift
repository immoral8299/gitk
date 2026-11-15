// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct BranchDialogTests {
    @Test func emptyNameAndConfirmedOverwrite() async throws {
        let repo = try await ActionTestRepo.make()
        let id = try await repo.resolve()
        #expect(!(await repo.actions.branch(name: "", at: id)))
        #expect(repo.messages.last?.contains("Please specify a name") == true)
        #expect(await repo.actions.branch(name: "topic", at: id))
        let older = try await repo.resolve("HEAD~1")
        #expect(await repo.actions.branch(name: "topic", at: older))
        #expect(repo.session.refs.headIDs["topic"] == older)
        #expect(await repo.actions.branch(name: "renamed", at: older, renameFrom: "topic"))
        #expect(repo.session.refs.headIDs["renamed"] == older)
        #expect(repo.session.refs.headIDs["topic"] == nil)
        await repo.cleanup()
    }

    @Test func renameValidationAndDeclinedOverwrite() async throws {
        let repo = try await ActionTestRepo.make(confirm: "no")
        let id = try await repo.resolve()
        let older = try await repo.resolve("HEAD~1")
        #expect(await repo.actions.branch(name: "topic", at: id))
        #expect(!(await repo.actions.branch(name: "", at: id, renameFrom: "topic")))
        #expect(repo.messages.last?.contains("Please specify a new name") == true)
        #expect(await repo.actions.branch(name: "topic", at: id, renameFrom: "topic"))
        #expect(!(await repo.actions.branch(name: "topic", at: older)))
        #expect(repo.session.refs.headIDs["topic"] == id)
        _ = NSApplication.shared
        let dialog = BranchDialog(id: id, renameFrom: "topic", coordinator: repo.actions)
        #expect(dialog.nameField.stringValue == "topic")
        #expect(dialog.window?.title == "Rename branch topic")
        dialog.close()
        repo.actions.showRenameBranch("topic", at: id)
        repo.actions.cancel()
        await repo.cleanup()
    }
}
