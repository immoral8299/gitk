// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkUI

/// commit-details "Word wrap": `wrapcomment` maps to text container settings.
@MainActor
@Suite struct WrapModeTests {
    @Test func mapping() {
        #expect(CommentWrap(setting: "none").lineBreakMode == .byWordWrapping)
        #expect(CommentWrap(setting: "char").lineBreakMode == .byCharWrapping)
        #expect(CommentWrap(setting: "word").lineBreakMode == .byWordWrapping)
        #expect(CommentWrap(setting: "bogus").mode == .word)
    }

    @Test(arguments: ["none", "bogus", "word", "char"], [12.0, 20.0])
    func messagesWrapAndReflowAtThePaneWidth(setting: String, fontSize: Double) throws {
        let view = AutoHeightTextView()
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.textStorage?.setAttributedString(NSAttributedString(
            string: "a message line that is clearly longer than two hundred points of text", attributes: [.font: font]))
        CommentWrap(setting: setting).apply(to: view)
        let container = try #require(view.textContainer)
        #expect(container.widthTracksTextView)
        view.layoutManager?.ensureLayout(for: container)
        let wrapped = try #require(view.layoutManager?.usedRect(for: container))
        #expect(wrapped.width <= 200)
        #expect(wrapped.height > font.boundingRectForFont.height * 1.5)
        view.setFrameSize(NSSize(width: 100, height: 20))
        view.layoutManager?.ensureLayout(for: container)
        let narrow = try #require(view.layoutManager?.usedRect(for: container))
        #expect(narrow.width <= 100)
        #expect(narrow.height > wrapped.height)
        #expect(view.intrinsicContentSize.height >= narrow.height)
    }
}
