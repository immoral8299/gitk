// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Owns one application's scratch directory; the app calls cleanup on quit.
public struct TempFiles: Sendable {
    public let directory: URL

    /// Port of gitk proc `gitknewtmpdir` (gitk/gitk 3729–3761).
    public init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let base = environment["GITK_TMPDIR"] ?? environment["TMPDIR"]
        let root = base.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        directory = root.appendingPathComponent(".gitk-tmp.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    public func makeDirectory() throws -> URL {
        let child = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return child
    }

    public func cleanup() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
