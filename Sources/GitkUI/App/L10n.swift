// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Maps a gitk English msgid to the text shown to the user.
typealias L10nLookup = @Sendable (String) -> String

/// The lookup used until the localized resources exist (task 19.3/19.4).
let identityL10nLookup: L10nLookup = { $0 }

/// Returns the user-visible text for a gitk msgid, with `%@`/`%ld` placeholders
/// filled from `args` in the POSIX locale. Strings without arguments are
/// returned unformatted, so a literal `%` is left alone.
///
/// The msgid is gitk's English text from `[mc "..."]`, without the `&` marker.
func L(_ key: String, _ args: CVarArg..., lookup: L10nLookup = identityL10nLookup) -> String {
    // TODO(19.4): switch default lookup to Bundle.module once GitkUI has resources.
    let text = lookup(key)
    guard !args.isEmpty else { return text }
    return String(format: text, locale: Locale(identifier: "en_US_POSIX"), arguments: args)
}
