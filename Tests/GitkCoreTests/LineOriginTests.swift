// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct LineOriginTests {
    @Test func normalHunkCoordinates() {
        let lines = [" context", "-old", "+new", " after"]
        #expect(LineOrigin.blameSpec(header: "@@ -10,3 +20,3 @@", lines: lines, lineIndex: 1)
                == LineOrigin.BlameSpec(parentIndex: 1, line: 11))
        #expect(LineOrigin.blameSpec(header: "@@ -10,3 +20,3 @@", lines: lines, lineIndex: 2)
                == LineOrigin.BlameSpec(parentIndex: 0, line: 21))
        #expect(LineOrigin.blameSpec(header: "@@ -10,3 +20,3 @@", lines: lines, lineIndex: 3)
                == LineOrigin.BlameSpec(parentIndex: 1, line: 12))
    }

    @Test func combinedHunkChoosesRemovedParent() {
        #expect(LineOrigin.blameSpec(header: "@@@ -4,2 -8,2 +3,3 @@@", lines: ["  common", " -removed"], lineIndex: 1)
                == LineOrigin.BlameSpec(parentIndex: 2, line: 9))
    }

    @Test func parsesBlameOutputAndIndexSentinel() {
        let id = AncestryIndexBuildTests.oid(42)
        let text = "\(id.hex) 7 9 1\nauthor Alice\nfilename path with spaces.txt\n\ttext\n"
        #expect(LineOrigin.parseBlame(Data(text.utf8)) == .init(commitID: id, line: 7, path: "path with spaces.txt"))
        #expect(LineOrigin.parseBlame(Data("bad output".utf8)) == nil)
        let zero = String(repeating: "0", count: 40)
        #expect(LineOrigin.parseBlame(Data("\(zero) 1 1\nfilename f\n".utf8))?.commitID == ObjectID.localStaged(hashLength: 40))
    }

    @Test func headerAndNonDiffLinesBlameTheCurrentCommit() {
        let diff = ["diff --git a/f b/f", "@@ -10,3 +20,3 @@", " context", "-old", "+new", "\\ No newline at end of file"]
        #expect(LineOrigin.blameSpec(diffLines: diff, at: 1) == .init(parentIndex: 0, line: 20))
        #expect(LineOrigin.blameSpec(diffLines: diff, at: 5) == .init(parentIndex: 0, line: 20))
        #expect(LineOrigin.blameSpec(diffLines: diff, at: 0) == nil)
        #expect(LineOrigin.blameSpec(header: "@@ nonsense", lines: [" x"], lineIndex: 0) == nil)
    }

    @Test func wholeDiffLookupMatchesHunkLookup() {
        let diff = ["--- a/f", "+++ b/f", "@@ -10,3 +20,3 @@", " context", "-old", "+new", " after",
                    "@@ -50 +60 @@", "-gone", " kept"]
        #expect(LineOrigin.blameSpec(diffLines: diff, at: 3) == .init(parentIndex: 1, line: 10))
        #expect(LineOrigin.blameSpec(diffLines: diff, at: 5) == .init(parentIndex: 0, line: 21))
        #expect(LineOrigin.blameSpec(diffLines: diff, at: 6) == .init(parentIndex: 1, line: 12))
        #expect(LineOrigin.blameSpec(diffLines: diff, at: 9) == .init(parentIndex: 1, line: 51))
    }

    @Test func findsNewFileLineInDiff() {
        let diff = ["@@ -10,3 +20,3 @@", " context", "-old", "+new", " after", "@@@ -1,2 -1,2 +5,3 @@@", "  a", "- b", "++c"]
        #expect(LineOrigin.diffLineIndex(ofNewLine: 21, in: diff, range: 0..<diff.count) == 3)
        #expect(LineOrigin.diffLineIndex(ofNewLine: 22, in: diff, range: 0..<diff.count) == 4)
        #expect(LineOrigin.diffLineIndex(ofNewLine: 6, in: diff, range: 0..<diff.count) == 8)
        #expect(LineOrigin.diffLineIndex(ofNewLine: 99, in: diff, range: 0..<diff.count) == nil)
    }

    @Test func guiBlameArguments() {
        #expect(LineOrigin.guiArguments(revision: "abc", path: "f", line: 7) == ["gui", "blame", "--line=7", "abc", "f"])
        #expect(LineOrigin.guiArguments(revision: nil, path: "f", line: 1) == ["gui", "blame", "f"])
    }
}
