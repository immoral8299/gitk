// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
import GitkCore
@testable import GitkUI

@MainActor
@Suite struct KeyRouterTests {
    private func event(_ text: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
            characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code))
    }

    @Test func lettersStayInEditableFields() throws {
        let key = try event("j", code: 38)
        let field = NSTextField()
        field.isEditable = true
        #expect(KeyRouter.command(for: key, firstResponder: field) == nil)
        let editor = NSTextView()
        editor.isEditable = true
        #expect(KeyRouter.command(for: key, firstResponder: editor) == nil)
        #expect(KeyRouter.command(for: key, firstResponder: NSTableView()) == .selectNext)
        editor.isEditable = false
        #expect(KeyRouter.command(for: key, firstResponder: editor) == .selectNext)
    }

    @Test func navigationStaysInTextEditor() throws {
        let editor = NSTextView()
        editor.isEditable = true
        #expect(KeyRouter.command(for: try event("", code: 125), firstResponder: editor) == nil)
        #expect(KeyRouter.command(for: try event("g", code: 5, modifiers: .command), firstResponder: editor)
            == .findNext(wrap: false))
    }

    @Test func functionAndSymbolKeys() throws {
        #expect(KeyRouter.command(for: try event("", code: 96, modifiers: .shift), firstResponder: nil) == .reload)
        #expect(KeyRouter.command(for: try event("?", code: 44, modifiers: .shift), firstResponder: nil)
            == .findPrev(wrap: true))
        #expect(KeyRouter.command(for: try event("", code: 75), firstResponder: nil) == .focusFind)
    }
}
