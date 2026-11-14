// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor
@Suite struct FocusKeyTests {
    @Test func searchAndCommitKeysRespectFieldEditing() throws {
        for (text, code, command) in [("/", UInt16(44), AppCommand.focusFind), ("g", UInt16(5), AppCommand.focusCommitID)] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: code))
            #expect(KeyRouter.command(for: event, firstResponder: NSTableView()) == command)
            #expect(KeyRouter.command(for: event, firstResponder: NSTextField()) == nil)
        }
    }

    /// `g` puts the titlebar field into go-to-commit mode; Escape and Return go back
    /// to search mode with the search text restored (D16 "Go to commit").
    @Test func goToCommitModeRoundTrip() throws {
        let repo = RepoContext(gitDir: ".git", worktree: "/tmp", cdup: "", isBare: false, hasWorktree: true,
                               hashAlgorithm: "sha1", hashLength: 40, logShowRoot: true, gitEncoding: "utf-8", guiEncoding: "utf-8")
        let bar = SearchBar(session: ViewSession(repo: repo, runner: GitRunner(), view: ViewSpec(name: "Test")))
        bar.field.stringValue = "fix"
        bar.enterGoToCommitMode()
        #expect(bar.fieldMode == .goToCommit)
        #expect(bar.field.stringValue.isEmpty)
        #expect(bar.field.placeholderString == L("Go to commit…"))
        #expect(bar.query.pattern == "fix")
        bar.field.stringValue = "abc123"
        var went: String?
        bar.onGo = { went = $0 }
        bar.field.sendAction(bar.field.action, to: bar.field.target)
        #expect(went == "abc123")
        #expect(bar.fieldMode == .search)
        #expect(bar.field.stringValue == "fix")
        #expect(bar.field.placeholderString == L("Search commits…"))
        bar.enterGoToCommitMode()
        let textView = NSTextView()
        #expect(bar.control(bar.field, textView: textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(bar.fieldMode == .search)
        #expect(bar.field.stringValue == "fix")
    }
}
