// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct DiffCommandBuilderTests {
    static let n1 = ObjectID.localUnstaged(hashLength: 40)!
    static let n2 = ObjectID.localStaged(hashLength: 40)!
    static let a = ObjectID(hex: String(repeating: "a", count: 40))!
    static let b = ObjectID(hex: String(repeating: "b", count: 40))!
    static let base = ["-p", "--textconv", "--submodule", "-C", "--cc", "--no-commit-id", "-U3"]

    struct Row: Sendable, CustomTestStringConvertible {
        var name: String
        var ids: [ObjectID]
        var expected: [String]
        var testDescription: String { name }
    }

    static var rows: [Row] {
        let ign = base + ["--ignore-submodules=dirty"]
        return [
            Row(name: "single commit", ids: [a],
                expected: ["diff-tree", "-r"] + base + [a.hex]),
            Row(name: "two commits", ids: [a, b],
                expected: ["diff-tree", "-r"] + base + [a.hex, b.hex]),
            Row(name: "nullid alone", ids: [n1], expected: ["diff-files"] + base),
            Row(name: "nullid2 alone", ids: [n2],
                expected: ["diff-index", "--cached"] + ign + ["HEAD"]),
            Row(name: "nullid, commit", ids: [n1, a],
                expected: ["diff-index"] + base + ["-R", a.hex]),
            Row(name: "commit, nullid", ids: [a, n1],
                expected: ["diff-index"] + base + [a.hex]),
            Row(name: "nullid2, commit", ids: [n2, a],
                expected: ["diff-index", "--cached"] + ign + ["-R", a.hex]),
            Row(name: "commit, nullid2", ids: [a, n2],
                expected: ["diff-index", "--cached"] + ign + [a.hex]),
            Row(name: "nullid, nullid2", ids: [n1, n2],
                expected: ["diff-files"] + base + ["-R"]),
            Row(name: "nullid2, nullid", ids: [n2, n1], expected: ["diff-files"] + base),
        ]
    }

    @Test(arguments: rows)
    func combinations(row: Row) {
        #expect(DiffCommandBuilder.blobDiff(ids: row.ids, options: DiffOptions()) == row.expected)
    }

    @Test func flagVariants() {
        let o = DiffOptions(context: 10, ignoreSpace: true, wordDiff: .color,
                            logShowRoot: true, limitPaths: ["x y", "z"])
        let flags = ["-p", "--textconv", "--submodule", "-C", "--cc", "--no-commit-id", "-U10"]
        #expect(DiffCommandBuilder.blobDiff(ids: [Self.a], options: o)
                == ["diff-tree", "-r"] + flags + ["--root", Self.a.hex, "-w",
                    "--word-diff=porcelain", "--", "x y", "z"])
        // --root only on the diff-tree branch
        #expect(DiffCommandBuilder.blobDiff(ids: [Self.n1], options: o)
                == ["diff-files"] + flags + ["-w", "--word-diff=porcelain", "--", "x y", "z"])
        var m = DiffOptions()
        m.wordDiff = .markup
        #expect(DiffCommandBuilder.blobDiff(ids: [Self.a], options: m).last == "--word-diff=porcelain")
        var empty = DiffOptions()
        empty.limitPaths = []
        #expect(!DiffCommandBuilder.blobDiff(ids: [Self.a], options: empty).contains("--"))
    }

    @Test func sha256PseudoIDs() {
        let n1 = ObjectID.localUnstaged(hashLength: 64)!
        let n2 = ObjectID.localStaged(hashLength: 64)!
        let o = DiffOptions(hashLength: 64)
        #expect(DiffCommandBuilder.blobDiff(ids: [n1], options: o).first == "diff-files")
        #expect(DiffCommandBuilder.blobDiff(ids: [n2], options: o).last == "HEAD")
    }

    @Test func treeDiffFlags() {
        #expect(DiffCommandBuilder.treeDiff(ids: [Self.a], logShowRoot: true, limitPaths: ["p"])
                == ["diff-tree", "-r", "--no-commit-id", "--root", Self.a.hex, "--", "p"])
        #expect(DiffCommandBuilder.treeDiff(ids: [Self.n1]) == ["diff-files", "--no-commit-id"])
        #expect(DiffCommandBuilder.treeDiff(ids: [Self.n2])
                == ["diff-index", "--cached", "--no-commit-id", "--ignore-submodules=dirty", "HEAD"])
    }

    @Test func runsAgainstLocalChanges() async throws {
        let repo = try FixtureRepo.makeCopy("local-changes")
        let runner = GitRunner(cwd: repo)
        let unstaged = try await runner.run(
            DiffCommandBuilder.blobDiff(ids: [Self.n1], options: DiffOptions()))
        let u = String(decoding: unstaged.stdout, as: UTF8.self)
        #expect(u.contains("b.txt"))
        let staged = try await runner.run(
            DiffCommandBuilder.blobDiff(ids: [Self.n2], options: DiffOptions()))
        let s = String(decoding: staged.stdout, as: UTF8.self)
        #expect(s.contains("a.txt"))
        #expect(!s.contains("b.txt"))
    }
}
