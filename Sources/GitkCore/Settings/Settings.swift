// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// A view remembered across launches (gitk's `permviews` entry:
/// `{name files args argscmd}`).
struct SavedView: Codable, Sendable, Hashable {
    var name: String
    var files: [String]
    var args: [String]
    var argsCmd: String

    init(name: String, files: [String] = [], args: [String] = [], argsCmd: String = "") {
        self.name = name
        self.files = files
        self.args = args
        self.argsCmd = argsCmd
    }
}

/// User settings: one property per supported gitk `config_variables` entry, plus
/// `geometry` and `views`.
///
/// Port of the defaults in gitk/gitk 12616–12730 (aqua branch) and the variable list
/// 12748–12810, except:
/// - fonts use the system font at 12pt (design D9, represented with the
///   `FontSpec` sentinel families);
/// - `theme`, `themeloader`, `uicolor`, `uifgcolor`, `uifgdisabledcolor` are not
///   supported (they configure Tk's ttk theme).
///
/// Colours are stored as the original Tk colour strings (`"#00ff00"`, `"red"`,
/// `"gray85"`) so they round-trip and keep gitk semantics; the `...RGBA`
/// accessors resolve them with `TkColor`.
///
/// Decoding is tolerant: unknown keys are ignored, and missing or mistyped keys keep
/// their default, so older or hand-edited settings files still load.
struct Settings: Codable, Sendable, Equatable {
    // MARK: General
    var autoCopy = false
    var autoSelect = true
    /// gitk: `autosellen` defaults to `$hashlength` (40 for SHA-1 repositories).
    var autoSelLen = 40
    var cmitMode = "patch"
    var dateTimeFormat = "%Y-%m-%d %H:%M:%S"
    var diffContext = 3
    var extDiffTool = "opendiff"
    var findMergeFiles = false
    var hideRemotes = false
    var kscroll = 3
    var limitDiffs = true
    var maxGraphPct = 50
    var maxRefs = 20
    var maxWidth = 16
    var perFileAttrs = false
    var refsToHide = ""
    var showLocalChanges = true
    var showNearTags = true
    var sortRefsByType = true
    var tabStop = 8
    var visibleRefs = ["master"]
    var webBrowser = "open"
    var wrapComment = "none"
    var wrapDefault = "none"

    // MARK: Fonts
    var mainFont = FontSpec(family: FontSpec.systemFamily, pointSize: 12)
    var textFont = FontSpec(family: FontSpec.monospacedSystemFamily, pointSize: 12)
    var uiFont = FontSpec(family: FontSpec.systemFamily, pointSize: 12, bold: true)

    // MARK: Colours (Tk colour strings)
    var bgColor = "white"
    var fgColor = "black"
    var selectBgColor = "gray85"
    var colors = ["#00ff00", "red", "blue", "magenta", "darkgrey", "brown", "orange"]
    var diffColors = ["#c30000", "#009800", "blue"]
    var diffBgColors = ["#fff3f3", "#f0fff0"]
    var mergeColors = [
        "red", "blue", "#00ff00", "purple", "brown", "#009090", "magenta", "#808000",
        "#009000", "#ff0080", "cyan", "#b07070", "#70b0f0", "#70f0b0", "#f0b070", "#ff70b0",
    ]
    var markBgColor = "#e0e0ff"
    var headBgColor = "#00ff00"
    var headFgColor = "black"
    var headOutlineColor = "black"
    var remoteBgColor = "#ffddaa"
    var tagBgColor = "yellow"
    var tagFgColor = "black"
    var tagOutlineColor = "black"
    var refLineColor = "black"
    var fileSepBgColor = "#aaaaaa"
    var fileSepFgColor = "black"
    var lineHoverBgColor = "#ffff80"
    var lineHoverFgColor = "black"
    var lineHoverOutlineColor = "black"
    var mainHeadCircleColor = "yellow"
    var workingFilesCircleColor = "red"
    var indexCircleColor = "#00ff00"
    var circleColors = ["white", "blue", "gray", "blue", "blue"]
    var linkFgColor = "blue"
    /// gitk: `set circleoutlinecolor $fgcolor`, i.e. black by default.
    var circleOutlineColor = "black"
    var foundBgColor = "yellow"
    var currentSearchHitBgColor = "orange"

