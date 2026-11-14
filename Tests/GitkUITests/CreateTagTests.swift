// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

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
}
