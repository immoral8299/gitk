// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Font-derived default sizes of the main window.
///
/// Port of gitk/gitk 2451–2458 (`geometry(topheight)` and friends, in terms of
/// `linespc` and `charspc`) and of `setcoords` (8803–8804): `linespc` is the
/// main font's line height and `charspc` the width of "m".
struct MainLayoutMetrics: Equatable {
    var linespc: CGFloat
    var charspc: CGFloat
    /// Height of a placeholder bar (the real bars arrive with tasks 10.x and 12.x).
    var barHeight: CGFloat = 28

    var topHeight: CGFloat { 15 * linespc }
    var topWidth: CGFloat { 80 * charspc }
    var botHeight: CGFloat { 15 * linespc }
    var botWidth: CGFloat { 50 * charspc }
    /// `pwsash0` and `pwsash1`: x positions of the two history column dividers.
    var sash0: CGFloat { 40 * charspc }
    var sash1: CGFloat { 60 * charspc }

    /// Height of the top half: the history area plus the Commit ID bar and find bar.
    var topPaneHeight: CGFloat { topHeight + 2 * barHeight }
    /// Height of the bottom half: two control rows plus the details text.
    var bottomPaneHeight: CGFloat { botHeight + 2 * barHeight }
    var dividerThickness: CGFloat { 1 }

