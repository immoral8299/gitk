// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public typealias UISettings = Settings

extension Settings {
    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) -> Settings {
        SettingsStore(environment: environment).load()
    }
}
