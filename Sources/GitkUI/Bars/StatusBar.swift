// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// The slim status strip along the bottom of the window (design D16): the row
/// counter that gitk shows beside the Commit ID field, then the busy status and
/// its progress bar.
@MainActor
final class StatusBar: NSView {
    let rowLabel = NSTextField(labelWithString: "")
    let label = NSTextField(labelWithString: "")
    let progress = NSProgressIndicator()
    private let stack = NSStackView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 22))
        for field in [rowLabel, label] {
            field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            field.textColor = .secondaryLabelColor
        }
        rowLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        progress.style = .bar
        progress.controlSize = .small
        progress.isIndeterminate = true
        progress.isDisplayedWhenStopped = false
        progress.widthAnchor.constraint(equalToConstant: 120).isActive = true
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        for view in [rowLabel, spacer, label, progress] { stack.addArrangedSubview(view) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setRow(0, of: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    /// "Row N / M" (gitk 2582–2590: the `Row` label and `rowtext`).
    func setRow(_ row: Int, of count: Int) {
        rowLabel.stringValue = "\(L("Row")) \(row) / \(count)"
    }

    func refresh(session: ViewSession) {
        let row = session.selection.selectedID.flatMap { session.row(of: $0) }.map { $0 + 1 } ?? 0
        setRow(row, of: session.rowCount)
    }

    func setSearching() {
        label.stringValue = L("Searching")
        progress.startAnimation(nil)
    }

    func setReading(_ reading: Bool, count: Int = 0) {
        label.stringValue = reading ? L("Reading") : ""
        if reading { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        progress.setAccessibilityValue(reading ? String(count) : "")
    }
}
