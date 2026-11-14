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
        case allFields, headline, comments, author, committer, commitID
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
    /// message). The Swift search also includes the commit ID.
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
        check(.commitID) { store.id(at: index).hex }
        check(.headline) { store.headline(at: index) }
        check(.author) { store.author(at: index) }
        check(.committer) { store.committer(at: index) }
        check(.comments) { store.message(at: index) }
        return out
    }

    // MARK: compilation

    private enum Compiled: Sendable {
        case glob([TclGlob], nocase: Bool)
        case regex(NSRegularExpression)

        func matches(_ text: String) -> Bool {
            switch self {
            case .glob(let tokens, let nocase):
                let s = nocase ? text.lowercased() : text
                return TclGlob.match(tokens, Array(s.unicodeScalars))
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
            compiled = .glob(TclGlob.parse(nocase ? p.lowercased() : p), nocase: nocase)
        }
    }
}
