// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// A view remembered across launches (gitk's `permviews` entry:
/// `{name files args argscmd}`).
public struct SavedView: Codable, Sendable, Hashable {
    public var name: String
    public var files: [String]
    public var args: [String]
    public var argsCmd: String

    public init(name: String, files: [String] = [], args: [String] = [], argsCmd: String = "") {
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
public struct Settings: Codable, Sendable, Equatable {
    // MARK: General
    public var autoCopy = false
    public var autoSelect = true
    /// gitk: `autosellen` defaults to `$hashlength` (40 for SHA-1 repositories).
    public var autoSelLen = 40
    public var cmitMode = "patch"
    public var dateTimeFormat = "%Y-%m-%d %H:%M:%S"
    public var diffContext = 3
    public var extDiffTool = "opendiff"
    public var findMergeFiles = false
    public var hideRemotes = false
    public var kscroll = 3
    public var limitDiffs = true
    public var maxGraphPct = 50
    public var maxRefs = 20
    public var maxWidth = 16
    public var perFileAttrs = false
    public var refsToHide = ""
    public var showLocalChanges = true
    public var showNearTags = true
    public var sortRefsByType = true
    public var tabStop = 8
    public var visibleRefs = ["master"]
    public var webBrowser = "open"
    public var wrapComment = "none"
    public var wrapDefault = "none"

    // MARK: Fonts
    public var mainFont = FontSpec(family: FontSpec.systemFamily, pointSize: 12)
    public var textFont = FontSpec(family: FontSpec.monospacedSystemFamily, pointSize: 12)
    public var uiFont = FontSpec(family: FontSpec.systemFamily, pointSize: 12, bold: true)

    // MARK: Colours (Tk colour strings)
    public var bgColor = "white"
    public var fgColor = "black"
    public var selectBgColor = "gray85"
    public var colors = ["#00ff00", "red", "blue", "magenta", "darkgrey", "brown", "orange"]
    public var diffColors = ["#c30000", "#009800", "blue"]
    public var diffBgColors = ["#fff3f3", "#f0fff0"]
    public var mergeColors = [
        "red", "blue", "#00ff00", "purple", "brown", "#009090", "magenta", "#808000",
        "#009000", "#ff0080", "cyan", "#b07070", "#70b0f0", "#70f0b0", "#f0b070", "#ff70b0",
    ]
    public var markBgColor = "#e0e0ff"
    public var headBgColor = "#00ff00"
    public var headFgColor = "black"
    public var headOutlineColor = "black"
    public var remoteBgColor = "#ffddaa"
    public var tagBgColor = "yellow"
    public var tagFgColor = "black"
    public var tagOutlineColor = "black"
    public var refLineColor = "black"
    public var fileSepBgColor = "#aaaaaa"
    public var fileSepFgColor = "black"
    public var lineHoverBgColor = "#ffff80"
    public var lineHoverFgColor = "black"
    public var lineHoverOutlineColor = "black"
    public var mainHeadCircleColor = "yellow"
    public var workingFilesCircleColor = "red"
    public var indexCircleColor = "#00ff00"
    public var circleColors = ["white", "blue", "gray", "blue", "blue"]
    public var linkFgColor = "blue"
    /// gitk: `set circleoutlinecolor $fgcolor`, i.e. black by default.
    public var circleOutlineColor = "black"
    public var foundBgColor = "yellow"
    public var currentSearchHitBgColor = "orange"

    // MARK: Window state and views
    /// gitk's `geometry(<key>)` array: `main`, `state`, `topwidth`, `topheight`,
    /// `pwsash0`, `pwsash1`, `botwidth`, `botheight`, `showrefs`. Values are the
    /// strings gitk writes (for example `"1000x800+10+20"`, `"300 1"`).
    public var geometry: [String: String] = [:]
    public var views: [SavedView] = []

    public init() {}

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

    public init(from decoder: Decoder) throws {
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

    public var bgRGBA: RGBA? { TkColor.parse(bgColor) }
    public var fgRGBA: RGBA? { TkColor.parse(fgColor) }
    public var selectBgRGBA: RGBA? { TkColor.parse(selectBgColor) }
    public var markBgRGBA: RGBA? { TkColor.parse(markBgColor) }
    public var headBgRGBA: RGBA? { TkColor.parse(headBgColor) }
    public var headFgRGBA: RGBA? { TkColor.parse(headFgColor) }
    public var headOutlineRGBA: RGBA? { TkColor.parse(headOutlineColor) }
    public var remoteBgRGBA: RGBA? { TkColor.parse(remoteBgColor) }
    public var tagBgRGBA: RGBA? { TkColor.parse(tagBgColor) }
    public var tagFgRGBA: RGBA? { TkColor.parse(tagFgColor) }
    public var tagOutlineRGBA: RGBA? { TkColor.parse(tagOutlineColor) }
    public var refLineRGBA: RGBA? { TkColor.parse(refLineColor) }
    public var fileSepBgRGBA: RGBA? { TkColor.parse(fileSepBgColor) }
    public var fileSepFgRGBA: RGBA? { TkColor.parse(fileSepFgColor) }
    public var lineHoverBgRGBA: RGBA? { TkColor.parse(lineHoverBgColor) }
    public var lineHoverFgRGBA: RGBA? { TkColor.parse(lineHoverFgColor) }
    public var lineHoverOutlineRGBA: RGBA? { TkColor.parse(lineHoverOutlineColor) }
    public var mainHeadCircleRGBA: RGBA? { TkColor.parse(mainHeadCircleColor) }
    public var workingFilesCircleRGBA: RGBA? { TkColor.parse(workingFilesCircleColor) }
    public var indexCircleRGBA: RGBA? { TkColor.parse(indexCircleColor) }
    public var linkFgRGBA: RGBA? { TkColor.parse(linkFgColor) }
    public var circleOutlineRGBA: RGBA? { TkColor.parse(circleOutlineColor) }
    public var foundBgRGBA: RGBA? { TkColor.parse(foundBgColor) }
    public var currentSearchHitBgRGBA: RGBA? { TkColor.parse(currentSearchHitBgColor) }

    /// List-valued colour settings, resolved element by element (index preserved;
    /// an invalid entry is `nil`).
    public var colorsRGBA: [RGBA?] { colors.map(TkColor.parse) }
    public var diffColorsRGBA: [RGBA?] { diffColors.map(TkColor.parse) }
    public var diffBgColorsRGBA: [RGBA?] { diffBgColors.map(TkColor.parse) }
    public var mergeColorsRGBA: [RGBA?] { mergeColors.map(TkColor.parse) }
    public var circleColorsRGBA: [RGBA?] { circleColors.map(TkColor.parse) }
}
