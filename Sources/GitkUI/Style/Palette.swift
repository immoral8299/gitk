// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Resolves gitk colour settings to `NSColor`.
///
/// gitk's defaults assume a white Tk window. When a setting still has gitk's
/// default value, an adaptive system colour with the same role is used, so the
/// app reads correctly in dark mode. A colour the user configured is used
/// exactly (see docs/architecture.md, Deviations).
@MainActor
enum Palette {
    /// Parses a Tk colour; `.textColor` for an unparseable value.
    static func tk(_ value: String) -> NSColor {
        guard let rgba = TkColor.parse(value) else { return .textColor }
        return NSColor(srgbRed: CGFloat(rgba.r) / 255, green: CGFloat(rgba.g) / 255,
                       blue: CGFloat(rgba.b) / 255, alpha: CGFloat(rgba.a) / 255)
    }

    private static func resolve(_ value: String, gitkDefault: String, _ adaptive: NSColor) -> NSColor {
        value.caseInsensitiveCompare(gitkDefault) == .orderedSame ? adaptive : tk(value)
    }

    private static let defaults = Settings()

    static func foreground(_ s: Settings) -> NSColor { resolve(s.fgColor, gitkDefault: defaults.fgColor, .textColor) }
    static func background(_ s: Settings) -> NSColor { resolve(s.bgColor, gitkDefault: defaults.bgColor, .textBackgroundColor) }
    static func link(_ s: Settings) -> NSColor { resolve(s.linkFgColor, gitkDefault: defaults.linkFgColor, .linkColor) }

    /// `diffColors`: removed, added, hunk header.
    static func diff(_ s: Settings, _ index: Int) -> NSColor {
        let adaptive: [NSColor] = [.systemRed, .systemGreen, .systemBlue]
        guard s.diffColors.indices.contains(index) else { return adaptive[min(index, 2)] }
        return resolve(s.diffColors[index], gitkDefault: defaults.diffColors[index], adaptive[index])
    }

    /// `diffBgColors`: removed, added.
    static func diffBackground(_ s: Settings, _ index: Int) -> NSColor {
        let adaptive: [NSColor] = [NSColor.systemRed.withAlphaComponent(0.12), NSColor.systemGreen.withAlphaComponent(0.12)]
        guard s.diffBgColors.indices.contains(index) else { return adaptive[min(index, 1)] }
        return resolve(s.diffBgColors[index], gitkDefault: defaults.diffBgColors[index], adaptive[index])
    }

    static func fileSeparatorBackground(_ s: Settings) -> NSColor {
        resolve(s.fileSepBgColor, gitkDefault: defaults.fileSepBgColor, .tertiarySystemFill)
    }

    static func fileSeparatorForeground(_ s: Settings) -> NSColor {
        resolve(s.fileSepFgColor, gitkDefault: defaults.fileSepFgColor, .labelColor)
    }

    /// System colours for the named colours in gitk's default palettes.
    private static let systemEquivalents: [String: NSColor] = [
        "red": .systemRed, "blue": .systemBlue, "#00ff00": .systemGreen, "magenta": .systemPink,
        "purple": .systemPurple, "brown": .systemBrown, "orange": .systemOrange, "darkgrey": .systemGray,
        "#009090": .systemTeal, "cyan": .systemCyan,
    ]

    /// Entry `index` of a colour list; while the list is gitk's default, its
    /// named colours become their system equivalents.
    private static func list(_ values: [String], gitkDefault: [String], _ index: Int, fallback: NSColor) -> NSColor {
        guard !values.isEmpty else { return fallback }
        let value = values[index % values.count]
        if values == gitkDefault, let system = systemEquivalents[value.lowercased()] { return system }
        return tk(value)
    }

    /// gitk's merge parent colours (`mergecolors`).
    static func merge(_ s: Settings, _ index: Int) -> NSColor {
        list(s.mergeColors, gitkDefault: defaults.mergeColors, index, fallback: .textColor)
    }

    /// gitk's graph line colours (`colors`).
    static func graphLine(_ s: Settings, _ index: Int) -> NSColor {
        guard s.colors.indices.contains(index) else { return foreground(s) }
        return list(s.colors, gitkDefault: defaults.colors, index, fallback: foreground(s))
    }
}
