// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct SettingsDefaultsTests {
    /// gitk `config_variables` (gitk/gitk 12748–12810), copied verbatim.
    static let configVariables = """
        autocopy autoselect autosellen bgcolor circlecolors circleoutlinecolor cmitmode colors
        currentsearchhitbgcolor datetimeformat diffbgcolors diffcolors diffcontext extdifftool
        fgcolor filesepbgcolor filesepfgcolor findmergefiles foundbgcolor headbgcolor headfgcolor
        headoutlinecolor hideremotes indexcirclecolor kscroll limitdiffs linehoverbgcolor
        linehoverfgcolor linehoveroutlinecolor linkfgcolor mainfont mainheadcirclecolor markbgcolor
        maxgraphpct maxrefs maxwidth mergecolors perfile_attrs reflinecolor refstohide
        remotebgcolor selectbgcolor showlocalchanges showneartags sortrefsbytype tabstop tagbgcolor
        tagfgcolor tagoutlinecolor textfont theme themeloader uicolor uifgcolor uifgdisabledcolor
        uifont visiblerefs web_browser workingfilescirclecolor wrapcomment wrapdefault
        """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)

    /// Variables deliberately not supported (Tk ttk theme configuration).
    static let excluded: Set<String> = [
        "theme", "themeloader", "uicolor", "uifgcolor", "uifgdisabledcolor",
    ]

    /// gitk name, value from `Settings()`, and the aqua default from gitk/gitk 12616–12730
    /// (rendered as text). Fonts are checked separately (design D9).
    static var table: [(String, @Sendable (Settings) -> String, String)] { [
        ("tabstop", { "\($0.tabStop)" }, "8"),
        ("findmergefiles", { "\($0.findMergeFiles)" }, "false"),
        ("maxgraphpct", { "\($0.maxGraphPct)" }, "50"),
        ("maxwidth", { "\($0.maxWidth)" }, "16"),
        ("cmitmode", { $0.cmitMode }, "patch"),
        ("wrapcomment", { $0.wrapComment }, "none"),
        ("wrapdefault", { $0.wrapDefault }, "none"),
        ("showneartags", { "\($0.showNearTags)" }, "true"),
        ("hideremotes", { "\($0.hideRemotes)" }, "false"),
        ("refstohide", { $0.refsToHide }, ""),
        ("sortrefsbytype", { "\($0.sortRefsByType)" }, "true"),
        ("maxrefs", { "\($0.maxRefs)" }, "20"),
        ("visiblerefs", { $0.visibleRefs.joined(separator: "|") }, "master"),
        ("showlocalchanges", { "\($0.showLocalChanges)" }, "true"),
        ("limitdiffs", { "\($0.limitDiffs)" }, "true"),
        ("kscroll", { "\($0.kscroll)" }, "3"),
        ("datetimeformat", { $0.dateTimeFormat }, "%Y-%m-%d %H:%M:%S"),
        ("autocopy", { "\($0.autoCopy)" }, "false"),
        ("autoselect", { "\($0.autoSelect)" }, "true"),
        ("autosellen", { "\($0.autoSelLen)" }, "40"),
        ("perfile_attrs", { "\($0.perFileAttrs)" }, "false"),
        ("extdifftool", { $0.extDiffTool }, "opendiff"),
        ("colors", { $0.colors.joined(separator: "|") }, "#00ff00|red|blue|magenta|darkgrey|brown|orange"),
        ("bgcolor", { $0.bgColor }, "white"),
        ("fgcolor", { $0.fgColor }, "black"),
        ("selectbgcolor", { $0.selectBgColor }, "gray85"),
        ("web_browser", { $0.webBrowser }, "open"),
        ("diffcolors", { $0.diffColors.joined(separator: "|") }, "#c30000|#009800|blue"),
        ("diffbgcolors", { $0.diffBgColors.joined(separator: "|") }, "#fff3f3|#f0fff0"),
        ("diffcontext", { "\($0.diffContext)" }, "3"),
        ("mergecolors", { $0.mergeColors.joined(separator: "|") },
         "red|blue|#00ff00|purple|brown|#009090|magenta|#808000|#009000|#ff0080|cyan|#b07070|#70b0f0|#70f0b0|#f0b070|#ff70b0"),
        ("markbgcolor", { $0.markBgColor }, "#e0e0ff"),
        ("headbgcolor", { $0.headBgColor }, "#00ff00"),
        ("headfgcolor", { $0.headFgColor }, "black"),
        ("headoutlinecolor", { $0.headOutlineColor }, "black"),
        ("remotebgcolor", { $0.remoteBgColor }, "#ffddaa"),
        ("tagbgcolor", { $0.tagBgColor }, "yellow"),
        ("tagfgcolor", { $0.tagFgColor }, "black"),
        ("tagoutlinecolor", { $0.tagOutlineColor }, "black"),
        ("reflinecolor", { $0.refLineColor }, "black"),
        ("filesepbgcolor", { $0.fileSepBgColor }, "#aaaaaa"),
        ("filesepfgcolor", { $0.fileSepFgColor }, "black"),
        ("linehoverbgcolor", { $0.lineHoverBgColor }, "#ffff80"),
        ("linehoverfgcolor", { $0.lineHoverFgColor }, "black"),
        ("linehoveroutlinecolor", { $0.lineHoverOutlineColor }, "black"),
        ("mainheadcirclecolor", { $0.mainHeadCircleColor }, "yellow"),
        ("workingfilescirclecolor", { $0.workingFilesCircleColor }, "red"),
        ("indexcirclecolor", { $0.indexCircleColor }, "#00ff00"),
        ("circlecolors", { $0.circleColors.joined(separator: "|") }, "white|blue|gray|blue|blue"),
        ("linkfgcolor", { $0.linkFgColor }, "blue"),
        ("circleoutlinecolor", { $0.circleOutlineColor }, "black"),
        ("foundbgcolor", { $0.foundBgColor }, "yellow"),
        ("currentsearchhitbgcolor", { $0.currentSearchHitBgColor }, "orange"),
    ] }

    @Test func everyDefaultMatchesGitk() {
        let s = Settings()
        for (name, actual, expected) in Self.table {
            #expect(actual(s) == expected, "\(name)")
        }
    }

    @Test func fontsAreSystemFontsPerD9() {
        let s = Settings()
        #expect(s.mainFont == FontSpec(family: FontSpec.systemFamily, pointSize: 12))
        #expect(s.textFont == FontSpec(family: FontSpec.monospacedSystemFamily, pointSize: 12))
        #expect(s.uiFont == FontSpec(family: FontSpec.systemFamily, pointSize: 12, bold: true))
    }

    @Test func tableCoversEveryConfigVariable() {
        var covered = Set(Self.table.map { $0.0 })
        covered.formUnion(["mainfont", "textfont", "uifont"])
        covered.formUnion(Self.excluded)
        #expect(covered == Set(Self.configVariables))
        #expect(Self.configVariables.count == Set(Self.configVariables).count)
    }

    @Test func everyDefaultColourResolves() {
        let s = Settings()
        let singles = [
            s.bgRGBA, s.fgRGBA, s.selectBgRGBA, s.markBgRGBA, s.headBgRGBA, s.headFgRGBA,
            s.headOutlineRGBA, s.remoteBgRGBA, s.tagBgRGBA, s.tagFgRGBA, s.tagOutlineRGBA,
            s.refLineRGBA, s.fileSepBgRGBA, s.fileSepFgRGBA, s.lineHoverBgRGBA,
            s.lineHoverFgRGBA, s.lineHoverOutlineRGBA, s.mainHeadCircleRGBA,
            s.workingFilesCircleRGBA, s.indexCircleRGBA, s.linkFgRGBA, s.circleOutlineRGBA,
            s.foundBgRGBA, s.currentSearchHitBgRGBA,
        ]
        #expect(singles.allSatisfy { $0 != nil })
        let lists = s.colorsRGBA + s.diffColorsRGBA + s.diffBgColorsRGBA + s.mergeColorsRGBA
            + s.circleColorsRGBA
        #expect(lists.allSatisfy { $0 != nil })
        #expect(s.headBgRGBA == RGBA(r: 0, g: 255, b: 0))
        #expect(s.tagBgRGBA == RGBA(r: 255, g: 255, b: 0))
    }

    @Test func emptyCollectionsByDefault() {
        let s = Settings()
        #expect(s.geometry.isEmpty)
        #expect(s.views.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        var s = Settings()
        s.diffContext = 7
        s.headBgColor = "salmon"
        s.mainFont = FontSpec(family: "Menlo", pointSize: 11, bold: true, italic: true)
        s.geometry = ["main": "1000x800+1+2", "pwsash0": "300 1"]
        s.views = [SavedView(name: "v", files: ["a b", "c"], args: ["--all"], argsCmd: "echo")]
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(Settings.self, from: data) == s)
    }

    @Test func missingKeysUseDefaultsAndUnknownKeysAreIgnored() throws {
        let json = #"{"diffContext": 9, "futureSetting": [1,2], "tabStop": "oops"}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        var expected = Settings()
        expected.diffContext = 9
        #expect(s == expected)
        #expect(try JSONDecoder().decode(Settings.self, from: Data("{}".utf8)) == Settings())
    }
}
