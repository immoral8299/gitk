// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor @Suite struct ViewEditorFormTests {
    @Test func rowsFollowLayoutFlags() {
        let rows = ViewEditorForm.rows()
        #expect(rows[0].hasName && rows[0].options.map(\.id) == ["perm"])
        #expect(rows[1].options.map(\.id) == ["reflabel"] && !rows[1].indented)
        #expect(rows[2].options.map(\.id) == ["refs"] && rows[2].indented && !rows[2].expands)
        #expect(rows[3].options.map(\.id) == ["allrefs", "branches", "tags", "remotes"])
        #expect(rows[3].indented && rows[3].expands)
        // Every option appears exactly once, in gitk's order.
        #expect(rows.flatMap(\.options).map(\.id) == ViewOptions.known.map(\.id))
        #expect(rows.last?.options.map(\.id) == ["cmd"])
    }

    @Test func createViewBuildsSpec() throws {
        var v = ViewOptionCodec.decode([])
        v.name = "Alice since March"
        v.values["author"] = .text("alice")
        v.values["since"] = .text("2026-03-01")
        let spec = try ViewEditorForm.spec(values: v, pathsText: "")
        #expect(spec.name == "Alice since March")
        #expect(spec.args == ["--author=alice", "--since=2026-03-01"])
        #expect(spec.files.isEmpty && spec.argsCmd == nil && !spec.perm)
    }

    @Test func pathsFieldSplitsLines() throws {
        let spec = try ViewEditorForm.spec(values: ViewOptionCodec.decode([]), pathsText: "src/\n  docs/ \n\n")
        #expect(spec.files == ["src/", "docs/"])
    }

    @Test func encodingErrorThrows() {
        var v = ViewOptionCodec.decode([])
        v.values["args"] = .text("\"unterminated")
        #expect(throws: ViewArgsError.self) { try ViewEditorForm.spec(values: v, pathsText: "") }
    }

    @Test func editorFieldsRoundTrip() {
        let view = ViewSpec(
            name: "v", args: ["--author=bob", "-20", "--no-merges"], files: ["a"], argsCmd: "echo", perm: true)
        let editor = ViewEditorController(
            view: view, alerts: Alerts(environment: ["GITK_SWIFT_HEADLESS_ERRORS": "1"], sink: { _ in }))
        var applied: ViewSpec?
        editor.onApply = { applied = $0 }
        #expect(editor.apply())
        #expect(applied == ViewSpec(
            name: "v", args: ["--author=bob", "--max-count=20", "--no-merges"], files: ["a"],
            argsCmd: "echo", perm: true))
    }
}
