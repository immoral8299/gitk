// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct RememberedViewsTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gitk-swift-remembered-\(UUID().uuidString)", isDirectory: true)
    }

    /// Saves the manager's remembered views through a store in `dir`, as `MainWindowController` does.
    private func persist(_ manager: ViewManager, to dir: URL) throws {
        let store = SettingsStore(environment: ["GITK_SWIFT_CONFIG_DIR": dir.path])
        var settings = store.load()
        settings.views = manager.rememberedViews.map(SavedView.init(view:))
        #expect(try store.save(settings))
    }

    /// Starts a manager from the settings in `dir`, as `MainWindowController.init` does.
    private func reload(from dir: URL) -> ViewManager {
        let store = SettingsStore(environment: ["GITK_SWIFT_CONFIG_DIR": dir.path])
        return ViewManager(remembered: store.load().views.map(ViewSpec.init(saved:)))
    }

    @Test func persistAcrossLaunches() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var first = ViewManager()
        let view = ViewSpec(
            name: "Mine", args: ["--all", "--since=1.week"], files: ["docs", "with space"],
            argsCmd: "echo --first-parent", perm: true)
        first.add(view)
        try persist(first, to: dir)

        let second = reload(from: dir)
        let remembered = second.entries.filter { !$0.isBuiltIn }
        #expect(remembered.count == 1)
        #expect(remembered.first?.spec.name == "Mine")
        #expect(remembered.first?.spec.args == ["--all", "--since=1.week"])
        #expect(remembered.first?.spec.files == ["docs", "with space"])
        #expect(remembered.first?.spec.argsCmd == "echo --first-parent")
        #expect(remembered.first?.spec.perm == true)
        #expect(second.rememberedViews == first.rememberedViews)
    }

    @Test func uncheckedViewNotSaved() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var first = ViewManager()
        first.add(ViewSpec(name: "Temporary", args: ["--all"], perm: false))
        #expect(first.rememberedViews.isEmpty)
        try persist(first, to: dir)

        let second = reload(from: dir)
        #expect(second.entries.count == 1)
        #expect(second.entry(1) == nil)
    }

    @Test func legacyPermviewsImported() throws {
        let dir = tempDir()
        let home = tempDir()
        defer {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.removeItem(at: home)
        }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let legacy = """
        set permviews {
        {Docs {docs {with space}} {--all --since=1.week} {}}
        {Mine {} {--author=me} {echo --first-parent}}
        }
        """
        try legacy.write(to: home.appendingPathComponent(".gitk"), atomically: true, encoding: .utf8)
        let env = ["GITK_SWIFT_CONFIG_DIR": dir.path, "HOME": home.path]
        let store = SettingsStore(environment: env, homeDirectory: home)
        let settings = store.loadImportingLegacy()
        #expect(settings.views.map(\.name) == ["Docs", "Mine"])

        let manager = ViewManager(remembered: settings.views.map(ViewSpec.init(saved:)))
        #expect(manager.rememberedViews.map(\.name) == ["Docs", "Mine"])
        #expect(manager.rememberedViews[0].files == ["docs", "with space"])
        #expect(manager.rememberedViews[1].argsCmd == "echo --first-parent")
        #expect(manager.rememberedViews[0].argsCmd == nil)
    }
}
