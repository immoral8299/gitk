// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Darwin
import GitkCore

/// Process start-up. `main.swift` calls only `run`.
public enum GitkLauncher {
    /// Keeps the delegate alive; `NSApplication.delegate` is weak.
    @MainActor private static var delegate: AppDelegate?

    /// Strips the dynamic-loader search paths that make macOS's image decoder
    /// load Homebrew's `libpng`/`libtiff` instead of its own and crash with
    /// SIGBUS while drawing an emoji. Returns nil when there is nothing to
    /// strip, so an ordinary launch is left alone.
    static func environmentWithoutLoaderPaths(_ environment: [String: String]) -> [String: String]? {
        let keys = ["DYLD_LIBRARY_PATH", "DYLD_FALLBACK_LIBRARY_PATH"]
        guard keys.contains(where: { !(environment[$0] ?? "").isEmpty }) else { return nil }
        var clean = environment
        for key in keys { clean.removeValue(forKey: key) }
        return clean
    }

    /// Replaces this process with a fresh launch that has the loader paths
    /// removed. `execve` keeps the working directory, arguments and terminal,
    /// and never returns when it succeeds.
    private static func relaunch(arguments: [String], environment: [String: String]) {
        guard let executable = Bundle.main.executablePath else { return }
        FileHandle.standardError.write(Data((
            "gitk-swift: relaunching without DYLD_LIBRARY_PATH; " +
            "it makes macOS's image decoder crash while drawing emoji\n").utf8))
        var argv: [UnsafeMutablePointer<CChar>?] = ([executable] + arguments).map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") }
        envp.append(nil)
        defer {
            for pointer in argv { free(pointer) }
            for pointer in envp { free(pointer) }
        }
        argv.withUnsafeBufferPointer { argvBuffer in
            envp.withUnsafeBufferPointer { envpBuffer in
                executable.withCString {
                    _ = execve($0, argvBuffer.baseAddress, envpBuffer.baseAddress)
                }
            }
        }
    }

    /// Starts the AppKit run loop and does not return. The start-up work
    /// (`AppDelegate.start`) runs from `applicationDidFinishLaunching`, because the
    /// run loop must not be entered from inside an async main-actor function:
    /// that would keep every other main-actor task from running.
    @MainActor
    public static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Never {
        if let clean = environmentWithoutLoaderPaths(environment) {
            relaunch(arguments: arguments, environment: clean)
        }
        let app = NSApplication.shared
        let appDelegate = AppDelegate(arguments: arguments, environment: environment)
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.regular)
        app.run()
        exit(0)
    }
}
