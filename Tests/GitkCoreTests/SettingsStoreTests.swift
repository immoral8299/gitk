// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

/// Collects warnings from a `@Sendable` sink.
private final class Warnings: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct SettingsStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gitk-swift-store-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func roundTrip() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(environment: ["GITK_SWIFT_CONFIG_DIR": dir.path])
        #expect(!store.fileExists)
        #expect(store.load() == Settings())
        var s = Settings()
        s.diffContext = 11
        s.views = [SavedView(name: "x", files: ["a"], args: ["--all"], argsCmd: "")]
        #expect(try store.save(s))
        #expect(store.fileExists)
        let again = SettingsStore(environment: ["GITK_SWIFT_CONFIG_DIR": dir.path])
        #expect(again.load() == s)
    }

    @Test func overrideDirectoryAndDefaultLocation() {
        let home = URL(fileURLWithPath: "/home/test", isDirectory: true)
        let override = SettingsStore(environment: ["GITK_SWIFT_CONFIG_DIR": "/x/cfg"], homeDirectory: home)
        #expect(override.fileURL.path == "/x/cfg/settings.json")
        let empty = SettingsStore(environment: ["GITK_SWIFT_CONFIG_DIR": ""], homeDirectory: home)
        #expect(empty.fileURL.path == "/home/test/Library/Application Support/gitk-swift/settings.json")
        let unset = SettingsStore(environment: [:], homeDirectory: home)
        #expect(unset.fileURL == empty.fileURL)
    }

    @Test func corruptFileGivesDefaultsAndIsNotOverwrittenUntilChanged() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bad = Data("{ not json".utf8)
        let warnings = Warnings()
        let store = SettingsStore(environment: ["GITK_SWIFT_CONFIG_DIR": dir.path], warn: { warnings.add($0) })
        try bad.write(to: store.fileURL)

        #expect(store.load() == Settings())
        #expect(warnings.all.count == 1)
        #expect(store.isProtectingBadFile)

        // Quit-time save before any change must leave the bad file alone.
        #expect(try store.save(Settings()) == false)
        #expect(try Data(contentsOf: store.fileURL) == bad)

        store.markChanged()
        var s = Settings()
        s.tabStop = 4
        #expect(try store.save(s))
        #expect(store.load().tabStop == 4)
        #expect(warnings.all.count == 1)
    }

    @Test func saveCreatesDirectoryAtomicallyWithoutLeftovers() throws {
        let dir = tempDir().appendingPathComponent("nested", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let store = SettingsStore(environment: ["GITK_SWIFT_CONFIG_DIR": dir.path])
        try store.save(Settings())
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["settings.json"])
    }

    @Test func oldFileWithMissingAndUnknownKeysLoads() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(environment: ["GITK_SWIFT_CONFIG_DIR": dir.path])
        try Data(#"{"diffContext": 5, "removedInFuture": true}"#.utf8).write(to: store.fileURL)
        let s = store.load()
        #expect(s.diffContext == 5)
        #expect(s.tabStop == 8)
        #expect(!store.isProtectingBadFile)
    }
}
