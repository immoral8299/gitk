// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

/// Tokenizer for Tcl list syntax and Tcl scripts, as used by gitk's saved
/// settings and the legacy `~/.gitk` configuration file.
enum TclList {
    /// A malformed list or script (unbalanced braces or quotes, or a braced or
    /// quoted element followed by something other than white space).
    struct Error: Swift.Error, Equatable, CustomStringConvertible {
        let message: String

        var description: String { message }
    }

    /// Splits a Tcl list into its elements, following `Tcl_SplitList`.
    static func split(_ s: String) throws -> [String] {
        let c = Array(s.unicodeScalars)
        var out: [String] = []
        var i = skipSpace(c, 0)
        while i < c.count {
            var value: [Unicode.Scalar] = []
            switch c[i] {
            case "{":
                let close = try closingBrace(c, from: i)
                value = Array(c[(i + 1)..<close])
                i = close + 1
                try requireSeparator(c, i, after: "braces")
            case "\"":
                var j = i + 1
                while true {
                    guard j < c.count else {
                        throw Error(message: "unmatched open quote in list")
                    }
                    if c[j] == "\"" { break }
                    if c[j] == "\\" {
                        let (sub, next) = substitute(c, at: j)
                        value += sub
                        j = next
                    } else {
                        value.append(c[j])
                        j += 1
                    }
                }
                i = j + 1
                try requireSeparator(c, i, after: "quotes")
            default:
                var j = i
                while j < c.count && !isSpace(c[j]) {
                    if c[j] == "\\" {
                        let (sub, next) = substitute(c, at: j)
                        value += sub
                        j = next
                    } else {
                        value.append(c[j])
                        j += 1
                    }
                }
                i = j
            }
            out.append(String(String.UnicodeScalarView(value)))
            i = skipSpace(c, i)
        }
        return out
    }

    /// Splits a Tcl script into its top-level commands. Commands end at a
    /// newline or `;` outside braces, quotes and brackets. Comment lines at
    /// the start of a command are dropped. Each command is returned trimmed.
    /// This never fails: an unbalanced brace or quote runs to the end of the
    /// script, as Tcl's `info complete` would report.
    static func splitCommands(_ script: String) -> [String] {
        let c = Array(script.unicodeScalars)
        var out: [String] = []
        var i = 0
        while i < c.count {
            while i < c.count && (isSpace(c[i]) || c[i] == ";") {
                i += 1
            }
            if i >= c.count { break }
            if c[i] == "#" {
                while i < c.count && c[i] != "\n" {
                    i += c[i] == "\\" ? 2 : 1
                }
                continue
            }
            let start = i
            var end = c.count
            var braceDepth = 0
            var bracketDepth = 0
            var inQuotes = false
            scan: while i < c.count {
                let ch = c[i]
                if ch == "\\" {
                    i += 2
                    continue
                }
                if braceDepth > 0 {
                    if ch == "{" { braceDepth += 1 }
                    if ch == "}" { braceDepth -= 1 }
                    i += 1
                    continue
                }
                if inQuotes {
                    if ch == "\"" { inQuotes = false }
                    i += 1
                    continue
                }
                switch ch {
                case "{" where isWordStart(c, i):
                    braceDepth = 1
                case "\"" where isWordStart(c, i):
                    inQuotes = true
                case "[":
                    bracketDepth += 1
                case "]":
                    if bracketDepth > 0 { bracketDepth -= 1 }
                case "\n", ";":
                    if bracketDepth == 0 {
                        end = i
                        i += 1
                        break scan
                    }
                default:
                    break
                }
                i += 1
            }
            let stop = min(end, c.count)
            let command = trimmed(Array(c[start..<stop]))
            if !command.isEmpty {
                out.append(String(String.UnicodeScalarView(command)))
            }
            i = max(i, stop)
        }
        return out
    }

    // MARK: - Helpers

    private static func isSpace(_ u: Unicode.Scalar) -> Bool {
        switch u {
        case " ", "\t", "\n", "\r", "\u{0B}", "\u{0C}": return true
        default: return false
        }
    }

