// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit

/// The right-hand details sidebar (design D16). For now it is the container:
/// a header row with the close button and a body slot. Task 11.1 fills the body
/// with the identity header, metadata rows, message and Changed Files.
@MainActor
final class DetailsSidebar: NSView {
    let closeButton: NSButton
    private let header = NSView()
    private(set) var body: NSView
    var onClose: (() -> Void)?

    static let headerHeight: CGFloat = 30

    init() {
        let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)
        closeButton = image.map { NSButton(image: $0, target: nil, action: nil) }
            ?? NSButton(title: "×", target: nil, action: nil)
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.isBordered = false
        let empty = NSTextField(labelWithString: "")
        empty.textColor = .secondaryLabelColor
        body = empty
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        closeButton.target = self
        closeButton.action = #selector(close)
        header.addSubview(closeButton)
        addSubview(header)
        addSubview(body)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    /// Replaces the body (the sidebar content below the header).
    func setBody(_ view: NSView) {
        body.removeFromSuperview()
        body = view
        addSubview(view)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = Self.headerHeight
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: h)
        let size = closeButton.fittingSize
        closeButton.frame = NSRect(x: bounds.width - size.width - 8, y: (h - size.height) / 2,
                                   width: size.width, height: size.height)
        body.frame = NSRect(x: 0, y: h, width: bounds.width, height: max(0, bounds.height - h))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
    }

    @objc private func close() { onClose?() }
}
