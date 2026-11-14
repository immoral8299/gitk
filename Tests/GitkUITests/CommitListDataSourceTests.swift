// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor
@Suite struct CommitListDataSourceTests {
    @Test func subjectAuthorAndCommitTimezone() throws {
        let repo = RepoContext(gitDir: ".git", worktree: "/tmp", cdup: "", isBare: false, hasWorktree: true,
                               hashAlgorithm: "sha1", hashLength: 40, logShowRoot: true, gitEncoding: "utf-8", guiEncoding: "utf-8")
        let session = ViewSession(repo: repo, runner: GitRunner(), view: ViewSpec(name: "Test"))
        let id = String(repeating: "a", count: 40)
        let raw = """
        commit \(id)
        tree \(String(repeating: "b", count: 40))
        author Alice <alice@example.com> 0 +0530
        committer Alice <alice@example.com> 0 +0530

            A precise subject
        """
        let commit = try RawLogParser.parse(record: Data(raw.utf8))
        session.ingest(batch: HistoryBatch(generation: 1, commits: [commit]))
        let controller = CommitListController(session: session, font: .systemFont(ofSize: 12))
        controller.dateFormat = "%Y-%m-%d %H:%M:%S %z"
        #expect(controller.numberOfRows(in: controller.tableView) == 1)
        #expect(controller.values(at: 0) == ["A precise subject", "Alice", "1970-01-01 05:30:00 +0530"])
        session.selection = session.selection.selecting(commit.id)
        controller.refresh()
        #expect(controller.tableView.selectedRow == 0)
        let bar = CommitIDBar(font: .monospacedSystemFont(ofSize: 12, weight: .regular))
        bar.refresh(session: session)
        #expect(bar.field.stringValue == commit.id.hex)
        #expect(bar.counter.stringValue == "1 / 1")
    }
}
