// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class GraphCellView: NSTableCellView {
    var geometry: GraphRowGeometry? { didSet { needsDisplay = true } }
    var attributedHeadline = NSAttributedString() { didSet { needsDisplay = true } }
    var font = NSFont.systemFont(ofSize: 12) { didSet { needsDisplay = true } }
    var settings = UISettings() { didSet { needsDisplay = true } }
    /// Horizontal scroll of the ref labels and headline. The graph lanes stay
    /// put, so dots and lines remain visible while long ref names and messages
    /// scroll under the text region.
    var contentOffset: CGFloat = 0 { didSet { needsDisplay = true } }
    var onTagClick: ((GraphRowGeometry.RefLabel) -> Void)?
    var onArrowClick: ((Int) -> Void)?
    var onLineClick: ((CommitIndex) -> Void)?
    /// The hover tooltip for a line: the parent's subject (gitk `linehover`).
    var lineTooltip: ((CommitIndex) -> String?)?
    var onHeadMenu: ((GraphRowGeometry.RefLabel, NSEvent) -> NSMenu?)?

    override var isFlipped: Bool { true }

    // Views do not clip to their bounds by default since macOS 14; long ref
    // labels must not spill into the Author and Date columns.
    override var clipsToBounds: Bool {
        get { true }
        set {}
    }
    private var originX: CGFloat { floor(3 + 0.5 * bounds.height) }

    /// The x where the scrolling content (ref labels and headline) begins: the
    /// first label's left edge, or the headline's x when the row has no labels.
    var graphContentStart: CGFloat {
        guard let geometry else { return 0 }
        return geometry.labels.first.map { CGFloat($0.x) } ?? CGFloat(geometry.textX)
    }

    /// The part of the cell where labels and text may draw. The graph lanes to
    /// its left stay fixed and are never painted over.
    var contentClipRect: NSRect {
        NSRect(x: graphContentStart, y: 0, width: max(0, bounds.width - graphContentStart), height: bounds.height)
    }

    /// The part of the cell where the graph lanes, arrows and dot may draw.
    /// When the graph is wider than the width limit the text starts at the
    /// limit, and the lanes past it are cut off rather than drawn through the
    /// text. Ends 1pt short so a lane centred on the limit does not show.
    var graphClipRect: NSRect {
        NSRect(x: 0, y: 0, width: max(0, graphContentStart - 1), height: bounds.height)
    }

    /// The headline's draw rect. It spans the whole attributed string rather
    /// than stopping at the column edge, so horizontal scrolling reveals the
    /// rest of a long message instead of blank space.
    var textDrawRect: NSRect {
        guard geometry != nil else { return .zero }
        let textHeight = font.ascender - font.descender
        let width = attributedHeadline.size().width + 2
        return NSRect(x: CGFloat(geometry?.textX ?? 0) - contentOffset,
                      y: (bounds.height - textHeight) / 2 - 1,
                      width: max(0, width), height: bounds.height)
    }

    private func point(_ value: GraphRowGeometry.Point) -> NSPoint {
        NSPoint(x: originX + CGFloat(value.column) * bounds.height, y: CGFloat(value.y) * bounds.height)
    }

    private func lineColor(_ index: Int) -> NSColor {
        Palette.graphLine(settings, index)
    }

    /// Port of gitk procs `drawlineseg`, `drawparentlinks`, `drawcmittext`.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let geometry else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: graphClipRect).addClip()
        for segment in geometry.segments {
            let path = NSBezierPath()
            path.move(to: point(segment.from))
            path.line(to: point(segment.to))
            path.lineWidth = segment.thick ? 3 : 2
            lineColor(segment.colorIndex).setStroke()
            path.stroke()
        }
        for arrow in geometry.arrows {
            let x = originX + CGFloat(arrow.column) * bounds.height
            let y = bounds.midY
            let direction: CGFloat = arrow.direction == .up ? 1 : -1
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x - 3, y: y + direction * 5))
            path.line(to: NSPoint(x: x, y: y))
            path.line(to: NSPoint(x: x + 3, y: y + direction * 5))
            path.lineWidth = 2.5
            lineColor(arrow.colorIndex).setStroke()
            path.stroke()
        }
        let x = originX + CGFloat(geometry.dotColumn) * bounds.height
        let radius = floor(bounds.height / 3)
        let dotRect = NSRect(x: x - radius, y: bounds.midY - radius, width: radius * 2 - 1, height: radius * 2 - 1)
        let path: NSBezierPath
        if geometry.dotStyle == .left || geometry.dotStyle == .right {
            path = NSBezierPath()
            let left = geometry.dotStyle == .left
            path.move(to: NSPoint(x: left ? dotRect.minX : dotRect.maxX, y: bounds.midY))
            path.line(to: NSPoint(x: left ? dotRect.maxX : dotRect.minX, y: dotRect.minY))
            path.line(to: NSPoint(x: left ? dotRect.maxX : dotRect.minX, y: dotRect.maxY))
            path.close()
        } else { path = NSBezierPath(ovalIn: dotRect) }
        let fill: Palette.Dot
        switch geometry.dotStyle {
        case .mainHead: fill = .mainHead
        case .unstaged: fill = .unstaged
        case .staged: fill = .staged
        case .boundary: fill = .boundary
        case .negative: fill = .negative
        default: fill = .normal
        }
        Palette.dot(settings, fill).setFill()
        path.fill()
        Palette.dotOutline(settings).setStroke()
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // Labels and headline scroll sideways, clipped to the right of the
        // graph so they never cover it.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: contentClipRect).addClip()
        RefLabelDrawing.draw(geometry.labels, height: bounds.height, font: font,
                             settings: settings, offset: contentOffset)
        if geometry.hasNotes {
            let side = max(3, radius * 2 - 1)
            let rect = NSRect(x: CGFloat(geometry.textX) - contentOffset - bounds.height,
                              y: bounds.midY - radius, width: side, height: side)
            Palette.notesMarker(settings).setFill()
            rect.fill()
            Palette.dotOutline(settings).setStroke()
            NSBezierPath(rect: rect).stroke()
        }
        let text = NSMutableAttributedString(attributedString: attributedHeadline)
        if text.length > 0 {
            // One line, clipped at the scroll offset rather than wrapped into
            // the next row.
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byClipping
            text.addAttribute(.paragraphStyle, value: paragraph,
                              range: NSRange(location: 0, length: text.length))
        }
        if backgroundStyle == .emphasized, text.length > 0 {
            text.addAttribute(.foregroundColor, value: NSColor.alternateSelectedControlTextColor, range: NSRange(location: 0, length: text.length))
        }
        let textRect = textDrawRect
        MatchBoxes.draw(text, at: textRect.origin, height: font.ascender - font.descender)
        text.draw(in: textRect)
        NSGraphicsContext.restoreGraphicsState()
        setAccessibilityLabel(attributedHeadline.string)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let geometry, let label = RefLabelDrawing.tagLabel(at: point.x + contentOffset, labels: geometry.labels),
           let onTagClick {
            onTagClick(label)
            return
        }
        if let geometry, let hit = LineHitTest.hit(in: geometry, x: Double(point.x), y: Double(point.y),
                                                   rowHeight: Double(bounds.height)) {
            switch hit {
            case .arrow(let arrow): if let onArrowClick { onArrowClick(arrow.targetRow); return }
            case .line(let id): if let onLineClick { onLineClick(id); return }
            }
        }
        super.mouseDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let geometry, case .line(let id)? = LineHitTest.hit(in: geometry, x: Double(point.x), y: Double(point.y),
                                                               rowHeight: Double(bounds.height)) {
            toolTip = lineTooltip?(id)
        } else {
            toolTip = nil
        }
    }

    override func mouseExited(with event: NSEvent) { toolTip = nil }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let geometry, let label = RefLabelDrawing.headLabel(at: point.x + contentOffset, labels: geometry.labels),
           let menu = onHeadMenu?(label, event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        super.rightMouseDown(with: event)
    }
}

