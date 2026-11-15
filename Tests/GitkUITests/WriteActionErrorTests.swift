// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct WriteActionErrorTests {
    @Test func startGitGuiLaunchesGuiArguments() async throws {
        let repo = try await ActionTestRepo.make()
        var launched: [[String]] = []
        repo.actions.toolLauncher = { arguments, _ in launched.append(arguments) }
        #expect(repo.actions.perform(.startGitGui, id: nil, selected: nil))
        #expect(launched == [["gui"]])
        await repo.cleanup()
    }

    @Test func missingToolShowsGitMessageHeadless() async throws {
        let repo = try await ActionTestRepo.make()
        repo.actions.launchGitTool(["nonexistent-gitk-tool"])
        for _ in 0..<100 where repo.messages.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(repo.messages.contains { $0.hasPrefix("gitk: ") && $0.contains("is not a git command") })
        await repo.cleanup()
    }

    @Test func writeActionReportsBusyThenIdle() async throws {
        let repo = try await ActionTestRepo.make()
        let head = try await repo.resolve()
        var statuses: [String?] = []
        repo.actions.onBusy = { statuses.append($0) }
        #expect(await repo.actions.reset(to: head, type: .mixed))
        #expect(statuses == [L("Resetting"), nil])
        await repo.cleanup()
    }

    @Test func branchCreatedOutsideAppReportsGitMessage() async throws {
        let repo = try await ActionTestRepo.make()
        let head = try await repo.resolve()
        // Created after the session loaded, so the app's refs still lack it.
        _ = try await repo.runner.run(["branch", "outside", head.hex])
        #expect(await repo.actions.branch(name: "outside", at: head) == false)
        #expect(repo.messages.contains { $0.contains("already exists") })
        #expect(repo.session.refs.headIDs["outside"] != nil)
        await repo.cleanup()
    }
}
