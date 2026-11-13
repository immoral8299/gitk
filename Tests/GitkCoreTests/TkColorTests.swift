// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct TkColorTests {
    @Test func shortHexReplicatesEachDigit() throws {
        // Matches `winfo rgb . #f00` = 65535 0 0 in Tk 9.0.
        let red = try #require(TkColor.parse("#f00"))
        #expect(red == RGBA(r: 255, g: 0, b: 0))
        let mixed = try #require(TkColor.parse("#1F2"))
        #expect(mixed == RGBA(r: 0x11, g: 0xFF, b: 0x22))
        #expect(TkColor.parse("#FFF") == RGBA(r: 255, g: 255, b: 255))
    }

    @Test func sixDigitHex() throws {
        let color = try #require(TkColor.parse("#1a2B3c"))
        #expect(color == RGBA(r: 0x1A, g: 0x2B, b: 0x3C))
        #expect(color.a == 255)
    }

    @Test func nineDigitHexKeepsTopBitsOfEachComponent() throws {
        // Tk: 4657, 17764, 30871 in 16 bits, i.e. 0x12, 0x45, 0x78 once truncated.
        let color = try #require(TkColor.parse("#123456789"))
        #expect(color == RGBA(r: 0x12, g: 0x45, b: 0x78))
    }

    @Test func twelveDigitHexUsesTopByteOfEachComponent() throws {
        let color = try #require(TkColor.parse("#123456789abc"))
        #expect(color == RGBA(r: 0x12, g: 0x56, b: 0x9A))
    }

    @Test func namesResolveThroughTheTable() throws {
        #expect(TkColor.parse("LightSkyBlue") == RGBA(r: 135, g: 206, b: 250))
        #expect(TkColor.parse("light sky blue") == RGBA(r: 135, g: 206, b: 250))
        #expect(TkColor.parse("gray85") == RGBA(r: 217, g: 217, b: 217))
    }

    @Test func malformedSpecsAreRejected() {
        #expect(TkColor.parse("") == nil)
        #expect(TkColor.parse("#") == nil)
        #expect(TkColor.parse("#12") == nil)
        #expect(TkColor.parse("#12345") == nil)
        #expect(TkColor.parse("#12345678") == nil)
        #expect(TkColor.parse("#ffff") == nil)
        #expect(TkColor.parse("#ffg") == nil)
        #expect(TkColor.parse("#ff0000000000000") == nil)
        #expect(TkColor.parse("notacolour") == nil)
    }

    @Test func hexStringIsLowercaseAndRoundTrips() throws {
        #expect(TkColor.hexString(RGBA(r: 0x1A, g: 0x2B, b: 0x3C)) == "#1a2b3c")
        #expect(TkColor.hexString(RGBA(r: 0, g: 0, b: 0)) == "#000000")
        let parsed = try #require(TkColor.parse(TkColor.hexString(RGBA(r: 9, g: 128, b: 255))))
        #expect(parsed == RGBA(r: 9, g: 128, b: 255))
    }
}
