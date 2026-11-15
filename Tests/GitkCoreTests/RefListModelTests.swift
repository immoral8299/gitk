// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct RefListModelTests {
    private func refs() async throws -> RefSet {
        let repo = try FixtureRepo.make("tags-notes")
        return await RefParser.load(runner: GitRunner(cwd: repo))
    }

    @Test func openListsAllHeadsAndTags() async throws {
        let refs = try await refs()
        let list = RefListModel().entries(refs: refs, inView: { _ in true })
        #expect(Set(list.filter { $0.kind == .tag }.map(\.name)) == Set(refs.tagIDs.keys))
        #expect(Set(list.filter { $0.kind == .head }.map(\.name)) == Set(refs.headIDs.keys.filter { !$0.hasPrefix("remotes/") }))
        #expect(!list.isEmpty)
    }

    @Test func globFilter() async throws {
        let refs = try await refs()
        let prefix = String(try #require(refs.tagIDs.keys.sorted().first).prefix(1))
        let list = RefListModel(filter: prefix + "*").entries(refs: refs, inView: { _ in true })
        #expect(!list.isEmpty)
        #expect(list.allSatisfy { $0.name.hasPrefix(prefix) })
        #expect(RefListModel(filter: "no-such-*").entries(refs: refs, inView: { _ in true }).isEmpty)
    }

    @Test func sortOrders() async throws {
        let refs = try await refs()
        let byName = RefListModel().entries(refs: refs, inView: { _ in true })
        #expect(byName.map(\.name) == byName.map(\.name).sorted())
        let byType = RefListModel(sortByType: true).entries(refs: refs, inView: { _ in true })
        let kinds = byType.map(\.kind.rawValue).joined()
        #expect(kinds.firstIndex(of: "T").map { t in !kinds[t...].contains("H") } ?? true)
        for kind in ["H", "T"] {
            let names = byType.filter { $0.kind.rawValue == kind }.map(\.name)
            #expect(names == names.sorted())
        }
        #expect(Set(byType.map(\.name)) == Set(byName.map(\.name)))
    }

    @Test func refOutsideViewIsOmitted() async throws {
        let refs = try await refs()
        let hidden = try #require(refs.tagIDs.values.first)
        let list = RefListModel().entries(refs: refs, inView: { $0 != hidden })
        #expect(list.allSatisfy { $0.id != hidden })
    }
}
