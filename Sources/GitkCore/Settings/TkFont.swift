// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// A font as gitk stores it: family, size and the two style flags gitk keeps.
///
/// The family names `systemFamily` and `monospacedSystemFamily` are sentinels meaning
/// "the macOS system font" and "the monospaced system font" (design D9); the UI layer
/// maps them to `NSFont.systemFont` / `NSFont.monospacedSystemFont`.
public struct FontSpec: Codable, Sendable, Hashable {
    public static let systemFamily = ".AppleSystemUIFont"
    public static let monospacedSystemFamily = ".AppleSystemUIFontMonospaced"

    public var family: String
    public var pointSize: Double
    public var bold: Bool
    public var italic: Bool

    public init(family: String, pointSize: Double, bold: Bool = false, italic: Bool = false) {
        self.family = family
        self.pointSize = pointSize
        self.bold = bold
        self.italic = italic
    }
}

/// Parsing and formatting of Tk font descriptions `{family} size ?style ...?`.
enum TkFont {
    /// Port of gitk proc `parsefont` (gitk/gitk 8829–8848).
    ///
    /// An empty or zero size becomes 10. A negative size means pixels and is
    /// converted to points 1:1. Unknown styles are ignored; `normal` and `roman`
    /// reset weight and slant. Returns `nil` for a malformed Tcl list or a
    /// non-numeric size (gitk would raise a Tcl error).
    static func parse(_ description: String) -> FontSpec? {
        guard let words = try? TclList.split(description) else { return nil }
        let family = words.first ?? ""
        var size = 10.0
        if words.count > 1, !words[1].isEmpty {
            guard let n = Double(words[1]), n.isFinite else { return nil }
            if n < 0 {
                size = (-n).rounded(.toNearestOrAwayFromZero)
            } else if n != 0 {
                size = n
            }
        }
        var bold = false
        var italic = false
        for style in words.dropFirst(2) {
            switch style {
            case "normal": bold = false
            case "bold": bold = true
            case "roman": italic = false
            case "italic": italic = true
            default: break
            }
        }
        return FontSpec(family: family, pointSize: size, bold: bold, italic: italic)
    }

    /// Port of gitk proc `fontname` (gitk/gitk 8863–8873): `{family} size ?bold? ?italic?`.
    /// (`fontflags`, 8857–8861, only builds Tk option lists; the UI layer applies
    /// `FontSpec` directly, forcing bold where gitk passes `isbold`.)
    static func format(_ font: FontSpec) -> String {
        var words = [quote(font.family), sizeText(font.pointSize)]
        if font.bold { words.append("bold") }
        if font.italic { words.append("italic") }
        return words.joined(separator: " ")
    }

    private static func sizeText(_ size: Double) -> String {
        size == size.rounded() && abs(size) < 1e15 ? String(Int(size)) : String(size)
    }

    private static func quote(_ s: String) -> String {
        if s.isEmpty { return "{}" }
        let special = " \t\n\r\u{0B}\u{0C}{}[]$;\"\\"
        return s.contains(where: { special.contains($0) }) ? "{\(s)}" : s
    }
}
