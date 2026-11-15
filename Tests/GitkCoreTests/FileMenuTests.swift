// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct FileMenuTests {
    @Test func highlightOnlyReplacesPattern() {
        #expect(FileMenu.highlightPattern(path: "lib/util.c", only: true, currentPattern: "old", currentIsTouchingPaths: true) == "lib/util.c")
    }

    @Test func highlightTooAppendsToTouchingPaths() {
        #expect(FileMenu.highlightPattern(path: "b.c", only: false, currentPattern: "a.c", currentIsTouchingPaths: true) == "a.c b.c")
    }

    @Test func highlightTooReplacesOtherTypeOrEmpty() {
        #expect(FileMenu.highlightPattern(path: "b.c", only: false, currentPattern: "a.c", currentIsTouchingPaths: false) == "b.c")
        #expect(FileMenu.highlightPattern(path: "b.c", only: false, currentPattern: "", currentIsTouchingPaths: true) == "b.c")
    }

    @Test func highlightQuotesPathsWithSpaces() {
        #expect(FileMenu.highlightPattern(path: "my dir/a.c", only: true, currentPattern: "", currentIsTouchingPaths: false) == "\"my dir/a.c\"")
    }

    @Test func blameArgumentsUseParentAndCdup() throws {
        let parent = try #require(ObjectID(hex: String(repeating: "ab", count: 20)))
        #expect(FileMenu.blameArguments(base: parent, path: "a.c", cdup: "../", hashLength: 40)
            == ["gui", "blame", parent.hex, "../a.c"])
        #expect(FileMenu.blameArguments(base: parent, path: "a.c", cdup: "", hashLength: 40)
            == ["gui", "blame", parent.hex, "a.c"])
    }

    @Test func blameWithoutParentOrOnLocalChangesIsRefused() {
        #expect(FileMenu.blameArguments(base: nil, path: "a.c", cdup: "", hashLength: 40) == nil)
        #expect(FileMenu.blameArguments(base: ObjectID.localUnstaged(hashLength: 40), path: "a.c", cdup: "", hashLength: 40) == nil)
        #expect(FileMenu.blameArguments(base: ObjectID.localStaged(hashLength: 40), path: "a.c", cdup: "", hashLength: 40) == nil)
    }
}
