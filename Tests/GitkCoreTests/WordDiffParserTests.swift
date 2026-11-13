// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct WordDiffParserTests {
    private func d(_ s: String) -> Data { Data(s.utf8) }

    /// Runs the full chain DiffParser -> WordDiffParser and returns completed display lines.
    private func wordLines(_ output: Data) -> [[WordRun]] {
        var diff = DiffParser()
        var words = WordDiffParser()
        var result: [[WordRun]] = []
        for raw in output.split(separator: 0x0A, omittingEmptySubsequences: true) {
            if case .line(let runs) = words.feed(diff.parse(line: Data(raw))) { result.append(runs) }
        }
        if let rest = words.finish() { result.append(rest) }
        return result
    }

    @Test func additionsRemovalsAndNewlines() {
        var p = WordDiffParser()
        #expect(p.feed(rawLine: d(" one ")) == .pending)
        #expect(p.feed(rawLine: d("-two")) == .pending)
        #expect(p.feed(rawLine: d("+2")) == .pending)
        #expect(p.feed(rawLine: d("  three ")) == .pending)
        #expect(p.feed(rawLine: d("+four")) == .pending)
        #expect(p.feed(rawLine: d("~")) == .line([
            .same(d("one ")), .removed(d("two")), .added(d("2")), .same(d(" three ")), .added(d("four")),
        ]))
        // Empty line: a lone newline.
        #expect(p.feed(rawLine: d("~")) == .line([]))
        #expect(p.finish() == nil)
    }

    @Test func headersPassThrough() {
        var diff = DiffParser()
        var words = WordDiffParser()
        let header = diff.parse(line: d("diff --git a/f b/f"))
        #expect(words.feed(header) == .passthrough(header))
        let hunk = diff.parse(line: d("@@ -1 +1 @@"))
        #expect(words.feed(hunk) == .passthrough(hunk))
        #expect(words.feed(diff.parse(line: d("+x"))) == .pending)
        #expect(words.finish() == [.added(d("x"))])
        #expect(words.finish() == nil)
    }

    @Test func unterminatedLineIsFlushedByFinish() {
        var p = WordDiffParser()
        _ = p.feed(rawLine: d(" last"))
        #expect(p.finish() == [.same(d("last"))])
    }

    @Test func realPorcelainOutput() throws {
        let repo = try FixtureRepo.makeCopy("linear")
        let file = repo.appendingPathComponent("w.txt")
        try "one two three\n\nlast\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try runGit(repo, ["add", "w.txt"])
        let commit = ["-c", "user.name=T", "-c", "user.email=t@example.com", "commit", "-q"]
        _ = try runGit(repo, commit + ["-m", "w1"])
        try "one 2 three four\n\n\nlast".write(to: file, atomically: true, encoding: .utf8)
        _ = try runGit(repo, commit + ["-a", "-m", "w2"])
        let out = try runGit(repo, ["diff-tree", "-r", "-p", "--word-diff=porcelain", "--no-commit-id", "-U3", "HEAD"])
        let lines = wordLines(out)
        #expect(lines.count == 4)
        #expect(lines[0] == [.same(d("one ")), .removed(d("two")), .added(d("2")), .same(d(" three ")), .added(d("four"))])
        #expect(lines[1] == [.same(d(""))])
        #expect(lines[2] == [])
        #expect(lines[3] == [.same(d("last"))])
    }
}
