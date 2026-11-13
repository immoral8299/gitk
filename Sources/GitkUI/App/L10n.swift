// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import PoConvert

/// Maps a converted msgid (Foundation placeholders, `%1$@`/`%2$ld`) to the
/// text shown to the user.
typealias L10nLookup = @Sendable (String) -> String

/// Looks a converted key up in `bundle`'s `Localizable` table. A key with no
/// translation (in the chosen language, or at all) returns the key itself,
/// which is gitk's English text (design D11).
func bundleL10nLookup(_ bundle: Bundle) -> L10nLookup {
    { key in bundle.localizedString(forKey: key, value: key, table: "Localizable") }
}

/// The GitkUI resource bundle (the per-language `.lproj` tables).
let l10nResourceBundle: Bundle = Bundle.module

/// The default lookup: the GitkUI resource bundle, in the language chosen by
/// the system or by `LanguageOverride`.
let defaultL10nLookup: L10nLookup = bundleL10nLookup(l10nResourceBundle)

/// Kept for tests that want the untranslated English text.
let identityL10nLookup: L10nLookup = { $0 }

/// Caches `PoConverter.convertPlaceholders` results, since `L()` is called for
/// every label and the same keys recur.
private final class ConvertedKeyCache: @unchecked Sendable {
    // Safe: every access to `table` happens while holding `lock`.
    private let lock = NSLock()
    private var table: [String: String] = [:]

    func converted(_ key: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        if let hit = table[key] { return hit }
        let value = PoConverter.convertPlaceholders(key)
        table[key] = value
        return value
    }
}

private let convertedKeys = ConvertedKeyCache()

/// Returns the user-visible text for a gitk msgid.
///
/// `key` is gitk's English text from `[mc "..."]`, without the `&` marker and
/// with Tcl placeholders (`%s`, `%d`, `%1$s`) exactly as gitk writes them. It is
/// converted like the `.po` catalogs were, looked up, and then formatted in the
/// POSIX locale with `args` (`String` for `%s`, `Int` for `%d`). Strings with no
/// arguments are returned unformatted, so a literal `%` is left alone.
func L(_ key: String, _ args: CVarArg..., lookup: L10nLookup = defaultL10nLookup) -> String {
    let text = lookup(convertedKeys.converted(key))
    guard !args.isEmpty else { return text }
    return String(format: text, locale: Locale(identifier: "en_US_POSIX"), arguments: args)
}
