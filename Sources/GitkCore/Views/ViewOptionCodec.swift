// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Conversion between the view editor's fields and `git log` arguments.
public enum ViewOptionCodec {
    /// Port of gitk proc `encode_view_opts` (gitk/gitk 4338–4369). Throws a
    /// `ViewArgsError` ("Error in commit selection arguments:") when the
    /// refs or args field has a quoting error.
    public static func encode(_ v: ViewOptionValues) throws -> [String] {
        var rargs: [String] = []
        for opt in ViewOptions.known {
            guard let pattern = opt.patterns.first else { continue }
            switch opt.kind {
            case .checkbox:
                if v.bool(opt.id) { rargs.append(pattern) }
            case .radio(let value):
                if let group = opt.radioGroup, v.radio(group) == value {
                    rargs.append(pattern)
                }
            default:
                let val = tclTrim(v.text(opt.id))
                if !val.isEmpty {
                    rargs.append(String(pattern.dropLast()) + val)
                }
            }
        }
        do {
            rargs += try ShellWords.split(v.text("refs"))
            rargs += try ShellWords.split(v.text("args"))
        } catch let e as ShellWords.Error {
            throw ViewArgsError(prefix: "Error in commit selection arguments:", detail: e.message)
        }
        return rargs
    }

    /// Port of gitk proc `decode_view_opts` (gitk/gitk 4372–4432). The name
    /// is left empty, as gitk's callers set it separately.
    public static func decode(_ viewArgs: [String]) -> ViewOptionValues {
        var out = ViewOptionValues()
        for opt in ViewOptions.known {
            switch opt.kind {
            case .checkbox:
                out.values[opt.id] = .bool(false)
            case .radio:
                if let g = opt.radioGroup { out.values[g] = .radio(0) }
            case .label, .path:
                // gitk also initializes these ids (to {}); they hold no value.
                break
            case .text, .textStacked:
                out.values[opt.id] = .text("")
            }
        }
        var oargs: [String] = []
        var refargs: [String] = []
        var found = Set<String>()
        for arg in viewArgs {
            if !found.contains("limit"), let cnt = limitCount(arg) {
                out.values["limit"] = .text(cnt)
                found.insert("limit")
                continue
            }
            var matched = false
            search: for opt in ViewOptions.known {
                if found.contains(opt.id) { continue }
                for pattern in opt.patterns where TclGlob.matches(pattern: pattern, arg) {
                    var id = opt.id
                    let val: ViewOptionValue
                    switch opt.kind {
                    case .checkbox:
                        val = .bool(true)
                    case .radio(let num):
                        id = opt.radioGroup ?? id
                        val = .radio(num)
                    default:
                        let size = pattern.unicodeScalars.count
                        val = .text(String(String.UnicodeScalarView(
                            arg.unicodeScalars.dropFirst(size - 1))))
                    }
                    out.values[id] = val
                    found.insert(id)
                    matched = true
                    break search
                }
            }
            if matched { continue }
            if arg.hasPrefix("-") {
                oargs.append(arg)
            } else {
                refargs.append(arg)
            }
        }
        out.values["refs"] = .text(ShellWords.argList(refargs))
        out.values["args"] = .text(ShellWords.argList(oargs))
        return out
    }

    /// `regexp -- {^-([0-9]+)$}`: the digits of a `-<n>` argument.
    private static func limitCount(_ arg: String) -> String? {
        let rest = arg.unicodeScalars.dropFirst()
        guard arg.hasPrefix("-"), !rest.isEmpty,
              rest.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else { return nil }
        return String(String.UnicodeScalarView(rest))
    }

    /// Tcl `string trim`: strips space, tab, newline, CR, VT and FF.
    static func tclTrim(_ s: String) -> String {
        let ws: Set<Unicode.Scalar> = [" ", "\t", "\n", "\r", "\u{0B}", "\u{0C}"]
        var u = Substring(s).unicodeScalars
        while let f = u.first, ws.contains(f) { u.removeFirst() }
        while let l = u.last, ws.contains(l) { u.removeLast() }
        return String(String.UnicodeScalarView(u))
    }
}
