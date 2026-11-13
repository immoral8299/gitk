// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit

/// Receives one headless alert line, e.g. `gitk: <message>`.
typealias HeadlessSink = @MainActor (String) -> Void

/// Error and confirmation dialogs, mirroring gitk's `show_error`, `error_popup`
/// and `confirm_popup`. With `GITK_SWIFT_HEADLESS_ERRORS=1` alerts go to stderr
/// instead of a dialog, and confirmations answer from `GITK_SWIFT_CONFIRM`
/// (`yes` or `no`, default `no`). See design D12.
@MainActor
final class Alerts {
    static let headlessErrorsKey = "GITK_SWIFT_HEADLESS_ERRORS"
    static let confirmKey = "GITK_SWIFT_CONFIRM"

    private let environment: [String: String]
    private let sink: HeadlessSink
    private let lookup: L10nLookup

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        sink: @escaping HeadlessSink = Alerts.standardErrorSink,
        lookup: @escaping L10nLookup = identityL10nLookup
    ) {
        self.environment = environment
        self.sink = sink
        self.lookup = lookup
    }

    private var isHeadless: Bool {
        environment[Alerts.headlessErrorsKey] == "1"
    }

    /// Port of gitk proc `show_error` (gitk/gitk 2146–2158): shows `message`
    /// with an OK button. A sheet is used when `parent` is given, so this
    /// returns without waiting for the user.
    func showError(_ message: String, parent: NSWindow?) {
        if isHeadless {
            sink("gitk: \(message)")
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = message
        alert.addButton(withTitle: L("OK", lookup: lookup))
        if let parent {
            alert.beginSheetModal(for: parent) { _ in }
        } else {
            _ = alert.runModal()
        }
    }

    /// Port of gitk proc `error_popup` (gitk/gitk 2160–2172). Same behaviour as
    /// `showError`; kept as a separate entry point so callers read like gitk.
    func errorPopup(_ message: String, parent: NSWindow?) {
        showError(message, parent: parent)
    }

    /// Port of gitk proc `confirm_popup` (gitk/gitk 2174–2192): returns true
    /// when the user chooses OK. Runs modally, as gitk's `tkwait` blocks.
    func confirmPopup(_ message: String, parent: NSWindow?) -> Bool {
        if isHeadless {
            sink("gitk: \(message)")
            return environment[Alerts.confirmKey] == "yes"
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.addButton(withTitle: L("OK", lookup: lookup))
        alert.addButton(withTitle: L("Cancel", lookup: lookup))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Writes the headless line to standard error.
    static let standardErrorSink: HeadlessSink = { line in
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
