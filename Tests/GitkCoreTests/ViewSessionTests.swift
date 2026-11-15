// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite @MainActor struct ViewSessionTests {
    @Test func orderAndEvents() async throws {
        let repo = try FixtureRepo.make("merge-simple")
        let context = try await RepoContext.discover(cwd: repo)
        let session = ViewSession(repo: context, runner: GitRunner(cwd: repo), view: ViewSpec(name: "all", args: ["--all"]))
        session.showLocalChanges = false
        var events: [String] = []
        session.onEvent = { event in
            switch event {
            case .loadStarted: events.append("started")
            case .loadProgress: events.append("progress")
            case .loadFinished: events.append("finished")
            case .loadFailed(let message): Issue.record("\(message)")
            default: break
            }
        }
        await session.load()
        let oracle = try OracleGolden.load("merge-simple")
        #expect((0..<session.rowCount).compactMap { session.id(at: $0)?.hex } == oracle.order)
        #expect(events.first == "started")
        #expect(events.contains("progress"))
        #expect(events.last == "finished")
        #expect(!session.isLoading)
    }
}

@Suite @MainActor struct UpdateReloadTests {
    @Test func updatePreservesSelectionAndReloadDropsUnreachableCommit() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        defer { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        let runner = GitRunner(cwd: repo)
        let context = try await RepoContext.discover(cwd: repo)
        let session = ViewSession(repo: context, runner: runner, view: ViewSpec(name: "all"))
        session.showLocalChanges = false
        await session.load()
        let oldHead = try #require(session.refs.mainHeadID)
        session.selection = session.selection.selecting(oldHead)
        _ = try await runner.run(["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--allow-empty", "-m", "new"])
        await session.update()
        let newHead = try #require(session.refs.mainHeadID)
        #expect(newHead != oldHead)
        #expect(session.id(at: 0) == newHead)
        #expect(session.row(of: oldHead) == 1)
        #expect(session.selection.selectedID == oldHead)
        _ = try await runner.run(["reset", "--hard", oldHead.hex])
        await session.reload()
        #expect(session.row(of: newHead) == nil)
        #expect(session.selection.selectedID == oldHead)
    }

    /// preferences: Quit during load. `MainWindowController.stop()` awaits this, so it
    /// must return promptly and leave no running child.
    @Test func cancelDuringLoadReturnsPromptly() async throws {
        let repo = try FixtureRepo.make("long-lines")
        let context = try await RepoContext.discover(cwd: repo)
        let session = ViewSession(repo: context, runner: GitRunner(cwd: repo), view: ViewSpec(name: "all", args: ["--all"]))
        let load = Task { await session.load() }
        try await Task.sleep(for: .milliseconds(20))
        let start = ContinuousClock.now
        await session.cancel()
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(!session.isLoading)
        await load.value
    }
}
