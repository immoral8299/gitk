// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Reads and writes `Settings` as JSON (design D9).
///
/// The file is `settings.json` in `$GITK_SWIFT_CONFIG_DIR` if that is set and
/// non-empty, otherwise `~/Library/Application Support/gitk-swift/`. Writes are
/// atomic. A file that cannot be parsed yields defaults plus a warning, and is
/// left alone until `markChanged()` is called (spec "Corrupt settings").
///
/// The environment, home directory and warning sink are injectable for tests.
public final class SettingsStore: @unchecked Sendable {
    // @unchecked Sendable: the only mutable state is `badFileProtected`, guarded by `lock`.
    static let configDirVariable = "GITK_SWIFT_CONFIG_DIR"
    static let fileName = "settings.json"

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    private let warn: @Sendable (String) -> Void
    private let environment: [String: String]
    private let homeDirectory: URL
    private let lock = NSLock()
    private var badFileProtected = false

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        warn: @escaping @Sendable (String) -> Void = { message in
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        if let override = environment[Self.configDirVariable], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = homeDirectory
                .appendingPathComponent("Library/Application Support/gitk-swift", isDirectory: true)
        }
        self.warn = warn
    }

    /// True if the settings file exists (so legacy gitk import should not run).
    public var fileExists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// True while an unparseable file is being kept: `save` does nothing until `markChanged()`.
    public var isProtectingBadFile: Bool {
        lock.lock()
        defer { lock.unlock() }
        return badFileProtected
    }

    /// Loads the settings. A missing file gives defaults silently. An unreadable or
    /// corrupt file gives defaults, calls the warning sink, and protects the file
    /// from being overwritten until `markChanged()`.
    public func load() -> Settings {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            if fileExists {
                protect("gitk-swift: cannot read \(fileURL.path): \(error.localizedDescription); using defaults")
            }
            return Settings()
        }
        do {
            let settings = try JSONDecoder().decode(Settings.self, from: data)
            setProtected(false)
            return settings
        } catch {
            protect("gitk-swift: cannot parse \(fileURL.path): \(error); using defaults")
            return Settings()
        }
    }

    /// Like `load()`, but when the app has no settings file yet, imports the Tcl gitk
    /// config (`$XDG_CONFIG_HOME/git/gitk`, `~/.config/git/gitk`, `~/.gitk`). The
    /// legacy file is only read. `HOME` in the environment, when set, names the home
    /// directory.
    public func loadImportingLegacy() -> Settings {
        if fileExists { return load() }
        let home = environment["HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? homeDirectory
        return LegacyConfigImporter.importConfig(environment: environment, homeDirectory: home) ?? Settings()
    }

    /// Records that the user changed something, allowing the next `save` to replace a
    /// corrupt file.
    public func markChanged() { setProtected(false) }

    /// Writes the settings atomically, creating the directory if needed. Returns
    /// `false` (writing nothing) while a corrupt file is protected.
    @discardableResult
    public func save(_ settings: Settings) throws -> Bool {
        if isProtectingBadFile { return false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
        return true
    }

    private func protect(_ message: String) {
        setProtected(true)
        warn(message)
    }

    private func setProtected(_ value: Bool) {
        lock.lock()
        badFileProtected = value
        lock.unlock()
    }
}
