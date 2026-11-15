// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Font-derived default sizes of the main window.
///
/// Port of gitk/gitk 2451–2458 (`geometry(topheight)` and friends, in terms of
/// `linespc` and `charspc`) and of `setcoords` (8803–8804): `linespc` is the
/// main font's line height and `charspc` the width of "m". The D16 layout adds
/// the search strip, the details sidebar and the status strip around them.
struct MainLayoutMetrics: Equatable {
    var linespc: CGFloat
    var charspc: CGFloat
    /// Height of the search strip when it is a content row (no unified titlebar).
    var searchBarHeight: CGFloat = 36
    var statusBarHeight: CGFloat = 22
    var sidebarWidth: CGFloat = 320
    var sidebarMinWidth: CGFloat = 220
    /// Below this content width the sidebar collapses (D16 "Small windows").
    var narrowWidth: CGFloat = 700

    var topHeight: CGFloat { 15 * linespc }
    var topWidth: CGFloat { 80 * charspc }
    var botHeight: CGFloat { 15 * linespc }
    var botWidth: CGFloat { 50 * charspc }
    /// `pwsash0` and `pwsash1`: x positions of the two history column dividers.
    var sash0: CGFloat { 40 * charspc }
    var sash1: CGFloat { 60 * charspc }
    var dividerThickness: CGFloat { 1 }
    /// The history list keeps at least a few rows when the diff pane grows.
    var listMinHeight: CGFloat { 4 * linespc }

    /// Content size of a window that shows the defaults without resizing: the
    /// list over an equally tall diff pane, the sidebar beside them.
    var windowContentSize: NSSize {
        NSSize(width: topWidth + dividerThickness + sidebarWidth,
               height: searchBarHeight + topHeight + dividerThickness + botHeight + statusBarHeight)
    }

    init(linespc: CGFloat, charspc: CGFloat) {
        self.linespc = linespc
        self.charspc = charspc
    }

    init(mainFont: FontSpec) {
        let font = MainLayoutMetrics.nsFont(mainFont)
        let advance = ("m" as NSString).size(withAttributes: [.font: font]).width
        self.init(
            linespc: ceil(font.ascender - font.descender + font.leading),
            charspc: ceil(advance))
    }

    /// Maps a `FontSpec` (design D9) to an `NSFont`.
    static func nsFont(_ spec: FontSpec) -> NSFont {
        let size = CGFloat(spec.pointSize)
        let weight: NSFont.Weight = spec.bold ? .bold : .regular
        var font: NSFont
        switch spec.family {
        case FontSpec.systemFamily:
            font = NSFont.systemFont(ofSize: size, weight: weight)
        case FontSpec.monospacedSystemFamily:
            font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        default:
            font = NSFont(name: spec.family, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
            if spec.bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        }
        if spec.italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }
}

/// An empty content pane, used until a pane's real view is installed (the diff
/// pane stays empty until a commit is selected).
final class PlaceholderPane: NSView {
    let name: String

    init(name: String) {
        self.name = name
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityLabel(name)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    override var wantsUpdateLayer: Bool { true }
}

/// The main window's split (design D16): the content column and, on the
/// right, the details sidebar as a full-height inspector. With a unified
/// titlebar the toolbar spans only the content column (an inspector tracking
/// separator), so the titlebar no longer runs over the sidebar.
@MainActor
final class MainSplitController: NSSplitViewController {
    let content: MainSplitView
    let sidebar = DetailsSidebar()
    let contentItem: NSSplitViewItem
    let sidebarItem: NSSplitViewItem
    private let metrics: MainLayoutMetrics
    /// Set by View → Details Sidebar and the toolbar toggle.
    /// Width restored from the settings; used instead of the default.
    var restoredSidebarWidth: CGFloat? {
        didSet { if let width = restoredSidebarWidth { sidebar.frame.size.width = width } }
    }
    /// The sidebar's width while it is shown, else the last one used.
    var sidebarWidth: CGFloat {
        if !sidebarItem.isCollapsed, sidebar.frame.width > 0 { return sidebar.frame.width }
        return restoredSidebarWidth ?? metrics.sidebarWidth
    }
    var sidebarHiddenByUser = false { didSet { updateSidebar(animated: true) } }
    /// True while the sidebar is shown (not hidden and not collapsed by width).
    var isSidebarShown: Bool { !sidebarItem.isCollapsed }

