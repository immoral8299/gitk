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
    var onTagClick: ((GraphRowGeometry.RefLabel) -> Void)?
    var onArrowClick: ((Int) -> Void)?
    var onLineClick: ((CommitIndex) -> Void)?
    var onHeadMenu: ((GraphRowGeometry.RefLabel, NSEvent) -> NSMenu?)?

    override var isFlipped: Bool { true }

    // Views do not clip to their bounds by default since macOS 14; long ref
    // labels must not spill into the Author and Date columns.
    override var clipsToBounds: Bool {
        get { true }
        set {}
    }
    private var originX: CGFloat { floor(3 + 0.5 * bounds.height) }

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
        for segment in geometry.segments {
            let path = NSBezierPath()
            path.move(to: point(segment.from))
            path.line(to: point(segment.to))
            path.lineWidth = segment.thick ? 2 : 1
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
            path.lineWidth = 1.5
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
        RefLabelDrawing.draw(geometry.labels, height: bounds.height, font: font, settings: settings)
        if geometry.hasNotes {
            let side = max(3, radius * 2 - 1)
            let rect = NSRect(x: CGFloat(geometry.textX) - bounds.height, y: bounds.midY - radius, width: side, height: side)
            Palette.notesMarker(settings).setFill()
            rect.fill()
            Palette.dotOutline(settings).setStroke()
            NSBezierPath(rect: rect).stroke()
        }
        let text = NSMutableAttributedString(attributedString: attributedHeadline)
        if backgroundStyle == .emphasized, text.length > 0 {
            text.addAttribute(.foregroundColor, value: NSColor.selectedTextColor, range: NSRange(location: 0, length: text.length))
        }
        let textHeight = font.ascender - font.descender
        text.draw(in: NSRect(x: CGFloat(geometry.textX), y: (bounds.height - textHeight) / 2 - 1,
            width: max(0, bounds.width - CGFloat(geometry.textX)), height: bounds.height))
        setAccessibilityLabel(attributedHeadline.string)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let geometry, let label = RefLabelDrawing.hitTest(point.x, labels: geometry.labels),
           label.kind == .tag || label.kind == .collapsedTags, let onTagClick {
            onTagClick(label)
            return
        }
        if let geometry, let arrow = geometry.arrows.first(where: {
            abs(originX + CGFloat($0.column) * bounds.height - point.x) < 6 && abs(bounds.midY - point.y) < 7
        }), let onArrowClick {
            onArrowClick(arrow.targetRow)
            return
        }
        if let geometry, let segment = geometry.segments.first(where: {
            distance(point, from: self.point($0.from), to: self.point($0.to)) < 3
        }), point.x < CGFloat(geometry.textX),
           hypot(point.x - originX - CGFloat(geometry.dotColumn) * bounds.height, point.y - bounds.midY) > bounds.height / 3 + 2,
           let onLineClick {
            onLineClick(segment.id)
            return
        }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let geometry, let label = RefLabelDrawing.hitTest(point.x, labels: geometry.labels),
           label.kind == .head || label.kind == .remote,
           let menu = onHeadMenu?(label, event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        super.rightMouseDown(with: event)
    }

    private func distance(_ p: NSPoint, from a: NSPoint, to b: NSPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let t = length > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
}
