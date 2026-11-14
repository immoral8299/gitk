// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct RevertTests {
    @Test func successfulRevertSelectsNewHead() async throws {
        let repo = try await ActionTestRepo.make()
        let old = try await repo.resolve()
        var selected: ObjectID?
        repo.actions.onSelect = { selected = $0 }
        #expect(await repo.actions.pick(old, revert: true))
        let head = try await repo.resolve()
        #expect(head != old)
        #expect(selected == head)
        #expect(repo.session.refs.mainHeadID == head)
        await repo.cleanup()
    }
}
