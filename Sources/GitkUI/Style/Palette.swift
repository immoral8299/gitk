// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Resolves gitk colour settings to `NSColor`.
///
/// gitk's defaults assume a white Tk window and saturated primaries. While a
/// setting still has gitk's default value, the app's own theme is used instead:
/// a pastel palette with light and dark variants that follows the system
/// appearance. A colour set in the settings (Preferences or `settings.json`) is
/// used exactly, so a user theme always wins (see docs/architecture.md).
@MainActor
enum Palette {
    /// Parses a Tk colour; `.textColor` for an unparseable value.
    static func tk(_ value: String) -> NSColor {
        guard let rgba = TkColor.parse(value) else { return .textColor }
        return NSColor(srgbRed: CGFloat(rgba.r) / 255, green: CGFloat(rgba.g) / 255,
                       blue: CGFloat(rgba.b) / 255, alpha: CGFloat(rgba.a) / 255)
    }

    private static let defaults = Settings()

    private static func isDefault(_ value: String, _ gitkDefault: String) -> Bool {
        value.caseInsensitiveCompare(gitkDefault) == .orderedSame
    }

    private static func resolve(_ value: String, gitkDefault: String, _ themed: NSColor) -> NSColor {
        isDefault(value, gitkDefault) ? themed : tk(value)
    }

    /// Entry `index` of a colour list; the theme's list while the setting is gitk's.
    private static func list(_ values: [String], gitkDefault: [String], themed: [NSColor], _ index: Int) -> NSColor {
        if values == gitkDefault { return themed[index % themed.count] }
        guard !values.isEmpty else { return .textColor }
        return tk(values[index % values.count])
    }

    // MARK: Text and panes

    static func foreground(_ s: Settings) -> NSColor { resolve(s.fgColor, gitkDefault: defaults.fgColor, .textColor) }
    static func background(_ s: Settings) -> NSColor { resolve(s.bgColor, gitkDefault: defaults.bgColor, .textBackgroundColor) }
    static func link(_ s: Settings) -> NSColor { resolve(s.linkFgColor, gitkDefault: defaults.linkFgColor, Theme.blue) }
    /// `foundbgcolor`: find matches in the list and text.
    static func found(_ s: Settings) -> NSColor {
        resolve(s.foundBgColor, gitkDefault: defaults.foundBgColor, Theme.yellow.withAlphaComponent(0.45))
    }

    // MARK: Diff

    /// `diffColors`: removed, added, hunk header.
    static func diff(_ s: Settings, _ index: Int) -> NSColor {
        let themed = [Theme.red, Theme.green, Theme.lavender]
        guard s.diffColors.indices.contains(index), defaults.diffColors.indices.contains(index) else { return themed[min(index, 2)] }
        return resolve(s.diffColors[index], gitkDefault: defaults.diffColors[index], themed[index])
    }

    /// `diffBgColors`: removed, added.
    static func diffBackground(_ s: Settings, _ index: Int) -> NSColor {
        let themed = [Theme.red.withAlphaComponent(0.14), Theme.green.withAlphaComponent(0.14)]
        guard s.diffBgColors.indices.contains(index), defaults.diffBgColors.indices.contains(index) else { return themed[min(index, 1)] }
        return resolve(s.diffBgColors[index], gitkDefault: defaults.diffBgColors[index], themed[index])
    }

    static func fileSeparatorBackground(_ s: Settings) -> NSColor {
        resolve(s.fileSepBgColor, gitkDefault: defaults.fileSepBgColor, .tertiarySystemFill)
    }

    static func fileSeparatorForeground(_ s: Settings) -> NSColor {
        resolve(s.fileSepFgColor, gitkDefault: defaults.fileSepFgColor, .labelColor)
    }

    // MARK: Graph

    /// gitk's merge parent colours (`mergecolors`).
    static func merge(_ s: Settings, _ index: Int) -> NSColor {
        list(s.mergeColors, gitkDefault: defaults.mergeColors, themed: Theme.merge, index)
    }

    /// gitk's graph line colours (`colors`).
    static func graphLine(_ s: Settings, _ index: Int) -> NSColor {
        list(s.colors, gitkDefault: defaults.colors, themed: Theme.lines, index)
    }

    enum Dot { case normal, boundary, negative, mainHead, unstaged, staged }