    init(metrics: MainLayoutMetrics) {
        self.metrics = metrics
        content = MainSplitView(metrics: metrics)
        let contentController = NSViewController()
        contentController.view = content
        contentItem = NSSplitViewItem(viewController: contentController)
        contentItem.minimumThickness = 300
        let sidebarController = NSViewController()
        sidebar.frame.size.width = metrics.sidebarWidth
        sidebarController.view = sidebar
        sidebarItem = NSSplitViewItem(inspectorWithViewController: sidebarController)
        sidebarItem.minimumThickness = metrics.sidebarMinWidth
        sidebarItem.maximumThickness = 560
        sidebarItem.canCollapse = true
        sidebarItem.canCollapseFromWindowResize = true
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.holdingPriority = .init(260)
        contentItem.holdingPriority = .init(250)
        super.init(nibName: nil, bundle: nil)
        addSplitViewItem(contentItem)
        addSplitViewItem(sidebarItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.dividerStyle = .thin
        view.frame.size = metrics.windowContentSize
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateSidebar(animated: false)
    }

    /// D16 "Small windows": below `narrowWidth` the sidebar collapses first.
    private func updateSidebar(animated: Bool) {
        guard view.bounds.width > 0 else { return }
        let collapse = sidebarHiddenByUser || view.bounds.width < metrics.narrowWidth
        guard collapse != sidebarItem.isCollapsed else { return }
        if animated { sidebarItem.animator().isCollapsed = collapse } else { sidebarItem.isCollapsed = collapse }
    }

    /// Puts the sidebar at its default width once the window has its size.
    func applyDefaultSidebarWidth() {
        guard !sidebarItem.isCollapsed, splitView.arrangedSubviews.count == 2 else { return }
        let width = min(max(restoredSidebarWidth ?? metrics.sidebarWidth, metrics.sidebarMinWidth), sidebarItem.maximumThickness)
        splitView.setPosition(splitView.bounds.width - width, ofDividerAt: 0)
    }

    // A divider dragged to the edge collapses the sidebar: remember that.
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        if NSApp.currentEvent?.type == .leftMouseDragged, sidebarItem.isCollapsed != sidebarHiddenByUser,
           view.bounds.width >= metrics.narrowWidth {
            sidebarHiddenByUser = sidebarItem.isCollapsed
        }
    }
}

/// The content column (design D16): an optional search row, then the history
/// list over the diff pane, with the status strip along the bottom.
///
/// Replaces the structure of gitk's `makewindow` (gitk/gitk 2374–2913): the
/// panes are gitk's, relocated. On systems with a unified titlebar the search
/// bar lives in the toolbar instead: the panes then run up under the titlebar
/// so the system can blur scrolled content beneath it (the scroll edge effect,
/// as in Music).
final class MainSplitView: NSView, NSSplitViewDelegate {
    let metrics: MainLayoutMetrics
    /// History list over the diff pane.
    let listDiffSplit = NSSplitView()
    let statusBar = StatusBar()
    private(set) var listPane: NSView = PlaceholderPane(name: "History list")
    private(set) var diffPane: NSView = PlaceholderPane(name: "Diff")
    private(set) var searchRow: NSView?
    private var appliedDefaultSizes = false
    /// Set once the default divider position is in place; until then
    /// NSSplitView's own initial distribution must not be remembered.
    private var defaultsInPlace = false

    /// The diff pane is shown only while a commit is selected; otherwise the
    /// history list takes the whole column.
    var showsDiffPane = false {
        didSet {
            guard showsDiffPane != oldValue else { return }
            diffPane.isHidden = !showsDiffPane
            listDiffSplit.adjustSubviews()
            if showsDiffPane { placeDiffDivider() }
        }
    }
    private var diffFraction: CGFloat = 0.5
    /// A diff height restored from the settings, applied when the divider is first placed.
    var initialDiffHeight: CGFloat?

    /// The diff pane's height below the history list (the saved value).
    var diffHeight: CGFloat? {
        let total = listDiffSplit.bounds.height - listDiffSplit.dividerThickness
        guard total > 0 else { return initialDiffHeight }
        return (diffFraction * total).rounded()
    }

