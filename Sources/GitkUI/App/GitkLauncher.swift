// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Process start-up. `main.swift` calls only `run`.
public enum GitkLauncher {
    /// Keeps the delegate alive; `NSApplication.delegate` is weak.
    @MainActor private static var delegate: AppDelegate?

    /// Starts the AppKit run loop and does not return. The start-up work
    /// (`AppDelegate.start`) runs from `applicationDidFinishLaunching`, because the
    /// run loop must not be entered from inside an async main-actor function:
    /// that would keep every other main-actor task from running.
    @MainActor
    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Never {
        let app = NSApplication.shared
        let appDelegate = AppDelegate(arguments: arguments, environment: environment)
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        app.run()
        exit(0)
    }
}
