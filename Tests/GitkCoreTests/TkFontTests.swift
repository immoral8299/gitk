// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct TkFontTests {
    @Test func bracedFamily() throws {
        let f = try #require(TkFont.parse("{Lucida Grande} 9"))
        #expect(f == FontSpec(family: "Lucida Grande", pointSize: 9))
        #expect(TkFont.format(f) == "{Lucida Grande} 9")
    }

    @Test func plainFamily() {
        #expect(TkFont.parse("Monaco 9") == FontSpec(family: "Monaco", pointSize: 9))
    }

    @Test func boldStyle() throws {
        let f = try #require(TkFont.parse("{sans} 9 bold"))
        #expect(f == FontSpec(family: "sans", pointSize: 9, bold: true))
        #expect(TkFont.format(f) == "sans 9 bold")
    }

    @Test func negativeSizeIsPixels() {
        #expect(TkFont.parse("Helvetica -12")?.pointSize == 12)
    }

    @Test func missingOrZeroSizeIsTen() {
        #expect(TkFont.parse("Menlo")?.pointSize == 10)
        #expect(TkFont.parse("Menlo 0")?.pointSize == 10)
    }

    @Test func italicAndResets() throws {
        let f = try #require(TkFont.parse("Menlo 11 bold italic"))
        #expect(f.bold && f.italic)
        #expect(TkFont.format(f) == "Menlo 11 bold italic")
        let g = try #require(TkFont.parse("Menlo 11 bold normal roman bogus"))
        #expect(!g.bold && !g.italic)
    }

    @Test func malformedIsNil() {
        #expect(TkFont.parse("{Menlo 11") == nil)
        #expect(TkFont.parse("Menlo big") == nil)
    }

    @Test func roundTrip() throws {
        for s in ["Monaco 9", "{Lucida Grande} 9 bold", "x 12 italic"] {
            #expect(TkFont.format(try #require(TkFont.parse(s))) == s)
        }
    }
}
