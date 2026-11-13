// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct TclListTests {
    @Test func bareWords() throws {
        #expect(try TclList.split("a b  c") == ["a", "b", "c"])
        #expect(try TclList.split("  leading and trailing  ") == ["leading", "and", "trailing"])
        #expect(try TclList.split("") == [])
        #expect(try TclList.split(" \t\n ") == [])
    }

    @Test func bracedFontDescription() throws {
        #expect(try TclList.split("{Lucida Grande} 9") == ["Lucida Grande", "9"])
    }

    @Test func bracedElementKeepsQuotes() throws {
        #expect(try TclList.split("{\"#00ff00\" red}") == ["\"#00ff00\" red"])
        #expect(try TclList.split("\"#00ff00\" red") == ["#00ff00", "red"])
    }

    @Test func nestedBracesStayLiteral() throws {
        #expect(try TclList.split("{a {b c}}") == ["a {b c}"])
        #expect(try TclList.split("a {b {c d}} e") == ["a", "b {c d}", "e"])
    }

    @Test func emptyBracedElement() throws {
        #expect(try TclList.split("{}") == [""])
        #expect(try TclList.split("a {} b") == ["a", "", "b"])
    }

    @Test func emptyQuotedElement() throws {
        #expect(try TclList.split("\"\" x") == ["", "x"])
    }

    @Test func backslashSpaceInBareWord() throws {
        #expect(try TclList.split("a\\ b c") == ["a b", "c"])
    }

    @Test func quotedElementWithEscapes() throws {
        #expect(try TclList.split("\"q\\\"r\"") == ["q\"r"])
        #expect(try TclList.split("\"a\\tb\\nc\"") == ["a\tb\nc"])
        #expect(try TclList.split("\"a b\" c") == ["a b", "c"])
    }

    @Test func bareBackslashSubstitutions() throws {
        #expect(try TclList.split("\\x414x") == ["A4x"])
        #expect(try TclList.split("\\x4142") == ["A42"])
        #expect(try TclList.split("\\u00e9z") == ["éz"])
        #expect(try TclList.split("\\u41") == ["A"])
        #expect(try TclList.split("\\101") == ["A"])
        #expect(try TclList.split("\\1010") == ["A0"])
        #expect(try TclList.split("\\x") == ["x"])
        #expect(try TclList.split("\\\\") == ["\\"])
        #expect(try TclList.split("a\\") == ["a\\"])
    }

    @Test func bracedContentIsLiteral() throws {
        #expect(try TclList.split("{a\\}b}") == ["a\\}b"])
        #expect(try TclList.split("{a\\\\}") == ["a\\\\"])
        #expect(try TclList.split("{a\\ b}") == ["a\\ b"])
        #expect(try TclList.split("{\\{x}") == ["\\{x"])
    }

    @Test func bracesInsideBareWordAreLiteral() throws {
        #expect(try TclList.split("a{b") == ["a{b"])
        #expect(try TclList.split("\\{x") == ["{x"])
    }

    @Test func backslashNewlineIsSpace() throws {
        #expect(try TclList.split("a\\\n b") == ["a b"])
        #expect(try TclList.split("a \\\n b") == ["a", "b"])
        #expect(try TclList.split("\"a\\\nb\"") == ["a b"])
    }

    @Test func unmatchedBraceThrows() {
        #expect(throws: TclList.Error.self) { try TclList.split("{a b") }
        #expect(throws: TclList.Error.self) { try TclList.split("a {b {c}") }
    }

    @Test func unmatchedQuoteThrows() {
        #expect(throws: TclList.Error.self) { try TclList.split("\"a b") }
    }

    @Test func textAfterClosingDelimiterThrows() {
        #expect(throws: TclList.Error.self) { try TclList.split("{a}b") }
        #expect(throws: TclList.Error.self) { try TclList.split("\"a\"b") }
    }

    @Test func errorMessageNamesTheProblem() {
        do {
            _ = try TclList.split("{a")
            Issue.record("expected an error")
        } catch let error as TclList.Error {
            #expect(error.message == "unmatched open brace in list")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func splitCommandsSplitsOnNewlineAndSemicolon() {
        let script = "set a 1\nset b 2; set c 3\n"
        #expect(TclList.splitCommands(script) == ["set a 1", "set b 2", "set c 3"])
    }

    @Test func splitCommandsKeepsBracesAndQuotesTogether() {
        let script = """
        set geometry(main) {1000x600+0+0}
        set font {Lucida Grande 9; not a separate command}
        set msg "a;b
        c"
        """
        #expect(TclList.splitCommands(script) == [
            "set geometry(main) {1000x600+0+0}",
            "set font {Lucida Grande 9; not a separate command}",
            "set msg \"a;b\nc\"",
        ])
    }

    @Test func splitCommandsSkipsComments() {
        let script = "# a comment; not a command\nset a 1\n   # indented comment\nset b 2\n"
        #expect(TclList.splitCommands(script) == ["set a 1", "set b 2"])
    }

    @Test func splitCommandsKeepsBracketedNewlines() {
        let script = "set permviews [list 1\n2]\nset x 1"
        #expect(TclList.splitCommands(script) == ["set permviews [list 1\n2]", "set x 1"])
    }

    @Test func splitCommandsRunsUnbalancedBraceToEnd() {
        let script = "set a 1\nset b {open\nset c 3"
        #expect(TclList.splitCommands(script) == ["set a 1", "set b {open\nset c 3"])
    }

    @Test func splitCommandsOfEmptyScript() {
        #expect(TclList.splitCommands("").isEmpty)
        #expect(TclList.splitCommands(" \n ;\n").isEmpty)
    }
}
