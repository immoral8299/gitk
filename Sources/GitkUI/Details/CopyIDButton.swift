// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit

/// The commit ID in the details sidebar, drawn on a dim rounded fill so it
/// reads as clickable. It brightens while the pointer is over it and shows a
/// "Copy" hint; after a click, `showCopied()` changes the hint to "Copied!"
/// for half a second.
@MainActor
final class CopyIDButton: NSButton {
    private static let confirmationDuration: Duration = .milliseconds(500)
    /// Space between the fill's edge and the ID.
    private static let padding = NSSize(width: 6, height: 2)

    private let hint = HintBubble()
    private var hoverArea: NSTrackingArea?
    private var confirmation: Task<Void, Never>?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    init() {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        setAccessibilityHelp(L("Copy"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Replaces the hint with "Copied!", then hides it.
    func showCopied() {
        confirmation?.cancel()
        hint.show(L("Copied!"), above: self)
        confirmation = Task { [weak self] in
            try? await Task.sleep(for: Self.confirmationDuration)
            guard !Task.isCancelled else { return }
            self?.hint.hide()
        }
    }

    override var title: String { didSet { invalidateIntrinsicContentSize() } }

    override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: titleAttributes)
        return NSSize(width: ceil(text.width) + 2 * Self.padding.width,
                      height: ceil(text.height) + 2 * Self.padding.height)
    }

    private var titleAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        return [.font: font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: isHovered ? NSColor.labelColor : NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph]
    }

    /// Drawn here rather than by the cell, so the fill and the padded,
    /// middle-truncated ID stay in step with `intrinsicContentSize`.
    override func draw(_ dirtyRect: NSRect) {
        let fill = isHighlighted ? Palette.inlineControlFillPressed
            : isHovered ? Palette.inlineControlFillHovered : Palette.inlineControlFill
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Palette.cornerRadius, yRadius: Palette.cornerRadius).fill()
        (title as NSString).draw(with: bounds.insetBy(dx: Self.padding.width, dy: Self.padding.height),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                 attributes: titleAttributes)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        guard confirmation == nil else { return }
        hint.show(L("Copy"), above: self)
    }

    override func mouseExited(with event: NSEvent) { endHover() }
    override func viewDidHide() { super.viewDidHide(); endHover() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { super.viewWillMove(toWindow: newWindow); endHover() }

    private func endHover() {
        isHovered = false
        confirmation?.cancel()
        confirmation = nil
        hint.hide()
    }
}

/// A small tooltip-style label in a borderless child window, shown and hidden
/// immediately (AppKit's `toolTip` appears after a delay and can't be updated
/// while visible).
@MainActor
private final class HintBubble {
    private static let padding = NSSize(width: 6, height: 2)
    private static let gap: CGFloat = 4
    private static let cornerRadius: CGFloat = 5

    private let label = NSTextField(labelWithString: "")
    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        let background = NSVisualEffectView()
        background.material = .toolTip
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.masksToBounds = true
        label.font = .toolTipsFont(ofSize: 0)
        label.textColor = .labelColor
        background.addSubview(label)
        panel.contentView = background
        return panel
    }()

    /// Shows `text` centred just above `view`.
    func show(_ text: String, above view: NSView) {
        guard let window = view.window else { return }
        label.stringValue = text
        label.sizeToFit()
        let textSize = NSSize(width: ceil(label.frame.width), height: ceil(label.frame.height))
        let size = NSSize(width: textSize.width + 2 * Self.padding.width,
                          height: textSize.height + 2 * Self.padding.height)
        let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        let origin = NSPoint(x: round(anchor.midX - size.width / 2), y: anchor.maxY + Self.gap)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        label.frame = NSRect(origin: NSPoint(x: Self.padding.width, y: Self.padding.height), size: textSize)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}
