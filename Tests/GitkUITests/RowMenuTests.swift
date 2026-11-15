// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct RowMenuTests {
    @Test func orderAndMarkEnablement() throws {
        let a = try #require(ObjectID(hex: String(repeating: "a", count: 40)))
        let b = try #require(ObjectID(hex: String(repeating: "b", count: 40)))
        let menu = RowMenus.commitMenu(id: a, selected: b, marked: nil, refs: RefSet()) { _ in }
        #expect(menu.items.count == 16)
        #expect(menu.items[0].title == L("Diff this -> selected"))
        #expect(menu.items[15].title == L("Revert this commit"))
        for n in [10, 11, 12, 13, 14] { #expect(!menu.items[n].isEnabled) }
        let marked = RowMenus.commitMenu(id: a, selected: b, marked: b, refs: RefSet()) { _ in }
        for n in [10, 11, 12, 13, 14] { #expect(marked.items[n].isEnabled) }
    }

    @Test func fakeRowHasOnlyDiffAndPatch() throws {
        let a = try #require(ObjectID.localUnstaged(hashLength: 40))
        let menu = RowMenus.commitMenu(id: a, selected: nil, marked: nil, refs: RefSet()) { _ in }
        #expect(menu.items.count == 5)
        #expect(menu.items.compactMap { $0.representedObject as? AppCommand }
                == [.diffThisToSelected, .diffSelectedToThis, .makePatch, .diffThisToMarked, .diffMarkedToThis])
        #expect(menu.items.allSatisfy { !$0.isEnabled })
    }

    /// The menu attached to a commit row follows the session's mark.
    @Test func attachedMenuFollowsSessionMark() throws {
        let session = try makeSession(headline: "A subject")
        let controller = CommitListController(session: session, font: .systemFont(ofSize: 12))
        let unmarked = try #require(controller.contextMenu(forRow: 0))
        #expect(unmarked.items.count == 16)
        for n in [10, 11, 12, 13, 14] { #expect(!unmarked.items[n].isEnabled) }
        #expect(controller.contextMenu(forRow: -1) == nil)
        #expect(controller.contextMenu(forRow: 1) == nil)

        session.selection.markedID = session.id(at: 0)
        // The commit is the mark itself, so the mark-dependent items stay disabled.
        let marked = try #require(controller.contextMenu(forRow: 0))
        for n in [10, 11, 12, 13, 14] { #expect(!marked.items[n].isEnabled) }
    }

    /// Choosing an attached item reports its command and the row's commit.
    @Test func attachedItemReportsCommandAndCommit() throws {
        let session = try makeSession(headline: "A subject")
        let controller = CommitListController(session: session, font: .systemFont(ofSize: 12))
        var received: [(AppCommand, ObjectID)] = []
        controller.onRowCommand = { received.append(($0, $1)) }
        let menu = try #require(controller.contextMenu(forRow: 0))
        // "Mark this commit" needs no mark, so it is enabled.
        menu.performActionForItem(at: 9)
        #expect(received.count == 1)
        #expect(received.first?.0 == .markCommit)
        #expect(received.first?.1 == session.id(at: 0))
    }

    /// The reduced menu on a local-changes row.
    @Test func attachedMenuOnLocalChangesRow() throws {
        let session = try makeSession(headline: nil)
        let head = try #require(ObjectID(hex: String(repeating: "c", count: 40)))
        let tree = try #require(ObjectID(hex: String(repeating: "d", count: 40)))
        let local = LocalChanges(staged: false, unstaged: true).commits(head: head, tree: tree, hashLength: 40)
        session.ingest(batch: HistoryBatch(generation: 1, commits: local))
        let controller = CommitListController(session: session, font: .systemFont(ofSize: 12))
        let menu = try #require(controller.contextMenu(forRow: 0))
        #expect(menu.items.count == 5)
        #expect(menu.items.allSatisfy { !$0.isEnabled })
    }

    /// A session holding one commit with the given headline (or none when nil).
    private func makeSession(headline: String?) throws -> ViewSession {
        let repo = RepoContext(gitDir: ".git", worktree: "/tmp", cdup: "", isBare: false, hasWorktree: true,
                               hashAlgorithm: "sha1", hashLength: 40, logShowRoot: true, gitEncoding: "utf-8", guiEncoding: "utf-8")
        let session = ViewSession(repo: repo, runner: GitRunner(), view: ViewSpec(name: "Test"))
        guard let headline else { return session }
        let raw = """
        commit \(String(repeating: "a", count: 40))
        tree \(String(repeating: "b", count: 40))
        author Alice <alice@example.com> 0 +0000
        committer Alice <alice@example.com> 0 +0000

            \(headline)
        """
        let commit = try RawLogParser.parse(record: Data(raw.utf8))
        session.ingest(batch: HistoryBatch(generation: 1, commits: [commit]))
        return session
    }
}
