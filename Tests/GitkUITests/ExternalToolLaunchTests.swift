// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkUI

@MainActor @Suite struct ExternalToolLaunchTests {
    @Test func missingGitToolReportsErrorWithoutBlocking() async throws {
        let repo = try await ActionTestRepo.make()
        repo.actions.launchGitTool(["nonexistent-gitk-tool"])
        for _ in 0..<100 where repo.messages.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(repo.messages.contains { $0.contains("nonexistent-gitk-tool") })
        #expect(!repo.actions.isBusy)
        await repo.cleanup()
    }
}
