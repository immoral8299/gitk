// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

/// diff-viewer "Next file": `f` and `b` move between file separators.
@Suite struct FileJumpTests {
    private let starts = [0, 100, 250]

    @Test func nextFile() {
        #expect(DiffDocument.fileJump(from: 0, sectionStarts: starts, forward: true) == 100)
        #expect(DiffDocument.fileJump(from: 120, sectionStarts: starts, forward: true) == 250)
        #expect(DiffDocument.fileJump(from: 250, sectionStarts: starts, forward: true) == nil)
    }

    @Test func previousFile() {
        // At a file start, b goes to the previous file; inside a file, to its start.
        #expect(DiffDocument.fileJump(from: 100, sectionStarts: starts, forward: false) == 0)
        #expect(DiffDocument.fileJump(from: 180, sectionStarts: starts, forward: false) == 100)
        #expect(DiffDocument.fileJump(from: 0, sectionStarts: starts, forward: false) == 0)
        #expect(DiffDocument.fileJump(from: 30, sectionStarts: [], forward: false) == 0)
    }
}
