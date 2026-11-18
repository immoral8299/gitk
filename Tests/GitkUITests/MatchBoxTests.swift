// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor
@Suite struct MatchBoxTests {
    private func makeSession() throws -> (ViewSession, [ObjectID]) {
        let repo = RepoContext(gitDir: ".git", worktree: "/tmp", cdup: "", isBare: false, hasWorktree: true,
                               hashAlgorithm: "sha1", hashLength: 40, logShowRoot: true, gitEncoding: "utf-8", guiEncoding: "utf-8")
        let session = ViewSession(repo: repo, runner: GitRunner(), view: ViewSpec(name: "Test"))
        var commits: [ParsedCommit] = []
        for (n, subject) in ["merge and merge again", "plain"].enumerated() {
            let id = String(repeating: String(n + 1), count: 40)
            let parent = n == 0 ? "" : "parent \(String(repeating: "1", count: 40))\n"
            let raw = """
            commit \(id)
            tree \(String(repeating: "b", count: 40))
            \(parent)author Alice <alice@example.com> 0 +0000
            committer Alice <alice@example.com> 0 +0000

                \(subject)
            """
            commits.append(try RawLogParser.parse(record: Data(raw.utf8)))
        }
        session.ingest(batch: HistoryBatch(generation: 1, commits: commits))
        return (session, commits.map(\.id))
    }

    private func headline(_ controller: CommitListController, row: Int) -> NSAttributedString? {
        let column = controller.tableView.tableColumns[0]
        return (controller.tableView(controller.tableView, viewFor: column, row: row) as? GraphCellView)?.attributedHeadline
    }

    @Test func everyOccurrenceGetsABoxAndRowsStayRegular() throws {
        let (session, ids) = try makeSession()
        let controller = CommitListController(session: session, font: .systemFont(ofSize: 12))
        controller.findQuery = FindQuery(pattern: "merge")
        controller.highlightedIDs = [ids[0]]
        let text = try #require(headline(controller, row: 0))
        var boxes: [NSRange] = []
        text.enumerateAttribute(MatchBoxes.key, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value != nil { boxes.append(range) }
        }
        #expect(boxes == [NSRange(location: 0, length: 5), NSRange(location: 10, length: 5)])
        let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(!font.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(text.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
        let plain = try #require(headline(controller, row: 1))
        #expect(plain.attribute(MatchBoxes.key, at: 0, effectiveRange: nil) == nil)
    }

    @Test func currentMatchUsesTheCurrentHitColour() throws {
        let (session, ids) = try makeSession()
        let controller = CommitListController(session: session, font: .systemFont(ofSize: 12))
        controller.findQuery = FindQuery(pattern: "merge")
        controller.highlightedIDs = [ids[0]]
        let found = try #require(headline(controller, row: 0)?.attribute(MatchBoxes.key, at: 0, effectiveRange: nil) as? NSColor)
        session.selection = session.selection.selecting(ids[0])
        let current = try #require(headline(controller, row: 0)?.attribute(MatchBoxes.key, at: 0, effectiveRange: nil) as? NSColor)
        #expect(found == Palette.found(controller.settings))
        #expect(current == Palette.tk(controller.settings.currentSearchHitBgColor))
        #expect(found != current)
    }

    @Test func onlyTheFirstOccurrenceIsCurrent() throws {
        let (session, ids) = try makeSession()
        let controller = CommitListController(session: session, font: .systemFont(ofSize: 12))
        controller.findQuery = FindQuery(pattern: "merge")
        controller.highlightedIDs = [ids[0]]
        session.selection = session.selection.selecting(ids[0])
        let text = try #require(headline(controller, row: 0))
        let first = text.attribute(MatchBoxes.key, at: 0, effectiveRange: nil) as? NSColor
        let second = text.attribute(MatchBoxes.key, at: 10, effectiveRange: nil) as? NSColor
        #expect(first == Palette.tk(controller.settings.currentSearchHitBgColor))
        #expect(second == Palette.found(controller.settings))
    }

    @Test func sidebarMessageShowsTheSameBoxes() throws {
        let (session, ids) = try makeSession()
        let sidebar = DetailsSidebar()
        let index = try #require(session.store.index(of: ids[0]))
        sidebar.show(DetailsHeaderBuilder.build(commit: index, session: session), session: session)
        sidebar.setFind(FindQuery(pattern: "merge"), matches: [ids[0]])
        let storage = try #require(sidebar.messageView.textStorage)
        let first = storage.attribute(MatchBoxes.key, at: 0, effectiveRange: nil) as? NSColor
        let second = storage.attribute(MatchBoxes.key, at: 10, effectiveRange: nil) as? NSColor
        #expect(first == Palette.tk(sidebar.settings.currentSearchHitBgColor))
        #expect(second == Palette.found(sidebar.settings))
        sidebar.setFind(FindQuery(pattern: "merge"), matches: [])
        #expect(sidebar.messageView.textStorage?.attribute(MatchBoxes.key, at: 0, effectiveRange: nil) == nil)
    }

    @Test func advancedOptionsDefaultAndSnapshotQuery() throws {
        let (session, _) = try makeSession()
        let bar = SearchBar(session: session)
        #expect(!bar.advancedChanged)
        #expect(bar.query.type == .containing && bar.query.matchMode == .exact && bar.query.field == .allFields)
        #expect(!bar.advancedShown)
        bar.applySnapshotQuery("containing:IgnCase:Author:alice")
        #expect(bar.query == FindQuery(type: .containing, matchMode: .ignoreCase, field: .author, pattern: "alice"))
        #expect(bar.advancedChanged)
        bar.applySnapshotQuery("containing:Exact:All fields:merge")
        #expect(bar.query == FindQuery(pattern: "merge"))
        #expect(!bar.advancedChanged)
        bar.cancel()
    }
}
