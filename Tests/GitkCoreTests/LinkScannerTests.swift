// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation
import Testing
@testable import GitkCore

@Suite struct LinkScannerTests {
    private let known = ObjectID(hex: "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678")!

    private func resolve(_ prefix: String) -> ObjectID? { known.hex.hasPrefix(prefix) ? known : nil }

    private func substring(_ text: String, _ link: TextLink) -> String { (text as NSString).substring(with: link.range) }

    /// commit-details "Revert message link".
    @Test func revertMessage() {
        let text = "Revert \"Fix things\"\n\nThis reverts commit a1b2c3d4e5f60718293a4b5c6d7e8f9012345678."
        let links = LinkScanner.scan(text, hashLength: 40, resolve: resolve)
        #expect(links.count == 1)
        #expect(links.first?.target == .commit(known))
        #expect(links.first.map { substring(text, $0) } == known.hex)
    }

    @Test func shortIDsAndDescribeSuffix() {
        let text = "see a1b2c3 and v1.0-3-ga1b2c3d4"
        let links = LinkScanner.scan(text, hashLength: 40, resolve: resolve)
        #expect(links.map { substring(text, $0) } == ["a1b2c3", "-ga1b2c3d4"])
        // Five hex digits are too short, and words with other letters do not count.
        #expect(LinkScanner.scan("a1b2c and a1b2c3x", hashLength: 40, resolve: resolve).isEmpty)
    }

    /// commit-details "Unknown hash": a hash that does not resolve is not a link.
    @Test func unknownHash() {
        #expect(LinkScanner.scan("fixes deadbeefcafe", hashLength: 40, resolve: resolve).isEmpty)
    }

    /// commit-details "Open a URL".
    @Test func urls() {
        let text = "Bug: https://example.com/issue/1 and http://x.org/a1b2c3d4."
        let links = LinkScanner.scan(text, hashLength: 40, resolve: resolve)
        #expect(links.map { substring(text, $0) } == ["https://example.com/issue/1", "http://x.org/a1b2c3d4."])
        #expect(links.allSatisfy { if case .web = $0.target { true } else { false } })
    }

    @Test func webBrowserSetting() {
        #expect(WebBrowser.action(setting: "") == .none)
        #expect(WebBrowser.action(setting: "open") == .systemDefault)
        #expect(WebBrowser.action(setting: "open -a Safari") == .command(["open", "-a", "Safari"]))
        #expect(WebBrowser.action(setting: "{/Applications/My Browser.app/x}") == .command(["/Applications/My Browser.app/x"]))
    }
}
