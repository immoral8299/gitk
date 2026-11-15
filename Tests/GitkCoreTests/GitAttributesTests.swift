// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct GitAttributesTests {
    /// diff-viewer "Shift-JIS file".
    @Test func shiftJISFileTextDecodes() async throws {
        let repo = try FixtureRepo.make("encodings")
        let runner = GitRunner(cwd: repo)
        let attrs = GitAttributes(runner: runner)
        #expect(await attrs.encoding(for: "sjis.txt", fallback: "utf-8").lowercased() == "shift_jis")
        #expect(await attrs.encoding(for: "notes.txt", fallback: "utf-8") == "utf-8")

        let out = try await runner.run(["diff-tree", "-p", "--root", "HEAD~1"])
        var doc = DiffDocument()
        for line in out.stdout.split(separator: 10, omittingEmptySubsequences: false) { doc.append(Data(line)) }
        let index = try #require(doc.lines.indices.first {
            if case .add = doc.lines[$0] { doc.path(ofLine: $0) == "sjis.txt" } else { false }
        })
        let text = await doc.text(ofLine: index, attributes: attrs, guiEncoding: "utf-8", perFileAttrs: true)
        #expect(text.contains("日本語のテキスト"))
        let off = await doc.text(ofLine: index, attributes: attrs, guiEncoding: "utf-8", perFileAttrs: false)
        #expect(!off.contains("日本語"))
    }

    @Test func unknownEncodingFallsBack() async throws {
        let repo = try FixtureRepo.make("encodings")
        let attrs = GitAttributes(runner: GitRunner(cwd: repo))
        let s = await attrs.decode(Data([0x41, 0xE9]), path: "notes.txt", guiEncoding: "x-bogus", perFileAttrs: true)
        #expect(s == "A\u{E9}")
    }
}
