// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

/// A window frame as stored in `Settings.geometry`: `"x y width height"`.
/// Not gitk's Tk `WxH+X+Y` form (that one is imported under gitk's own keys
/// and left unused).
public struct StoredFrame: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public init?(_ string: String) {
        let parts = string.split(separator: " ").compactMap { Double($0) }
        guard parts.count == 4, parts.allSatisfy(\.isFinite), parts[2] > 0, parts[3] > 0 else { return nil }
        self.init(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    public var string: String { "\(x) \(y) \(width) \(height)" }
}

/// Typed access to the geometry entries the app saves (design D16, spec
/// "Persistence"), kept in `Settings.geometry` next to gitk's imported keys.
extension Settings {
    enum GeometryKey {
        static let window = "window"
        static let diffHeight = "diffheight"
        static let sidebarWidth = "sidebarwidth"
        static let sidebarHidden = "sidebarhidden"
        static let authorWidth = "authorwidth"
        static let dateWidth = "datewidth"
        static let refList = "reflist"
    }

    public var windowFrame: StoredFrame? {
        get { geometry[GeometryKey.window].flatMap(StoredFrame.init) }
        set { geometry[GeometryKey.window] = newValue?.string }
    }

    public var refListFrame: StoredFrame? {
        get { geometry[GeometryKey.refList].flatMap(StoredFrame.init) }
        set { geometry[GeometryKey.refList] = newValue?.string }
    }

    /// Height of the diff pane below the history list.
    public var diffHeight: Double? {
        get { number(GeometryKey.diffHeight) }
        set { geometry[GeometryKey.diffHeight] = newValue.map { "\($0)" } }
    }

    public var sidebarWidth: Double? {
        get { number(GeometryKey.sidebarWidth) }
        set { geometry[GeometryKey.sidebarWidth] = newValue.map { "\($0)" } }
    }

    public var sidebarHidden: Bool {
        get { geometry[GeometryKey.sidebarHidden] == "1" }
        set { geometry[GeometryKey.sidebarHidden] = newValue ? "1" : nil }
    }

    /// Widths the user dragged the author and date columns to.
    public var authorWidth: Double? {
        get { number(GeometryKey.authorWidth) }
        set { geometry[GeometryKey.authorWidth] = newValue.map { "\($0)" } }
    }

    public var dateWidth: Double? {
        get { number(GeometryKey.dateWidth) }
        set { geometry[GeometryKey.dateWidth] = newValue.map { "\($0)" } }
    }

    private func number(_ key: String) -> Double? {
        guard let value = geometry[key].flatMap(Double.init), value.isFinite, value > 0 else { return nil }
        return value
    }
}
