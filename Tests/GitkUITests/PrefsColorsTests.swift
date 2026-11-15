// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor
@Suite struct PrefsColorsTests {
    private func make() -> PreferencesController {
        PreferencesController(settings: Settings(), notificationCenter: NotificationCenter())
    }

    private func pick(_ c: PreferencesController, _ id: String, _ color: NSColor) {
        let well = c.colorWells[id]!
        well.color = color
        _ = well.target?.perform(well.action)
    }

    @Test func wellsInGitkOrder() {
        let c = make()
        #expect(PreferencesController.colorSettings.map(\.id) == [
            "bg", "fg", "selbg", "linkfg", "diffold", "diffoldbg", "diffnew", "diffnewbg",
            "hunksep", "markbg", "foundbg", "currenthit",
        ])
        #expect(c.colorWells.count == 12)
    }

    @Test func tkStringRoundTrip() {
        #expect(PreferencesController.tkString(Palette.tk("#12ab9f")) == "#12ab9f")
        #expect(PreferencesController.tkString(Palette.tk("red")) == "#ff0000")
    }

    /// Spec "Change a colour": OK applies the new line background, which
    /// reaches the diff attributes.
    @Test func newLineBackgroundReachesDiffAttributes() throws {
        let c = make()
        var applied: Settings?
        c.onApply = { applied = $0 }
        pick(c, "diffnewbg", Palette.tk("#123456"))
        #expect(c.draft.diffBgColors == ["#fff3f3", "#123456"])
        c.okAction()
        let s = try #require(applied)
        var renderer = DiffRenderer(settings: s)
        let text = renderer.render(.add(Data("new".utf8)))
        let bg = try #require(text.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(PreferencesController.tkString(bg) == "#123456")
    }

    /// Nothing is applied before OK, and Cancel discards the change.
    @Test func changesApplyOnlyOnOK() {
        let c = make()
        var applied: [Settings] = []
        c.onApply = { applied.append($0) }
        pick(c, "diffnewbg", Palette.tk("#123456"))
        #expect(applied.isEmpty)
        c.cancelAction()
        #expect(applied.isEmpty)
        #expect(c.draft == Settings())
    }

    /// Spec "Change a search colour": found and current-hit colours reach the
    /// colours the match boxes draw with (`Palette.found`, PaneSearch).
    @Test func searchColoursReachPalette() throws {
        let c = make()
        var applied: Settings?
        c.onApply = { applied = $0 }
        pick(c, "foundbg", Palette.tk("#00ffff"))
        pick(c, "currenthit", Palette.tk("#ff00ff"))
        c.okAction()
        let s = try #require(applied)
        #expect(s.foundBgColor == "#00ffff")
        #expect(s.currentSearchHitBgColor == "#ff00ff")
        #expect(PreferencesController.tkString(Palette.found(s)) == "#00ffff")
        #expect(PreferencesController.tkString(Palette.tk(s.currentSearchHitBgColor)) == "#ff00ff")
    }
}
