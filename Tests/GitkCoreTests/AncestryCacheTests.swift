// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct AncestryCacheTests {
    @Test @MainActor func roundTrip() async throws {
        let repo = try FixtureRepo.makeCopy("merge-simple")
        defer { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        let runner = GitRunner(cwd: repo)
        let refs = await RefParser.load(runner: runner)
        let index = AncestryIndex(refs: refs)
        _ = try await index.load(runner: runner)
        let file = repo.appendingPathComponent(".git/gitk-swift.cache")
        try AncestryCache.write(index, to: file)
        let restored = try #require(AncestryCache.read(from: file, refs: refs))
        #expect(restored.nextArc == index.nextArc)
        #expect(Set(restored.seedIDs) == Set(index.seedIDs))
        for a in 1..<(index.nextArc + 1) {
            #expect(restored.arcStart(a) == index.arcStart(a))
            #expect(restored.arcEnd(a) == index.arcEnd(a))
            #expect(restored.arcIDs(a) == index.arcIDs(a))
            #expect(restored.arcTags(a) == index.arcTags(a))
            #expect(restored.arcHeads(a) == index.arcHeads(a))
        }
        for id in index.ids {
            #expect(restored.allParents(of: id) == index.allParents(of: id))
            #expect(Set(restored.allChildren(of: id) ?? []) == Set(index.allChildren(of: id) ?? []))
        }
    }

    @Test @MainActor func corruptCacheRebuiltAndSecondLaunchUsesIt() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        defer { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        let gitDir = repo.appendingPathComponent(".git")
        let file = gitDir.appendingPathComponent(AncestryCache.filename)
        try Data("gitk-swift-cache 1\n1 8\nbroken\n".utf8).write(to: file)
        #expect(AncestryCache.read(from: file) == nil)
        let runner = GitRunner(cwd: repo)
        let refs = await RefParser.load(runner: runner)
        let first = AncestryIndex(refs: refs, gitDir: gitDir)
        _ = try await first.load(runner: runner)
        #expect(first.commitCount == 10)
        #expect(AncestryCache.read(from: file) != nil)
        let next = AncestryIndex(refs: refs, gitDir: gitDir)
        _ = try await next.load(runner: runner)
        #expect(next.commitCount == first.commitCount)
        #expect(next.generation == 0)
        #expect(next.isComplete)
    }
}
