// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct ShellWordsTests {
    @Test func quotePlainWordIsUnchanged() {
        #expect(ShellWords.quote("abc") == "abc")
        #expect(ShellWords.quote("") == "")
    }

    @Test func quoteWordWithSpaceUsesDoubleQuotes() {
        #expect(ShellWords.quote("a b") == "\"a b\"")
    }

    @Test func quoteWordWithBackslashUsesSingleQuotes() {
        #expect(ShellWords.quote("a\\b") == "'a\\b'")
        #expect(ShellWords.quote("a \"b\" c") == "'a \"b\" c'")
    }

    @Test func quoteWordWithSingleQuoteEscapesDoubleQuotes() {
        #expect(ShellWords.quote("it's") == "\"it's\"")
        #expect(ShellWords.quote("it's \"x\"") == "\"it's \\\"x\\\"\"")
        #expect(ShellWords.quote("a'b \"c\"") == "\"a'b \\\"c\\\"\"")
    }

    @Test func argListJoinsQuotedWords() {
        #expect(ShellWords.argList(["a b", "c"]) == "\"a b\" c")
        #expect(ShellWords.argList([]) == "")
    }

    /// gitk adds the separator only when the text so far is non-empty, so an
    /// empty first argument is dropped from the separator count. This is a
    /// faithful port of that quirk (checked against `shellarglist` under tclsh).
    @Test func argListMatchesGitkForEmptyFirstWord() {
        #expect(ShellWords.argList(["", "x"]) == "x")
    }

    @Test func splitSimpleWords() throws {
        #expect(try ShellWords.split("a \"b c\" d") == ["a", "b c", "d"])
        #expect(try ShellWords.split("x\ty  z") == ["x", "y", "z"])
    }

    @Test func splitEmptyAndBlankInput() throws {
        #expect(try ShellWords.split("") == [])
        #expect(try ShellWords.split("   ") == [])
        #expect(try ShellWords.split("\"\"") == [""])
        #expect(try ShellWords.split("x \"\"") == ["x", ""])
    }

    @Test func splitSingleQuotesKeepSpacesLiterally() throws {
        #expect(try ShellWords.split("'single quoted'") == ["single quoted"])
        #expect(try ShellWords.split("\"x\" 'y z' w") == ["x", "y z", "w"])
    }

    @Test func splitBackslashEscapesOutsideQuotes() throws {
        #expect(try ShellWords.split("a\\ b") == ["a b"])
        #expect(try ShellWords.split("a\\\\b") == ["a\\b"])
    }

    @Test func splitBackslashEscapesInsideDoubleQuotes() throws {
        #expect(try ShellWords.split("\"a\\\"b\"") == ["a\"b"])
        #expect(try ShellWords.split("\"a\\\\b\"") == ["a\\b"])
        // Inside double quotes only the escaped character is kept, so \n is "n".
        #expect(try ShellWords.split("\"a\\nb\"") == ["anb"])
    }

    @Test func splitAdjacentQuotedAndBareParts() throws {
        #expect(try ShellWords.split("'a'\"b\"c") == ["abc"])
    }

    @Test func unterminatedDoubleQuoteThrows() {
        #expect(throws: ShellWords.Error.self) { try ShellWords.split("\"abc") }
    }

    @Test func unterminatedSingleQuoteThrows() {
        #expect(throws: ShellWords.Error.self) { try ShellWords.split("'abc") }
    }

    @Test func trailingBackslashThrows() {
        #expect(throws: ShellWords.Error.self) { try ShellWords.split("abc\\") }
    }

    @Test func errorMessagesAreGitkText() {
        do {
            _ = try ShellWords.split("'abc")
            Issue.record("expected an error")
        } catch let error as ShellWords.Error {
            #expect(error.message == "unmatched single-quote")
        } catch {
            Issue.record("unexpected error \(error)")
        }
        do {
            _ = try ShellWords.split("\"abc")
            Issue.record("expected an error")
        } catch let error as ShellWords.Error {
            #expect(error.message == "unmatched double-quote")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func dequoteReturnsWordAndEndIndex() throws {
        let plain = try ShellWords.dequote("abc def")
        #expect(plain.used == 3)
        #expect(plain.word == "abc")

        let quoted = try ShellWords.dequote("'x y' z")
        #expect(quoted.used == 5)
        #expect(quoted.word == "x y")
    }

    @Test func quoteRoundTripsThroughSplit() throws {
        let words = ["a b", "it's", "a\\b", "x \"y\" z", "plain"]
        for word in words {
            #expect(try ShellWords.split(ShellWords.quote(word)) == [word])
        }
        #expect(try ShellWords.split(ShellWords.argList(["a b", "c", "it's"])) == ["a b", "c", "it's"])
    }
}
