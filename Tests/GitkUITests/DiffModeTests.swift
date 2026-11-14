// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor
@Suite struct DiffModeTests {
    private func render(_ lines: [DiffLine], mode: DiffDisplayMode) -> String {
        var renderer = DiffRenderer(settings: Settings(), mode: mode)
        return lines.map { renderer.render($0).string }.joined()
    }

    private let hunk: [DiffLine] = [
        .context(Data("same".utf8)), .remove(Data("old".utf8)), .add(Data("new".utf8)),
    ]

    /// diff-viewer "Old version": added lines are hidden, no +/- prefixes.
    @Test func oldVersionHidesAdds() {
        #expect(render(hunk, mode: .old) == "same\nold\n")
    }

    @Test func newVersionHidesRemovesAndDiffShowsBoth() {
        #expect(render(hunk, mode: .new) == "same\nnew\n")
        #expect(render(hunk, mode: .diff) == " same\n-old\n+new\n")
    }

    @Test func octopusMarkersUseConfiguredParentColors() async throws {
        let repo = try await ActionTestRepo.make("evil-octopus")
        #expect(try await repo.resolve().hex == "df3f0db1158d8be5a70c0574da8bc43f143e6d26")
        let output = try await repo.runner.run(["diff-tree", "-p", "--cc", "--no-commit-id", "HEAD"])
        await repo.cleanup()
        let (lines, _) = DiffParser.parse(output: output.stdout)
        let combined = lines.filter { if case .combined = $0 { true } else { false } }
        #expect(!combined.isEmpty)
        var settings = Settings()
        settings.mergeColors = ["#123456", "#654321", "#abcdef"]
        var renderer = DiffRenderer(settings: settings)
        for line in combined {
            guard case .combined(let markers, let data) = line else { continue }
            #expect(markers.count == 3)
            let text = renderer.render(line)
            #expect(text.string == String(markers) + String(decoding: data, as: UTF8.self) + "\n")
            for index in markers.indices {
                let color = try #require(text.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor)
                #expect(color == Palette.merge(settings, index))
            }
            let bodyColor = try #require(text.attribute(.foregroundColor, at: markers.count, effectiveRange: nil) as? NSColor)
            #expect(bodyColor == Palette.foreground(settings))
        }
    }

    /// diff-viewer "Context lines": the bar's options reach the diff command.
    @Test func controlsChangeOptions() {
        let pane = DiffPane(settings: Settings(), hashLength: 40)
        pane.applySnapshotOptions("context=10,words=color,mode=old,ignorespace")
        #expect(pane.options.context == 10)
        #expect(pane.options.wordDiff == .color)
        #expect(pane.options.ignoreSpace)
        #expect(pane.mode == .old)
        let id = ObjectID(hex: String(repeating: "a", count: 40))!
        let command = DiffCommandBuilder.blobDiff(ids: [id], options: pane.options)
        #expect(command.contains("-U10"))
        #expect(command.contains("-w"))
        #expect(command.contains("--word-diff=porcelain"))
    }
}
