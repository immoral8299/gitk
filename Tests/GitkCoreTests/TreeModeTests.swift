// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

/// Tree mode of the Changed Files section (task 13.3): the `ls-tree` outline
/// and the blob text.
@Suite struct TreeModeTests {
    private func entry(_ path: String, type: String = "blob") -> TreeEntry {
        TreeEntry(mode: "100644", type: type, objectID: ObjectID(hex: String(repeating: "ab", count: 20))!, path: path)
    }

    /// file-list "Expand a directory": directories start closed; opening `src/`
    /// shows its children indented beneath it.
    @Test func directoriesStartClosedAndExpand() {
        var outline = TreeOutline(entries: [
            entry("README"), entry("src/lib/a.c"), entry("src/lib/b.c"), entry("src/main.c"), entry("zed.txt"),
        ])
        #expect(outline.rows.map(\.path) == ["README", "src/", "zed.txt"])
        #expect(outline.rows.allSatisfy { $0.depth == 0 && !$0.isOpen })

        outline.toggle("src/")
        #expect(outline.rows.map(\.path) == ["README", "src/", "src/lib/", "src/main.c", "zed.txt"])
        #expect(outline.rows.map(\.depth) == [0, 0, 1, 1, 0])
        #expect(outline.rows[1].isOpen)

        outline.toggle("src/lib/")
        #expect(outline.rows.map(\.name) == ["README", "src/", "lib/", "a.c", "b.c", "main.c", "zed.txt"])
        #expect(outline.rows.map(\.depth) == [0, 0, 1, 2, 2, 1, 0])

        // Closing the parent hides the open child's rows again.
        outline.toggle("src/")
        #expect(outline.rows.map(\.path) == ["README", "src/", "zed.txt"])
        // Files and unknown paths do not toggle.
        outline.toggle("README")
        outline.toggle("nope/")
        #expect(outline.rows.count == 3)
    }

    @Test func nonBlobEntriesAreSkippedAndRevealOpensParents() {
        var outline = TreeOutline(entries: [entry("sub", type: "commit"), entry("d/e/f.txt")])
        #expect(outline.rows.map(\.path) == ["d/"])
        outline.reveal("d/e/f.txt")
        #expect(outline.rows.map(\.path) == ["d/", "d/e/", "d/e/f.txt"])
        #expect(outline.objectID(ofFile: "d/e/f.txt") != nil)
    }

    private func git(_ runner: GitRunner, _ args: [String]) async throws {
        _ = try await runner.run(["-c", "user.name=T", "-c", "user.email=t@example.com"] + args)
    }

    /// diff-viewer "View a file at a revision": the outline of a real commit and
    /// the blob text, decoded with the `encoding` attribute of its path.
    @Test func loadsTreeAndDecodesBlob() async throws {
        let repo = try FixtureRepo.makeCopy("encodings")
        let runner = GitRunner(cwd: repo)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("src/lib"), withIntermediateDirectories: true)
        try "int a;\n".write(to: repo.appendingPathComponent("src/lib/a.c"), atomically: true, encoding: .utf8)
        try "int m;\n".write(to: repo.appendingPathComponent("src/main.c"), atomically: true, encoding: .utf8)
        try await git(runner, ["add", "src"])
        try await git(runner, ["commit", "-q", "-m", "add src"])
        let head = try #require(ObjectID(hex: String(decoding: try await runner.run(["rev-parse", "HEAD"]).stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)))

        var outline = try await TreeOutline.load(id: head, runner: runner)
        #expect(outline.rows.map(\.path).contains("sjis.txt"))
        #expect(outline.rows.contains { $0.path == "src/" && !$0.isOpen })
        #expect(!outline.rows.contains { $0.path == "src/main.c" })
        outline.toggle("src/")
        let main = try #require(outline.rows.first { $0.path == "src/main.c" })
        #expect(main.depth == 1)

        let attributes = GitAttributes(runner: runner)
        let c = try await TreeOutline.blobText(try #require(main.objectID), path: "src/main.c", runner: runner,
                                               attributes: attributes, guiEncoding: "utf-8", perFileAttrs: false)
        #expect(c == "int m;")

        let sjis = try #require(outline.rows.first { $0.path == "sjis.txt" })
        let text = try await TreeOutline.blobText(try #require(sjis.objectID), path: "sjis.txt", runner: runner,
                                                  attributes: attributes, guiEncoding: "utf-8", perFileAttrs: true)
        #expect(text.hasPrefix("日本語のテキスト"))
    }
}
