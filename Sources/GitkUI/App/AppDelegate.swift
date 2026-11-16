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
        var cwd = repository.cwd
        let arguments = repository.arguments
        if cwd != launchDirectory { FileManager.default.changeCurrentDirectoryPath(cwd.path) }
        let alerts = Alerts(environment: environment)

        do {
            while true {
                do {
                    startup = try await StartupChecks(cwd: cwd, environment: environment).run()
                    break
                } catch StartupError.notARepository
                            where Self.offersRepositoryPicker(arguments: arguments, environment: environment) {
                    guard let picked = Self.chooseRepository(startingAt: cwd) else { exit(1) }
                    cwd = picked
                    FileManager.default.changeCurrentDirectoryPath(cwd.path)
                }
            }
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

    /// Launched outside a repository (from Finder, or a shell in another
    /// directory) with no revisions or paths, the app asks for a repository
    /// instead of exiting. gitk exits with "Cannot find a git repository here.",
    /// which is still what happens with headless errors or when arguments other
    /// than options were given, since those only make sense in a known repository.
    static func offersRepositoryPicker(arguments: [String], environment: [String: String]) -> Bool {
        environment[Alerts.headlessErrorsKey] != "1" && arguments.allSatisfy { $0.hasPrefix("-") && $0 != "--" }
    }

    /// Asks for a repository folder; nil when the person cancels.
    private static func chooseRepository(startingAt directory: URL) -> URL? {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = L("Cannot find a git repository here.") + " " + L("Choose a repository to open.")
        panel.prompt = L("Open")
        panel.directoryURL = directory.path == "/"
            ? FileManager.default.homeDirectoryForCurrentUser : directory
        guard panel.runModal() == .OK else { return nil }
        return panel.url
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
            // terminate(_:) with .terminateLater spins a nested run loop, and the
            // reply Task needs the main actor and main queue. Calling it from a
            // main-actor Task or a main-queue block would hold both, so the reply
            // could never run and the quit would hang. A run-loop timer fires like a
            // real ⌘-Q event, outside either.
            let timer = Timer(timeInterval: Double(delay) / 1000, repeats: false) { _ in
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        if let snapshot = Snapshot.fromEnvironment(environment) {
            snapshot.ready = { [weak controller] window in
                // GITK_SWIFT_SNAPSHOT_EARLY=1 captures right after the first history batch, without the settle delay.
                let early = self.environment["GITK_SWIFT_SNAPSHOT_EARLY"] == "1"
                await controller?.waitForSnapshot(early: early)
                await Snapshot.defaultReady(window, settleMilliseconds: early ? 0 : Snapshot.settleMilliseconds)
            }
            snapshot.capturesFrame = prefsWindow != nil
            Task { await snapshot.run(window: prefsWindow ?? w) }
        }
    }
}
