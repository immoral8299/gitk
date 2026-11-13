// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// One-way import of a Tcl gitk configuration file (design D9). No Tcl is ever
/// evaluated: the file is split into commands with `TclList`, and only
/// `set <name> <value>` commands whose name is a supported variable or
/// `geometry(<key>)` are accepted. Everything else (`proc`, `exec`, `source`,
/// `set x [cmd]`, unknown variables, unsupported ones such as `theme`) is skipped
/// silently. The file is only read, never written.
enum LegacyConfigImporter {
    /// Port of the config-file lookup in gitk/gitk 12733–12746.
    ///
    /// `$XDG_CONFIG_HOME/git/gitk` if `XDG_CONFIG_HOME` is set and non-empty, else
    /// `<home>/.config/git/gitk`; if that does not exist, `<home>/.gitk`. Returns
    /// `nil` if neither exists.
    static func configFileURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let fm = FileManager.default
        let primary: URL
        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            primary = URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent("git/gitk")
        } else {
            primary = homeDirectory.appendingPathComponent(".config/git/gitk")
        }
        if fm.fileExists(atPath: primary.path) { return primary }
        let old = homeDirectory.appendingPathComponent(".gitk")
        return fm.fileExists(atPath: old.path) ? old : nil
    }

    /// Finds and imports the legacy config. Returns `nil` if there is no readable file.
    static func importConfig(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Settings? {
        guard let url = configFileURL(environment: environment, homeDirectory: homeDirectory),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Applies every acceptable `set` command in `script` on top of `base`.
    /// Later commands override earlier ones, as in Tcl.
    static func parse(_ script: String, into base: Settings = Settings()) -> Settings {
        var settings = base
        var viewsFromFile: [SavedView]?
        for command in TclList.splitCommands(script) {
            guard let words = try? TclList.split(command), words.count == 3, words[0] == "set"
            else { continue }
            let name = words[1]
            let value = words[2]
            if !isLiteral(command: command, value: value) { continue }
            if name == "permviews" {
                viewsFromFile = parseViews(value)
            } else if let key = geometryKey(name) {
                settings.geometry[key] = value
            } else {
                _ = apply(name, value, to: &settings)
            }
        }
        if let views = viewsFromFile { settings.views = views }
        return settings
    }

    // MARK: - Safety

    /// A value is literal if it was braced, or contains no command (`[`) or variable
    /// (`$`) substitution. Backslash sequences are already resolved by `TclList.split`.
    private static func isLiteral(command: String, value: String) -> Bool {
        if !value.contains("[") && !value.contains("$") { return true }
        return thirdWordIsBraced(command)
    }

    private static func thirdWordIsBraced(_ command: String) -> Bool {
        let c = Array(command.unicodeScalars)
        var i = 0
        for _ in 0..<2 {
            while i < c.count, isBlank(c[i]) { i += 1 }
            guard i < c.count else { return false }
            if c[i] == "{" {
                var depth = 0
                while i < c.count {
                    if c[i] == "\\" { i += 2; continue }
                    if c[i] == "{" { depth += 1 }
                    if c[i] == "}" { depth -= 1; if depth == 0 { i += 1; break } }
                    i += 1
                }
            } else if c[i] == "\"" {
                i += 1
                while i < c.count, c[i] != "\"" { i += c[i] == "\\" ? 2 : 1 }
                i += 1
            } else {
                while i < c.count, !isBlank(c[i]) { i += 1 }
            }
        }
        while i < c.count, isBlank(c[i]) { i += 1 }
        return i < c.count && c[i] == "{"
    }

    private static func isBlank(_ u: Unicode.Scalar) -> Bool {
        u == " " || u == "\t" || u == "\n" || u == "\r"
    }

    // MARK: - Mapping

    private static func geometryKey(_ name: String) -> String? {
        guard name.hasPrefix("geometry("), name.hasSuffix(")") else { return nil }
        let key = String(name.dropFirst("geometry(".count).dropLast())
        let ok = !key.isEmpty && key.unicodeScalars.allSatisfy {
            $0 == "_" || ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0)
        }
        return ok ? key : nil
    }

    /// Parses `permviews`: a list of `{name files args argscmd}`; `files` and `args` are lists.
    /// Malformed entries are skipped; a repeated name replaces the earlier entry in place.
    private static func parseViews(_ value: String) -> [SavedView] {
        guard let entries = try? TclList.split(value) else { return [] }
        var views: [SavedView] = []
        for entry in entries {
            guard let fields = try? TclList.split(entry), let name = fields.first else { continue }
            let files = fields.count > 1 ? (try? TclList.split(fields[1])) : []
            let args = fields.count > 2 ? (try? TclList.split(fields[2])) : []
            guard let files, let args else { continue }
            let view = SavedView(name: name, files: files, args: args, argsCmd: fields.count > 3 ? fields[3] : "")
            if let existing = views.firstIndex(where: { $0.name == name }) {
                views[existing] = view
            } else {
                views.append(view)
            }
        }
        return views
    }

    private static func bool(_ s: String) -> Bool? {
        switch s.lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: return nil
        }
    }

    private static func int(_ s: String) -> Int? {
        Int(s.trimmingCharacters(in: .whitespaces))
    }

    private static func colour(_ s: String) -> String? {
        TkColor.parse(s) == nil ? nil : s
    }

    private static func colourList(_ s: String) -> [String]? {
        guard let items = try? TclList.split(s), !items.isEmpty,
              items.allSatisfy({ TkColor.parse($0) != nil })
        else { return nil }
        return items
    }

    /// Applies one supported variable; returns `false` if the name is unsupported or the
    /// value is invalid (the setting then keeps its previous value).
    private static func apply(_ name: String, _ v: String, to s: inout Settings) -> Bool {
        func set<T>(_ kp: WritableKeyPath<Settings, T>, _ value: T?) -> Bool {
            guard let value else { return false }
            s[keyPath: kp] = value
            return true
        }
        func oneOf(_ allowed: [String]) -> String? { allowed.contains(v) ? v : nil }
        switch name {
        case "autocopy": return set(\.autoCopy, bool(v))
        case "autoselect": return set(\.autoSelect, bool(v))
        case "autosellen": return set(\.autoSelLen, int(v))
        case "cmitmode": return set(\.cmitMode, oneOf(["patch", "tree"]))
        case "datetimeformat": return set(\.dateTimeFormat, v)
        case "diffcontext": return set(\.diffContext, int(v))
        case "extdifftool": return set(\.extDiffTool, v)
        case "findmergefiles": return set(\.findMergeFiles, bool(v))
        case "hideremotes": return set(\.hideRemotes, bool(v))
        case "kscroll": return set(\.kscroll, int(v))
        case "limitdiffs": return set(\.limitDiffs, bool(v))
        case "maxgraphpct": return set(\.maxGraphPct, int(v))
        case "maxrefs": return set(\.maxRefs, int(v))
        case "maxwidth": return set(\.maxWidth, int(v))
        case "perfile_attrs": return set(\.perFileAttrs, bool(v))
        case "refstohide": return set(\.refsToHide, v)
        case "showlocalchanges": return set(\.showLocalChanges, bool(v))
        case "showneartags": return set(\.showNearTags, bool(v))
        case "sortrefsbytype": return set(\.sortRefsByType, bool(v))
        case "tabstop": return set(\.tabStop, int(v))
        case "visiblerefs": return set(\.visibleRefs, try? TclList.split(v))
        case "web_browser": return set(\.webBrowser, v)
        case "wrapcomment": return set(\.wrapComment, oneOf(["none", "char", "word"]))
        case "wrapdefault": return set(\.wrapDefault, oneOf(["none", "char", "word"]))
        case "mainfont": return set(\.mainFont, TkFont.parse(v))
        case "textfont": return set(\.textFont, TkFont.parse(v))
        case "uifont": return set(\.uiFont, TkFont.parse(v))
        case "bgcolor": return set(\.bgColor, colour(v))
        case "fgcolor": return set(\.fgColor, colour(v))
        case "selectbgcolor": return set(\.selectBgColor, colour(v))
        case "colors": return set(\.colors, colourList(v))
        case "diffcolors": return set(\.diffColors, colourList(v))
        case "diffbgcolors": return set(\.diffBgColors, colourList(v))
        case "mergecolors": return set(\.mergeColors, colourList(v))
        case "markbgcolor": return set(\.markBgColor, colour(v))
        case "headbgcolor": return set(\.headBgColor, colour(v))
        case "headfgcolor": return set(\.headFgColor, colour(v))
        case "headoutlinecolor": return set(\.headOutlineColor, colour(v))
        case "remotebgcolor": return set(\.remoteBgColor, colour(v))
        case "tagbgcolor": return set(\.tagBgColor, colour(v))
        case "tagfgcolor": return set(\.tagFgColor, colour(v))
        case "tagoutlinecolor": return set(\.tagOutlineColor, colour(v))
        case "reflinecolor": return set(\.refLineColor, colour(v))
        case "filesepbgcolor": return set(\.fileSepBgColor, colour(v))
        case "filesepfgcolor": return set(\.fileSepFgColor, colour(v))
        case "linehoverbgcolor": return set(\.lineHoverBgColor, colour(v))
        case "linehoverfgcolor": return set(\.lineHoverFgColor, colour(v))
        case "linehoveroutlinecolor": return set(\.lineHoverOutlineColor, colour(v))
        case "mainheadcirclecolor": return set(\.mainHeadCircleColor, colour(v))
        case "workingfilescirclecolor": return set(\.workingFilesCircleColor, colour(v))
        case "indexcirclecolor": return set(\.indexCircleColor, colour(v))
        case "circlecolors": return set(\.circleColors, colourList(v))
        case "linkfgcolor": return set(\.linkFgColor, colour(v))
        case "circleoutlinecolor": return set(\.circleOutlineColor, colour(v))
        case "foundbgcolor": return set(\.foundBgColor, colour(v))
        case "currentsearchhitbgcolor": return set(\.currentSearchHitBgColor, colour(v))
        default: return false  // theme, themeloader, uicolor, uifgcolor, uifgdisabledcolor, unknown
        }
    }
}