/// Rounded match boxes behind the glyphs (design D17), replacing gitk's bold
/// rows. A range carries the box colour under `key`; the boxes are measured from
/// the text itself, so they follow it when a column is resized.
enum MatchBoxes {
    static let key = NSAttributedString.Key("gitk.matchBox")

    /// Draws the boxes for `text` laid out on one line starting at `origin`
    /// (the top-left of the line box), `height` tall.
    static func draw(_ text: NSAttributedString, at origin: NSPoint, height: CGFloat) {
        guard text.length > 0 else { return }
        text.enumerateAttribute(key, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let colour = value as? NSColor else { return }
            let before = text.attributedSubstring(from: NSRange(location: 0, length: range.location)).size().width
            let width = text.attributedSubstring(from: range).size().width
            let box = NSRect(x: origin.x + before, y: origin.y, width: width, height: height)
                .insetBy(dx: -Palette.matchBoxOutset, dy: 0)
            colour.setFill()
            NSBezierPath(roundedRect: box, xRadius: Palette.cornerRadius, yRadius: Palette.cornerRadius).fill()
        }
    }
}

/// A list cell label that draws `MatchBoxes` behind its text.
@MainActor
final class MatchLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ dirtyRect: NSRect) {
        if let cell {
            let rect = cell.titleRect(forBounds: bounds)
            let size = attributedStringValue.size()
            MatchBoxes.draw(attributedStringValue,
                            at: NSPoint(x: rect.minX, y: rect.minY + (rect.height - size.height) / 2), height: size.height)
        }
        super.draw(dirtyRect)
    }
}
