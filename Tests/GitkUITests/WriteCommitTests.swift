// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct WriteCommitTests {
    @Test func defaultCommandWritesEmailPatchAndCustomCommandReceivesID() async throws {
        let repo = try await ActionTestRepo.make()
        let id = try await repo.resolve()
        let output = repo.directory.appendingPathComponent("commit")
        #expect(await repo.actions.writeCommit(id, command: "git diff-tree --stdin -p --pretty=email", output: output))
        #expect(try String(contentsOf: output, encoding: .utf8).contains("Subject:"))
        #expect(await repo.actions.writeCommit(id, command: "cat", output: output))
        #expect(try String(contentsOf: output, encoding: .utf8) == id.hex + "\n")
        await repo.cleanup()
    }

    @Test func failingCommandReportsErrorWithGitkPrefix() async throws {
        let repo = try await ActionTestRepo.make()
        let id = try await repo.resolve()
        let output = repo.directory.appendingPathComponent("never")
        #expect(await repo.actions.writeCommit(id, command: "echo boom >&2; exit 3", output: output) == false)
        #expect(repo.messages.contains { $0.contains("Error writing commit:") })
        await repo.cleanup()
    }
}
