// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing

@testable import GitkUI

@MainActor
@Suite struct SnapshotTests {
    @Test func parsesSize() {
        #expect(Snapshot.parseSize("1400x900") == NSSize(width: 1400, height: 900))
        #expect(Snapshot.parseSize("0x900") == nil)
        #expect(Snapshot.parseSize("1400") == nil)
        #expect(Snapshot.parseSize("axb") == nil)
    }

    @Test func readsEnvironment() {
        #expect(Snapshot.fromEnvironment([:]) == nil)
        #expect(Snapshot.fromEnvironment([Snapshot.pathKey: ""]) == nil)
        let s = Snapshot.fromEnvironment([
            Snapshot.pathKey: "/tmp/x.png", Snapshot.sizeKey: "640x480",
        ])
        #expect(s?.outputURL.path == "/tmp/x.png")
        #expect(s?.size == NSSize(width: 640, height: 480))
    }

    @Test func rendersPNG() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
        let data = try #require(Snapshot.pngData(of: view))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }
}
