// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct TwoCommitDiffTests {
    static let a = ObjectID(hex: String(repeating: "a", count: 40))!
    static let b = ObjectID(hex: String(repeating: "b", count: 40))!

    @Test func endpointsFollowTheMenuItem() {
        let (a, b) = (Self.a, Self.b)
        // A selected, menu on B.
        #expect(TwoCommitDiff.make(command: .diffThisToSelected, menuID: b, selected: a, marked: nil) == TwoCommitDiff(old: b, new: a))
        #expect(TwoCommitDiff.make(command: .diffSelectedToThis, menuID: b, selected: a, marked: nil) == TwoCommitDiff(old: a, new: b))
        #expect(TwoCommitDiff.make(command: .diffThisToMarked, menuID: b, selected: nil, marked: a) == TwoCommitDiff(old: b, new: a))
        #expect(TwoCommitDiff.make(command: .diffMarkedToThis, menuID: b, selected: nil, marked: a) == TwoCommitDiff(old: a, new: b))
        #expect(TwoCommitDiff.make(command: .diffThisToSelected, menuID: b, selected: nil, marked: a) == nil)
        #expect(TwoCommitDiff.make(command: .diffThisToMarked, menuID: b, selected: a, marked: nil) == nil)
    }

    @Test func commandDiffsFromBToA() {
        let diff = TwoCommitDiff(old: Self.b, new: Self.a)
        let command = diff.command(options: DiffOptions(hashLength: 40))
        #expect(command.prefix(2) == ["diff-tree", "-r"])
        #expect(Array(command.suffix(2)) == [Self.b.hex, Self.a.hex])
    }

    @Test func headerNamesBothCommitsWithHeadlines() {
        let header = TwoCommitDiff(old: Self.a, new: Self.b).header(oldHeadline: "first", newHeadline: "second")
        #expect(header.text == "From \(Self.a.hex)\n     first\n\nTo   \(Self.b.hex)\n     second\n")
        let text = header.text as NSString
        #expect(text.substring(with: header.oldRange) == Self.a.hex)
        #expect(text.substring(with: header.newRange) == Self.b.hex)
    }

    @Test func coordinatorReportsDiffAndSidebarShowsLinks() async throws {
        let repo = try await ActionTestRepo.make()
        let head = try await repo.resolve()
        let parent = try await repo.resolve("HEAD~1")
        var got: TwoCommitDiff?
        repo.actions.onDiffCommits = { got = $0 }
        _ = repo.actions.perform(.diffThisToSelected, id: parent, selected: head)
        #expect(got == TwoCommitDiff(old: parent, new: head))
        let sidebar = DetailsSidebar()
        sidebar.show(diff: try #require(got), session: repo.session)
        #expect(sidebar.shownID == nil)
        await repo.cleanup()
    }
}
