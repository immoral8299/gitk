// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// The controls above the diff pane (gitk's `.bleft.mid`, gitk/gitk 2614–2640):
/// Diff / Old version / New version, Lines of context, Ignore space change and
/// the Line diff / Markup words / Color words choice.
@MainActor
final class DiffControlsBar: NSView {
    let mode = NSSegmentedControl(labels: [L("Diff"), L("Old version"), L("New version")],
                                  trackingMode: .selectOne, target: nil, action: nil)
    let context = NSTextField()
    let contextStepper = NSStepper()
    let ignoreSpace = NSButton(checkboxWithTitle: L("Ignore space change"), target: nil, action: nil)
    let wordDiff = NSPopUpButton()
    private let stack = NSStackView()

    /// Diff/Old/New changed: re-render from the model (gitk `changediffdisp`).
    var onModeChange: ((DiffDisplayMode) -> Void)?
    /// Context, whitespace or word-diff changed: re-fetch (gitk `diffcontextchange`, `changeignorespace`, `changeworddiff`).
    var onOptionsChange: ((Int, Bool, WordDiffMode) -> Void)?

    static let height: CGFloat = 30

    init(context lines: Int) {
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: Self.height))
        mode.selectedSegment = 0
        mode.controlSize = .small
        mode.target = self
        mode.action = #selector(modeChanged)

        context.integerValue = lines
        context.controlSize = .small
        context.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        context.alignment = .right
        context.target = self
        context.action = #selector(contextTyped)
        context.widthAnchor.constraint(equalToConstant: 34).isActive = true
        contextStepper.controlSize = .small
        contextStepper.minValue = 0
        contextStepper.maxValue = 1000
        contextStepper.integerValue = lines
        contextStepper.target = self
        contextStepper.action = #selector(contextStepped)

        ignoreSpace.controlSize = .small
        ignoreSpace.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        ignoreSpace.target = self
        ignoreSpace.action = #selector(optionsChanged)

        wordDiff.controlSize = .small
        wordDiff.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        wordDiff.addItems(withTitles: [L("Line diff"), L("Markup words"), L("Color words")])
        wordDiff.target = self
        wordDiff.action = #selector(optionsChanged)

        let contextLabel = NSTextField(labelWithString: L("Lines of context") + ":")
        contextLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        contextLabel.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        for view in [mode, spacer, contextLabel, context, contextStepper, ignoreSpace, wordDiff] { stack.addArrangedSubview(view) }
        stack.setCustomSpacing(2, after: context)
        stack.setCustomSpacing(12, after: contextStepper)
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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
        onOptionsChange?(context.integerValue, ignoreSpace.state == .on, wordDiffMode)
    }
}
