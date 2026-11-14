// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor
@Suite struct ColumnSizingTests {
    @Test func authorAndDateFitContentAndHeadlineTakesTheRest() {
        let s = ColumnSizing.fit(available: 800, authorContent: 90, dateContent: 130)
        #expect(s == ColumnSizing(subject: 580, author: 90, date: 130))
    }

    @Test func authorIsCapped() {
        let s = ColumnSizing.fit(available: 800, authorContent: 340, dateContent: 130)
        #expect(s.author == ColumnSizing.authorCap)
        #expect(s.total == 800)
    }

    @Test func narrowListShrinksAuthorBeforeHeadlineAndKeepsDate() {
        let s = ColumnSizing.fit(available: 300, authorContent: 150, dateContent: 130)
        #expect(s == ColumnSizing(subject: ColumnSizing.minSubject, author: 50, date: 130))
        let tiny = ColumnSizing.fit(available: 200, authorContent: 150, dateContent: 130)
        #expect(tiny.date == 130)
        #expect(tiny.author == ColumnSizing.minColumn)
        #expect(tiny.subject == ColumnSizing.minColumn)
    }

    @Test func fractionalContentRoundsUpAndTotalStaysWithinAvailable() {
        let s = ColumnSizing.fit(available: 701.5, authorContent: 90.2, dateContent: 129.3)
        #expect(s.author == 91)
        #expect(s.date == 130)
        #expect(s.total <= 701.5)
    }

    @Test func userWidthsAreKeptAndHeadlineAbsorbsWidthChanges() {
        let wide = ColumnSizing.fit(available: 900, authorContent: 90, dateContent: 130, userAuthor: 250, userDate: 160)
        #expect(wide == ColumnSizing(subject: 490, author: 250, date: 160))
        let narrow = ColumnSizing.fit(available: 600, authorContent: 90, dateContent: 130, userAuthor: 250, userDate: 160)
        #expect(narrow == ColumnSizing(subject: 190, author: 250, date: 160))
    }

    @Test func draggedDividerMovesWithTheMouse() {
        let start = ColumnSizing(subject: 500, author: 100, date: 150)
        // Headline | author: the author column gives or takes the difference.
        #expect(ColumnSizing.dragged(column: 0, to: 450, from: start, available: 750)
                == ColumnSizing(subject: 450, author: 150, date: 150))
        // Author | date: the date column gives or takes it.
        #expect(ColumnSizing.dragged(column: 1, to: 130, from: start, available: 750)
                == ColumnSizing(subject: 500, author: 130, date: 120))
        // The date column's right edge: the headline absorbs it.
        #expect(ColumnSizing.dragged(column: 2, to: 120, from: start, available: 750)
                == ColumnSizing(subject: 530, author: 100, date: 120))
        // A neighbour never goes below the minimum width.
        #expect(ColumnSizing.dragged(column: 1, to: 300, from: start, available: 750).date == ColumnSizing.minColumn)
    }

    /// The table's three columns fill the list's width exactly (no
    /// horizontal scrolling) and follow it when it changes.
    @Test func controllerFitsColumnsToTheListWidth() throws {
        let repo = RepoContext(gitDir: ".git", worktree: "/tmp", cdup: "", isBare: false, hasWorktree: true,
                               hashAlgorithm: "sha1", hashLength: 40, logShowRoot: true, gitEncoding: "utf-8", guiEncoding: "utf-8")
        let session = ViewSession(repo: repo, runner: GitRunner(), view: ViewSpec(name: "Test"))
        let raw = """
        commit \(String(repeating: "a", count: 40))
        tree \(String(repeating: "b", count: 40))
        author Alice Author <alice@example.com> 1577862420 +0000
        committer Alice Author <alice@example.com> 1577862420 +0000

            A subject
        """
        session.ingest(batch: HistoryBatch(generation: 1, commits: [try RawLogParser.parse(record: Data(raw.utf8))]))
        let font = NSFont.systemFont(ofSize: 13)
        let controller = CommitListController(session: session, font: font)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        let content = try #require(window.contentView)
        controller.scrollView.frame = content.bounds
        content.addSubview(controller.scrollView)
        controller.refresh()
        let table = controller.tableView

        func check(width: CGFloat) {
            #expect(table.headerView != nil)
            #expect(table.rect(ofColumn: 2).maxX <= controller.scrollView.contentView.bounds.width)
            #expect(table.frame.width == width)
            let date = ("2020-01-01 07:07:00" as NSString).size(withAttributes: [.font: font]).width
            #expect(table.tableColumns[2].width >= date)
        }
        check(width: 600)
        let author = table.tableColumns[1].width
        controller.scrollView.frame.size.width = 900
        check(width: 900)
        #expect(table.tableColumns[1].width == author)
    }
}
