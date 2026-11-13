// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct TkColorTableTests {
    @Test func grayLevelsFollowTk() throws {
        let gray85 = try #require(TkColorTable.rgb(named: "gray85"))
        #expect(gray85 == (217, 217, 217))
        let gray50 = try #require(TkColorTable.rgb(named: "gray50"))
        #expect(gray50 == (127, 127, 127))
        let gray0 = try #require(TkColorTable.rgb(named: "gray0"))
        #expect(gray0 == (0, 0, 0))
        let grey100 = try #require(TkColorTable.rgb(named: "grey100"))
        #expect(grey100 == (255, 255, 255))
        let gray = try #require(TkColorTable.rgb(named: "gray"))
        let grey = try #require(TkColorTable.rgb(named: "grey"))
        #expect(gray == grey)
    }

    @Test func darkGreyMatchesX11() throws {
        let value = try #require(TkColorTable.rgb(named: "darkgrey"))
        #expect(value == (169, 169, 169))
    }

    @Test func lightSkyBlueResolves() throws {
        let value = try #require(TkColorTable.rgb(named: "LightSkyBlue"))
        #expect(value == (135, 206, 250))
    }

    @Test func lookupIgnoresCaseAndSpaces() throws {
        let canonical = try #require(TkColorTable.rgb(named: "LightSkyBlue"))
        let lower = try #require(TkColorTable.rgb(named: "lightskyblue"))
        let upper = try #require(TkColorTable.rgb(named: "LIGHTSKYBLUE"))
        let spaced = try #require(TkColorTable.rgb(named: "light sky blue"))
        #expect(lower == canonical)
        #expect(upper == canonical)
        #expect(spaced == canonical)
    }

    @Test func unknownNameIsNil() {
        #expect(TkColorTable.rgb(named: "notacolour") == nil)
        #expect(TkColorTable.rgb(named: "") == nil)
    }
}
