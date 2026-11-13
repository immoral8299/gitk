// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public enum PoConverter {
    /// Maps a `po/<name>.po` base name to its lproj directory name (design D11).
    public static func lprojName(forPo name: String) -> String {
        switch name.lowercased() {
        case "pt_br": return "pt-BR"
        case "pt_pt": return "pt-PT"
        case "zh_cn": return "zh-Hans"
        default: return name.lowercased()
        }
    }

    /// Removes Tk mnemonic markers: `&&` becomes `&`, a single `&` is dropped.
    public static func stripMnemonics(_ s: String) -> String {
        var out = ""
        var it = s.makeIterator()
        while let c = it.next() {
            if c == "&" {
                guard let n = it.next() else { break }
                out.append(n)
            } else {
                out.append(c)
            }
        }
        return out
    }

    /// Converts Tcl `format` specifiers to Foundation positional ones:
    /// `%s`/`%N$s` become `%N$@`, `%d`/`%N$d` become `%N$ld`, `%%` stays.
    /// Unnumbered specifiers are numbered sequentially within the string.
    public static func convertPlaceholders(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var next = 1
        var i = 0
        while i < chars.count {
            let c = chars[i]
            guard c == "%" else { out.append(c); i += 1; continue }
            if i + 1 < chars.count, chars[i + 1] == "%" { out += "%%"; i += 2; continue }
            var j = i + 1
            var digits = ""
            while j < chars.count, chars[j].isASCII, chars[j].isNumber {
                digits.append(chars[j])
                j += 1
            }
            var position: Int?
            if !digits.isEmpty, j < chars.count, chars[j] == "$" {
                position = Int(digits)
                j += 1
            } else {
                j = i + 1
            }
            if j < chars.count, chars[j] == "s" || chars[j] == "d", position != nil || digits.isEmpty {
                let n: Int
                if let p = position { n = p } else { n = next; next += 1 }
                out += "%\(n)$" + (chars[j] == "s" ? "@" : "ld")
                i = j + 1
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }

    /// Returns the sorted (key, value) pairs of a catalog, ready to be written.
    /// Skips fuzzy entries, empty translations, plural entries and the header.
    /// Placeholders are converted unless the entry is flagged `no-tcl-format`.
    public static func pairs(from catalog: PoCatalog) -> [(key: String, value: String)] {
        var seen = Set<String>()
        var result: [(key: String, value: String)] = []
        for e in catalog.entries {
            if e.isFuzzy || e.id.isEmpty || e.idPlural != nil || e.string.isEmpty { continue }
            var key = stripMnemonics(e.id)
            var value = stripMnemonics(e.string)
            if !e.flags.contains("no-tcl-format") {
                key = convertPlaceholders(key)
                value = convertPlaceholders(value)
            }
            if seen.insert(key).inserted { result.append((key, value)) }
        }
        return result.sorted { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) }
    }

    /// Escapes a string for a `.strings` quoted literal.
    public static func escape(_ s: String) -> String {
        var out = ""
        for u in s.unicodeScalars {
            switch u {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default: out.unicodeScalars.append(u)
            }
        }
        return out
    }

    /// Renders a catalog as the text of a `Localizable.strings` file.
    public static func stringsFile(from catalog: PoCatalog) -> String {
        var out = ""
        for (k, v) in pairs(from: catalog) {
            out += "\"\(escape(k))\" = \"\(escape(v))\";\n"
        }
        return out
    }

    /// Converts every `*.po` in `poDir` into `<outDir>/<lproj>.lproj/Localizable.strings`.
    /// Returns the lproj names written, sorted.
    @discardableResult
    public static func convertDirectory(poDir: URL, outDir: URL) throws -> [String] {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(atPath: poDir.path)
            .filter { $0.hasSuffix(".po") }.sorted()
        var written: [String] = []
        for f in files {
            let data = try Data(contentsOf: poDir.appendingPathComponent(f))
            let catalog: PoCatalog
            do { catalog = try PoParser.parse(data: data) } catch {
                throw NSError(domain: "po2strings", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "\(f): \(error)"])
            }
            guard catalog.charset.uppercased() == "UTF-8" else {
                throw NSError(domain: "po2strings", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "\(f): unsupported charset \(catalog.charset)"])
            }
            let lproj = lprojName(forPo: String(f.dropLast(3)))
            let dir = outDir.appendingPathComponent("\(lproj).lproj", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(stringsFile(from: catalog).utf8)
                .write(to: dir.appendingPathComponent("Localizable.strings"), options: .atomic)
            written.append(lproj)
        }
        return written.sorted()
    }
}
