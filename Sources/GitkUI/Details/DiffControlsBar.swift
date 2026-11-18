// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// The controls above the diff pane (gitk's `.bleft.top` and `.bleft.mid`,
/// gitk/gitk 2606–2640). Left to right: the pane's search field, the Diff
/// options popover button and Diff / Old version / New version. The popover
/// holds Lines of context, Ignore space change and the Line diff / Markup
/// words / Color words choice, like the commit search's Advanced popover.
@MainActor
final class DiffControlsBar: NSView, NSPopoverDelegate {
    let mode = NSSegmentedControl(labels: [L("Diff"), L("Old version"), L("New version")],
                                  trackingMode: .selectOne, target: nil, action: nil)
    let options: NSButton
    let context = NSTextField()
    let contextStepper = NSStepper()
    let ignoreSpace = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let wordDiff = NSPopUpButton()
    private let stack = NSStackView()
    private let popover = NSPopover()
    /// The context the options button compares against for its marker.
    private let defaultContext: Int

    /// Diff/Old/New changed: re-render from the model (gitk `changediffdisp`).
    var onModeChange: ((DiffDisplayMode) -> Void)?
    /// Context, whitespace or word-diff changed: re-fetch (gitk `diffcontextchange`, `changeignorespace`, `changeworddiff`).
    var onOptionsChange: ((Int, Bool, WordDiffMode) -> Void)?

    static let height: CGFloat = 30

    init(context lines: Int) {
        defaultContext = lines
        if let image = OptionsIcon.image(changed: false, accessibilityDescription: L("Diff options")) {
            options = NSButton(image: image, target: nil, action: nil)
        } else {
            options = NSButton(title: L("Diff options"), target: nil, action: nil)
        }
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: Self.height))
        mode.selectedSegment = 0
        mode.controlSize = .small
        mode.target = self
        mode.action = #selector(modeChanged)
        mode.setContentCompressionResistancePriority(.required, for: .horizontal)

        options.bezelStyle = .accessoryBarAction
        options.setButtonType(.pushOnPushOff)
        options.controlSize = .small
        options.toolTip = L("Diff options")
        options.target = self
        options.action = #selector(toggleOptions)

        context.integerValue = lines
        context.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        context.alignment = .right
        context.target = self
        context.action = #selector(contextTyped)
        context.widthAnchor.constraint(equalToConstant: 44).isActive = true
        contextStepper.minValue = 0
        contextStepper.maxValue = 1000
        contextStepper.integerValue = lines
        contextStepper.target = self
        contextStepper.action = #selector(contextStepped)
        ignoreSpace.target = self
        ignoreSpace.action = #selector(optionsChanged)
        wordDiff.addItems(withTitles: [L("Line diff"), L("Markup words"), L("Color words")])
        wordDiff.target = self
        wordDiff.action = #selector(optionsChanged)

        for view in [options, mode] { stack.addArrangedSubview(view) }
        stack.spacing = 6
        stack.setCustomSpacing(10, after: options)
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        buildPopover()
    }

    /// Puts the pane's search field (gitk's `$sstring`) first; it takes the spare width.
    func addSearchField(_ field: NSSearchField, counter: NSTextField) {
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        stack.insertArrangedSubview(field, at: 0)
        stack.insertArrangedSubview(counter, at: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildPopover() {
        let contextRow = NSStackView(views: [context, contextStepper])
        contextRow.spacing = 2
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: L("Lines of context")), contextRow],
            [NSTextField(labelWithString: L("Ignore space change")), ignoreSpace],
            [NSTextField(labelWithString: L("Diff mode")), wordDiff],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
        let controller = NSViewController()
        controller.view = content
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
    }

    @objc func toggleOptions() {
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: options.bounds, of: options, preferredEdge: .maxY)
        options.state = .on
    }

    /// Opens the options popover if it is closed (snapshots).
    func showOptions() { if !popover.isShown { toggleOptions() } }

    func popoverDidClose(_ notification: Notification) { options.state = .off }

    /// Tints the options button while any option differs from its default.
    func updateOptionsMarker() {
        let changed = context.integerValue != defaultContext || ignoreSpace.state == .on || wordDiff.indexOfSelectedItem > 0
        if let image = OptionsIcon.image(changed: changed, accessibilityDescription: L("Diff options")) { options.image = image }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    var displayMode: DiffDisplayMode { [.diff, .old, .new][max(0, mode.selectedSegment)] }
    var wordDiffMode: WordDiffMode { [.line, .markup, .color][max(0, wordDiff.indexOfSelectedItem)] }

    @objc private func modeChanged() { onModeChange?(displayMode) }

    @objc private func contextTyped() {
        let value = max(0, context.integerValue)
        context.integerValue = value
        contextStepper.integerValue = value
        optionsChanged()
    }

    @objc private func contextStepped() {
        context.integerValue = contextStepper.integerValue
        optionsChanged()
    }

    @objc private func optionsChanged() {
        updateOptionsMarker()
        onOptionsChange?(context.integerValue, ignoreSpace.state == .on, wordDiffMode)
    }
}
