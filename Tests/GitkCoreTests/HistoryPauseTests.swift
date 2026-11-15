// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

/// The history load holds back while the selected commit's details load.
@Suite @MainActor struct HistoryPauseTests {
    private func session() async throws -> ViewSession {
        let repo = try FixtureRepo.make("merge-simple")
        let context = try await RepoContext.discover(cwd: repo)
        let session = ViewSession(repo: context, runner: GitRunner(cwd: repo), view: ViewSpec(name: "all", args: ["--all"]))
        session.showLocalChanges = false
        return session
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !condition() {
            #expect(ContinuousClock.now < deadline, "condition not reached")
            if ContinuousClock.now >= deadline { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func pausedLoadTakesNoRowsUntilResumed() async throws {
        let session = try await session()
        session.historyPaused = true
        session.historyPauseLimit = .seconds(30)
        let load = Task { await session.load() }
        // Wait for the load to start (refs are read first), then give the
        // first batch time to arrive and be held back.
        try await waitUntil { session.isLoading }
        try await Task.sleep(for: .milliseconds(400))
        #expect(session.isLoading)
        #expect(session.rowCount == 0)
        session.historyPaused = false
        await load.value
        #expect(!session.isLoading)
        #expect(session.rowCount > 0)
    }

    @Test func pauseIsBoundedByTheLimit() async throws {
        let session = try await session()
        session.historyPaused = true
        session.historyPauseLimit = .milliseconds(150)
        await session.load()  // never resumed: finishes once the limit passes
        #expect(!session.isLoading)
        #expect(session.rowCount > 0)
    }

    @Test func cancelEndsAPausedLoad() async throws {
        let session = try await session()
        session.historyPaused = true
        session.historyPauseLimit = .seconds(30)
        let load = Task { await session.load() }
        try await waitUntil { session.isLoading }
        let start = ContinuousClock.now
        await session.cancel()
        await load.value
        #expect(start.duration(to: .now) < .seconds(1))
        #expect(!session.isLoading)
    }
}
