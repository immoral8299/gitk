// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Testing
@testable import GitkCore

@Suite struct KeyBindingsTests {
    private let keys = KeyBindings.gitk

    private func command(_ key: KeyName, _ modifiers: Set<KeyModifier> = []) -> AppCommand? {
        keys.command(for: KeyDescriptor(key, modifiers))
    }

    private func binding(_ key: KeyName, _ modifiers: Set<KeyModifier> = []) -> KeyBinding? {
        keys.binding(for: KeyDescriptor(key, modifiers))
    }

    // MARK: Commit list (commit-list spec, "Keyboard navigation")

    @Test func upAndDownMoveSelection() {
        #expect(command(.up) == .selectPrev)
        #expect(command(.down) == .selectNext)
        #expect(command(.character("p")) == .selectPrev)
        #expect(command(.character("k")) == .selectPrev)
        #expect(command(.character("n")) == .selectNext)
        #expect(command(.character("j")) == .selectNext)
    }

    @Test func homeEndAndPagesMoveSelection() {
        #expect(command(.home) == .selectFirst)
        #expect(command(.end) == .selectLast)
        #expect(command(.pageUp) == .selectPageUp)
        #expect(command(.pageDown) == .selectPageDown)
    }

    @Test func commandScrollsCommitListWithoutSelecting() {
        #expect(command(.home, [.command]) == .scrollList(.toStart))
        #expect(command(.end, [.command]) == .scrollList(.toEnd))
        #expect(command(.up, [.command]) == .scrollList(.lines(-1)))
        #expect(command(.down, [.command]) == .scrollList(.lines(1)))
        #expect(command(.pageUp, [.command]) == .scrollList(.pages(-1)))
        #expect(command(.pageDown, [.command]) == .scrollList(.pages(1)))
    }

    @Test func commandDigitsGoToParent() {
        for n in 1...9 {
            #expect(command(.character(Character("\(n)")), [.command]) == .goToParent(n))
        }
    }

    @Test func historyKeys() {
        #expect(command(.left) == .goBack)
        #expect(command(.character("z")) == .goBack)
        #expect(command(.character("h")) == .goBack)
        #expect(command(.right) == .goForward)
        #expect(command(.character("x")) == .goForward)
        #expect(command(.character("l")) == .goForward)
    }

    // MARK: Commit find (commit-find spec)

    @Test func returnAndCommandFSearchDownWithWrap() {
        #expect(command(.returnKey) == .findNext(wrap: true))
        #expect(command(.character("f"), [.command]) == .findNext(wrap: true))
    }

    @Test func questionMarkSearchesUpWithWrap() {
        #expect(command(.character("?")) == .findPrev(wrap: true))
    }

    @Test func commandGAndShiftDownSearchDownWithoutWrap() {
        #expect(command(.character("g"), [.command]) == .findNext(wrap: false))
        #expect(command(.down, [.shift]) == .findNext(wrap: false))
    }

    @Test func shiftUpSearchesUpWithoutWrap() {
        #expect(command(.up, [.shift]) == .findPrev(wrap: false))
    }

    @Test func slashAndKeypadDivideFocusFind() {
        #expect(command(.character("/")) == .focusFind)
        #expect(command(.keypadDivide) == .focusFind)
    }

    @Test func gFocusesCommitID() {
        #expect(command(.character("g")) == .focusCommitID)
    }

    // MARK: Diff pane (diff-viewer spec, "Pane scrolling keys" and "Text search in the pane")

    @Test func spaceScrollsPaneDownAPage() {
        #expect(command(.space) == .scrollPane(.pages(1)))
    }

    @Test func deleteAndBackspaceScrollPaneUpAPage() {
        #expect(command(.delete) == .scrollPane(.pages(-1)))
        #expect(command(.backspace) == .scrollPane(.pages(-1)))
    }

    @Test func dAndUScrollPaneEighteenLines() {
        #expect(command(.character("d")) == .scrollPane(.lines(18)))
        #expect(command(.character("u")) == .scrollPane(.lines(-18)))
    }

    @Test func fAndBJumpBetweenFiles() {
        #expect(command(.character("f")) == .nextFile)
        #expect(command(.character("b")) == .prevFile)
    }