    // MARK: Window state and views
    /// gitk's `geometry(<key>)` array: `main`, `state`, `topwidth`, `topheight`,
    /// `pwsash0`, `pwsash1`, `botwidth`, `botheight`, `showrefs`. Values are the
    /// strings gitk writes (for example `"1000x800+10+20"`, `"300 1"`).
    var geometry: [String: String] = [:]
    var views: [SavedView] = []

    init() {}

    enum CodingKeys: String, CodingKey, CaseIterable {
        case autoCopy, autoSelect, autoSelLen, cmitMode, dateTimeFormat, diffContext
        case extDiffTool, findMergeFiles, hideRemotes, kscroll, limitDiffs, maxGraphPct
        case maxRefs, maxWidth, perFileAttrs, refsToHide, showLocalChanges, showNearTags
        case sortRefsByType, tabStop, visibleRefs, webBrowser, wrapComment, wrapDefault
        case mainFont, textFont, uiFont
        case bgColor, fgColor, selectBgColor, colors, diffColors, diffBgColors, mergeColors
        case markBgColor, headBgColor, headFgColor, headOutlineColor, remoteBgColor
        case tagBgColor, tagFgColor, tagOutlineColor, refLineColor, fileSepBgColor
        case fileSepFgColor, lineHoverBgColor, lineHoverFgColor, lineHoverOutlineColor
        case mainHeadCircleColor, workingFilesCircleColor, indexCircleColor, circleColors
        case linkFgColor, circleOutlineColor, foundBgColor, currentSearchHitBgColor
        case geometry, views
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var s = Settings()
        func v<T: Decodable>(_ key: CodingKeys, _ kp: WritableKeyPath<Settings, T>) {
            if let x = try? c.decodeIfPresent(T.self, forKey: key) { s[keyPath: kp] = x }
        }
        v(.autoCopy, \.autoCopy); v(.autoSelect, \.autoSelect); v(.autoSelLen, \.autoSelLen)
        v(.cmitMode, \.cmitMode); v(.dateTimeFormat, \.dateTimeFormat)
        v(.diffContext, \.diffContext); v(.extDiffTool, \.extDiffTool)
        v(.findMergeFiles, \.findMergeFiles); v(.hideRemotes, \.hideRemotes)
        v(.kscroll, \.kscroll); v(.limitDiffs, \.limitDiffs); v(.maxGraphPct, \.maxGraphPct)
        v(.maxRefs, \.maxRefs); v(.maxWidth, \.maxWidth); v(.perFileAttrs, \.perFileAttrs)
        v(.refsToHide, \.refsToHide); v(.showLocalChanges, \.showLocalChanges)
        v(.showNearTags, \.showNearTags); v(.sortRefsByType, \.sortRefsByType)
        v(.tabStop, \.tabStop); v(.visibleRefs, \.visibleRefs); v(.webBrowser, \.webBrowser)
        v(.wrapComment, \.wrapComment); v(.wrapDefault, \.wrapDefault)
        v(.mainFont, \.mainFont); v(.textFont, \.textFont); v(.uiFont, \.uiFont)
        v(.bgColor, \.bgColor); v(.fgColor, \.fgColor); v(.selectBgColor, \.selectBgColor)
        v(.colors, \.colors); v(.diffColors, \.diffColors); v(.diffBgColors, \.diffBgColors)
        v(.mergeColors, \.mergeColors); v(.markBgColor, \.markBgColor)
        v(.headBgColor, \.headBgColor); v(.headFgColor, \.headFgColor)
        v(.headOutlineColor, \.headOutlineColor); v(.remoteBgColor, \.remoteBgColor)
        v(.tagBgColor, \.tagBgColor); v(.tagFgColor, \.tagFgColor)
        v(.tagOutlineColor, \.tagOutlineColor); v(.refLineColor, \.refLineColor)
        v(.fileSepBgColor, \.fileSepBgColor); v(.fileSepFgColor, \.fileSepFgColor)
        v(.lineHoverBgColor, \.lineHoverBgColor); v(.lineHoverFgColor, \.lineHoverFgColor)
        v(.lineHoverOutlineColor, \.lineHoverOutlineColor)
        v(.mainHeadCircleColor, \.mainHeadCircleColor)
        v(.workingFilesCircleColor, \.workingFilesCircleColor)
        v(.indexCircleColor, \.indexCircleColor); v(.circleColors, \.circleColors)
        v(.linkFgColor, \.linkFgColor); v(.circleOutlineColor, \.circleOutlineColor)
        v(.foundBgColor, \.foundBgColor); v(.currentSearchHitBgColor, \.currentSearchHitBgColor)
        v(.geometry, \.geometry); v(.views, \.views)
        self = s
    }

