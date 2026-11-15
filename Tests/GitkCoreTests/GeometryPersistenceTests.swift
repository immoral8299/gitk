// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

private final class Warnings: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct GeometryPersistenceTests {
    private struct Sandbox {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitk-swift-geometry-\(UUID().uuidString)", isDirectory: true)
        var config: URL { root.appendingPathComponent("config", isDirectory: true) }
        var xdg: URL { root.appendingPathComponent("xdg", isDirectory: true) }
        var home: URL { root.appendingPathComponent("home", isDirectory: true) }
        var legacy: URL { xdg.appendingPathComponent("git/gitk") }
        var environment: [String: String] {
            ["GITK_SWIFT_CONFIG_DIR": config.path, "XDG_CONFIG_HOME": xdg.path, "HOME": home.path]
        }

        func writeLegacy(_ text: String) throws {
            try FileManager.default.createDirectory(
                at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: legacy, atomically: true, encoding: .utf8)
        }

        func store(_ warnings: Warnings = Warnings()) -> SettingsStore {
            SettingsStore(environment: environment, homeDirectory: home, warn: { warnings.add($0) })
        }

        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func geometryRestored() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        var s = Settings()
        s.windowFrame = StoredFrame(x: 10, y: 20, width: 1234.5, height: 800)
        s.diffHeight = 333
        s.sidebarWidth = 280
        s.authorWidth = 150
        s.dateWidth = 130
        s.refListFrame = StoredFrame(x: 5, y: 6, width: 400, height: 300)
        #expect(try box.store().save(s))
        let back = box.store().load()
        #expect(back.windowFrame == StoredFrame(x: 10, y: 20, width: 1234.5, height: 800))
        #expect(back.diffHeight == 333)
        #expect(back.sidebarWidth == 280)
        #expect(back.authorWidth == 150)
        #expect(back.dateWidth == 130)
        #expect(back.refListFrame == StoredFrame(x: 5, y: 6, width: 400, height: 300))
    }

    @Test func sidebarStateRestored() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        var s = Settings()
        s.sidebarHidden = true
        #expect(try box.store().save(s))
        #expect(box.store().load().sidebarHidden)
        s.sidebarHidden = false
        #expect(try box.store().save(s))
        #expect(!box.store().load().sidebarHidden)
    }

    @Test func badGeometryValuesAreIgnored() {
        var s = Settings()
        s.geometry = ["window": "1 2 0 5", "diffheight": "-4", "sidebarwidth": "abc", "reflist": "1 2 3"]
        #expect(s.windowFrame == nil)
        #expect(s.diffHeight == nil)
        #expect(s.sidebarWidth == nil)
        #expect(s.refListFrame == nil)
    }

    @Test func importExistingConfig() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        try box.writeLegacy("""
        set mainfont {Menlo 11}
        set diffcontext 5
        set permviews {{one {} {--all} {}} {two {a.txt} {HEAD} {}}}
        """)
        let s = box.store().loadImportingLegacy()
        #expect(s.mainFont.family == "Menlo")
        #expect(s.mainFont.pointSize == Settings().mainFont.pointSize)  // family only
        #expect(s.diffContext == 5)
        #expect(s.views.map(\.name) == ["one", "two"])
    }

    @Test func configWithCodeIsSkipped() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        let marker = box.root.appendingPathComponent("marker")
        try box.writeLegacy("""
        proc evil {} { exec touch \(marker.path) }
        exec touch \(marker.path)
        set diffcontext 7
        set tabstop [expr 4]
        """)
        let s = box.store().loadImportingLegacy()
        #expect(s.diffContext == 7)
        #expect(s.tabStop == Settings().tabStop)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func legacyFileUntouched() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        try box.writeLegacy("set diffcontext 5\n")
        let before = try Data(contentsOf: box.legacy)
        let stamp = try FileManager.default.attributesOfItem(atPath: box.legacy.path)[.modificationDate] as? Date
        let store = box.store()
        var s = store.loadImportingLegacy()
        s.diffContext = 9
        s.windowFrame = StoredFrame(x: 1, y: 2, width: 3, height: 4)
        #expect(try store.save(s))
        #expect(try Data(contentsOf: box.legacy) == before)
        #expect(try FileManager.default.attributesOfItem(atPath: box.legacy.path)[.modificationDate] as? Date == stamp)
        // With settings of its own, the legacy file is no longer consulted.
        #expect(box.store().loadImportingLegacy().diffContext == 9)
    }

    @Test func corruptSettings() throws {
        let box = Sandbox()
        defer { box.cleanup() }
        try box.writeLegacy("set diffcontext 5\n")
        try FileManager.default.createDirectory(at: box.config, withIntermediateDirectories: true)
        let bad = Data("{ not json".utf8)
        let file = box.config.appendingPathComponent("settings.json")
        try bad.write(to: file)
        let warnings = Warnings()
        let store = box.store(warnings)
        #expect(store.loadImportingLegacy() == Settings())
        #expect(warnings.all.count == 1)
        var s = Settings()
        s.windowFrame = StoredFrame(x: 1, y: 2, width: 3, height: 4)
        #expect(try store.save(s) == false)
        #expect(try Data(contentsOf: file) == bad)
        store.markChanged()
        #expect(try store.save(s))
        #expect(box.store().load().windowFrame != nil)
    }

    @Test func freshInstall() {
        let box = Sandbox()
        defer { box.cleanup() }
        let s = box.store().loadImportingLegacy()
        #expect(s == Settings())
        #expect(s.headBgColor == "#00ff00")
        #expect(s.tagBgColor == "yellow")
        #expect(s.diffContext == 3)
        #expect(s.showLocalChanges)
        #expect(s.windowFrame == nil)
    }
}
