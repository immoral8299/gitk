// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Port of gitk proc `bindkey`: text editing keeps priority over history keys.
final class KeyRouter: NSWindow {
    var commandHandler: ((AppCommand) -> Bool)?

    static func command(for event: NSEvent, firstResponder: NSResponder?) -> AppCommand? {
        guard event.type == .keyDown, let descriptor = descriptor(for: event) else { return nil }
        let editing = (firstResponder as? NSTextView)?.isEditable == true
            || (firstResponder as? NSTextField)?.isEditable == true
        if editing && !descriptor.modifiers.contains(.command)
            && !descriptor.modifiers.contains(.control) && !descriptor.modifiers.contains(.option) {
            return nil
        }
        return KeyBindings.gitk.command(for: descriptor)
    }

    static func descriptor(for event: NSEvent) -> KeyDescriptor? {
        let named: [UInt16: KeyName] = [
            126: .up, 125: .down, 123: .left, 124: .right,
            115: .home, 119: .end, 116: .pageUp, 121: .pageDown,
            51: .backspace, 117: .delete, 36: .returnKey, 76: .returnKey,
            120: .f2, 118: .f4, 96: .f5,
            75: .keypadDivide, 69: .keypadPlus, 78: .keypadMinus,
        ]
        var modifiers = Set<KeyModifier>()
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if let key = named[event.keyCode] { return KeyDescriptor(key, modifiers) }
        guard let text = event.charactersIgnoringModifiers, text.count == 1, let c = text.first else {
            return nil
        }
        if c == "?" || c == "+" { modifiers.remove(.shift) }
        return KeyDescriptor(c == " " ? .space : .character(Character(String(c).lowercased())), modifiers)
    }

    override func sendEvent(_ event: NSEvent) {
        if let command = Self.command(for: event, firstResponder: firstResponder),
           commandHandler?(command) == true { return }
        super.sendEvent(event)
    }
}
