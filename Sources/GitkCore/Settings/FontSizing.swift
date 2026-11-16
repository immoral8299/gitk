// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// The font size arithmetic of the ⌘-plus and ⌘-minus commands.
public enum FontSizing {
    /// Port of the size arithmetic of gitk proc `incrfont` (gitk/gitk 8873–8901):
    /// the size grows by `delta` and never drops below 1. The preferences spec
    /// applies it to all three fonts; gitk's `incrfont` leaves its UI font alone.
    public static func incremented(_ font: FontSpec, by delta: Int) -> FontSpec {
        var result = font
        result.pointSize = max(1, font.pointSize + Double(delta))
        return result
    }

    public static func incremented(_ settings: Settings, by delta: Int) -> Settings {
        var result = settings
        result.mainFont = incremented(settings.mainFont, by: delta)
        result.textFont = incremented(settings.textFont, by: delta)
        result.uiFont = incremented(settings.uiFont, by: delta)
        return result
    }

    /// The ⌘-0 counterpart of `incremented`: all three fonts go back to the
    /// built-in default size. Family, weight and slant are kept, so a font
    /// chosen in Preferences survives the reset.
    public static func resetSizes(_ settings: Settings) -> Settings {
        let defaults = Settings()
        var result = settings
        result.mainFont.pointSize = defaults.mainFont.pointSize
        result.textFont.pointSize = defaults.textFont.pointSize
        result.uiFont.pointSize = defaults.uiFont.pointSize
        return result
    }
}
