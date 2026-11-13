// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// One entry of a gettext `.po` catalog.
public struct PoEntry: Equatable, Sendable {
    public var context: String?
    public var id: String
    public var idPlural: String?
    /// `msgstr` (index 0) or `msgstr[n]` values, indexed by n.
    public var strings: [String]
    public var flags: Set<String>

    public var isFuzzy: Bool { flags.contains("fuzzy") }
    /// The singular translation.
    public var string: String { strings.first ?? "" }
}

public struct PoParseError: Error, Equatable, CustomStringConvertible {
    public var line: Int
    public var message: String
    public var description: String { "line \(line): \(message)" }
}

/// A parsed catalog: header metadata plus all live entries (obsolete `#~` entries are dropped).
public struct PoCatalog: Equatable, Sendable {
    public var header: String
    public var charset: String
    public var entries: [PoEntry]
}

public enum PoParser {
    private enum Field { case none, context, id, idPlural, str(Int) }

    private struct Builder {
        var context: String?
        var id: String?
        var idPlural: String?
        var strings: [Int: String] = [:]
        var flags: Set<String> = []
        /// Flags or comments with no entry behind them (e.g. before an obsolete `#~` entry).
        var isEmpty: Bool { context == nil && id == nil && strings.isEmpty }
    }

    public static func parse(data: Data) throws -> PoCatalog {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PoParseError(line: 0, message: "file is not valid UTF-8")
        }
        return try parse(text)
    }

    public static func parse(_ text: String) throws -> PoCatalog {
        var entries: [PoEntry] = []
        var cur = Builder()
        var field = Field.none
        var buffer: [UInt8] = []

        func commitField() {
            let s = String(decoding: buffer, as: UTF8.self)
            buffer = []
            switch field {
            case .none: break
            case .context: cur.context = s
            case .id: cur.id = s
            case .idPlural: cur.idPlural = s
            case .str(let n): cur.strings[n] = s
            }
            field = .none
        }
        func flush(_ lineNo: Int) throws {
            commitField()
            defer { cur = Builder() }
            if cur.isEmpty { return }
            guard let id = cur.id else {
                throw PoParseError(line: lineNo, message: "entry without msgid")
            }
            let count = (cur.strings.keys.max() ?? -1) + 1
            let strs = (0..<count).map { cur.strings[$0] ?? "" }
            entries.append(PoEntry(context: cur.context, id: id, idPlural: cur.idPlural,
                                   strings: strs, flags: cur.flags))
        }

        var lineNo = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNo += 1
            var line = Substring(rawLine)
            if line.hasSuffix("\r") { line = line.dropLast() }
            line = line.drop(while: { $0 == " " || $0 == "\t" })
            if line.isEmpty { try flush(lineNo); continue }

            if line.hasPrefix("#") {
                if line.hasPrefix("#~") { cur.flags = []; continue }  // obsolete entry: skipped, with its flags
                commitField()
                if !cur.strings.isEmpty { try flush(lineNo) }
                if line.hasPrefix("#,") {
                    for f in line.dropFirst(2).split(separator: ",") {
                        cur.flags.insert(f.trimmingCharacters(in: .whitespaces))
                    }
                }
                continue
            }

            if line.hasPrefix("\"") {
                if case .none = field {
                    throw PoParseError(line: lineNo, message: "string continuation without keyword")
                }
                buffer += try unquote(line, lineNo)
                continue
            }

            let (keyword, rest) = splitKeyword(line)
            let value = try unquote(rest, lineNo)
            commitField()
            switch keyword {
            case "msgctxt":
                if cur.id != nil { try flush(lineNo) }
                field = .context
            case "msgid":
                if cur.id != nil { try flush(lineNo) }
                field = .id
            case "msgid_plural":
                field = .idPlural
            case "msgstr":
                field = .str(0)
            default:
                if keyword.hasPrefix("msgstr["), keyword.hasSuffix("]"),
                   let n = Int(keyword.dropFirst(7).dropLast()) {
                    field = .str(n)
                } else {
                    throw PoParseError(line: lineNo, message: "unknown keyword '\(keyword)'")
                }
            }
            buffer = value
        }
        try flush(lineNo + 1)

        var header = ""
        var charset = "UTF-8"
        if let i = entries.firstIndex(where: { $0.id.isEmpty && $0.context == nil }) {
            header = entries[i].string
            entries.remove(at: i)
            charset = headerCharset(header) ?? charset
        }
        return PoCatalog(header: header, charset: charset, entries: entries)
    }

    private static func splitKeyword(_ line: Substring) -> (String, Substring) {
        let idx = line.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "\"" }) ?? line.endIndex
        return (String(line[..<idx]), line[idx...].drop(while: { $0 == " " || $0 == "\t" }))
    }

    private static func headerCharset(_ header: String) -> String? {
        for l in header.split(separator: "\n") where l.lowercased().hasPrefix("content-type:") {
            guard let r = l.range(of: "charset=", options: .caseInsensitive) else { continue }
            let v = l[r.upperBound...].trimmingCharacters(in: .whitespaces)
            let name = v.prefix(while: { !$0.isWhitespace && $0 != ";" })
            if !name.isEmpty { return String(name) }
        }
        return nil
    }

    /// Decodes one quoted C string (`"..."`) into raw bytes.
    private static func unquote(_ s: Substring, _ lineNo: Int) throws -> [UInt8] {
        let bytes = Array(s.utf8)
        guard bytes.count >= 2, bytes.first == UInt8(ascii: "\""),
              bytes.last == UInt8(ascii: "\"") else {
            throw PoParseError(line: lineNo, message: "expected a quoted string")
        }
        var out: [UInt8] = []
        var i = 1
        let end = bytes.count - 1
        while i < end {
            let c = bytes[i]
            if c != UInt8(ascii: "\\") { out.append(c); i += 1; continue }
            i += 1
            guard i < end else { throw PoParseError(line: lineNo, message: "dangling backslash") }
            let e = bytes[i]
            i += 1
            switch e {
            case UInt8(ascii: "n"): out.append(10)
            case UInt8(ascii: "t"): out.append(9)
            case UInt8(ascii: "r"): out.append(13)
            case UInt8(ascii: "a"): out.append(7)
            case UInt8(ascii: "b"): out.append(8)
            case UInt8(ascii: "f"): out.append(12)
            case UInt8(ascii: "v"): out.append(11)
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                var v = Int(e - 48)
                var n = 1
                while n < 3, i < end, bytes[i] >= 48, bytes[i] <= 55 {
                    v = v * 8 + Int(bytes[i] - 48)
                    i += 1
                    n += 1
                }
                out.append(UInt8(truncatingIfNeeded: v))
            case UInt8(ascii: "x"):
                var v = 0
                var n = 0
                while i < end, let h = hexValue(bytes[i]) {
                    v = v * 16 + h
                    i += 1
                    n += 1
                }
                if n == 0 { throw PoParseError(line: lineNo, message: "bad \\x escape") }
                out.append(UInt8(truncatingIfNeeded: v))
            default: out.append(e)  // \" \\ \' and unknown escapes
            }
        }
        return out
    }

    private static func hexValue(_ b: UInt8) -> Int? {
        switch b {
        case 48...57: return Int(b - 48)
        case 97...102: return Int(b - 87)
        case 65...70: return Int(b - 55)
        default: return nil
        }
    }
}