    init(metrics: MainLayoutMetrics) {
        self.metrics = metrics
        super.init(frame: NSRect(origin: .zero, size: metrics.windowContentSize))
        autoresizingMask = [.width, .height]
        listDiffSplit.isVertical = false
        listDiffSplit.dividerStyle = .thin
        listDiffSplit.delegate = self
        listDiffSplit.addArrangedSubview(listPane)
        listDiffSplit.addArrangedSubview(diffPane)
        diffPane.isHidden = true
        addSubview(listDiffSplit)
        addSubview(statusBar)
        statusBar.onBusyChange = { [weak self] _ in
            guard let self, let window = self.window else { return }
            window.invalidateCursorRects(for: self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// The busy cursor (gitk's `nowbusy` sets the watch cursor). Views with their
    /// own cursor, such as the text views, keep theirs.
    override func resetCursorRects() {
        if statusBar.isBusy { addCursorRect(bounds, cursor: StatusBar.busyCursor) }
    }

    /// Puts the search bar in the first content row (no unified titlebar).
    func installSearchRow(_ view: NSView) {
        searchRow?.removeFromSuperview()
        let row = Chrome.bar(view)
        searchRow = row
        addSubview(row)
        needsLayout = true
    }

    func installList(_ view: NSView) {
        listDiffSplit.replaceSubview(listPane, with: view)
        listPane = view
    }

    func installDiff(_ view: NSView) {
        view.isHidden = diffPane.isHidden
        listDiffSplit.replaceSubview(diffPane, with: view)
        diffPane = view
    }

    /// Puts the list/diff divider back where it was (half height by default).
    private func placeDiffDivider() {
        let total = listDiffSplit.bounds.height - listDiffSplit.dividerThickness
        guard total > 0 else { return }
        if let height = initialDiffHeight {
            diffFraction = min(max(height / total, 0.05), 0.95)
            initialDiffHeight = nil
        }
        listDiffSplit.setPosition(floor(total * (1 - diffFraction)), ofDividerAt: 0)
    }

    override func layout() {
        var y: CGFloat = 0
        if let searchRow {
            searchRow.frame = NSRect(x: 0, y: y, width: bounds.width, height: metrics.searchBarHeight)
            y += metrics.searchBarHeight
        }
        let statusHeight = metrics.statusBarHeight
        statusBar.frame = NSRect(x: 0, y: bounds.height - statusHeight, width: bounds.width, height: statusHeight)
        listDiffSplit.frame = NSRect(x: 0, y: y, width: bounds.width, height: max(0, bounds.height - statusHeight - y))
        super.layout()
        guard !appliedDefaultSizes, listDiffSplit.bounds.height > 0 else { return }
        appliedDefaultSizes = true
        // NSSplitView distributes the initial sizes during this pass; put the
        // divider in place right after it.
        DispatchQueue.main.async { [self] in applyDefaultSizes() }
    }

    /// The list on top, the diff pane below at half the height.
    func applyDefaultSizes() {
        listDiffSplit.adjustSubviews()
        if showsDiffPane { placeDiffDivider() }
        layoutSubtreeIfNeeded()
        defaultsInPlace = true
    }

    // MARK: NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, metrics.listMinHeight)
    }

    /// Window resizes: the diff pane gives way before the history list when
    /// the height shrinks (D16 "Small windows").
    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        let d = splitView.dividerThickness
        let views = splitView.arrangedSubviews
        guard views.count == 2 else { splitView.adjustSubviews(); return }
        let (first, second) = (views[0], views[1])
        guard !second.isHidden else {
            first.frame = splitView.bounds
            return
        }
        let width = splitView.bounds.width
        let total = max(0, splitView.bounds.height - d)
        let oldTotal = max(1, oldSize.height - d)
        var top = first.frame.height
        if total >= oldTotal {
            top = (top / oldTotal * total).rounded()
        } else {
            // The list keeps its height while the diff pane shrinks to two
            // lines; only then does the list give way.
            let diffMin = min(metrics.linespc * 2, max(0, total - metrics.listMinHeight))
            top = min(top, total - diffMin)
        }
        top = min(max(0, top), total)
        first.frame = NSRect(x: 0, y: 0, width: width, height: top)
        second.frame = NSRect(x: 0, y: top + d, width: width, height: total - top)
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        if defaultsInPlace, !diffPane.isHidden, listDiffSplit.bounds.height > 0,
           NSApp.currentEvent?.type == .leftMouseDragged {
            diffFraction = diffPane.frame.height / listDiffSplit.bounds.height
        }
    }
}
