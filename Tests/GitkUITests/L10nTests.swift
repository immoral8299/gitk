// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkUI

@Suite struct L10nTests {
    @Test func identityLookupReturnsKey() {
        #expect(L("Cancel") == "Cancel")
    }

    @Test func argumentFreeStringKeepsPercent() {
        #expect(L("100% done") == "100% done")
    }

    @Test func formatsArgumentsInPOSIXLocale() {
        #expect(L("%@ has %ld commits", "linear", 42) == "linear has 42 commits")
    }

    @Test func lookupIsUsedBeforeFormatting() {
        let lookup: L10nLookup = { _ in "Fichier %@" }
        #expect(L("File %@", "a.txt", lookup: lookup) == "Fichier a.txt")
    }
}
