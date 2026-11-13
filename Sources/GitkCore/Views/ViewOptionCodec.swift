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

    /// Tcl `string trim`: strips space, tab, newline, CR, VT and FF.
    static func tclTrim(_ s: String) -> String {
        let ws: Set<Unicode.Scalar> = [" ", "\t", "\n", "\r", "\u{0B}", "\u{0C}"]
        var u = Substring(s).unicodeScalars
        while let f = u.first, ws.contains(f) { u.removeFirst() }
        while let l = u.last, ws.contains(l) { u.removeLast() }
        return String(String.UnicodeScalarView(u))
    }
}
