// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing

@Suite struct FixtureRepoTests {
    /// Runs git in `repo` and returns trimmed stdout. Test-only helper; production
    /// code goes through GitRunner (task 2.2).
    private func git(_ repo: URL, _ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repo.path] + args
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func linearMatchesReadme() throws {
        let repo = try FixtureRepo.make("linear")
        #expect(try git(repo, "rev-list", "--all", "--count") == "10")
        #expect(try git(repo, "rev-parse", "HEAD") == "b7729902a3f81cc7da12ad56b4af698ee6ad444c")
    }

    @Test func makeIsCachedAndStable() throws {
        let first = try FixtureRepo.make("merge-simple")
        let second = try FixtureRepo.make("merge-simple")
        #expect(first == second)
        #expect(try git(first, "rev-parse", "HEAD") == "f27c29fa5ea3afbdb540a7475337378f2957d577")
    }

    @Test func copyIsIndependent() throws {
        let shared = try FixtureRepo.make("linear")
        let copy = try FixtureRepo.makeCopy("linear")
        #expect(copy != shared)
        try "scratch\n".write(to: copy.appendingPathComponent("scratch.txt"), atomically: true, encoding: .utf8)
        #expect(!FileManager.default.fileExists(atPath: shared.appendingPathComponent("scratch.txt").path))
        #expect(try git(copy, "rev-parse", "HEAD") == "b7729902a3f81cc7da12ad56b4af698ee6ad444c")
    }

    @Test func unknownFixtureFails() {
        #expect(throws: FixtureRepo.BuildError.self) { try FixtureRepo.make("no-such-fixture") }
    }
}
