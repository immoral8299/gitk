// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

/// Resizing the diff pane keeps its horizontal and vertical scroll position.
@MainActor
@Suite struct DiffScrollTests {
    @Test func resizeKeepsScrollOrigin() throws {
        let pane = DiffPane(settings: Settings(), hashLength: 40)
        pane.view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        pane.view.layoutSubtreeIfNeeded()
        let line = String(repeating: "0123456789", count: 40)
        let text = Array(repeating: line, count: 200).joined(separator: "\n")
        pane.textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        ]))
        let container = try #require(pane.textView.textContainer)
        pane.textView.layoutManager?.ensureLayout(for: container)
        pane.textView.sizeToFit()
        let clip = pane.scrollView.contentView
        #expect(pane.textView.frame.width > clip.bounds.width)
        clip.scroll(to: NSPoint(x: 120, y: 200))
        pane.scrollView.reflectScrolledClipView(clip)
        for width in [300.0, 520.0, 360.0] {
            pane.view.frame.size = NSSize(width: width, height: 260)
            pane.view.layoutSubtreeIfNeeded()
            #expect(clip.bounds.origin.x == 120, "width \(width)")
            #expect(clip.bounds.origin.y == 200, "width \(width)")
        }
        // The text view is never narrower than the pane, so the left inset stays.
        pane.view.frame.size = NSSize(width: 4000, height: 260)
        pane.view.layoutSubtreeIfNeeded()
        #expect(pane.textView.frame.width >= clip.bounds.width)
        #expect(clip.bounds.origin.x == 0)
    }
}
