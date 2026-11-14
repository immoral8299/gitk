// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct ExternalDiffTests {
    @Test func renamedFilesReachToolAndAreRemoved() async throws {
        let repo = try FixtureRepo.make("renames")
        let runner = GitRunner(cwd: repo)
        func resolve(_ rev: String) async throws -> ObjectID {
            let output = try await runner.run(["rev-parse", rev])
            return try #require(ObjectID(hex: String(decoding: output.stdout, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        let temp = try TempFiles()
        defer { try? temp.cleanup() }
        let oldID = try await resolve("HEAD~2")
        let newID = try await resolve("HEAD~1")
        let files = try await ExternalDiff.prepare(from: .commit(oldID),
            to: .commit(newID), path: "gadget.c", oldPath: "widget.c", worktree: repo,
            runner: runner, tempFiles: temp)
        #expect(try String(contentsOf: files.oldFile, encoding: .utf8).contains("widget_fn_7"))
        #expect(try String(contentsOf: files.newFile, encoding: .utf8).contains("gadget_fn_7"))
        let script = temp.directory.appendingPathComponent("fake viewer")
        let capture = temp.directory.appendingPathComponent("capture")
        try Data("#!/bin/sh\nprintf '%s\\n' \"$2\" \"$3\" > \"$1\"\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        try await ExternalDiff.launch(tool: ShellWords.argList([script.path, capture.path]), files: files)
        #expect(try String(contentsOf: capture, encoding: .utf8) == files.oldFile.path + "\n" + files.newFile.path + "\n")
        #expect(!FileManager.default.fileExists(atPath: files.directory.path))
        try temp.cleanup()
        #expect(!FileManager.default.fileExists(atPath: temp.directory.path))
    }
}
