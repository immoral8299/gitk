// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct PathPatternsTests {
    @Test func directoryPathMatchesItselfAndChildren() {
        let p = PathPatterns(paths: ["src/net"])
        #expect(p.patterns == ["src/net", "src/net/*"])
        #expect(p.matches("src/net"))
        #expect(p.matches("src/net/a.c"))
        #expect(p.matches("src/net/a/b.c"))
        #expect(!p.matches("src/netx/a.c"))
        #expect(!p.matches("src/other/net/a.c"))
    }

    @Test func pathEndingInSlashMatchesOnlyChildren() {
        let p = PathPatterns(paths: ["src/net/"])
        #expect(p.patterns == ["src/net/*"])
        #expect(p.matches("src/net/a.c"))
        #expect(!p.matches("src/net"))
    }

    @Test func quotedPathWithSpacesMatchesOnlyThatFile() throws {
        let p = try PathPatterns(findString: "\"docs/user guide.md\"", exact: false)
        #expect(p.paths == ["docs/user guide.md"])
        #expect(p.matches("docs/user guide.md"))
        #expect(p.matches("docs/user guide.md/x"))
        #expect(!p.matches("docs/user"))
        #expect(!p.matches("docs/user guide.mdx"))
    }

    @Test func multipleWordsAreEachPatterned() throws {
        let p = try PathPatterns(findString: "a.txt 'b c'/", exact: false)
        #expect(p.paths == ["a.txt", "b c/"])
        #expect(p.matches("a.txt"))
        #expect(p.matches("b c/d"))
        #expect(!p.matches("b c"))
    }

    @Test func exactModeTreatsBackslashAsSlash() throws {
        let p = try PathPatterns(findString: "src\\net", exact: true)
        #expect(p.paths == ["src/net"])
        #expect(p.matches("src/net/a.c"))
    }

    @Test func globCharactersInPathAreMatchedLiterally() {
        let star = PathPatterns(paths: ["a*b"])
        #expect(star.matches("a*b"))
        #expect(!star.matches("aXb"))
        let question = PathPatterns(paths: ["f?.c"])
        #expect(question.matches("f?.c"))
        #expect(!question.matches("fx.c"))
        let bracket = PathPatterns(paths: ["[x]"])
        #expect(bracket.matches("[x]"))
        #expect(!bracket.matches("x"))
        let backslash = PathPatterns(paths: ["a\\b"])
        #expect(backslash.matches("a\\b"))
        #expect(!backslash.matches("ab"))
    }

    @Test func unbalancedQuoteThrows() {
        #expect(throws: ShellWords.Error.self) {
            _ = try PathPatterns(findString: "\"open", exact: false)
        }
    }

    @Test func emptyFindStringMatchesNothing() throws {
        let p = try PathPatterns(findString: "   ", exact: false)
        #expect(p.patterns.isEmpty)
        #expect(!p.matches("anything"))
    }

    @Test func starInPatternCrossesSlashes() {
        // Tcl's string match lets * match "/" too, unlike shell globs.
        let p = PathPatterns(paths: ["src"])
        #expect(p.matches("src/a/b/c/d.swift"))
    }
}