    @Test func commandSAndRSearchPane() {
        #expect(command(.character("s"), [.command]) == .paneSearchNext)
        #expect(command(.character("r"), [.command]) == .paneSearchPrev)
    }

    // MARK: Preferences (preferences spec, "Font size shortcuts" and "Quit and close")

    @Test func commandPlusEqualAndKeypadPlusMakeFontsBigger() {
        #expect(command(.character("="), [.command]) == .fontBigger)
        #expect(command(.character("+"), [.command]) == .fontBigger)
        #expect(command(.keypadPlus, [.command]) == .fontBigger)
    }

    @Test func commandMinusAndKeypadMinusMakeFontsSmaller() {
        #expect(command(.character("-"), [.command]) == .fontSmaller)
        #expect(command(.keypadMinus, [.command]) == .fontSmaller)
    }

    @Test func commandZeroResetsFontSizes() {
        #expect(command(.character("0"), [.command]) == .fontReset)
    }

    @Test func commandQQuitsAndCommandWClosesWindow() {
        #expect(command(.character("q"), [.command]) == .quit)
        #expect(command(.character("w"), [.command]) == .closeWindow)
    }

    @Test func commandCommaOpensPreferences() {
        #expect(command(.character(","), [.command]) == .preferences)
    }

    // MARK: File, references and views (history-loading, reference-list, views specs)

    @Test func f5UpdatesAndShiftF5Reloads() {
        #expect(command(.f5) == .update)
        #expect(command(.f5, [.shift]) == .reload)
    }

    @Test func f2ListsReferences() {
        #expect(command(.f2) == .listRefs)
    }

    @Test func shiftF4CreatesViewAndF4EditsOrCreates() {
        #expect(command(.f4, [.shift]) == .newView)
        #expect(command(.f4) == .editOrNewView)
    }

    // MARK: Text-focus gating

    @Test func unmodifiedLetterAndTextKeysRequireNonTextFocus() {
        let letters: [Character] = ["j", "k", "n", "p", "h", "l", "x", "z", "g", "f", "b", "d", "u", "/", "?"]
        for letter in letters {
            #expect(binding(.character(letter))?.requiresNonTextFocus == true, "\(letter)")
        }
        #expect(binding(.space)?.requiresNonTextFocus == true)
        #expect(binding(.backspace)?.requiresNonTextFocus == true)
        #expect(binding(.delete)?.requiresNonTextFocus == true)
        #expect(binding(.returnKey)?.requiresNonTextFocus == true)
        #expect(binding(.keypadDivide)?.requiresNonTextFocus == true)
        #expect(binding(.left)?.requiresNonTextFocus == true)
        #expect(binding(.right)?.requiresNonTextFocus == true)
        #expect(binding(.home)?.requiresNonTextFocus == true)
        #expect(binding(.end)?.requiresNonTextFocus == true)
    }

    @Test func modifiedAndNavigationKeysDoNotRequireNonTextFocus() {
        #expect(binding(.character("f"), [.command])?.requiresNonTextFocus == false)
        #expect(binding(.character("s"), [.command])?.requiresNonTextFocus == false)
        #expect(binding(.down, [.shift])?.requiresNonTextFocus == false)
        #expect(binding(.up)?.requiresNonTextFocus == false)
        #expect(binding(.down)?.requiresNonTextFocus == false)
        #expect(binding(.pageUp)?.requiresNonTextFocus == false)
        #expect(binding(.pageDown)?.requiresNonTextFocus == false)
        #expect(binding(.f5)?.requiresNonTextFocus == false)
    }

    // MARK: Table integrity

    @Test func everyDescriptorIsBoundOnce() {
        let descriptors = keys.bindings.map(\.descriptor)
        #expect(Set(descriptors).count == descriptors.count)
    }

    @Test func everyBindingResolvesToItsOwnCommand() {
        for entry in keys.bindings {
            #expect(keys.command(for: entry.descriptor) == entry.command)
        }
    }

    @Test func unboundKeysReturnNil() {
        #expect(command(.character("v")) == nil)
        #expect(command(.character("q")) == nil)
    }
}
