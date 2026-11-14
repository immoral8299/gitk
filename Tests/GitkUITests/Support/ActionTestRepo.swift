// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor
final class ActionTestRepo {
    let directory: URL
    let session: ViewSession
    let confirm: String
    lazy var actions = RepositoryActionCoordinator(session: session, alerts: Alerts(
        environment: ["GITK_SWIFT_HEADLESS_ERRORS": "1", "GITK_SWIFT_CONFIRM": confirm],
        sink: { [weak self] in self?.messages.append($0) }))
    var messages: [String] = []
    var runner: GitRunner { session.runner }

    private init(directory: URL, session: ViewSession, confirm: String) {
        self.directory = directory
        self.session = session
        self.confirm = confirm
    }

    static func make(_ fixture: String = "linear", confirm: String = "yes") async throws -> ActionTestRepo {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gitk-action-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try await ProcessRunner().run(executable: root.appendingPathComponent("Tests/Fixtures/make-fixture.sh"),
                                                  arguments: [fixture, directory.path])
        guard result.status == 0 else {
            throw GitError(args: [fixture], status: result.status, stderr: result.stderrText)
        }
        let repo = directory.appendingPathComponent(fixture)
        let runner = GitRunner(cwd: repo)
        _ = try await runner.run(["config", "user.name", "Action Test"])
        _ = try await runner.run(["config", "user.email", "actions@example.com"])
        let context = try await RepoContext.discover(cwd: repo)
        let session = ViewSession(repo: context, runner: runner, view: ViewSpec(name: "All files"))
        await session.load()
        return ActionTestRepo(directory: directory, session: session, confirm: confirm)
    }

    func resolve(_ rev: String = "HEAD") async throws -> ObjectID {
        let output = try await runner.run(["rev-parse", rev])
        return try #require(ObjectID(hex: String(decoding: output.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func cleanup() async {
        actions.cancel()
        await session.cancel()
        try? FileManager.default.removeItem(at: directory)
    }
}
