// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore
import Testing
@testable import GitkUI

@MainActor
@Suite struct PrefsGeneralTests {
    private func make(_ settings: Settings = Settings()) -> (PreferencesController, NotificationCenter) {
        let center = NotificationCenter()
        return (PreferencesController(settings: settings, notificationCenter: center), center)
    }

    @Test func hasThreePages() {
        let (c, _) = make()
        #expect(c.tabView.tabViewItems.map(\.label) == ["General", "Colors", "Fonts"])
    }

    /// Spec "Cancel": nothing is applied or broadcast.
    @Test func cancelDiscardsChanges() {
        let (c, center) = make()
        var applied: [Settings] = []
        var posted = 0
        let token = center.addObserver(forName: .gitkSettingsDidChange, object: nil, queue: nil) { _ in posted += 1 }
        defer { center.removeObserver(token) }
        c.onApply = { applied.append($0) }
        c.showLocalChangesCheckbox?.performClick(nil)
        c.spinners["tabStop"]?.stepper.integerValue = 12
        c.spinners["tabStop"]?.stepper.performClick(nil)
        c.setExtDiffTool("/usr/bin/diff")
        #expect(c.draft != Settings())
        c.cancelAction()
        #expect(applied.isEmpty)
        #expect(posted == 0)
        #expect(c.draft == Settings())
    }

    /// Spec "Toggle local changes": OK delivers the draft with the box off.
    @Test func okAppliesAndBroadcasts() {
        let (c, center) = make()
        var applied: [Settings] = []
        var broadcast: Settings?
        let token = center.addObserver(forName: .gitkSettingsDidChange, object: nil, queue: nil) {
            broadcast = $0.object as? Settings
        }
        defer { center.removeObserver(token) }
        c.onApply = { applied.append($0) }
        #expect(c.showLocalChangesCheckbox?.state == .on)
        c.showLocalChangesCheckbox?.performClick(nil)
        c.setExtDiffTool("/usr/bin/diff")
        c.okAction()
        #expect(applied.count == 1)
        #expect(applied[0].showLocalChanges == false)
        #expect(applied[0].extDiffTool == "/usr/bin/diff")
        #expect(broadcast == applied[0])
    }

    @Test func spinnerClampsTypedValue() {
        let (c, _) = make()
        let s = c.spinners["kscroll"]
        s?.field.stringValue = "99"
        _ = s?.field.sendAction(s?.field.action, to: s?.field.target)
        #expect(s?.value == 20)
        #expect(c.draft.kscroll == 20)
        #expect(c.spinners["autoSelLen"]?.stepper.maxValue == 40)
    }
}
