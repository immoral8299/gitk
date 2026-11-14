// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

/// An 8-bit-per-channel colour. Tk colours have no alpha, so parsed colours use `a = 255`.
public struct RGBA: Sendable, Hashable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

/// Parses colour specifications from gitk settings: `#rgb`, `#rrggbb`, `#rrrgggbbb`,
/// `#rrrrggggbbbb`, or a Tk colour name (see `TkColorTable`).
public enum TkColor {
    /// Parses a Tk colour spec. Returns `nil` for malformed hex and unknown names.
    ///
    /// Hex components are scaled the way Tk scales them (`winfo rgb` reports 16-bit
    /// values: a 1-digit component is replicated, so `#f00` is pure red, and 3-digit
    /// components keep their top bits). The result is truncated to 8 bits.
    public static func parse(_ spec: String) -> RGBA? {
        guard spec.hasPrefix("#") else {
            guard let named = TkColorTable.rgb(named: spec) else { return nil }
            return RGBA(r: named.r, g: named.g, b: named.b)
        }
        let digits = Array(spec.utf8.dropFirst())
        guard [3, 6, 9, 12].contains(digits.count) else { return nil }
        let width = digits.count / 3
        guard
            let r = component(digits[0..<width]),
            let g = component(digits[width..<(2 * width)]),
            let b = component(digits[(2 * width)..<(3 * width)])
        else { return nil }
        return RGBA(r: r, g: g, b: b)
    }

    /// Formats a colour as lowercase `#rrggbb`. Alpha is not included.
    public static func hexString(_ color: RGBA) -> String {
        "#" + [color.r, color.g, color.b].map(hexByte).joined()
    }

    private static func component(_ digits: ArraySlice<UInt8>) -> UInt8? {
        var value = 0
        for digit in digits {
            guard let nibble = hexValue(digit) else { return nil }
            value = value * 16 + nibble
        }
        let scaled: Int
        switch digits.count {
        case 1: scaled = value * 0x1111
        case 2: scaled = value * 0x0101
        case 3: scaled = (value << 4) | (value >> 8)
        default: scaled = value
        }
        return UInt8(scaled >> 8)
    }

    private static func hexValue(_ c: UInt8) -> Int? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(c - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(c - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(c - UInt8(ascii: "A")) + 10
        default: return nil
        }
    }

    private static func hexByte(_ value: UInt8) -> String {
        let text = String(value, radix: 16)
        return text.count == 1 ? "0" + text : text
    }
}
