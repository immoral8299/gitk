// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite @MainActor struct DetailsHeaderTests {
    private func session(_ fixture: String) async throws -> ViewSession {
        let repo = try FixtureRepo.make(fixture)
        let context = try await RepoContext.discover(cwd: repo)
        let session = ViewSession(repo: context, runner: GitRunner(cwd: repo), view: ViewSpec(name: "all", args: ["--all"]))
        session.showLocalChanges = false
        await session.load()
        return session
    }

    private func commit(_ session: ViewSession, headline: String) throws -> CommitIndex {
        try #require((0..<session.rowCount).compactMap { session.commit(at: $0) }
            .first { session.store.headline(at: $0) == headline })
    }

    /// commit-details "Merge commit": one Parent row per parent, in merge colours.
    @Test func mergeHasColouredParentRowsAndChild() async throws {
        let session = try await session("merge-simple")
        let merge = try commit(session, headline: "Merge branch 'feature'")
        let header = DetailsHeaderBuilder.build(commit: merge, session: session)
        #expect(header.rows.map(\.kind) == [.author, .committer, .parent, .parent, .child])
        let parents = header.rows.filter { $0.kind == .parent }
        #expect(parents.map(\.mergeColor) == [0, 1])
        #expect(parents.map(\.value) == ["m3: more main work", "f2: more feature work"])
        #expect(parents.allSatisfy { $0.commit != nil })
        #expect(header.rows.last?.value == "m4: after merge")
        #expect(header.rows[0].value.hasPrefix("Alice Author <"))
        #expect(header.authorName == "Alice Author")
        #expect(header.initials == "AA")
        #expect(header.message.hasPrefix("Merge branch 'feature'"))
        #expect(header.notes == nil)

        let single = try commit(session, headline: "m3: more main work")
        let plain = DetailsHeaderBuilder.build(commit: single, session: session)
        #expect(plain.rows.filter { $0.kind == .parent }.map(\.mergeColor) == [nil])
    }

    /// commit-details "Commit with notes", plus the Tags row and refs.
    @Test func notesAndTags() async throws {
        let session = try await session("tags-notes")
        let noted = try commit(session, headline: "commit 5")
        let header = DetailsHeaderBuilder.build(commit: noted, session: session)
        #expect(header.notes?.contains("A note on commit 5") == true)
        let tagged = try commit(session, headline: "commit 4")
        let tags = DetailsHeaderBuilder.build(commit: tagged, session: session)
        #expect(tags.rows.contains { $0.kind == .tags && $0.value.contains("v1.0") })
        #expect(tags.refs.contains("release"))
        #expect(tags.refs.contains("v1.0"))
    }

    @Test func personAndInitials() {
        #expect(DetailsHeaderBuilder.splitPerson("Jane Q. Doe <jane@example.com>") == ("Jane Q. Doe", "jane@example.com"))
        #expect(DetailsHeaderBuilder.splitPerson("nobody") == ("nobody", ""))
        #expect(DetailsHeaderBuilder.initials(name: "Jane Q. Doe", email: "") == "JD")
        #expect(DetailsHeaderBuilder.initials(name: "", email: "x@y") == "X")
    }
}
