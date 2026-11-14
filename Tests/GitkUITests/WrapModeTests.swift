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
        #expect(CommentWrap(setting: "none").lineBreakMode == .byClipping)
        #expect(!CommentWrap(setting: "none").tracksWidth)
        #expect(CommentWrap(setting: "char").lineBreakMode == .byCharWrapping)
        #expect(CommentWrap(setting: "word").lineBreakMode == .byWordWrapping)
        #expect(CommentWrap(setting: "word").tracksWidth)
        #expect(CommentWrap(setting: "bogus").mode == .none)
    }

    @Test func wordWrapFitsThePaneWidth() throws {
        let view = AutoHeightTextView()
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textStorage?.setAttributedString(NSAttributedString(
            string: "a message line that is clearly longer than two hundred points of text", attributes: [.font: font]))
        CommentWrap(setting: "word").apply(to: view)
        let container = try #require(view.textContainer)
        view.layoutManager?.ensureLayout(for: container)
        let wrapped = try #require(view.layoutManager?.usedRect(for: container))
        #expect(wrapped.width <= 200)
        #expect(wrapped.height > font.boundingRectForFont.height * 1.5)
        CommentWrap(setting: "none").apply(to: view)
        view.layoutManager?.ensureLayout(for: container)
        let single = try #require(view.layoutManager?.usedRect(for: container))
        #expect(single.width > 200)
        #expect(single.height < wrapped.height)
    }
}