    /// Commit dot fills (`circlecolors`, `mainheadcirclecolor`, …).
    static func dot(_ s: Settings, _ kind: Dot) -> NSColor {
        func circle(_ i: Int, _ themed: NSColor) -> NSColor {
            guard s.circleColors.indices.contains(i) else { return themed }
            return s.circleColors == defaults.circleColors ? themed : tk(s.circleColors[i])
        }
        switch kind {
        case .normal: return circle(1, Theme.blue)
        case .boundary: return circle(0, .textBackgroundColor)
        case .negative: return circle(2, Theme.gray)
        case .mainHead: return resolve(s.mainHeadCircleColor, gitkDefault: defaults.mainHeadCircleColor, Theme.yellow)
        case .unstaged: return resolve(s.workingFilesCircleColor, gitkDefault: defaults.workingFilesCircleColor, Theme.red)
        case .staged: return resolve(s.indexCircleColor, gitkDefault: defaults.indexCircleColor, Theme.green)
        }
    }

    static func dotOutline(_ s: Settings) -> NSColor {
        resolve(s.circleOutlineColor, gitkDefault: defaults.circleOutlineColor, NSColor.labelColor.withAlphaComponent(0.45))
    }

    /// The notes marker beside a commit dot.
    static func notesMarker(_ s: Settings) -> NSColor { Theme.yellow }

    // MARK: Ref labels

    enum Ref { case head, tag, remote, other }

    static func refBackground(_ s: Settings, _ kind: Ref) -> NSColor {
        switch kind {
        case .head: return resolve(s.headBgColor, gitkDefault: defaults.headBgColor, Theme.Label.green)
        case .tag: return resolve(s.tagBgColor, gitkDefault: defaults.tagBgColor, Theme.Label.yellow)
        case .remote: return resolve(s.remoteBgColor, gitkDefault: defaults.remoteBgColor, Theme.Label.peach)
        case .other: return Theme.Label.lavender
        }
    }

    static func refForeground(_ s: Settings, _ kind: Ref) -> NSColor {
        let value = kind == .tag ? s.tagFgColor : s.headFgColor
        let gitk = kind == .tag ? defaults.tagFgColor : defaults.headFgColor
        return resolve(value, gitkDefault: gitk, Theme.Label.text)
    }

    static func refOutline(_ s: Settings, _ kind: Ref) -> NSColor {
        let value = kind == .tag ? s.tagOutlineColor : s.headOutlineColor
        let gitk = kind == .tag ? defaults.tagOutlineColor : defaults.headOutlineColor
        return resolve(value, gitkDefault: gitk, .clear)
    }
}

/// The app's pastel theme (Catppuccin Latte in light mode, Mocha in dark mode).
@MainActor
enum Theme {
    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    /// A colour that follows the system appearance.
    static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light)
        }
    }

    static let green = adaptive(light: 0x40A02B, dark: 0xA6E3A1)
    static let red = adaptive(light: 0xD20F39, dark: 0xF38BA8)
    static let blue = adaptive(light: 0x1E66F5, dark: 0x89B4FA)
    static let mauve = adaptive(light: 0x8839EF, dark: 0xCBA6F7)
    static let gray = adaptive(light: 0x7C7F93, dark: 0x9399B2)
    static let peach = adaptive(light: 0xFE640B, dark: 0xFAB387)
    static let yellow = adaptive(light: 0xDF8E1D, dark: 0xF9E2AF)
    static let teal = adaptive(light: 0x179299, dark: 0x94E2D5)
    static let pink = adaptive(light: 0xEA76CB, dark: 0xF5C2E7)
    static let sky = adaptive(light: 0x04A5E5, dark: 0x89DCEB)
    static let lavender = adaptive(light: 0x7287FD, dark: 0xB4BEFE)
    static let maroon = adaptive(light: 0xE64553, dark: 0xEBA0AC)
    static let flamingo = adaptive(light: 0xDD7878, dark: 0xF2CDCD)
    static let sapphire = adaptive(light: 0x209FB5, dark: 0x74C7EC)
    static let rosewater = adaptive(light: 0xDC8A78, dark: 0xF5E0DC)

    /// Graph lines, in the roles of gitk's `colors` (green, red, blue, magenta,
    /// dark grey, brown, orange).
    static let lines = [green, red, blue, mauve, gray, maroon, peach]
    /// Merge parents, in the roles of gitk's 16 `mergecolors`.
    static let merge = [red, blue, green, mauve, maroon, teal, pink, yellow,
                        sapphire, flamingo, sky, rosewater, lavender, peach, gray, sapphire]

    /// Ref label fills: the pastel (Mocha) tones in both modes, with dark text.
    @MainActor enum Label {
        static let green = Theme.rgb(0xA6E3A1)
        static let yellow = Theme.rgb(0xF9E2AF)
        static let peach = Theme.rgb(0xFAB387)
        static let lavender = Theme.rgb(0xB4BEFE)
        static let text = Theme.rgb(0x1E1E2E)
    }
}
