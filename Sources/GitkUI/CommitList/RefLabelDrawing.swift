// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
enum RefLabelDrawing {
    /// Branch and tag names are set in the monospaced system font, a point
    /// smaller than the list font so they sit inside the row. Label widths
    /// must be measured with this font too.
    static func font(for listFont: NSFont, bold: Bool = false) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: max(9, listFont.pointSize - 1), weight: bold ? .bold : .regular)
    }

    static func hitTest(_ x: CGFloat, labels: [GraphRowGeometry.RefLabel]) -> GraphRowGeometry.RefLabel? {
        labels.first { x >= $0.x && x < $0.x + $0.width }
    }

    /// Port of gitk proc `drawtags` (gitk/gitk 6753–6869).
    static func draw(_ labels: [GraphRowGeometry.RefLabel], height: CGFloat, font listFont: NSFont, settings: UISettings) {
        let font = Self.font(for: listFont)
        let delta = floor((height - 1) / 2)
        for label in labels {
            let isTag = label.kind == .tag || label.kind == .collapsedTags
            let x = CGFloat(label.x)
            let right = x + CGFloat(label.width) - height
            let path = NSBezierPath()
            if isTag {
                path.move(to: NSPoint(x: x, y: delta))
                path.line(to: NSPoint(x: x + delta, y: 0))
                path.line(to: NSPoint(x: right, y: 0))
                path.line(to: NSPoint(x: right, y: height - 1))
                path.line(to: NSPoint(x: x + delta, y: height - 1))
                path.line(to: NSPoint(x: x, y: height - delta - 1))
                path.close()
            } else { path.appendRect(NSRect(x: x, y: 0, width: max(1, right - x), height: height - 1)) }
            let kind: Palette.Ref = isTag ? .tag : (label.kind == .other ? .other : .head)
            Palette.refBackground(settings, kind).setFill()
            path.fill()
            Palette.refOutline(settings, kind).setStroke()
            path.lineWidth = 1
            path.stroke()
            if let prefix = label.remotePrefix {
                let width = (prefix as NSString).size(withAttributes: [.font: font]).width
                Palette.refBackground(settings, .remote).setFill()
                NSRect(x: x + 1, y: 1, width: min(width, max(0, right - x - 1)), height: max(0, height - 2)).fill()
            }
            let labelFont = Self.font(for: listFont, bold: label.isBold)
            let text: String
            if label.kind == .collapsedTags {
                // gitk draws these untranslated (gitk/gitk 6776–6781).
                text = label.tagCount == 1 ? "tag..." : "\(label.tagCount) tags..."
            } else { text = label.text }
            (text as NSString).draw(at: NSPoint(x: x + (isTag ? delta : floor(delta / 2)), y: (height - labelFont.ascender + labelFont.descender) / 2 - 1),
                withAttributes: [.font: labelFont, .foregroundColor: Palette.refForeground(settings, kind)])
        }
    }
}
