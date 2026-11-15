// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct MakePatchTests {
    @Test func patchAppliesAtParent() async throws {
        let repo = try await ActionTestRepo.make()
        let parent = try await repo.resolve("HEAD~1")
        let head = try await repo.resolve()
        let output = repo.directory.appendingPathComponent("fix.patch")
        #expect(await repo.actions.makePatch(from: parent, to: head, reverse: false, output: output))
        _ = try await repo.runner.run(["checkout", "--detach", parent.hex])
        _ = try await repo.runner.run(["apply", "--check", output.path])
        await repo.cleanup()
    }

    @Test func reverseSwapsEndpointsAndGeneratesReversePatch() async throws {
        let repo = try await ActionTestRepo.make()
        let parent = try await repo.resolve("HEAD~1")
        let head = try await repo.resolve()
        let dialog = PatchDialog(from: parent, to: head, number: 3, coordinator: repo.actions)
        #expect(dialog.outputField.stringValue.hasSuffix("patch3.patch"))
        dialog.reversePressed()
        #expect(dialog.fromField.stringValue == head.hex)
        #expect(dialog.toField.stringValue == parent.hex)
        let output = repo.directory.appendingPathComponent("rev.patch")
        dialog.outputField.stringValue = output.path
        #expect(await dialog.onAccept?() == true)
        _ = try await repo.runner.run(["apply", "--check", output.path])
        await repo.cleanup()
    }
}
