// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct CreateTagTests {
    @Test func annotatedTagAndValidation() async throws {
        let repo = try await ActionTestRepo.make()
        let id = try await repo.resolve()
        #expect(!(await repo.actions.tag(name: "", at: id, message: "")))
        #expect(await repo.actions.tag(name: "v2.0", at: id, message: "Release 2.0"))
        #expect(repo.session.refs.tagIDs["v2.0"] == id)
        let tag = try await repo.runner.run(["cat-file", "-p", "v2.0"])
        #expect(String(decoding: tag.stdout, as: UTF8.self).contains("Release 2.0"))
        #expect(!(await repo.actions.tag(name: "v2.0", at: id, message: "other")))
        await repo.cleanup()
    }

    @Test func refusalsUseGitkMessagesAndRunNoGit() async throws {
        let repo = try await ActionTestRepo.make()
        let id = try await repo.resolve()
        #expect(!(await repo.actions.tag(name: "", at: id, message: "msg")))
        #expect(await repo.actions.tag(name: "dup", at: id, message: ""))
        #expect(!(await repo.actions.tag(name: "dup", at: id, message: "")))
        #expect(repo.messages == ["gitk: No tag name specified", "gitk: Tag \"dup\" already exists"])
        await repo.cleanup()
    }

    @Test func emptyMessageMakesLightweightTagAndLabelIsInSession() async throws {
        let repo = try await ActionTestRepo.make()
        let id = try await repo.resolve("HEAD~1")
        #expect(await repo.actions.tag(name: "light", at: id, message: ""))
        #expect(repo.session.refs.tags(of: id) == ["light"])
        let type = try await repo.runner.run(["cat-file", "-t", "light"])
        #expect(String(decoding: type.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "commit")
        #expect(await repo.actions.tag(name: "ann", at: id, message: "m"))
        let t = try await repo.runner.run(["cat-file", "-t", "ann"])
        #expect(String(decoding: t.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "tag")
        await repo.cleanup()
    }

    @Test func dialogShowsIDAndSubmitsFields() async throws {
        let repo = try await ActionTestRepo.make()
        let id = try await repo.resolve()
        _ = NSApplication.shared
        let dialog = TagDialog(id: id, coordinator: repo.actions)
        dialog.nameField.stringValue = "viaDialog"
        dialog.messageField.stringValue = "hello"
        let ok = await dialog.onAccept?()
        #expect(ok == true)
        #expect(repo.session.refs.tagIDs["viaDialog"] == id)
        dialog.close()
        await repo.cleanup()
    }
}
