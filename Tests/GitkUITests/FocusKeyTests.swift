// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
import GitkCore
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
}
