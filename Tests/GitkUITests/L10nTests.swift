// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkUI

@Suite struct L10nTests {
    @Test func identityLookupReturnsKey() {
        #expect(L("Cancel", lookup: identityL10nLookup) == "Cancel")
    }

    @Test func argumentFreeStringKeepsPercent() {
        #expect(L("100% done", lookup: identityL10nLookup) == "100% done")
    }

    @Test func formatsArgumentsInPOSIXLocale() {
        #expect(L("%@ has %ld commits", "linear", 42, lookup: identityL10nLookup) == "linear has 42 commits")
    }

    @Test func lookupIsUsedBeforeFormatting() {
        let lookup: L10nLookup = { _ in "Fichier %@" }
        #expect(L("File %@", "a.txt", lookup: lookup) == "Fichier a.txt")
    }
}

@Suite struct L10nBundleTests {
    private func bundle(_ lproj: String) throws -> Bundle {
        let path = try #require(l10nResourceBundle.path(forResource: lproj, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func germanFileMenu() throws {
        #expect(L("File", lookup: bundleL10nLookup(try bundle("de"))) == "Datei")
    }

    @Test func untranslatedStringFallsBackToEnglish() throws {
        let key = "No such gitk string \(UUID().uuidString)"
        #expect(L(key, lookup: bundleL10nLookup(try bundle("de"))) == key)
    }

    @Test func formattedMessageInFrench() throws {
        let text = L("Reset branch %s to %s?", "main", "abc1234", lookup: bundleL10nLookup(try bundle("fr")))
        #expect(text.contains("main"))
        #expect(text.contains("abc1234"))
        #expect(!text.contains("%"))
        #expect(text != "Reset branch main to abc1234?")
    }

    @Test func tclPlaceholdersAreConvertedBeforeLookup() {
        let lookup: L10nLookup = { $0 }
        #expect(L("Reset %s to %d", "a", 3, lookup: lookup) == "Reset a to 3")
    }
}
