// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct RawLogParserTests {
    /// Runs git in `repo` and returns raw stdout. Test-only helper; production
    /// code goes through GitRunner (task 2.2).
    private func git(_ repo: URL, _ args: String...) throws -> Data { try gitArgs(repo, args) }

    private func gitArgs(_ repo: URL, _ args: [String]) throws -> Data {
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

    private func records(_ repo: URL, _ extra: String...) throws -> [ParsedCommit] {
        let out = try gitArgs(repo, ["log", "--no-color", "-z", "--pretty=raw", "--show-notes",
                                 "--parents", "--boundary"] + extra)
        return try out.split(separator: 0, omittingEmptySubsequences: true)
            .map { try RawLogParser.parse(record: Data($0), hashLength: 40) }
    }

    private func hex(_ repo: URL, _ rev: String) throws -> String {
        String(decoding: try git(repo, "rev-parse", rev), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func mergeSimpleHasTwoParentsAndMetadata() throws {
        let repo = try FixtureRepo.make("merge-simple")
        let commits = try records(repo)
        #expect(commits.count == 7)
        let head = commits[1]  // HEAD~1 is the merge; HEAD is m4
        #expect(head.id.hex.hasPrefix("8c4a517"))
        #expect(head.parents.count == 2)
        #expect(head.parents.map(\.hex) == [try hex(repo, "HEAD~1^1"), try hex(repo, "HEAD~1^2")])
        #expect(head.tree.hex == (try hex(repo, "HEAD~1^{tree}")))
        #expect(head.isBoundary == false)
        #expect(head.side == nil)
        #expect(head.authorNameString() == "Alice Author")
        #expect(String(decoding: head.authorEmail, as: UTF8.self) == "alice@example.com")
        #expect(head.committerNameString() == "Carol Committer")
        #expect(head.authorTZ == "+0000")
        #expect(head.authorTZOffset == 0)
        #expect(head.authorEpoch >= 1_577_836_800)
        #expect(head.encoding == nil)
        #expect(!head.headlineString().isEmpty)
        #expect(head.headlineString() == head.messageString().split(separator: "\n").first.map(String.init))
        #expect(head.notes == nil)
        // The root has no parents.
        #expect(commits.last?.parents.isEmpty == true)
    }

    @Test func tagsNotesExtractsNotesSeparately() throws {
        let repo = try FixtureRepo.make("tags-notes")
        let commits = try records(repo)
        #expect(commits.count == 8)
        let withNotes = commits.filter { $0.notes != nil }
        #expect(withNotes.count == 1)
        let c = try #require(withNotes.first)
        #expect(c.headlineString() == "commit 5")
        #expect(c.messageString() == "commit 5")
        #expect(c.notesString() == "Notes:\nA note on commit 5")
        #expect(c.parents.count == 1)
    }

    @Test func rangeMarksBoundaryCommit() throws {
        let repo = try FixtureRepo.make("linear")
        let commits = try records(repo, "HEAD~3..HEAD")
        #expect(commits.count == 4)
        #expect(commits.prefix(3).allSatisfy { !$0.isBoundary })
        let boundary = commits[3]
        #expect(boundary.isBoundary)
        #expect(boundary.id.hex == (try hex(repo, "HEAD~3")))
        // Git still prints the boundary's parent; gitk ignores it.
        #expect(boundary.listedParents.isEmpty)
        #expect(commits[0].listedParents.count == 1)
    }

    @Test func leftRightSetsSide() throws {
        let repo = try FixtureRepo.make("merge-simple")
        let commits = try records(repo, "--left-right", "HEAD~1^1...HEAD~1^2")
        let lefts = commits.filter { $0.side == .left }
        let rights = commits.filter { $0.side == .right }
        #expect(!lefts.isEmpty)
        #expect(!rights.isEmpty)
        #expect(lefts.count + rights.count + commits.filter(\.isBoundary).count == commits.count)
        #expect(rights.contains { $0.id.hex == (try? hex(repo, "HEAD~1^2")) })
        #expect(lefts.contains { $0.id.hex == (try? hex(repo, "HEAD~1^1")) })
    }

    @Test func latin1CommitKeepsRawBytesAndDecodesLater() throws {
        let repo = try FixtureRepo.make("encodings")
        let commits = try records(repo, "--encoding=ISO-8859-1")
        let c = try #require(commits.first { $0.encoding != nil })
        #expect(c.encoding?.lowercased() == "iso-8859-1")
        #expect(c.authorNameString() == "José Muñoz")
        // The raw bytes are Latin-1, not UTF-8.
        #expect(c.authorName.contains(0xE9))
    }

    @Test func gpgsigAndMergetagContinuationLinesAreSkipped() throws {
        let id = String(repeating: "a", count: 40)
        let parent = String(repeating: "b", count: 40)
        let tree = String(repeating: "c", count: 40)
        let text = [
            "commit \(id) \(parent)",
            "tree \(tree)",
            "parent \(parent)",
            "author A U Thor <a@example.com> 1700000000 -0530",
            "committer C O Mitter <c@example.com> 1700000001 +0100",
            "gpgsig -----BEGIN PGP SIGNATURE-----",
            " author fake <x@y> 1 +0000",
            " ",
            " abcd",
            " -----END PGP SIGNATURE-----",
            "encoding ISO-8859-1",
            "",
            "    Subject line  ",
            "    ",
            "    body line",
            "",
        ].joined(separator: "\n")
        let c = try RawLogParser.parse(record: Data(text.utf8), hashLength: 40)
        #expect(c.authorNameString() == "A U Thor")
        #expect(c.authorEpoch == 1_700_000_000)
        #expect(c.authorTZOffset == -(5 * 3600 + 1800))
        #expect(c.committerTZOffset == 3600)
        #expect(c.encoding == "ISO-8859-1")
        #expect(c.headlineString() == "Subject line")
        #expect(c.messageString() == "Subject line  \n\nbody line")
        #expect(c.parents.map(\.hex) == [parent])
    }

    @Test func malformedRecordsThrow() {
        #expect(throws: RawLogParseError.emptyRecord) { try RawLogParser.parse(record: Data()) }
        #expect(throws: RawLogParseError.self) { try RawLogParser.parse(record: Data("garbage\nlines".utf8)) }
        #expect(throws: RawLogParseError.self) { try RawLogParser.parse(record: Data("commit zz\n".utf8)) }
        let id = String(repeating: "a", count: 40)
        #expect(throws: RawLogParseError.self) {
            try RawLogParser.parse(record: Data("commit \(id)\ntree \(id)\nauthor x\n\n    m\n".utf8))
        }
        #expect(throws: RawLogParseError.missingHeader("tree")) {
            try RawLogParser.parse(record: Data("commit \(id)\n\n    m\n".utf8))
        }
        // Wrong hash length for the repository.
        #expect(throws: RawLogParseError.self) {
            try RawLogParser.parse(record: Data("commit \(id)\n".utf8), hashLength: 64)
        }
    }

    @Test func sha256Records() throws {
        let repo = try FixtureRepo.make("sha256")
        let out = try git(repo, "log", "--no-color", "-z", "--pretty=raw", "--parents")
        let commits = try out.split(separator: 0, omittingEmptySubsequences: true)
            .map { try RawLogParser.parse(record: Data($0), hashLength: 64) }
        #expect(commits.count == 5)
        #expect(commits[0].id.hexLength == 64)
    }
}
