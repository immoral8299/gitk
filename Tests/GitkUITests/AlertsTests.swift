// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkUI

@MainActor
@Suite struct AlertsTests {
    /// Collects headless lines written by an `Alerts` under test.
    private final class Lines {
        var values: [String] = []
    }

    private func makeAlerts(_ env: [String: String]) -> (Alerts, Lines) {
        let lines = Lines()
        let alerts = Alerts(environment: env, sink: { lines.values.append($0) })
        return (alerts, lines)
    }

    @Test func headlessErrorGoesToSink() {
        let (alerts, lines) = makeAlerts(["GITK_SWIFT_HEADLESS_ERRORS": "1"])
        alerts.showError("boom", parent: nil)
        alerts.errorPopup("bang", parent: nil)
        #expect(lines.values == ["gitk: boom", "gitk: bang"])
    }

    @Test func headlessConfirmYesReturnsTrue() {
        let (alerts, lines) = makeAlerts([
            "GITK_SWIFT_HEADLESS_ERRORS": "1",
            "GITK_SWIFT_CONFIRM": "yes",
        ])
        #expect(alerts.confirmPopup("Really?", parent: nil) == true)
        #expect(lines.values == ["gitk: Really?"])
    }

    @Test func headlessConfirmNoReturnsFalse() {
        let (alerts, _) = makeAlerts([
            "GITK_SWIFT_HEADLESS_ERRORS": "1",
            "GITK_SWIFT_CONFIRM": "no",
        ])
        #expect(alerts.confirmPopup("Really?", parent: nil) == false)
    }

    @Test func headlessConfirmUnsetDefaultsToNo() {
        let (alerts, _) = makeAlerts(["GITK_SWIFT_HEADLESS_ERRORS": "1"])
        #expect(alerts.confirmPopup("Really?", parent: nil) == false)
    }

    @Test func confirmValueOtherThanYesIsNo() {
        let (alerts, _) = makeAlerts([
            "GITK_SWIFT_HEADLESS_ERRORS": "1",
            "GITK_SWIFT_CONFIRM": "YES",
        ])
        #expect(alerts.confirmPopup("Really?", parent: nil) == false)
    }
}
