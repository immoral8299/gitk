// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

/// The Changed Files list comes from the streamed diff's file sections, so it
/// matches the diff pane (renames included).
@Suite struct FileListPatchTests {
    private func diff(_ fixture: String, _ rev: String) async throws -> DiffDocument {
        let repo = try FixtureRepo.make(fixture)
        let runner = GitRunner(cwd: repo)
        let hex = String(decoding: try await runner.run(["rev-parse", rev]).stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let id = try #require(ObjectID(hex: hex))
        var document = DiffDocument()
        let process = runner.stream(DiffCommandBuilder.blobDiff(ids: [id], options: DiffOptions(hashLength: 40)))
        for try await line in process.records(separator: 10) { document.append(line) }
        return document
    }

    /// file-list "Changed Files section" on `renames`: the rename shows both paths.
    @Test func renameEntriesAndCounts() async throws {
        let doc = try await diff("renames", "HEAD~1")
        let entries = doc.sections.map { ($0.oldPath ?? "", $0.newPath ?? "", $0.status) }
        #expect(entries.contains { $0.0 == "widget.c" && $0.1 == "gadget.c" && $0.2 == .renamed })
        #expect(doc.sections.count == doc.addedPerFile.count)
        let rename = try #require(doc.sections.firstIndex { $0.newPath == "gadget.c" })
        #expect(doc.addedPerFile[rename] == 1)
        #expect(doc.removedPerFile[rename] == 1)
    }

    @Test func deleteAndModeChange() async throws {
        let doc = try await diff("renames", "HEAD")
        let byPath = Dictionary(uniqueKeysWithValues: doc.sections.enumerated().map { ($0.element.newPath ?? $0.element.oldPath ?? "", $0.offset) })
        let old = try #require(byPath["old.txt"])
        #expect(doc.sections[old].status == .deleted)
        #expect(doc.removedPerFile[old] == 1)
        #expect(doc.totalAdded == doc.addedPerFile.reduce(0, +))
    }

    /// file-list "Change totals": one file, +10 −4.
    @Test func totals() {
        var doc = DiffDocument()
        var text = "diff --git a/f.txt b/f.txt\nindex 1..2 100644\n--- a/f.txt\n+++ b/f.txt\n@@ -1,4 +1,10 @@\n"
        text += String(repeating: "-old\n", count: 4) + String(repeating: "+new\n", count: 10)
        for line in text.split(separator: "\n") { doc.append(Data(line.utf8)) }
        #expect(doc.sections.count == 1)
        #expect(doc.totalAdded == 10)
        #expect(doc.totalRemoved == 4)
    }
}

/// file-list "Scroll the diff": the highlighted file follows the top of the diff pane.
@Suite struct FileHighlightSyncTests {
    @Test func offsetToSection() {
        let starts = [0, 120, 480]
        #expect(DiffDocument.section(at: 0, sectionStarts: starts) == 0)
        #expect(DiffDocument.section(at: 119, sectionStarts: starts) == 0)
        #expect(DiffDocument.section(at: 120, sectionStarts: starts) == 1)
        #expect(DiffDocument.section(at: 10_000, sectionStarts: starts) == 2)
        #expect(DiffDocument.section(at: 5, sectionStarts: [10, 20]) == nil)
        #expect(DiffDocument.section(at: 5, sectionStarts: []) == nil)
    }
}
