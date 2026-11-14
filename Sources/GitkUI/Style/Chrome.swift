// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit

/// Native chrome for the window's own controls.
///
/// macOS 26 draws control strips with Liquid Glass (`NSGlassEffectView`);
/// earlier systems get the same layout with a translucent material, so a single
/// code path keeps the app at its macOS 14 deployment target. The effect is
/// deliberately limited to chrome: content panes stay opaque so diff colours
/// and gitk's settings stay legible (design D15).
@MainActor
enum Chrome {
    /// Whether this process runs on a system with Liquid Glass.
    static var hasLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// Wraps a control strip in the platform's translucent background.
    ///
    /// Use it only for the window's own controls, not for panes that show
    /// content. The returned view is frame-sized by its container; the bar
    /// content fills it and stays the view callers hold on to.
    static func bar(_ content: NSView, cornerRadius: CGFloat = 8) -> NSView {
        if content is BarChrome { return content }
        return BarChrome(content: content, cornerRadius: cornerRadius)
    }

    /// Window-level conventions shared by every macOS version.
    ///
    /// The title bar is unified with the content and its separator is left to
    /// the material; toolbars and bars provide their own contrast.
    static func decorate(_ window: NSWindow) {
        window.titlebarSeparatorStyle = .none
        window.tabbingMode = .disallowed
    }

    /// Whether the search bar goes into a unified titlebar (D15/D16): only with
    /// Liquid Glass. `GITK_SWIFT_CHROME=legacy` or `=unified` overrides this, so
    /// both layouts can be checked with snapshots on one machine.
    static func usesUnifiedTitlebar(environment: [String: String]) -> Bool {
        switch environment["GITK_SWIFT_CHROME"] {
        case "legacy": return false
        case "unified": return true
        default: return hasLiquidGlass
        }
    }

    /// Makes the titlebar unified with the content and installs `toolbar`,
    /// leaving the traffic lights at the left. The content view then spans the
    /// whole window. Scroll views placed under the titlebar get the system's
    /// backdrop blur (scroll edge effect on macOS 26, titlebar material before),
    /// so the titlebar must not be made transparent.
    static func installUnifiedTitlebar(_ window: NSWindow, toolbar: NSToolbar) {
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
    }

    /// The details sidebar's backdrop: docked edge to edge (not a floating
    /// panel). Liquid Glass on macOS 26 and newer, the sidebar material before.
    static func sidebarBackground() -> SidebarPanel {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            let content = FlippedContent()
            glass.contentView = content
            return SidebarPanel(view: glass, content: content, inset: 0)
        }
        let material = NSVisualEffectView()
        material.material = .sidebar
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        let content = FlippedContent()
        content.autoresizingMask = [.width, .height]
        content.frame = material.bounds
        material.addSubview(content)
        return SidebarPanel(view: material, content: content, inset: 0)
    }
}


/// A bar drawn over a translucent backdrop.
///
/// `NSGlassEffectView` is used on macOS 26 and newer; older systems use
/// `NSVisualEffectView` with the header material. The content is a sibling of
/// the backdrop rather than a `contentView`, because containers size rows by
/// frame and need the bar to occupy the full row.
@MainActor
final class BarChrome: NSView {
    let content: NSView
    private let backdrop: NSView
    private let inset: NSEdgeInsets

    init(content: NSView, cornerRadius: CGFloat, inset: NSEdgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 4)) {
        self.content = content
        self.inset = inset
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            backdrop = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .headerView
            material.blendingMode = .withinWindow
            material.state = .followsWindowActiveState
            material.wantsLayer = true
            material.layer?.cornerRadius = cornerRadius
            material.layer?.masksToBounds = true
            backdrop = material
        }
        super.init(frame: content.frame)
        addSubview(backdrop)
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let box = NSRect(x: bounds.minX + inset.left, y: bounds.minY + inset.bottom,
                         width: max(0, bounds.width - inset.left - inset.right),
                         height: max(0, bounds.height - inset.top - inset.bottom))
        backdrop.frame = box
        content.frame = box
    }
}

/// A sidebar backdrop and the view that holds its content.
@MainActor
struct SidebarPanel {
    let view: NSView
    let content: NSView
    /// Gap between the panel and the sidebar's edges.
    let inset: CGFloat
}

/// A flipped container, so content lays out from the top.
final class FlippedContent: NSView {
    override var isFlipped: Bool { true }
}
