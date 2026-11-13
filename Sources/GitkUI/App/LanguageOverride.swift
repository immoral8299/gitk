// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Lets `LC_ALL`, `LC_MESSAGES` and `LANG` choose the UI language, as Tcl
/// msgcat does for gitk.
///
/// Requirement: `apply(environment:)` must run before the first `L()` call
/// (task 9.2 calls it first thing in `main.swift`). Bundle localization reads
/// `AppleLanguages` when the bundle first resolves its preferred
/// localizations, and caches the result.
enum LanguageOverride {
    /// The lproj names the app ships (design D11).
    static let shippedLanguages: [String] = [
        "af", "bg", "ca", "de", "es", "fr", "hu", "it", "ja",
        "pt-BR", "pt-PT", "ru", "sv", "ta", "vi", "zh-Hans",
    ]

    /// The first non-empty of `LC_ALL`, `LC_MESSAGES`, `LANG`, or nil.
    /// A variable that is set but empty is skipped, as in msgcat.
    static func chosenLocale(environment: [String: String]) -> String? {
        for name in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            if let v = environment[name], !v.isEmpty { return v }
        }
        return nil
    }

    /// Maps a POSIX locale name (`ja_JP.UTF-8`, `pt_BR`, `zh_CN`, `de_DE@euro`)
    /// to a shipped lproj name. Returns nil for `C`, `POSIX`, an unset locale
    /// or a language the app does not ship.
    static func lproj(forLocale locale: String?) -> String? {
        guard var name = locale, !name.isEmpty else { return nil }
        if let at = name.firstIndex(of: "@") { name = String(name[..<at]) }
        if let dot = name.firstIndex(of: ".") { name = String(name[..<dot]) }
        if name.isEmpty || name == "C" || name == "POSIX" { return nil }
        let parts = name.split(whereSeparator: { $0 == "_" || $0 == "-" }).map(String.init)
        guard let language = parts.first?.lowercased() else { return nil }
        if parts.count >= 2 {
            let region = parts[1].uppercased()
            if language == "zh", ["CN", "SG"].contains(region) { return "zh-Hans" }
            let full = "\(language)-\(region)"
            if let hit = shippedLanguages.first(where: { $0.caseInsensitiveCompare(full) == .orderedSame }) {
                return hit
            }
        }
        if language == "zh", parts.count == 1 { return "zh-Hans" }
        return shippedLanguages.contains(language) ? language : nil
    }

    /// The lproj the environment asks for, or nil to keep the system language.
    static func lproj(forEnvironment environment: [String: String]) -> String? {
        lproj(forLocale: chosenLocale(environment: environment))
    }

    /// Sets `AppleLanguages` to the chosen language in the process's argument
    /// domain, a volatile domain: it overrides the system preference for this
    /// process only and is never written to disk. Does nothing when the
    /// environment names no shipped language. Returns the lproj applied.
    @discardableResult
    static func apply(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard let lang = lproj(forEnvironment: environment) else { return nil }
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        domain["AppleLanguages"] = [lang]
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        return lang
    }
}