    /// Content size of a window that shows the defaults without resizing.
    var windowContentSize: NSSize {
        NSSize(width: topWidth, height: topPaneHeight + dividerThickness + bottomPaneHeight)
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

/// A labelled box standing in for a pane whose real view comes in a later task.
final class PlaceholderPane: NSView {
    let name: String
    private let label: NSTextField

    init(name: String, font: NSFont) {
        self.name = name
        label = NSTextField(labelWithString: name)
        super.init(frame: .zero)
        label.font = font
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        wantsLayer = true
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateLayer() {
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    override var wantsUpdateLayer: Bool { true }
}

/// Lays out `rows` top to bottom by frame: fixed-height rows keep their height
/// and the rest share what remains. Frame layout keeps the split views' default
/// divider positions exact at the first layout pass.
final class ColumnView: NSView {
    struct Row {
        var view: NSView
        var height: CGFloat?
    }

    var rows: [Row] = [] {
        didSet {
            oldValue.forEach { $0.view.removeFromSuperview() }
            rows.forEach { addSubview($0.view) }
            needsLayout = true
        }
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let fixed = rows.reduce(CGFloat(0)) { $0 + ($1.height ?? 0) }
        let flexCount = rows.filter { $0.height == nil }.count
        let flex = flexCount > 0 ? max(0, bounds.height - fixed) / CGFloat(flexCount) : 0
        var y: CGFloat = 0
        for row in rows {
            let h = row.height ?? flex
            row.view.frame = NSRect(x: 0, y: y, width: bounds.width, height: h)
            y += h
        }
    }
}

/// The Patch/Tree switch row (gitk `.bright.mode`).
final class ModeBar: NSView {
    private let buttons: [NSButton]

    init(_ buttons: NSButton...) {
        self.buttons = buttons
        super.init(frame: .zero)
        buttons.forEach { addSubview($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        var x: CGFloat = 8
        for b in buttons {
            let size = b.fittingSize
            b.frame = NSRect(
                x: x, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
            x += size.width + 12
        }
    }
}

/// The main window's content: gitk's `.ctop` vertical paned window.
///
/// Mirrors the structure of `makewindow` (gitk/gitk 2374–2913, structure only):
/// - top: the history area (three columns in a horizontal split, `pwclist`),
///   the Commit ID bar and the find bar;
/// - bottom: a horizontal split (`pwbottom`) of the details pane (diff controls
///   on top) and the file list (Patch/Tree switch on top).
///
/// Every pane except the Patch/Tree switch is a placeholder for now.
final class MainSplitView: NSSplitView {
    let metrics: MainLayoutMetrics
    let historySplit = NSSplitView()
    let bottomSplit = NSSplitView()
    let patchButton: NSButton
    let treeButton: NSButton
    private let topArea = ColumnView()
    private let bottomLeft = ColumnView()
    private let bottomRight = ColumnView()
    private var appliedDefaultSizes = false

    init(metrics: MainLayoutMetrics, uiFont: NSFont) {
        self.metrics = metrics
        patchButton = NSButton(radioButtonWithTitle: L("Patch"), target: nil, action: nil)
        treeButton = NSButton(radioButtonWithTitle: L("Tree"), target: nil, action: nil)
        super.init(frame: NSRect(origin: .zero, size: metrics.windowContentSize))
        isVertical = false
        dividerStyle = .thin
        autoresizingMask = [.width, .height]
        buildTop(uiFont: uiFont)
        buildBottom(uiFont: uiFont)
        topArea.frame = NSRect(x: 0, y: 0, width: metrics.topWidth, height: metrics.topPaneHeight)
        bottomSplit.frame = NSRect(x: 0, y: metrics.topPaneHeight + 1, width: metrics.topWidth, height: metrics.bottomPaneHeight)
        addArrangedSubview(topArea)
        addArrangedSubview(bottomSplit)
        setHoldingPriority(.defaultLow, forSubviewAt: 0)
        setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        patchButton.state = .on
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func placeholder(_ name: String, _ font: NSFont) -> PlaceholderPane {
        PlaceholderPane(name: name, font: font)
    }

    /// Stacks `views` top to bottom inside `container`; a view with a height gets
    /// that height, the others share the rest.
    private func stack(_ views: [(NSView, CGFloat?)], in container: ColumnView) {
        container.rows = views.map { ColumnView.Row(view: $0.0, height: $0.1) }
    }

    private func buildTop(uiFont: NSFont) {
        historySplit.isVertical = true
        historySplit.dividerStyle = .thin
        historySplit.frame = NSRect(x: 0, y: 0, width: metrics.topWidth, height: metrics.topHeight)
        for (index, name) in ["History: graph and subject", "History: author", "History: date"].enumerated() {
            let pane = placeholder(name, uiFont)
            pane.frame = NSRect(x: CGFloat(index) * metrics.topWidth / 3, y: 0, width: metrics.topWidth / 3, height: metrics.topHeight)
            historySplit.addArrangedSubview(pane)
        }
        stack(
            [
                (historySplit, nil),
                (placeholder("Commit ID bar", uiFont), metrics.barHeight),
                (placeholder("Find bar", uiFont), metrics.barHeight),
            ], in: topArea)
    }

    private func buildBottom(uiFont: NSFont) {
        bottomSplit.isVertical = true
        bottomSplit.dividerStyle = .thin
        stack(
            [
                (placeholder("Search bar", uiFont), metrics.barHeight),
                (placeholder("Diff controls bar", uiFont), metrics.barHeight),
                (placeholder("Details text", uiFont), nil),
            ], in: bottomLeft)

        let modeBar = ModeBar(patchButton, treeButton)
        patchButton.target = self
        treeButton.target = self
        patchButton.action = #selector(modeChanged(_:))
        treeButton.action = #selector(modeChanged(_:))
        stack(
            [
                (modeBar, metrics.barHeight),
                (placeholder("File list", uiFont), nil),
            ], in: bottomRight)

        bottomLeft.frame = NSRect(x: 0, y: 0, width: metrics.botWidth, height: metrics.bottomPaneHeight)
        bottomRight.frame = NSRect(x: metrics.botWidth + 1, y: 0, width: metrics.topWidth - metrics.botWidth - 1, height: metrics.bottomPaneHeight)
        bottomSplit.addArrangedSubview(bottomLeft)
        bottomSplit.addArrangedSubview(bottomRight)
        bottomSplit.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        bottomSplit.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
    }

    /// Radio buttons in one superview group automatically only when they share a
    /// parent and action; this keeps them exclusive.
    @objc private func modeChanged(_ sender: NSButton) {
        patchButton.state = sender === patchButton ? .on : .off
        treeButton.state = sender === treeButton ? .on : .off
    }

    /// Applies gitk's default divider positions once there is room for them.
    /// Port of the `<Map>` bindings at gitk/gitk 2486–2489 and 2748–2755
    /// (`sashpos` from `topheight`, `botwidth`, `pwsash0`, `pwsash1`).
    override func layout() {
        super.layout()
        guard !appliedDefaultSizes, bounds.width > 0, bounds.height > 0 else { return }
        appliedDefaultSizes = true
        // NSSplitView distributes the initial sizes itself during this pass; set
        // gitk's positions right after it, on the next run-loop turn.
        DispatchQueue.main.async { [self] in applyDefaultSizes() }
    }

    /// Puts the dividers at absolute positions using NSSplitView's native sizing.
    static func place(_ split: NSSplitView, leading: [CGFloat]) {
        split.adjustSubviews()
        for (index, position) in leading.enumerated() {
            split.setPosition(position, ofDividerAt: index)
        }
    }

    func installHistory(_ view: NSView, commitBar: NSView, findBar: NSView? = nil) {
        // Only the top control strip gets the native backdrop (design D15); the
        // content panes and the remaining bars stay opaque.
        topArea.rows = [ColumnView.Row(view: view, height: nil),
                        ColumnView.Row(view: Chrome.bar(commitBar), height: metrics.barHeight),
                        ColumnView.Row(view: Chrome.bar(findBar ?? topArea.rows[2].view), height: metrics.barHeight)]
    }

    func installDetails(_ details: NSView, controls: NSView? = nil, search: NSView? = nil, files: NSView? = nil) {
        bottomLeft.rows = [ColumnView.Row(view: search ?? bottomLeft.rows[0].view, height: metrics.barHeight),
                           ColumnView.Row(view: controls ?? bottomLeft.rows[1].view, height: metrics.barHeight),
                           ColumnView.Row(view: details, height: nil)]
        if let files { bottomRight.rows = [bottomRight.rows[0], ColumnView.Row(view: files, height: nil)] }
    }

    func applyDefaultSizes() {
        Self.place(self, leading: [metrics.topPaneHeight])
        topArea.layoutSubtreeIfNeeded()
        bottomSplit.layoutSubtreeIfNeeded()
        Self.place(bottomSplit, leading: [metrics.botWidth])
        Self.place(historySplit, leading: [metrics.sash0, metrics.sash1])
        layoutSubtreeIfNeeded()
    }
}
