// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// The `web_browser` setting (gitk/gitk 7284–7340, `setwlink`/`browseweb`).
public enum WebBrowser {
    /// What clicking a URL does.
    public enum Action: Equatable, Sendable {
        /// `web_browser` is empty: URLs are not links.
        case none
        /// `open` (the macOS default): the system's default browser.
        case systemDefault
        /// Any other command, run with the URL appended (gitk's `concat`).
        case command([String])
    }

    public static func action(setting: String) -> Action {
        let words = (try? TclList.split(setting)) ?? setting.split(separator: " ").map(String.init)
        guard let first = words.first else { return .none }
        return words == ["open"] || first.isEmpty ? .systemDefault : .command(words)
    }
}
