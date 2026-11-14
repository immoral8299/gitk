// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct PatchIDCompareTests {
    @Test func cherryPickedSeriesHaveEquivalentPatches() async throws {
        let repo = try FixtureRepo.makeCopy("linear")
        defer { try? FileManager.default.removeItem(at: repo.deletingLastPathComponent()) }
        let runner = GitRunner(cwd: repo)
        func resolve(_ rev: String) async throws -> ObjectID {
            let output = try await runner.run(["rev-parse", rev])
            return try #require(ObjectID(hex: String(decoding: output.stdout, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        let original = try await resolve("HEAD")
        _ = try await runner.run(["checkout", "-b", "picked", "HEAD~2"])
        _ = try await runner.run(["cherry-pick", original.hex + "~1", original.hex])
        let picked = try await resolve("HEAD")
        let result = try await PatchIDCompare.compare(original, with: picked, runner: runner)
        #expect(result.equivalent.count == 2)
        #expect(result.unmatchedLeft.isEmpty)
        #expect(result.unmatchedRight.isEmpty)
        try Data("different\n".utf8).write(to: repo.appendingPathComponent("extra"))
        _ = try await runner.run(["add", "extra"])
        _ = try await runner.run(["commit", "-m", "extra"])
        let extra = try await resolve("HEAD")
        let changed = try await PatchIDCompare.compare(original, with: extra, runner: runner)
        #expect(changed.unmatchedRight == [extra])
        #expect(changed.unmatchedLeft.isEmpty)
    }
}
