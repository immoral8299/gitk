// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct RefListRefreshTests {
    @Test func branchCreatedWhileOpenAppearsInList() async throws {
        let repo = try await ActionTestRepo.make("tags-notes")
        let session = repo.session

        let controller = RefListWindowController(
            repoName: "tags-notes",
            source: { [session] in
                (session.refs, { [session] in session.row(of: $0) != nil },
                 { [session] id in session.store.index(of: id).map { session.store.headline(at: $0) } })
            },
            onSelect: { _ in })
        controller.present()
        // Mirrors the `.refsChanged` case in MainWindowController.handle(_:).
        session.onEvent = { (event: ViewSession.Event) in
            if case .refsChanged = event { controller.reload() }
        }
        #expect(!controller.entries.contains { $0.name == "branch-opened-later" })

        _ = try await repo.runner.run(["branch", "branch-opened-later"])
        await session.readReferences()

        let model = RefListModel().entries(refs: session.refs, inView: { session.row(of: $0) != nil })
        #expect(model.contains { $0.name == "branch-opened-later" && $0.kind == RefListModel.Kind.head })
        #expect(controller.entries.contains { $0.name == "branch-opened-later" })
        controller.close()
        await repo.cleanup()
    }
}
