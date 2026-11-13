// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct TreeParserTests {
    /// Runs git in `repo` and returns raw stdout bytes. Test-only helper;
    /// production code goes through GitRunner (task 2.2).
    private func gitData(_ repo: URL, _ args: [String]) throws -> Data {
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

    private func git(_ repo: URL, _ args: String...) throws -> String {
        String(decoding: try gitData(repo, args), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func bytes(_ text: String) -> Data {
        Data(text.utf8)
    }

    private let sha = "0123456789abcdef0123456789abcdef01234567"

    // MARK: - ls-tree

    @Test func lsTreeRenamesHead() throws {
        let repo = try FixtureRepo.make("renames")
        let entries = TreeParser.parseLsTree(try gitData(repo, ["ls-tree", "-r", "-z", "--full-name", "HEAD"]))
        #expect(entries.map(\.path) == ["README", "gadget.c", "tool.sh"])
        #expect(entries.map(\.mode) == ["100644", "100644", "100755"])
        #expect(entries.allSatisfy { $0.type == "blob" })
        #expect(entries[1].objectID == ObjectID(hex: "552d6e002751566aa1fcc9006c990d9fa7b3c465"))
        #expect(entries[2].objectID == ObjectID(hex: "4163036efa65bd4a469e752267498f01ea36a55c"))
    }

    @Test func lsTreeLinearHeadMatchesGit() throws {
        let repo = try FixtureRepo.make("linear")
        let entries = TreeParser.parseLsTree(try gitData(repo, ["ls-tree", "-r", "-z", "--full-name", "HEAD"]))
        #expect(entries.count == 11)
        #expect(entries.first?.path == "f1.txt")
        #expect(entries.last?.path == "file.txt")
        #expect(entries.first?.objectID == ObjectID(hex: "366f17ff507eeda97ee143e1ae7ef7933e52f89b"))
        // Every object name round-trips to the hex git printed.
        let plain = try git(repo, "ls-tree", "-r", "HEAD")
        let fromGit = plain.split(separator: "\n").map { line -> String in
            String(line.split(separator: "\t")[0].split(separator: " ")[2])
        }
        #expect(entries.map { $0.objectID.hex } == fromGit)
    }

    @Test func lsTreeKeepsUnquotedPaths() {
        // With -z git never C-quotes, so tabs/newlines/quotes come through
        // as-is after the first TAB.
        let data = bytes("100644 blob \(sha)\ta\tb \"c\"\nd.txt\u{0}")
        let entries = TreeParser.parseLsTree(data)
        #expect(entries == [TreeEntry(mode: "100644", type: "blob",
                                      objectID: ObjectID(hex: sha)!,
                                      path: "a\tb \"c\"\nd.txt")])
    }

    @Test func lsTreeReportsTreeAndCommitTypes() {
        let commit = "fedcba9876543210fedcba9876543210fedcba98"
        let data = bytes("040000 tree \(sha)\tdir\u{0}160000 commit \(commit)\tsub\u{0}")
        let entries = TreeParser.parseLsTree(data)
        #expect(entries.map(\.type) == ["tree", "commit"])
        #expect(entries.map(\.path) == ["dir", "sub"])
        #expect(entries.map(\.mode) == ["040000", "160000"])
    }

    @Test func lsTreeSkipsMalformedRecords() {
        let data = bytes("nonsense\u{0}"
            + "100644 blob NOTHEX\tbad.txt\u{0}"
            + "100644 \(sha)\tmissing-type.txt\u{0}"
            + "100644 blob \(sha)\tgood.txt\u{0}")
        let entries = TreeParser.parseLsTree(data)
        #expect(entries.map(\.path) == ["good.txt"])
    }

    @Test func lsTreeEmptyInput() {
        #expect(TreeParser.parseLsTree(Data()).isEmpty)
    }

    // MARK: - diff-tree --name-status

    @Test func nameStatusRenameWithEdit() throws {
        let repo = try FixtureRepo.make("renames")
        let files = TreeParser.parseNameStatus(try gitData(repo, ["diff-tree", "-r", "-z", "--name-status", "-C", "--no-commit-id", "HEAD~1"]))
        #expect(files == [
            ChangedFile(status: .modified, path: "README", oldPath: nil),
            ChangedFile(status: .renamed(score: 97), path: "gadget.c", oldPath: "widget.c"),
        ])
    }

    @Test func nameStatusDeleteAndModeChange() throws {
        let repo = try FixtureRepo.make("renames")
        let files = TreeParser.parseNameStatus(try gitData(repo, ["diff-tree", "-r", "-z", "--name-status", "-C", "--no-commit-id", "HEAD"]))
        #expect(files == [
            ChangedFile(status: .modified, path: "README", oldPath: nil),
            ChangedFile(status: .deleted, path: "old.txt", oldPath: nil),
            ChangedFile(status: .modified, path: "tool.sh", oldPath: nil),
        ])
    }

    @Test func nameStatusLinearHead() throws {
        let repo = try FixtureRepo.make("linear")
        let files = TreeParser.parseNameStatus(try gitData(repo, ["diff-tree", "-r", "-z", "--name-status", "-C", "--no-commit-id", "HEAD"]))
        #expect(files == [
            ChangedFile(status: .added, path: "f10.txt", oldPath: nil),
            ChangedFile(status: .modified, path: "file.txt", oldPath: nil),
        ])
    }

    @Test func nameStatusMergeIsEmptyWithoutMOrCc() throws {
        // gitk never asks for a merge's list this way (it uses mergediff),
        // and git prints nothing for a merge without -m or --cc.
        let repo = try FixtureRepo.make("merge-simple")
        let merge = try git(repo, "rev-parse", "HEAD^")
        let files = TreeParser.parseNameStatus(try gitData(repo, ["diff-tree", "-r", "-z", "--name-status", "-C", "--no-commit-id", merge]))
        #expect(files.isEmpty)
    }

    @Test func nameStatusCopyAndTypeChangeAndUnknown() {
        let data = bytes("C075\u{0}src.c\u{0}copy.c\u{0}T\u{0}link\u{0}X\u{0}odd\u{0}")
        let files = TreeParser.parseNameStatus(data)
        #expect(files == [
            ChangedFile(status: .copied(score: 75), path: "copy.c", oldPath: "src.c"),
            ChangedFile(status: .typeChanged, path: "link", oldPath: nil),
            ChangedFile(status: .unknown, path: "odd", oldPath: nil),
        ])
    }

    @Test func nameStatusRenameKeepsSpacesInPaths() {
        let data = bytes("R100\u{0}old name.txt\u{0}new\tname.txt\u{0}U\u{0}conflict.txt\u{0}")
        let files = TreeParser.parseNameStatus(data)
        #expect(files == [
            ChangedFile(status: .renamed(score: 100), path: "new\tname.txt", oldPath: "old name.txt"),
            ChangedFile(status: .unmerged, path: "conflict.txt", oldPath: nil),
        ])
    }

    @Test func nameStatusDropsTruncatedTrailingRecord() {
        // A rename cut off before its new path, and an add with no path.
        #expect(TreeParser.parseNameStatus(bytes("A\u{0}a.txt\u{0}R090\u{0}old.txt\u{0}")).map(\.path) == ["a.txt"])
        #expect(TreeParser.parseNameStatus(bytes("A\u{0}a.txt\u{0}D\u{0}")).map(\.path) == ["a.txt"])
    }

    @Test func nameStatusEmptyInput() {
        #expect(TreeParser.parseNameStatus(Data()).isEmpty)
    }
}
