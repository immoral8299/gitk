// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// The slim status strip along the bottom of the window (design D16): the row
/// counter that gitk shows beside the Commit ID field, then the busy status and
/// its progress bar.
///
/// Busy state follows gitk's `nowbusy`/`notbusy` (gitk/gitk 6913–6943): while
/// the history is read or a search runs, the status text names the operation
/// and the window shows the busy cursor (`onBusyChange`).
@MainActor
final class StatusBar: NSView {
    let rowLabel = NSTextField(labelWithString: "")
    let label = NSTextField(labelWithString: "")
    let progress = NSProgressIndicator()
    private let stack = NSStackView()
    private var reading = false
    private var searching = false
    /// The reading progress as a fraction, or nil while the total is unknown.
    private var fraction: Double?
    private var reportedBusy = false

    /// True while a read or a search is running.
    var isBusy: Bool { reading || searching }
    /// Called when `isBusy` changes, so the window can show or drop the busy cursor.
    var onBusyChange: ((Bool) -> Void)?

    /// The native macOS busy cursor: the spinning disc with the arrow. AppKit
    /// exposes no public `NSCursor` for it, so this asks for the system's
    /// `busyButClickableCursor` and falls back to gitk's hourglass on systems
    /// that do not have it.
    static let busyCursor: NSCursor = {
        let selector = NSSelectorFromString("busyButClickableCursor")
        if NSCursor.responds(to: selector),
           let cursor = NSCursor.perform(selector)?.takeUnretainedValue() as? NSCursor {
            return cursor
        }
        return hourglassCursor
    }()

    /// gitk's watch cursor: an hourglass, centred on its hot spot.
    private static let hourglassCursor: NSCursor = {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else { return .arrow }
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.black.set()
            rect.fill(using: .sourceIn)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: image.size.width / 2, y: image.size.height / 2))
    }()

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
        progress.minValue = 0
        progress.maxValue = 1
        progress.isHidden = true
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

    /// Shows "Searching" with an indeterminate bar, or clears it (gitk `nowbusy finding`).
    func setSearching(_ on: Bool = true) {
        searching = on
        update()
    }

    /// Shows "Reading" while the history loads. With `total` known the bar fills
    /// to `count / total`, capped below full until the load finishes; otherwise
    /// it runs indeterminately. Turning reading off clears the text and the bar.
    func setReading(_ on: Bool, count: Int = 0, total: Int? = nil) {
        reading = on
        if on, let total, total > 0 {
            fraction = min(Double(count) / Double(total), 0.99)
        } else {
            fraction = nil
        }
        update()
        progress.setAccessibilityValue(on ? String(count) : "")
    }

    private func update() {
        label.stringValue = searching ? L("Searching") : reading ? L("Reading") : ""
        let determinate = reading && !searching && fraction != nil
        progress.isIndeterminate = !determinate
        if determinate, let fraction { progress.doubleValue = fraction }
        progress.isHidden = !isBusy
        if isBusy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        if isBusy != reportedBusy {
            reportedBusy = isBusy
            onBusyChange?(isBusy)
        }
    }
}
