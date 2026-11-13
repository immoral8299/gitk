// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// The find bar's criteria: what kind of search, how the text is compared,
/// which commit fields it covers, and the pattern typed by the user.
///
/// Only `.containing` is evaluated here (`matches(commit:in:)`). The other
/// types are run by `git diff-tree` through the find engine.
public struct FindQuery: Sendable, Equatable {
    /// The "containing:" drop-list (gitk `gdttype`).
    public enum SearchType: Sendable, Equatable {
        case containing, touchingPaths, addingRemovingString, changingLinesMatching
    }

    /// The "Exact / IgnCase / Regexp" drop-list (gitk `findtype`).
    public enum MatchMode: Sendable, Equatable {
        case exact, ignoreCase, regexp
    }

    /// The "All fields / Headline / ..." drop-list (gitk `findloc`).
    public enum Field: Sendable, Equatable {
        case allFields, headline, comments, author, committer
    }

    public var type: SearchType { didSet { recompile() } }
    public var matchMode: MatchMode { didSet { recompile() } }
    public var field: Field
    public var pattern: String { didSet { recompile() } }

    /// Compiled form of the pattern, rebuilt whenever an input changes. `nil`
    /// means nothing can match (wrong type, empty pattern, bad regexp).
    private var compiled: Compiled?

    public init(type: SearchType = .containing, matchMode: MatchMode = .exact,
                field: Field = .allFields, pattern: String = "") {
        self.type = type
        self.matchMode = matchMode
        self.field = field
        self.pattern = pattern
        self.compiled = nil
        recompile()
    }

    public static func == (a: FindQuery, b: FindQuery) -> Bool {
        a.type == b.type && a.matchMode == b.matchMode && a.field == b.field
            && a.pattern == b.pattern
    }

    /// Port of the pattern construction in gitk proc `findcom_change`
    /// (gitk/gitk 4953–4975). Regexp uses the string as is. Exact and IgnCase
    /// escape `* ? [ \` and wrap it as the glob `*<escaped>*`. `nil` when the
    /// type is not "containing:" or the pattern is empty (gitk's empty
    /// `findpattern`), meaning nothing matches.
    public var findPattern: String? {
        guard type == .containing, !pattern.isEmpty else { return nil }
        if matchMode == .regexp { return pattern }
        var e = ""
        for c in pattern {
            if "*?[\\".contains(c) { e.append("\\") }
            e.append(c)
        }
        return "*" + e + "*"
    }

    /// Port of gitk proc `doesmatch` (gitk/gitk 5079–5088) for one text
    /// field. An invalid regexp, an empty pattern or a non-"containing:" type
    /// matches nothing and never throws.
    ///
    /// Regexp uses ICU (`NSRegularExpression`), not Tcl ARE. Notable
    /// differences: Tcl's `\m \M \y \Y \Z` and `\A` word/string anchors, the
    /// `***=` and `(?e)` director/embedded options, `[[:<:]]`/`[[.x.]]`
    /// bracket extras and `\0`-style octal back-references are Tcl-only, and
    /// ICU treats `\Z`, `\h`, `\R`, `\p{..}` differently. Plain patterns
    /// (literals, classes, groups, alternation, `\d \w \s \b`) agree.
    public func doesMatch(_ text: String) -> Bool {
        compiled?.matches(text) ?? false
    }

