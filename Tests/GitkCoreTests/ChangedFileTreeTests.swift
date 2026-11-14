// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct ChangedFileTreeTests {
    @Test func groupsByDirectoryAndCompressesChains() {
        let rows = ChangedFileTree.rows(paths: ["README", "src/app/main.swift", "src/app/ui/view.swift", "docs/a/b/c.md", "src/lib.swift"])
        #expect(rows.map { "\(String(repeating: " ", count: $0.depth))\($0.name)\($0.isDirectory ? "/" : "")" } == [
            "docs/a/b/",
            " c.md",
            "src/",
            " app/",
            "  ui/",
            "   view.swift",
            "  main.swift",
            " lib.swift",
            "README",
        ])
        #expect(rows.first { $0.name == "README" }?.fileIndex == 0)
        #expect(rows.first { $0.name == "lib.swift" }?.fileIndex == 4)
    }

    @Test func flatFilesStayAtTheTop() {
        #expect(ChangedFileTree.rows(paths: ["b", "a"]).map(\.name) == ["a", "b"])
        #expect(ChangedFileTree.rows(paths: []).isEmpty)
    }
}
