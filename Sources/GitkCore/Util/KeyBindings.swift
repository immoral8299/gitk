// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

/// A modifier held with a key. gitk's `M1` is Command on macOS, so gitk's
/// `<Control-…>` shortcuts become `.command`.
public enum KeyModifier: Sendable, Hashable {
    case command
    case shift
    case option
    case control
}

/// A key as the UI reports it. Named cases cover the keys gitk binds; any
/// other printable key is `.character`. Characters are lowercase letters,
/// or the unshifted symbol the key produces (`?`, `+`, `=`).
public enum KeyName: Sendable, Hashable {
    case character(Character)
    case up
    case down
    case left
    case right
    case home
    case end
    case pageUp
    case pageDown
    case space
    /// The forward Delete key (gitk's `<Key-Delete>`).
    case delete
    /// The key labelled Delete on Mac keyboards (gitk's `<Key-BackSpace>`).
    case backspace
    case returnKey
    case f2
    case f4
    case f5
    case keypadDivide
    case keypadPlus
    case keypadMinus

    /// Keys that edit text in a field. gitk binds these with `bindkey`, which
    /// keeps them away from entry widgets, so they only act when focus is not
    /// in a text field.
    var editsText: Bool {
        switch self {
        case .character, .space, .delete, .backspace, .returnKey,
             .home, .end, .left, .right, .keypadDivide:
            true
        case .up, .down, .pageUp, .pageDown, .f2, .f4, .f5, .keypadPlus, .keypadMinus:
            false
        }
    }
}

/// A key press: the key and the modifiers held with it.
public struct KeyDescriptor: Sendable, Hashable {
    public var key: KeyName
    public var modifiers: Set<KeyModifier>

    public init(_ key: KeyName, _ modifiers: Set<KeyModifier> = []) {
        self.key = key
        self.modifiers = modifiers
    }
}

/// One entry of the key table.
public struct KeyBinding: Sendable, Hashable {
    public let descriptor: KeyDescriptor
    public let command: AppCommand

    public init(descriptor: KeyDescriptor, command: AppCommand) {
        self.descriptor = descriptor
        self.command = command
    }

    /// True for unmodified text-editing keys (letters, space, Delete, Return,
    /// arrows that move the caret). The key router must not run these while
    /// the first responder is an editable text view or field (design D8).
    public var requiresNonTextFocus: Bool {
        descriptor.modifiers.isEmpty && descriptor.key.editsText
    }
}

/// Maps key presses to `AppCommand` values. Port of gitk's key bindings
/// (`makewindow`, gitk 2592–2850) and the `keys` help text (3223–3293), with
/// Command in place of gitk's Control or Meta on macOS.
///
/// Where the spec and gitk disagree, the spec wins: `b` is previous file
/// (gitk binds `prevfile`; its help text says page up).
public struct KeyBindings: Sendable {
    public let bindings: [KeyBinding]
    private let table: [KeyDescriptor: KeyBinding]

    /// If two bindings share a descriptor, the first one wins.
    public init(_ bindings: [KeyBinding]) {
        self.bindings = bindings
        var table: [KeyDescriptor: KeyBinding] = [:]
        for binding in bindings where table[binding.descriptor] == nil {
            table[binding.descriptor] = binding
        }
        self.table = table
    }

    public func binding(for descriptor: KeyDescriptor) -> KeyBinding? {
        table[descriptor]
    }

    public func command(for descriptor: KeyDescriptor) -> AppCommand? {
        table[descriptor]?.command
    }

    /// The bindings of the main window, as gitk defines them on macOS.
    public static let gitk = KeyBindings(gitkBindings())

    private static func bind(_ key: KeyName, _ command: AppCommand, _ modifiers: Set<KeyModifier> = []) -> KeyBinding {
        KeyBinding(descriptor: KeyDescriptor(key, modifiers), command: command)
    }

