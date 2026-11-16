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
    private var repositoryPicker: RepositoryPickerWindowController?

    /// `--default-settings`: start with the built-in defaults, ignoring
    /// settings.json and the Tcl gitk config, and save nothing on quit.
    let usesDefaultSettings: Bool

    static let defaultSettingsFlag = "--default-settings"

    init(arguments: [String], environment: [String: String]) {
        (usesDefaultSettings, self.arguments) = Self.extractDefaultSettingsFlag(arguments)
        self.environment = environment
    }

    /// Removes `--default-settings` from the options (before any `--`), so it
    /// never reaches git.
    static func extractDefaultSettingsFlag(_ arguments: [String]) -> (Bool, [String]) {
        let end = arguments.firstIndex(of: "--") ?? arguments.endIndex
        let options = arguments[..<end]
        guard options.contains(defaultSettingsFlag) else { return (false, arguments) }
        return (true, options.filter { $0 != defaultSettingsFlag } + arguments[end...])
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
    /// Outside a repository the picker window may ask for one instead.
    private func start() async {
        LanguageOverride.apply(environment: environment)
        // `gitk-swift <path-to-repo> [args]` opens that repository (RepositoryArgument).
        let launchDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let repository = await RepositoryArgument.extract(arguments, cwd: launchDirectory)
        await open(cwd: repository.cwd, arguments: repository.arguments)
    }

    /// Runs the checks in `cwd` and opens the main window. Outside a
    /// repository, when `offersRepositoryPicker` allows it, the picker window
    /// asks for one and calls this again with the chosen folder.
    private func open(cwd: URL, arguments: [String]) async {
        if cwd.path != FileManager.default.currentDirectoryPath {
            FileManager.default.changeCurrentDirectoryPath(cwd.path)
        }
        let alerts = Alerts(environment: environment)

        do {
            startup = try await StartupChecks(cwd: cwd, environment: environment).run()
            launch = try await LaunchArguments.parse(
                argv: arguments, repo: cwd, environment: environment)
        } catch StartupError.notARepository
                    where Self.offersRepositoryPicker(arguments: arguments, environment: environment) {
            showRepositoryPicker(startingAt: cwd, arguments: arguments)
            return
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
        repositoryPicker?.close()
        repositoryPicker = nil
    }

    /// Launched outside a repository (from Finder, or a shell in another
    /// directory) with no revisions or paths, the app asks for a repository
    /// instead of exiting. gitk exits with "Cannot find a git repository here.",
    /// which is still what happens with headless errors or when arguments other
    /// than options were given, since those only make sense in a known repository.
    static func offersRepositoryPicker(arguments: [String], environment: [String: String]) -> Bool {
        environment[Alerts.headlessErrorsKey] != "1" && arguments.allSatisfy { $0.hasPrefix("-") && $0 != "--" }
    }

    /// Shows the picker window, then the folder chooser as a sheet on it. A
    /// folder that is not a repository comes back here and asks again.
    private func showRepositoryPicker(startingAt directory: URL, arguments: [String]) {
        let picker = repositoryPicker ?? RepositoryPickerWindowController()
        repositoryPicker = picker
        picker.onChoose = { [weak self] url in
            Task { await self?.open(cwd: url, arguments: arguments) }
        }
        picker.present(startingAt: directory)
    }

    private func openMainWindow(startup: StartupContext, launch: LaunchArguments, cwd: URL) {
        let controller = usesDefaultSettings
            ? MainWindowController(startup: startup, launch: launch, settings: UISettings(), store: nil,
                                   cwd: cwd, environment: environment)
            : MainWindowController(startup: startup, launch: launch,
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
