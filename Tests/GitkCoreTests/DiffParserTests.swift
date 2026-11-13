// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

/// Test-only git runner (GitRunner arrives with task 2.2).
func runGit(_ repo: URL, _ args: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", repo.path] + args
    let stdout = Pipe()
    process.standardOutput = stdout
    try process.run()
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return data
}

func diffTree(_ fixture: String, _ rev: String, extra: [String] = []) throws -> Data {
    let repo = try FixtureRepo.make(fixture)
    return try runGit(repo, ["diff-tree", "-r", "-p", "--textconv", "--submodule", "-C", "--cc",
                             "--no-commit-id", "-U3"] + extra + [rev])
}

/// Clean merges show nothing under `--cc`, so make an "evil merge": a private copy of the
/// fixture whose merge commit (`rev`, checked out and amended) also edits `file`.
func evilMergeDiff(_ fixture: String, rev: String, file: String) throws -> Data {
    let repo = try FixtureRepo.makeCopy(fixture)
    _ = try runGit(repo, ["checkout", "-q", rev])
    let path = repo.appendingPathComponent(file)
    let old = try String(contentsOf: path, encoding: .utf8)
    try (old + "evil line\n").write(to: path, atomically: true, encoding: .utf8)
    _ = try runGit(repo, ["-c", "user.name=T", "-c", "user.email=t@example.com",
                          "commit", "-q", "--amend", "-a", "--no-edit"])
    return try runGit(repo, ["diff-tree", "-r", "-p", "--textconv", "--submodule", "-C", "--cc",
                             "--no-commit-id", "-U3", "HEAD"])
}

@Suite struct DiffParserTests {
    private func text(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    @Test func mergeSimpleCombinedDiff() throws {
        let out = try evilMergeDiff("merge-simple", rev: "HEAD~1", file: "main.txt")
        let (lines, sections) = DiffParser.parse(output: out)
        #expect(!sections.isEmpty)
        for s in sections {
            #expect(s.oldPath != nil && s.oldPath == s.newPath)
        }
        let combined = lines.compactMap { line -> [Character]? in
            if case .combined(let markers, _) = line { return markers }
            return nil
        }
        #expect(!combined.isEmpty)
        #expect(combined.allSatisfy { $0.count == 2 })
        // Section start lines point at fileHeader lines.
        for s in sections {
            if case .fileHeader = lines[s.startLine] {} else { Issue.record("section start is not a header") }
        }
    }

    @Test func octopusHasThreeMarkerColumns() throws {
        let out = try evilMergeDiff("octopus", rev: "HEAD~1", file: "b1.txt")
        let (lines, sections) = DiffParser.parse(output: out)
        #expect(!sections.isEmpty)
        let hunks = lines.filter { if case .hunkHeader(let d, _) = $0 { return text(d).hasPrefix("@@@@ ") }; return false }
        #expect(!hunks.isEmpty)
        let combined = lines.compactMap { line -> [Character]? in
            if case .combined(let markers, _) = line { return markers }
            return nil
        }
        #expect(!combined.isEmpty)
        #expect(combined.allSatisfy { $0.count == 3 })
    }

    @Test func renameShowsOldAndNewPaths() throws {
        let out = try diffTree("renames", "HEAD~1")
        let (lines, sections) = DiffParser.parse(output: out)
        let rename = sections.first { $0.status == .renamed }
        #expect(rename?.oldPath == "widget.c")
        #expect(rename?.newPath == "gadget.c")
        #expect(lines.contains { if case .add = $0 { return true }; return false })
        #expect(lines.contains { if case .remove = $0 { return true }; return false })
    }

    @Test func renamesFixtureOtherStatuses() throws {
        let repo = try FixtureRepo.make("renames")
        var all: [DiffFileSection] = []
        for rev in ["HEAD", "HEAD~1", "HEAD~2"] {
            let out = try runGit(repo, ["diff-tree", "-r", "-p", "-C", "--cc", "--no-commit-id", "-U3", "--root", rev])
            all += DiffParser.parse(output: out).sections
        }
        #expect(all.contains { $0.status == .deleted })
        #expect(all.contains { $0.status == .modeChange })
        #expect(all.contains { $0.status == .added })
    }

    // MARK: Synthetic

    private func parse(_ s: String) -> (lines: [DiffLine], sections: [DiffFileSection]) {
        DiffParser.parse(output: Data(s.utf8))
    }

    @Test func quotedPathsAreDecoded() {
        let (lines, sections) = parse("""
        diff --git "a/a\\303\\251.txt" "b/a\\303\\251.txt"
        index 1..2 100644
        --- "a/a\\303\\251.txt"
        +++ "b/a\\303\\251.txt"
        @@ -1 +1 @@
        -x
        +y
        """)
        #expect(sections.count == 1)
        #expect(sections[0].oldPath == "a\u{e9}.txt")
        #expect(sections[0].newPath == "a\u{e9}.txt")
        #expect(lines[0] == .fileHeader(old: "a\u{e9}.txt", new: "a\u{e9}.txt", status: .modified))
    }

    @Test func pathsWithSpaces() {
        let (_, sections) = parse("diff --git a/my file.txt b/my file.txt\n")
        #expect(sections[0].oldPath == "my file.txt")
    }

    @Test func classifiesBodyLines() {
        let (lines, _) = parse("""
        diff --git a/f b/f
        --- a/f
        +++ b/f
        @@ -1,3 +4,3 @@ fn
         ctx
        -old
        +new
        \\ No newline at end of file
        """)
        #expect(lines[3] == .hunkHeader(Data("@@ -1,3 +4,3 @@ fn".utf8), newStart: 4))
        #expect(lines[4] == .context(Data("ctx".utf8)))
        #expect(lines[5] == .remove(Data("old".utf8)))
        #expect(lines[6] == .add(Data("new".utf8)))
        #expect(lines[7] == .other(Data("\\ No newline at end of file".utf8)))
    }

    @Test func binaryAndNewFile() {
        let (lines, sections) = parse("""
        diff --git a/b.bin b/b.bin
        new file mode 100644
        index 0000000..1111111
        Binary files /dev/null and b/b.bin differ
        diff --git a/c.bin b/c.bin
        index 1..2 100644
        Binary files a/c.bin and b/c.bin differ
        """)
        #expect(sections.count == 2)
        #expect(sections[0].status == .added && sections[0].isBinary)
        #expect(sections[1].status == .binary)
        #expect(sections[1].startLine == 4)
        if case .binary = lines[3] {} else { Issue.record("expected .binary") }
    }

    @Test func submoduleSections() {
        let (lines, sections) = parse("""
        Submodule sub 1234abc..5678def:
          > added commit
          < removed commit
        Submodule other contains modified content
        """)
        #expect(sections.map(\.oldPath) == ["sub", "other"])
        #expect(sections.allSatisfy { $0.status == .submodule })
        #expect(lines[1] == .submodule(Data("  > added commit".utf8)))
        #expect(lines[2] == .submodule(Data("  < removed commit".utf8)))
    }

    @Test func unmergedPath() {
        let (lines, sections) = parse("* Unmerged path conflict.txt\n")
        #expect(sections[0].status == .unmerged)
        #expect(lines[0] == .fileHeader(old: "conflict.txt", new: "conflict.txt", status: .unmerged))
    }

    @Test func unknownDiffLineIsOther() {
        let (lines, sections) = parse("diff --combined f\n")
        #expect(sections.isEmpty)
        #expect(lines == [.other(Data("diff --combined f".utf8))])
    }
}