    // MARK: RGBA accessors

    /// Resolves a Tk colour string; `nil` if it is not a valid Tk colour.
    static func rgba(_ spec: String) -> RGBA? { TkColor.parse(spec) }

    var bgRGBA: RGBA? { TkColor.parse(bgColor) }
    var fgRGBA: RGBA? { TkColor.parse(fgColor) }
    var selectBgRGBA: RGBA? { TkColor.parse(selectBgColor) }
    var markBgRGBA: RGBA? { TkColor.parse(markBgColor) }
    var headBgRGBA: RGBA? { TkColor.parse(headBgColor) }
    var headFgRGBA: RGBA? { TkColor.parse(headFgColor) }
    var headOutlineRGBA: RGBA? { TkColor.parse(headOutlineColor) }
    var remoteBgRGBA: RGBA? { TkColor.parse(remoteBgColor) }
    var tagBgRGBA: RGBA? { TkColor.parse(tagBgColor) }
    var tagFgRGBA: RGBA? { TkColor.parse(tagFgColor) }
    var tagOutlineRGBA: RGBA? { TkColor.parse(tagOutlineColor) }
    var refLineRGBA: RGBA? { TkColor.parse(refLineColor) }
    var fileSepBgRGBA: RGBA? { TkColor.parse(fileSepBgColor) }
    var fileSepFgRGBA: RGBA? { TkColor.parse(fileSepFgColor) }
    var lineHoverBgRGBA: RGBA? { TkColor.parse(lineHoverBgColor) }
    var lineHoverFgRGBA: RGBA? { TkColor.parse(lineHoverFgColor) }
    var lineHoverOutlineRGBA: RGBA? { TkColor.parse(lineHoverOutlineColor) }
    var mainHeadCircleRGBA: RGBA? { TkColor.parse(mainHeadCircleColor) }
    var workingFilesCircleRGBA: RGBA? { TkColor.parse(workingFilesCircleColor) }
    var indexCircleRGBA: RGBA? { TkColor.parse(indexCircleColor) }
    var linkFgRGBA: RGBA? { TkColor.parse(linkFgColor) }
    var circleOutlineRGBA: RGBA? { TkColor.parse(circleOutlineColor) }
    var foundBgRGBA: RGBA? { TkColor.parse(foundBgColor) }
    var currentSearchHitBgRGBA: RGBA? { TkColor.parse(currentSearchHitBgColor) }

    /// List-valued colour settings, resolved element by element (index preserved;
    /// an invalid entry is `nil`).
    var colorsRGBA: [RGBA?] { colors.map(TkColor.parse) }
    var diffColorsRGBA: [RGBA?] { diffColors.map(TkColor.parse) }
    var diffBgColorsRGBA: [RGBA?] { diffBgColors.map(TkColor.parse) }
    var mergeColorsRGBA: [RGBA?] { mergeColors.map(TkColor.parse) }
    var circleColorsRGBA: [RGBA?] { circleColors.map(TkColor.parse) }
}
