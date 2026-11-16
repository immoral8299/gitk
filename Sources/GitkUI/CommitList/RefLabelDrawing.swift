// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
enum RefLabelDrawing {
    /// Smallest point size for label text.
    private static let minimumFontSize: CGFloat = 9
    /// How many points smaller than the list font the label text is.
    private static let fontSizeReduction: CGFloat = 1
    /// Space between a label and the row's top and bottom edges.
    private static let rowInset: CGFloat = 1
    /// Narrowest a head label's rectangle can get.
    private static let minimumLabelWidth: CGFloat = 1
    /// Vertical adjustment applied to the centred text position.
    private static let textOffset: CGFloat = 1
    /// Extra width after a tag's name, so the text clears the rounded corners.
    /// Passed to `addingRefLabels(tagPadding:)` so hit-testing matches.
    static let tagRightPadding: CGFloat = 3

    /// Branch and tag names are set in the monospaced system font, a point
    /// smaller than the list font so they sit inside the row. Label widths
    /// must be measured with this font too.
    static func font(for listFont: NSFont, bold: Bool = false) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: max(minimumFontSize, listFont.pointSize - fontSizeReduction),
                                    weight: bold ? .bold : .regular)
    }

    static func hitTest(_ x: CGFloat, labels: [GraphRowGeometry.RefLabel]) -> GraphRowGeometry.RefLabel? {
        labels.first { x >= $0.x && x < $0.x + $0.width }
    }

    /// Primary click shows a tag (gitk binds `<1>` to tag labels only,
    /// gitk/gitk 6862); secondary click opens the head menu for head and
    /// remote labels (gitk/gitk 6864).
    static func tagLabel(at x: CGFloat, labels: [GraphRowGeometry.RefLabel]) -> GraphRowGeometry.RefLabel? {
        hitTest(x, labels: labels).flatMap { $0.kind == .tag || $0.kind == .collapsedTags ? $0 : nil }
    }

    static func headLabel(at x: CGFloat, labels: [GraphRowGeometry.RefLabel]) -> GraphRowGeometry.RefLabel? {
        hitTest(x, labels: labels).flatMap { $0.kind == .head || $0.kind == .remote ? $0 : nil }
    }

    /// Port of gitk proc `drawtags` (gitk/gitk 6753–6869). `offset` is the
    /// first column's horizontal scroll, applied to every label.
    static func draw(_ labels: [GraphRowGeometry.RefLabel], height: CGFloat, font listFont: NSFont,
                     settings: UISettings, offset: CGFloat = 0) {
        let top = rowInset
        let bottom = height - rowInset
        let delta = floor((bottom - top) / 2)
        for label in labels {
            let isTag = label.kind == .tag || label.kind == .collapsedTags
            let x = CGFloat(label.x) - offset
            let right = x + CGFloat(label.width) - height / 2
            let path: NSBezierPath
            if isTag {
                // Pointed on the left as in gitk, rounded on the right.
                path = NSBezierPath()
                path.move(to: NSPoint(x: x, y: top + delta))
                path.line(to: NSPoint(x: x + delta, y: top))
                path.appendArc(from: NSPoint(x: right, y: top), to: NSPoint(x: right, y: bottom), radius: Palette.cornerRadius)
                path.appendArc(from: NSPoint(x: right, y: bottom), to: NSPoint(x: x + delta, y: bottom), radius: Palette.cornerRadius)
                path.line(to: NSPoint(x: x + delta, y: bottom))
                path.line(to: NSPoint(x: x, y: bottom - delta))
                path.close()
            } else {
                path = NSBezierPath(roundedRect: NSRect(x: x, y: top, width: max(minimumLabelWidth, right - x), height: bottom - top),
                                    xRadius: Palette.cornerRadius, yRadius: Palette.cornerRadius)
            }
            let kind: Palette.Ref = isTag ? .tag : (label.kind == .other ? .other : .head)
            let labelFont = Self.font(for: listFont, bold: label.isBold)
            let textX = x + (isTag ? delta : floor(delta / 2))
            Palette.refBackground(settings, kind).setFill()
            path.fill()
            if let prefix = label.remotePrefix {
                // The prefix colour covers the label's left end up to where the
                // branch name starts, clipped to the label's shape.
                let prefixEnd = textX + (prefix as NSString).size(withAttributes: [.font: labelFont]).width
                NSGraphicsContext.saveGraphicsState()
                path.addClip()
                Palette.refBackground(settings, .remote).setFill()
                NSRect(x: x, y: top, width: max(0, min(prefixEnd, right) - x), height: bottom - top).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            let text: String
            if label.kind == .collapsedTags {
                // gitk draws these untranslated (gitk/gitk 6776–6781).
                text = label.tagCount == 1 ? "tag..." : "\(label.tagCount) tags..."
            } else { text = label.text }
            (text as NSString).draw(at: NSPoint(x: textX, y: (height - labelFont.ascender + labelFont.descender) / 2 - textOffset),
                withAttributes: [.font: labelFont, .foregroundColor: Palette.refForeground(settings, kind)])
        }
    }
}