    /// Port of gitk proc `findmatches` (gitk/gitk 6943–6962): the ranges of
    /// every match inside `text`, used to bold the matched text. Exact and
    /// IgnCase give non-overlapping literal occurrences (IgnCase compares
    /// lowercased text); Regexp gives each whole match. Empty for an invalid
    /// regexp or an empty pattern. Zero-length regexp matches are skipped.
    public func matches(in text: String) -> [Range<String.Index>] {
        guard type == .containing, !pattern.isEmpty else { return [] }
        switch matchMode {
        case .regexp:
            guard case .regex(let re)? = compiled else { return [] }
            let ns = NSRange(text.startIndex..., in: text)
            return re.matches(in: text, range: ns).compactMap { m in
                guard m.range.length > 0 else { return nil }
                return Range(m.range, in: text)
            }
        case .exact, .ignoreCase:
            let fold = matchMode == .ignoreCase
            let hay = fold ? text.lowercased() : text
            let needle = fold ? pattern.lowercased() : pattern
            // Lowercasing can change the length (e.g. "İ"); then offsets
            // cannot be mapped back, so fall back to the exact text.
            let same = hay.unicodeScalars.count == text.unicodeScalars.count
            let h = same ? hay : text
            let n = same ? needle : pattern
            var out: [Range<String.Index>] = []
            var from = h.startIndex
            while from < h.endIndex,
                  let r = h.range(of: n, options: .literal, range: from..<h.endIndex) {
                // Same scalar offsets in `text` as in `h`.
                let lo = text.unicodeScalars.index(text.unicodeScalars.startIndex,
                    offsetBy: h.unicodeScalars.distance(from: h.unicodeScalars.startIndex, to: r.lowerBound))
                let hi = text.unicodeScalars.index(text.unicodeScalars.startIndex,
                    offsetBy: h.unicodeScalars.distance(from: h.unicodeScalars.startIndex, to: r.upperBound))
                out.append(lo..<hi)
                from = r.upperBound
            }
            return out
        }
    }

    /// Port of the field loop of gitk procs `askfindhighlight` and `findmore`
    /// (gitk/gitk 5095–5110, 7050–7062). commitinfo is `{headline author
    /// authordate committer commitdate comments}`; the two dates have an
    /// empty field type and are never searched. "All fields" therefore covers
    /// headline, author (`Name <email>`), committer and comments (the full
    /// message).
    public func matches(commit index: CommitIndex, in store: CommitStore) -> Bool {
        !matchedFields(commit: index, in: store).isEmpty
    }

    /// The fields of the commit that match. `.author` in the result is what
    /// gitk bolds the author name for (`isbold == 2`).
    public func matchedFields(commit index: CommitIndex, in store: CommitStore) -> [Field] {
        guard compiled != nil else { return [] }
        var out: [Field] = []
        func check(_ f: Field, _ text: () -> String) {
            if field == .allFields || field == f, doesMatch(text()) { out.append(f) }
        }
        check(.headline) { store.headline(at: index) }
        check(.author) { store.author(at: index) }
        check(.committer) { store.committer(at: index) }
        check(.comments) { store.message(at: index) }
        return out
    }

    // MARK: compilation

    private enum Compiled: Sendable {
        case glob([FindGlobToken], nocase: Bool)
        case regex(NSRegularExpression)

        func matches(_ text: String) -> Bool {
            switch self {
            case .glob(let tokens, let nocase):
                let s = nocase ? text.lowercased() : text
                return FindGlobToken.match(tokens, Array(s.unicodeScalars))
            case .regex(let re):
                return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }
        }
    }

    private mutating func recompile() {
        guard let p = findPattern else {
            compiled = nil
            return
        }
        if matchMode == .regexp {
            compiled = (try? NSRegularExpression(pattern: p)).map { .regex($0) }
        } else {
            let nocase = matchMode == .ignoreCase
            compiled = .glob(FindGlobToken.parse(nocase ? p.lowercased() : p), nocase: nocase)
        }
    }
}

// TODO(orchestrator): replace with the shared TclGlob once integrated.
/// One element of a compiled Tcl glob pattern.
private enum FindGlobToken {
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
    static func parse(_ pattern: String) -> [FindGlobToken] {
        let p = Array(pattern.unicodeScalars)
        var tokens: [FindGlobToken] = []
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
    static func match(_ tokens: [FindGlobToken], _ text: [Unicode.Scalar]) -> Bool {
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

    private static func accepts(_ token: FindGlobToken, _ c: Unicode.Scalar) -> Bool {
        switch token {
        case .char(let x): return x == c
        case .any: return true
        case .star: return false
        case .set(let ranges): return ranges.contains { $0.contains(c.value) }
        }
    }
}
