// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

/// Shell-style quoting and word splitting, used by gitk to build and read
/// command lines (for example the `--argscmd` and find-path arguments).
enum ShellWords {
    /// A quoting error in `dequote` or `split`, with gitk's message text.
    struct Error: Swift.Error, Equatable, CustomStringConvertible {
        let message: String

        var description: String { message }
    }

    /// Port of gitk proc `shellquote` (gitk/gitk 4179–4191).
    static func quote(_ str: String) -> String {
        let s = Array(str.unicodeScalars)
        if !s.contains(where: { isSpecial($0) }) {
            return str
        }
        if !s.contains(where: { $0 == "'" || $0 == "\"" || $0 == "\\" }) {
            return "\"" + str + "\""
        }
        if !s.contains("'") {
            return "'" + str + "'"
        }
        var out = "\""
        for u in str.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            default: out.unicodeScalars.append(u)
            }
        }
        return out + "\""
    }

    /// Port of gitk proc `shellarglist` (gitk/gitk 4192–4202). As in gitk, a
    /// separator is added only when the text so far is non-empty.
    static func argList(_ l: [String]) -> String {
        var str = ""
        for a in l {
            if !str.isEmpty {
                str += " "
            }
            str += quote(a)
        }
        return str
    }

    /// Port of gitk proc `shelldequote` (gitk/gitk 4203–4256). Reads one word
    /// from the start of `str` and returns the index just past it, together
    /// with the word. The index is where the word ends (white space or the end
    /// of input), so the caller can skip ahead from there.
    static func dequote(_ str: String) throws -> (used: Int, word: String) {
        let (used, word) = try dequote(Array(str.unicodeScalars))
        return (used, String(String.UnicodeScalarView(word)))
    }

    /// Port of gitk proc `shellsplit` (gitk/gitk 4257–4270).
    static func split(_ str: String) throws -> [String] {
        let s = Array(str.unicodeScalars)
        var words: [String] = []
        var start = 0
        while true {
            while start < s.count && isWhitespace(s[start]) {
                start += 1
            }
            if start >= s.count { break }
            let (used, word) = try dequote(Array(s[start...]))
            start += used
            words.append(String(String.UnicodeScalarView(word)))
        }
        return words
    }

    // MARK: - Helpers

    /// The characters that start a shell token: quotes, backslash, space, tab.
    private static func isSpecial(_ u: Unicode.Scalar) -> Bool {
        switch u {
        case "'", "\"", "\\", " ", "\t": return true
        default: return false
        }
    }

    private static func isWhitespace(_ u: Unicode.Scalar) -> Bool {
        switch u {
        case " ", "\t", "\n", "\r", "\u{0B}", "\u{0C}": return true
        default: return false
        }
    }

    /// Index of the first scalar at or after `from` matching `pred`, or nil.
    private static func firstIndex(
        in s: [Unicode.Scalar], from: Int, where pred: (Unicode.Scalar) -> Bool
    ) -> Int? {
        guard from < s.count else { return nil }
        return s[from...].firstIndex(where: pred)
    }

    /// Scalar-array form of `dequote`. Index arithmetic follows the Tcl proc
    /// step for step, including the `used` value on break.
    private static func dequote(_ s: [Unicode.Scalar]) throws -> (used: Int, word: [Unicode.Scalar]) {
        var ret: [Unicode.Scalar] = []
        var used = -1
        while true {
            used += 1
            guard let first = firstIndex(in: s, from: used, where: isSpecial) else {
                if used < s.count {
                    ret += s[used...]
                }
                used = s.count
                break
            }
            let ch = s[first]
            if first > used {
                ret += s[used..<first]
                used = first
            }
            if ch == " " || ch == "\t" { break }
            used += 1
            if ch == "'" {
                guard let close = firstIndex(in: s, from: used, where: { $0 == "'" }) else {
                    throw Error(message: "unmatched single-quote")
                }
                ret += s[used..<close]
                used = close
                continue
            }
            if ch == "\\" {
                guard used < s.count else {
                    throw Error(message: "trailing backslash")
                }
                ret.append(s[used])
                continue
            }
            // Here ch is a double quote.
            while true {
                guard let f = firstIndex(in: s, from: used, where: { $0 == "\"" || $0 == "\\" }) else {
                    throw Error(message: "unmatched double-quote")
                }
                let inner = s[f]
                if f > used {
                    ret += s[used..<f]
                    used = f
                }
                if inner == "\"" { break }
                used += 1
                if used < s.count {
                    ret.append(s[used])
                }
                used += 1
            }
        }
        return (used, ret)
    }
}
