// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct LegacyConfigImporterTests {
    private func sampleURL() throws -> URL {
        try #require(Bundle.module.url(forResource: "sample-gitk-config", withExtension: nil, subdirectory: "Resources"))
    }

    private func tempHome() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitk-swift-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func place(_ source: URL, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: url)
    }

    @Test func importsSampleConfig() throws {
        let text = try String(contentsOf: sampleURL(), encoding: .utf8)
        let s = LegacyConfigImporter.parse(text)
        #expect(s.mainFont == FontSpec(family: "Menlo", pointSize: Settings().mainFont.pointSize))
        // Family only; Lucida Grande is a gitk default family and is not imported.
        #expect(s.textFont == FontSpec(family: "Courier New", pointSize: Settings().textFont.pointSize))
        #expect(s.uiFont == Settings().uiFont)
        #expect(s.diffContext == 5)
        #expect(s.tabStop == 4)
        #expect(s.autoCopy && !s.autoSelect && s.hideRemotes)
        #expect(s.autoSelLen == 12)
        #expect(s.dateTimeFormat == "%Y-%m-%d %H:%M")
        #expect(s.colors == ["#00ff00", "red", "blue", "magenta", "darkgrey", "brown", "orange"])
        #expect(s.diffBgColors == ["#fff3f3", "#f0fff0"])
        #expect(s.visibleRefs == ["master", "main"])
        #expect(s.wrapComment == "word")
        #expect(s.geometry == [
            "main": "1000x800+10+20", "state": "normal", "topwidth": "1000",
            "pwsash0": "300 1", "showrefs": "150",
        ])
        #expect(s.views == [
            SavedView(name: "Docs", files: ["docs", "with space"], args: ["--all", "--since=1.week"], argsCmd: ""),
            SavedView(name: "Mine", files: [], args: ["--author=me"], argsCmd: "echo --first-parent"),
        ])
    }

    @Test func codeIsSkippedNotExecuted() throws {
        let text = try String(contentsOf: sampleURL(), encoding: .utf8)
        let s = LegacyConfigImporter.parse(text)
        // `set headfgcolor "[exec echo red]"` is a command substitution: rejected.
        #expect(s.headFgColor == Settings().headFgColor)
        #expect(s.diffContext == 5)  // the rest is still imported
        #expect(!FileManager.default.fileExists(atPath: "/tmp/gitk-swift-should-not-exist"))
    }

    @Test func substitutionsAreRejectedUnlessBraced() {
        let s = LegacyConfigImporter.parse("""
            set tabstop $x
            set bgcolor "[exec echo red]"
            set fgcolor {[exec echo red]}
            set web_browser [exec echo x]
            set refstohide {$notvar}
            set tagbgcolor red extra
            set tagfgcolor
            """)
        #expect(s.tabStop == 8)
        #expect(s.bgColor == "white")
        #expect(s.fgColor == "black")  // braced but not a valid colour
        #expect(s.webBrowser == "open")
        #expect(s.refsToHide == "$notvar")
        #expect(s.tagBgColor == "yellow")
        #expect(s.tagFgColor == "black")
    }

    @Test func invalidValuesKeepDefaultsAndLaterSetWins() {
        let s = LegacyConfigImporter.parse("""
            set diffcontext lots
            set tabstop 2
            set tabstop 6
            set mainfont {Menlo big}
            set cmitmode weird
            set colors {red nosuchcolour}
            """)
        #expect(s.diffContext == 3)
        #expect(s.tabStop == 6)
        #expect(s.mainFont == Settings().mainFont)
        #expect(s.cmitMode == "patch")
        #expect(s.colors == Settings().colors)
    }

    @Test func lookupOrder() throws {
        let sample = try sampleURL()
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(LegacyConfigImporter.configFileURL(environment: [:], homeDirectory: home) == nil)

        try place(sample, at: home.appendingPathComponent(".gitk"))
        #expect(LegacyConfigImporter.configFileURL(environment: [:], homeDirectory: home)?.lastPathComponent == ".gitk")

        let dotConfig = home.appendingPathComponent(".config/git/gitk")
        try place(sample, at: dotConfig)
        #expect(LegacyConfigImporter.configFileURL(environment: [:], homeDirectory: home) == dotConfig)
        // Empty XDG_CONFIG_HOME counts as unset.
        #expect(LegacyConfigImporter.configFileURL(environment: ["XDG_CONFIG_HOME": ""], homeDirectory: home) == dotConfig)

        let xdg = home.appendingPathComponent("xdg")
        // XDG set but file missing there: falls back to ~/.gitk, as gitk does.
        #expect(LegacyConfigImporter.configFileURL(environment: ["XDG_CONFIG_HOME": xdg.path], homeDirectory: home)?
            .lastPathComponent == ".gitk")
        let xdgFile = xdg.appendingPathComponent("git/gitk")
        try place(sample, at: xdgFile)
        #expect(LegacyConfigImporter.configFileURL(environment: ["XDG_CONFIG_HOME": xdg.path], homeDirectory: home) == xdgFile)
    }

    @Test func importLeavesSourceBytesAndMtimeUntouched() throws {
        let sample = try sampleURL()
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".config/git/gitk")
        try place(sample, at: file)
        // Age the file so a rewrite would be visible in the mtime.
        let old = Date(timeIntervalSince1970: 1_500_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
        let bytesBefore = try Data(contentsOf: file)

        let imported = LegacyConfigImporter.importConfig(environment: [:], homeDirectory: home)
        #expect(imported?.diffContext == 5)

        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect(attrs[.modificationDate] as? Date == old)
        #expect(try Data(contentsOf: file) == bytesBefore)
        #expect(try Data(contentsOf: sample) == bytesBefore)
    }

    @Test func noFileGivesNil() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(LegacyConfigImporter.importConfig(environment: [:], homeDirectory: home) == nil)
    }
}

/// Legacy fonts: the family only, and never gitk's own default families.
@Suite struct LegacyFontImportTests {
    @Test func familyOnlyAndGitkDefaultsSkipped() {
        let defaults = Settings()
        let mono = LegacyConfigImporter.importedFont(FontSpec(family: "JetBrains Mono NL", pointSize: 8), over: defaults.textFont)
        #expect(mono == FontSpec(family: "JetBrains Mono NL", pointSize: defaults.textFont.pointSize))
        let ui = LegacyConfigImporter.importedFont(FontSpec(family: "Helvetica Neue", pointSize: 12, bold: true), over: defaults.uiFont)
        #expect(ui?.family == "Helvetica Neue" && ui?.bold == defaults.uiFont.bold)
        for family in ["Helvetica", "Lucida Grande", "sans", "Courier", "Monaco", "monospace"] {
            #expect(LegacyConfigImporter.importedFont(FontSpec(family: family, pointSize: 9), over: defaults.mainFont) == nil)
        }
    }
}
