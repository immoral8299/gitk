// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct AncestryQueryTests {
    @Test @MainActor func pairsEqualGitMergeBase() async throws {
        let repo = try FixtureRepo.make("criss-cross")
        let runner = GitRunner(cwd: repo)
        let index = AncestryIndex(refs: await RefParser.load(runner: runner))
        _ = try await index.load(runner: runner)
        let ids = index.ids
        for n in 0..<20 {
            let a = ids[(n * 7 + 1) % ids.count]
            let b = ids[(n * 11 + 3) % ids.count]
            if a == b { #expect(index.ancOrDesc(a, b) == 0); continue }
            let ab = try? await runner.run(["merge-base", "--is-ancestor", a.hex, b.hex])
            let ba = try? await runner.run(["merge-base", "--is-ancestor", b.hex, a.hex])
            #expect(index.ancOrDesc(a, b) == (ab != nil ? 1 : ba != nil ? -1 : 0))
            #expect(index.isCertain(descendant: b, ancestor: a))
        }
    }

    @Test func removedRefsAreValidated() {
        let id = AncestryIndexBuildTests.oid
        var refs = RefSet()
        refs.addTag("tag", id(2), peeled: false)
        refs.addHead("branch", id(2))
        let index = AncestryIndex(refs: refs)
        _ = index.beginLoad()
        for line in [AncestryLine(id: id(3), parents: [id(2)]),
                     AncestryLine(id: id(2), parents: [id(1)]),
                     AncestryLine(id: id(1), parents: [])] { index.add(line) }
        _ = index.finish(error: nil)
        #expect(index.arcTags(1) == [id(2)])
        #expect(index.arcHeads(1) == [id(2)])
        index.refs = RefSet()
        index.validateArcTags(1)
        index.validateArcHeads(1)
        #expect(index.arcTags(1).isEmpty)
        #expect(index.arcHeads(1).isEmpty)
    }

    @Test func growingBranchIsUncertain() {
        let id = AncestryIndexBuildTests.oid
        let index = AncestryIndex()
        _ = index.beginLoad()
        index.add(AncestryLine(id: id(6), parents: [id(5), id(4)]))
        index.add(AncestryLine(id: id(5), parents: [id(3)]))
        index.add(AncestryLine(id: id(3), parents: []))
        #expect(!index.isCertain(descendant: id(6), ancestor: id(3)))
        index.add(AncestryLine(id: id(4), parents: [id(3)]))
        _ = index.finish(error: nil)
        #expect(index.isCertain(descendant: id(6), ancestor: id(3)))
    }
}
