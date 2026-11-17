// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor
@Suite struct FontSettingsTests {
    private func make() -> PreferencesController {
        PreferencesController(settings: Settings(), notificationCenter: NotificationCenter())
    }

    @Test func sizeArithmeticClampsAtOne() {
        let base = Settings()
        let up = FontSizing.incremented(base, by: 1)
        #expect(up.mainFont.pointSize == base.mainFont.pointSize + 1)
        #expect(up.textFont.pointSize == base.textFont.pointSize + 1)
        #expect(up.uiFont.pointSize == base.uiFont.pointSize + 1)
        var tiny = base
        tiny.mainFont.pointSize = 1
        #expect(FontSizing.incremented(tiny, by: -1).mainFont.pointSize == 1)
        #expect(FontSizing.incremented(FontSpec(family: "x", pointSize: 12, bold: true), by: -3).bold)
    }

    @Test func rowsInGitkOrder() {
        let c = make()
        #expect(PreferencesController.fontSettings.map(\.id) == ["main", "text", "ui"])
        #expect(c.fontButtons.count == 3)
        #expect(c.fontButtons["text"]?.title == L("Choose..."))
    }

    /// Spec "Change the text font": Menlo 12 chosen, OK, the diff is drawn in Menlo 12.
    @Test func textFontReachesDiff() throws {
        let c = make()
        var applied: Settings?
        c.onApply = { applied = $0 }
        c.applyChosenFont(try #require(NSFont(name: "Menlo-Regular", size: 12)), row: "text")
        #expect(c.draft.textFont.family == "Menlo")
        #expect(c.fontLabels["text"]?.stringValue == "Menlo")
        c.okAction()
        let s = try #require(applied)
        var renderer = DiffRenderer(settings: s)
        let text = renderer.render(.add(Data("new".utf8)))
        let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.familyName == "Menlo")
        #expect(font.pointSize == 12)
    }

    @Test func systemFontsMapToSentinels() {
        #expect(PreferencesController.fontSpec(from: .systemFont(ofSize: 13)).family == FontSpec.systemFamily)
        #expect(PreferencesController.fontSpec(from: .monospacedSystemFont(ofSize: 13, weight: .regular)).family
                == FontSpec.monospacedSystemFamily)
    }

    /// Spec "Increase font": two bigger steps make all fonts 2 points bigger, and the
    /// size survives a save and load.
    @Test func increaseTwicePersists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fontsize-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(environment: ["GITK_SWIFT_CONFIG_DIR": dir.path])
        var s = Settings()
        s = FontSizing.incremented(s, by: 1)
        s = FontSizing.incremented(s, by: 1)
        _ = try store.save(s)
        let loaded = SettingsStore(environment: ["GITK_SWIFT_CONFIG_DIR": dir.path]).load()
        #expect(loaded.mainFont.pointSize == Settings().mainFont.pointSize + 2)
        #expect(loaded.textFont.pointSize == Settings().textFont.pointSize + 2)
        #expect(loaded.uiFont.pointSize == Settings().uiFont.pointSize + 2)
    }

    /// ⌘-0 puts all three fonts back at their default size. The families and
    /// styles chosen in Preferences stay, and other settings are untouched.
    @Test func commandZeroResetsSizesAndKeepsFamilies() {
        var s = Settings()
        s.mainFont = FontSpec(family: "Menlo", pointSize: 12)
        s.textFont = FontSpec(family: "Menlo", pointSize: 12)
        s.diffContext = 5
        s = FontSizing.incremented(s, by: 3)
        let reset = FontSizing.resetSizes(s)
        #expect(reset.mainFont.pointSize == Settings().mainFont.pointSize)
        #expect(reset.textFont.pointSize == Settings().textFont.pointSize)
        #expect(reset.uiFont.pointSize == Settings().uiFont.pointSize)
        #expect(reset.mainFont.family == "Menlo")
        #expect(reset.textFont.family == "Menlo")
        #expect(reset.uiFont.bold == Settings().uiFont.bold)
        #expect(reset.diffContext == 5)
    }
}