    private static func gitkBindings() -> [KeyBinding] {
        var list: [KeyBinding] = []

        // Commit list selection (gitk 2778–2805, `keys` help).
        list.append(bind(.home, .selectFirst))
        list.append(bind(.end, .selectLast))
        list.append(bind(.up, .selectPrev))
        list.append(bind(.character("p"), .selectPrev))
        list.append(bind(.character("k"), .selectPrev))
        list.append(bind(.down, .selectNext))
        list.append(bind(.character("n"), .selectNext))
        list.append(bind(.character("j"), .selectNext))
        list.append(bind(.pageUp, .selectPageUp))
        list.append(bind(.pageDown, .selectPageDown))
        list.append(bind(.left, .goBack))
        list.append(bind(.character("z"), .goBack))
        list.append(bind(.character("h"), .goBack))
        list.append(bind(.right, .goForward))
        list.append(bind(.character("x"), .goForward))
        list.append(bind(.character("l"), .goForward))

        // Scroll the commit list without changing the selection (gitk 2788–2793).
        list.append(bind(.home, .scrollList(.toStart), [.command]))
        list.append(bind(.end, .scrollList(.toEnd), [.command]))
        list.append(bind(.up, .scrollList(.lines(-1)), [.command]))
        list.append(bind(.down, .scrollList(.lines(1)), [.command]))
        list.append(bind(.pageUp, .scrollList(.pages(-1)), [.command]))
        list.append(bind(.pageDown, .scrollList(.pages(1)), [.command]))

        // Go to the n-th parent (gitk 2843–2846).
        for n in 1...9 {
            list.append(bind(.character(Character("\(n)")), .goToParent(n), [.command]))
        }

        // Commit find (gitk 2809–2812, 2782–2783, 2820–2821).
        list.append(bind(.returnKey, .findNext(wrap: true)))
        list.append(bind(.character("?"), .findPrev(wrap: true)))
        list.append(bind(.down, .findNext(wrap: false), [.shift]))
        list.append(bind(.up, .findPrev(wrap: false), [.shift]))
        list.append(bind(.character("f"), .nextFile))
        list.append(bind(.character("g"), .focusCommitID))
        list.append(bind(.character("/"), .focusFind))
        list.append(bind(.keypadDivide, .focusFind))
        list.append(bind(.character("f"), .findNext(wrap: true), [.command]))
        list.append(bind(.character("g"), .findNext(wrap: false), [.command]))

        // Diff pane scrolling and files (gitk 2794–2807, 2813).
        list.append(bind(.space, .scrollPane(.pages(1))))
        list.append(bind(.delete, .scrollPane(.pages(-1))))
        list.append(bind(.backspace, .scrollPane(.pages(-1))))
        list.append(bind(.character("d"), .scrollPane(.lines(18))))
        list.append(bind(.character("u"), .scrollPane(.lines(-18))))
        list.append(bind(.character("b"), .prevFile))

        // Pane search (gitk 2822–2823).
        list.append(bind(.character("s"), .paneSearchNext, [.command]))
        list.append(bind(.character("r"), .paneSearchPrev, [.command]))

        // Font size (gitk 2824–2828).
        list.append(bind(.character("="), .fontBigger, [.command]))
        list.append(bind(.character("+"), .fontBigger, [.command]))
        list.append(bind(.keypadPlus, .fontBigger, [.command]))
        list.append(bind(.character("-"), .fontSmaller, [.command]))
        list.append(bind(.keypadMinus, .fontSmaller, [.command]))

        // File and view menus (gitk 2414–2420, 2814–2818).
        list.append(bind(.f5, .update))
        list.append(bind(.f5, .reload, [.shift]))
        list.append(bind(.f2, .listRefs))
        list.append(bind(.f4, .editOrNewView))
        list.append(bind(.f4, .newView, [.shift]))

        // Application and windows (gitk 2776–2777, 2819).
        list.append(bind(.character("q"), .quit, [.command]))
        list.append(bind(.character("w"), .closeWindow, [.command]))
        list.append(bind(.character(","), .preferences, [.command]))

        return list
    }
}
