// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

/// Very large diffs show their first 200,000 lines; the rest stays parsed and
/// is rendered on request (design D7 risk).
@Suite struct DiffTruncationTests {
    private func document(lines: Int) -> DiffDocument {
        var doc = DiffDocument()
        doc.append(Data("diff --git a/big.txt b/big.txt".utf8))
        doc.append(Data("@@ -0,0 +1,\(lines) @@".utf8))
        for n in 0..<lines { doc.append(Data("+line \(n)".utf8)) }
        return doc
    }

    @Test func defaultCap() {
        #expect(DiffDocument().lineLimit == 200_000)
    }

    @Test func linesPastTheCapAreCountedAndStillParsed() {
        var doc = document(lines: 50)
        doc.lineLimit = 20
        #expect(doc.visibleIndices(mode: .diff).count == 20)
        #expect(doc.hiddenLineCount == 32)
        // Counts and sections cover the whole diff, not just the shown part.
        #expect(doc.totalAdded == 50)
        #expect(doc.sections.count == 1)
        doc.lineLimit = Int.max
        #expect(doc.hiddenLineCount == 0)
        #expect(doc.visibleIndices(mode: .diff).count == 52)
    }
}