    /// Skips white space and backslash-newline sequences between elements.
    private static func skipSpace(_ c: [Unicode.Scalar], _ start: Int) -> Int {
        var i = start
        while i < c.count {
            if isSpace(c[i]) {
                i += 1
            } else if c[i] == "\\", i + 1 < c.count, c[i + 1] == "\n" {
                i += 2
            } else {
                break
            }
        }
        return i
    }

    /// Index of the `}` matching the `{` at `open`. A backslash hides the next
    /// character from the brace count, and the text itself is kept literally.
    private static func closingBrace(_ c: [Unicode.Scalar], from open: Int) throws -> Int {
        var depth = 1
        var j = open + 1
        while j < c.count {
            switch c[j] {
            case "\\":
                j += 1
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return j }
            default:
                break
            }
            j += 1
        }
        throw Error(message: "unmatched open brace in list")
    }

    /// A braced or quoted element must be followed by white space or the end.
    private static func requireSeparator(_ c: [Unicode.Scalar], _ i: Int, after kind: String) throws {
        guard i < c.count, !isSpace(c[i]) else { return }
        if c[i] == "\\", i + 1 < c.count, c[i + 1] == "\n" { return }
        let next = String(String.UnicodeScalarView([c[i]]))
        throw Error(message: "list element in \(kind) followed by \"\(next)\" instead of space")
    }

    /// Decodes the backslash sequence starting at `i` (where `c[i] == "\\"`),
    /// returning the replacement scalars and the index just past the sequence.
    private static func substitute(_ c: [Unicode.Scalar], at i: Int) -> ([Unicode.Scalar], Int) {
        guard i + 1 < c.count else { return (["\\"], i + 1) }
        switch c[i + 1] {
        case "a": return (["\u{07}"], i + 2)
        case "b": return (["\u{08}"], i + 2)
        case "f": return (["\u{0C}"], i + 2)
        case "n": return (["\n"], i + 2)
        case "r": return (["\r"], i + 2)
        case "t": return (["\t"], i + 2)
        case "v": return (["\u{0B}"], i + 2)
        case "\n":
            var j = i + 2
            while j < c.count && (c[j] == " " || c[j] == "\t") { j += 1 }
            return ([" "], j)
        case "x":
            return numeric(c, letter: "x", from: i + 2, radix: 16, maxDigits: 2)
        case "u":
            return numeric(c, letter: "u", from: i + 2, radix: 16, maxDigits: 4)
        case "0"..."7":
            return numeric(c, letter: c[i + 1], from: i + 1, radix: 8, maxDigits: 3)
        default:
            return ([c[i + 1]], i + 2)
        }
    }

    /// Reads up to `maxDigits` digits in `radix` starting at `from`. A `\x` or
    /// `\u` with no digits yields its letter, as Tcl does. Octal escapes always
    /// have at least one digit, so `letter` is never used for them.
    private static func numeric(
        _ c: [Unicode.Scalar], letter: Unicode.Scalar, from: Int, radix: UInt32, maxDigits: Int
    ) -> ([Unicode.Scalar], Int) {
        var value: UInt32 = 0
        var digits = 0
        var j = from
        while digits < maxDigits, j < c.count, let d = hexDigit(c[j]), d < radix {
            value = value * radix + d
            digits += 1
            j += 1
        }
        if digits == 0 {
            return ([letter], from)
        }
        return ([Unicode.Scalar(value) ?? "\u{FFFD}"], j)
    }

    private static func hexDigit(_ u: Unicode.Scalar) -> UInt32? {
        switch u {
        case "0"..."9": return u.value - 0x30
        case "a"..."f": return u.value - 0x61 + 10
        case "A"..."F": return u.value - 0x41 + 10
        default: return nil
        }
    }

    /// A `{` or `"` begins a word only at the start of input or after white
    /// space, `;` or `[`.
    private static func isWordStart(_ c: [Unicode.Scalar], _ i: Int) -> Bool {
        guard i > 0 else { return true }
        let prev = c[i - 1]
        return isSpace(prev) || prev == ";" || prev == "["
    }

    private static func trimmed(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var lo = 0
        var hi = s.count
        while lo < hi && isSpace(s[lo]) { lo += 1 }
        while hi > lo && isSpace(s[hi - 1]) { hi -= 1 }
        return Array(s[lo..<hi])
    }
}
