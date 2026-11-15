// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor
@Suite struct FileMenuUITests {
    @Test func emptyRowHasNoMenu() {
        #expect(FileListController().menuItems(forRow: 0).isEmpty)
    }

    @Test func menuItemsInOrderAndCopyPath() throws {
        let controller = FileListController()
        var document = DiffDocument()
        for line in ["diff --git a/lib/util.c b/lib/util.c", "@@ -1,1 +1,1 @@", "-old", "+new"] {
            document.append(Data(line.utf8))
        }
        controller.update(document)
        let items = controller.menuItems(forRow: 0)
        #expect(items.map(\.title) == [L("Highlight this too"), L("Highlight this only"), L("Blame parent commit"), L("Copy path")])
        var calls: [String] = []
        controller.onHighlight = { calls.append("\($0) \($1)") }
        controller.onBlameParent = { calls.append("blame \($0)") }
        for item in items.prefix(3) { _ = item.target?.perform(item.action, with: item) }
        #expect(calls == ["lib/util.c false", "lib/util.c true", "blame lib/util.c"])
        let copy = items[3]
        _ = copy.target?.perform(copy.action, with: copy)
        #expect(NSPasteboard.general.string(forType: .string) == "lib/util.c")
    }
}
