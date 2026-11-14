// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct DiffDocumentTests {
    private func document(_ text: String) -> DiffDocument {
        var document = DiffDocument()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
            document.append(Data(line.utf8))
        }
        return document
    }

    private let twoFiles = """
        diff --git a/a.txt b/a.txt
        index 1111111..2222222 100644
        --- a/a.txt
        +++ b/a.txt
        @@ -1,2 +1,2 @@
         keep
        -old
        +new
        diff --git a/b.txt b/c.txt
        similarity index 90%
        rename from b.txt
        rename to c.txt
        @@ -1 +1 @@
        -x
        +y

        """

    @Test func sectionsAndOffsets() {
        let doc = document(twoFiles)
        #expect(doc.lines.count == 15)
        #expect(doc.sections.map(\.startLine) == [0, 8])
        #expect(doc.sections[1].oldPath == "b.txt")
        #expect(doc.sections[1].newPath == "c.txt")
        #expect(doc.fileSection(at: 3) == 0)
        #expect(doc.fileSection(at: 12) == 1)
        #expect(doc.fileJump(from: 2, forward: true) == 8)
        #expect(doc.fileJump(from: 10, forward: false) == 8)
        #expect(doc.fileJump(from: 8, forward: false) == 0)
        #expect(doc.fileJump(from: 9, forward: true) == nil)
    }

    @Test func modesHideTheOtherSide() {
        let doc = document(twoFiles)
        let all = doc.visibleIndices(mode: .diff)
        let old = doc.visibleIndices(mode: .old)
        let new = doc.visibleIndices(mode: .new)
        #expect(all.count == doc.lines.count)
        #expect(!old.contains(7) && old.contains(6))
        #expect(!new.contains(6) && new.contains(7))
    }

    /// diff-viewer "Large diff": lines past the limit are counted, not shown.
    @Test func lineLimit() {
        var doc = document(twoFiles)
        doc.lineLimit = 5
        #expect(doc.visibleIndices(mode: .diff).count == 5)
        #expect(doc.hiddenLineCount == doc.lines.count - 5)
    }
}
