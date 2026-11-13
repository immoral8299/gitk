// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

/// One element of a compiled Tcl glob pattern (Tcl `string match`).
/// `matches(pattern:_:)` is the one-shot form.
enum TclGlob {
    /// A literal character (also what a backslash escape produces).
    case char(Unicode.Scalar)
    /// `?`: any single character.
    case any
    /// `*`: any sequence of characters, including `/`.
    case star
    /// `[...]`: one character in any of the inclusive ranges.
    case set([ClosedRange<UInt32>])

    /// Compiles a pattern the way Tcl's `string match` reads it. A `[` set is
    /// read up to the closing `]`; a set with no `]` runs to the end of the
    /// pattern. Inside a set, `-` between two characters makes a range, and a
    /// backslash escapes the next character. Tcl has no `[!...]` or `[^...]`
    /// negation, so `!` and `^` are ordinary set members.
    static func parse(_ pattern: String) -> [TclGlob] {
        let p = Array(pattern.unicodeScalars)
        var tokens: [TclGlob] = []
        var i = 0
        while i < p.count {
            let c = p[i]
            switch c {
            case "*":
                tokens.append(.star)
                i += 1
            case "?":
                tokens.append(.any)
                i += 1
            case "\\" where i + 1 < p.count:
                tokens.append(.char(p[i + 1]))
                i += 2
            case "[":
                i += 1
                var ranges: [ClosedRange<UInt32>] = []
                var first = true
                while i < p.count, first || p[i] != "]" {
                    first = false
                    var lo = p[i]
                    if lo == "\\", i + 1 < p.count {
                        i += 1
                        lo = p[i]
                    }
                    var hi = lo
                    if i + 2 < p.count, p[i + 1] == "-", p[i + 2] != "]" {
                        hi = p[i + 2]
                        i += 2
                    }
                    ranges.append(lo.value...hi.value)
                    i += 1
                }
                i += 1  // skip the closing ']' (or step past the end)
                tokens.append(.set(ranges))
            default:
                tokens.append(.char(c))
                i += 1
            }
        }
        return tokens
    }

    /// Tcl `string match` for compiled tokens against the whole of `text`.
    /// Only `*` needs backtracking, so the usual single-star retry is enough.
    static func match(_ tokens: [TclGlob], _ text: [Unicode.Scalar]) -> Bool {
        var p = 0
        var t = 0
        var starP: Int?
        var starT = 0
        while t < text.count {
            if p < tokens.count, case .star = tokens[p] {
                starP = p
                starT = t
                p += 1
            } else if p < tokens.count, accepts(tokens[p], text[t]) {
                p += 1
                t += 1
            } else if let sp = starP {
                p = sp + 1
                starT += 1
                t = starT
            } else {
                return false
            }
        }
        while p < tokens.count, case .star = tokens[p] {
            p += 1
        }
        return p == tokens.count
    }

    private static func accepts(_ token: TclGlob, _ c: Unicode.Scalar) -> Bool {
        switch token {
        case .char(let x): return x == c
        case .any: return true
        case .star: return false
        case .set(let ranges): return ranges.contains { $0.contains(c.value) }
        }
    }

    /// Tcl `[string match $pattern $string]`.
    static func matches(pattern: String, _ string: String) -> Bool {
        match(parse(pattern), Array(string.unicodeScalars))
    }
}
