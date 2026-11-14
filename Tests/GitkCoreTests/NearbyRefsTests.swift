// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct NearbyRefsTests {
    @Test @MainActor func tagsAgreeWithDescribe() async throws {
        let repo = try FixtureRepo.make("tags-notes")
        let runner = GitRunner(cwd: repo)
        let index = AncestryIndex(refs: await RefParser.load(runner: runner))
        _ = try await index.load(runner: runner)
        let commits = try await runner.run(["rev-list", "HEAD"])
        for word in String(decoding: commits.stdout, as: UTF8.self).split(separator: "\n").prefix(5) {
            let id = try #require(ObjectID(hex: String(word)))
            // gitk excludes tags on the selected commit itself.
            if index.refs.tags(of: id).isEmpty {
                if let output = try? await runner.run(["describe", "--tags", "--abbrev=0", id.hex]) {
                    let name = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    let target = try #require(index.refs.tagIDs[name])
                    #expect(index.ancestorTags(of: id).contains(target))
                }
                if let output = try? await runner.run(["describe", "--tags", "--contains", "--abbrev=0", id.hex]) {
                    let name = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(separator: "~").first.map(String.init) ?? ""
                    let target = try #require(index.refs.tagIDs[name])
                    #expect(index.descendantTags(of: id).contains(target))
                }
            }
        }
    }

    @Test func overflowKeepsVisibleBranches() {
        let id = AncestryIndexBuildTests.oid
        var refs = RefSet()
        for n in 1...5 { refs.addHead("branch\(n)", id(n)) }
        let line = NearbyRefs.line(ids: (1...5).map(id), refs: refs, heads: true,
                                   maximum: 2, visible: ["branch2"])
        #expect(line.entries.map(\.name) == ["branch2"])
        #expect(line.overflowKey == "and many more")
        #expect(line.omittedCount == 4)
        #expect(NearbyRefs.line(ids: (1...5).map(id), refs: refs, heads: true,
                               maximum: 2, visible: []).overflowKey == "many")
    }
}
