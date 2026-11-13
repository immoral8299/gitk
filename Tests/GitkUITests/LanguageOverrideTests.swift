// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkUI

@Suite struct LanguageOverrideTests {
    @Test func mapsLocaleNamesToLprojs() {
        #expect(LanguageOverride.lproj(forLocale: "ja_JP.UTF-8") == "ja")
        #expect(LanguageOverride.lproj(forLocale: "de_DE") == "de")
        #expect(LanguageOverride.lproj(forLocale: "pt_BR") == "pt-BR")
        #expect(LanguageOverride.lproj(forLocale: "pt_PT.UTF-8") == "pt-PT")
        #expect(LanguageOverride.lproj(forLocale: "zh_CN.UTF-8") == "zh-Hans")
        #expect(LanguageOverride.lproj(forLocale: "fr_CA@euro") == "fr")
        #expect(LanguageOverride.lproj(forLocale: "xx_YY") == nil)
    }

    @Test func overrideFromTerminal() {
        #expect(LanguageOverride.lproj(forEnvironment: ["LANG": "ja_JP.UTF-8"]) == "ja")
    }

    @Test func cLocaleIsIgnored() {
        #expect(LanguageOverride.lproj(forEnvironment: ["LANG": "C"]) == nil)
        #expect(LanguageOverride.lproj(forEnvironment: ["LANG": "POSIX"]) == nil)
        #expect(LanguageOverride.lproj(forEnvironment: [:]) == nil)
    }

    @Test func variablePrecedence() {
        let env = ["LC_ALL": "fr_FR", "LC_MESSAGES": "de_DE", "LANG": "ja_JP"]
        #expect(LanguageOverride.lproj(forEnvironment: env) == "fr")
        #expect(LanguageOverride.lproj(forEnvironment: ["LC_ALL": "", "LC_MESSAGES": "de_DE", "LANG": "ja"]) == "de")
        #expect(LanguageOverride.lproj(forEnvironment: ["LC_MESSAGES": "de_DE", "LANG": "ja"]) == "de")
    }

    @Test func applySetsVolatileAppleLanguages() throws {
        let defaults = try #require(UserDefaults(suiteName: "gitk-swift.test.\(UUID().uuidString)"))
        let lang = LanguageOverride.apply(environment: ["LANG": "es_ES.UTF-8"], defaults: defaults)
        #expect(lang == "es")
        let domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        #expect(domain["AppleLanguages"] as? [String] == ["es"])
        defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
    }

    @Test func applyDoesNothingForCLocale() throws {
        let defaults = try #require(UserDefaults(suiteName: "gitk-swift.test.\(UUID().uuidString)"))
        #expect(LanguageOverride.apply(environment: ["LANG": "C"], defaults: defaults) == nil)
    }
}
