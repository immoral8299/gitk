// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// Builds and caches the deterministic fixture repositories from
/// `Tests/Fixtures/make-fixture.sh` (design D12).
///
/// - `make(_:)` returns a shared, read-only checkout. Never modify it.
/// - `makeCopy(_:)` returns a private copy that a test may change.
///
/// Fixtures live under `$TMPDIR/gitk-swift-fixtures/<script-hash>/<name>`. They
/// are built once per script version and shared between test processes. Each
/// build goes into a private directory that is renamed into place, so parallel
/// tests and processes never see a half-built repository.
enum FixtureRepo {
    struct BuildError: Error, CustomStringConvertible {
        let description: String
    }

    static var repoRoot: URL {
        // <repo>/Tests/GitkCoreTests/Support/FixtureRepo.swift → <repo>
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var scriptURL: URL {
        repoRoot.appendingPathComponent("Tests/Fixtures/make-fixture.sh")
    }

    /// Returns the shared fixture checkout for `name`, building it if needed.
    static func make(_ name: String) throws -> URL {
        try cache.withLock(name) { try buildIfNeeded(name) }
    }

    /// Returns a fresh, writable copy of the fixture in its own temp directory.
    static func makeCopy(_ name: String) throws -> URL {
        let source = try make(name)
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitk-swift-fixture-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let destination = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    // MARK: - Implementation

    private static let cache = FixtureCache()

    private static func buildIfNeeded(_ name: String) throws -> URL {
        let fm = FileManager.default
        let root = try cacheRoot()
        let destination = root.appendingPathComponent(name, isDirectory: true)
        if fm.fileExists(atPath: destination.appendingPathComponent(".git").path) {
            return destination
        }

        let staging = root.appendingPathComponent(".building-\(name)-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, name, staging.path]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self)
            throw BuildError(description: "make-fixture.sh \(name) failed (\(process.terminationStatus)): \(message)")
        }

        do {
            try fm.moveItem(at: staging.appendingPathComponent(name), to: destination)
        } catch where fm.fileExists(atPath: destination.appendingPathComponent(".git").path) {
            // Another process finished the same fixture first; use theirs.
        }
        return destination
    }

    /// `$TMPDIR/gitk-swift-fixtures/<hash of make-fixture.sh>`.
    private static func cacheRoot() throws -> URL {
        let script = try Data(contentsOf: scriptURL)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitk-swift-fixtures", isDirectory: true)
            .appendingPathComponent(fnv1a64Hex(script), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func fnv1a64Hex(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

/// One lock per fixture name, so different fixtures can build in parallel
/// while concurrent requests for the same fixture wait for a single build.
/// `@unchecked Sendable`: all mutable state is guarded by `lock`.
private final class FixtureCache: @unchecked Sendable {
    private let lock = NSLock()
    private var locks: [String: NSLock] = [:]

    func withLock<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        lock.lock()
        let nameLock = locks[name] ?? NSLock()
        locks[name] = nameLock
        lock.unlock()

        nameLock.lock()
        defer { nameLock.unlock() }
        return try body()
    }
}
