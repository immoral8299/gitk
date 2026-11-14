// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

public struct NavigationEntry: Sendable, Equatable {
    public enum Target: Sendable, Equatable {
        case commit(ObjectID)
        case line(ObjectID, child: ObjectID)
        case link(ObjectID)
    }
    public var target: Target
    public var scrollPosition: Double
    public init(target: Target, scrollPosition: Double = 0) {
        self.target = target
        self.scrollPosition = scrollPosition
    }
}

public struct NavigationHistory: Sendable {
    public private(set) var entries: [NavigationEntry] = []
    public private(set) var index: Int = -1
    public init() {}
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index >= 0 && index + 1 < entries.count }
    public var current: NavigationEntry? { entries.indices.contains(index) ? entries[index] : nil }

    /// Port of gitk proc `addtohistory` (gitk/gitk 7726–7755).
    public func adding(_ entry: NavigationEntry, saving position: Double = 0) -> NavigationHistory {
        var result = saving(position)
        if result.current?.target == entry.target { return result }
        result.entries = Array(result.entries.prefix(result.index + 1)) + [entry]
        result.index = result.entries.count - 1
        return result
    }

    /// Port of gitk proc `save_position` (gitk/gitk 7758–7768).
    public func saving(_ position: Double) -> NavigationHistory {
        var result = self
        if result.entries.indices.contains(result.index) { result.entries[result.index].scrollPosition = position }
        return result
    }

    /// Port of gitk procs `goback`, `goforw` (gitk/gitk 7791–7823).
    public func stepping(forward: Bool, saving position: Double) -> NavigationHistory {
        var result = saving(position)
        if forward ? canGoForward : canGoBack { result.index += forward ? 1 : -1 }
        return result
    }
}
