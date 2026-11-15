// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Runs the start-up checks, then owns the main window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let arguments: [String]
    let environment: [String: String]
    private(set) var startup: StartupContext?
    private(set) var launch: LaunchArguments?
    private(set) var mainWindowController: MainWindowController?

    init(arguments: [String], environment: [String: String]) {
        self.arguments = arguments
        self.environment = environment
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Task { await start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await mainWindowController?.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Order (design D11, cli-launch): `LanguageOverride` first, before any `L()`
    /// call; then `StartupChecks` (gitk 20–34, 12601, 12828) and
    /// `LaunchArguments` (gitk 12840–12893). A failure goes to stderr when
    /// `GITK_SWIFT_HEADLESS_ERRORS=1`, else to an alert; the exit status is 1.
    private func start() async {
        LanguageOverride.apply(environment: environment)
        // `gitk-swift <path-to-repo> [args]` opens that repository (RepositoryArgument).
        let launchDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let repository = await RepositoryArgument.extract(arguments, cwd: launchDirectory)
        let cwd = repository.cwd
        let arguments = repository.arguments
        if cwd != launchDirectory { FileManager.default.changeCurrentDirectoryPath(cwd.path) }
        let alerts = Alerts(environment: environment)

        do {
            startup = try await StartupChecks(cwd: cwd, environment: environment).run()
            launch = try await LaunchArguments.parse(
                argv: arguments, repo: cwd, environment: environment)
        } catch let e as StartupError {
            if case .unknownHashAlgorithm = e {
                // Spec: written to stderr, never an alert.
                Alerts.standardErrorSink("gitk: \(e.message)")
            } else {
                alerts.showError(e.message, parent: nil)
            }
            exit(1)
        } catch let e as LaunchArgumentsError {
            switch e {
            case .ambiguousArgument(let arg):
                alerts.showError(L(e.msgid, arg), parent: nil)
            case .badArguments(let err):
                alerts.showError("\(L(e.msgid))\n\(err)", parent: nil)
            }
            exit(1)
        } catch {
            alerts.showError("\(error)", parent: nil)
            exit(1)
        }
        guard let startup, let launch else { return }
        openMainWindow(startup: startup, launch: launch, cwd: cwd)
    }

    private func openMainWindow(startup: StartupContext, launch: LaunchArguments, cwd: URL) {
        let controller = MainWindowController(
            startup: startup, launch: launch,
            settingsStore: SettingsStore(environment: environment), cwd: cwd, environment: environment)
        mainWindowController = controller
        NSApp.mainMenu = controller.mainMenu?.menu
        guard let w = controller.window else { return }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
        controller.startLoading()
        // GITK_SWIFT_OPEN=prefs opens the preferences window (verification hook);
        // a snapshot then captures that window.
        let prefsWindow = environment["GITK_SWIFT_OPEN"] == "prefs" ? controller.showPreferences().window : nil
        if let delay = environment["GITK_SWIFT_QUIT_AFTER_MS"].flatMap(Int.init), delay >= 0 {
            Task {
                try? await Task.sleep(for: .milliseconds(delay))
                NSApp.terminate(nil)
            }
        }
        if let snapshot = Snapshot.fromEnvironment(environment) {
            snapshot.ready = { [weak controller] window in
                await controller?.waitForSnapshot(early: self.environment["GITK_SWIFT_SNAPSHOT_EARLY"] == "1")
                await Snapshot.defaultReady(window)
            }
            snapshot.capturesFrame = prefsWindow != nil
            Task { await snapshot.run(window: prefsWindow ?? w) }
        }
    }
}
