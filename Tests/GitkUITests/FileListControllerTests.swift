// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

@MainActor
@Suite struct FileListControllerTests {
    private func appendFile(_ path: String, to document: DiffDocument) -> DiffDocument {
        var result = document
        for line in ["diff --git a/\(path) b/\(path)", "@@ -1,1 +1,1 @@", "-old", "+new"] {
            result.append(Data(line.utf8))
        }
        return result
    }

    @Test(arguments: [FileListController.Layout.list, .tree])
    func streamedCountsKeepUnchangedCellsAndSelection(layout: FileListController.Layout) throws {
        let controller = FileListController()
        controller.layout = layout
        var document = appendFile("src/a.swift", to: DiffDocument())
        document = appendFile("src/b.swift", to: document)
        controller.update(document)
        let first = try #require(controller.row(ofFile: 0))
        let last = try #require(controller.row(ofFile: 1))
        controller.tableView.frame = NSRect(x: 0, y: 0, width: 320, height: CGFloat(controller.rows.count) * 22)
        let probe = RowProbe()
        controller.tableView.delegate = probe
        let stable = try #require(controller.tableView.view(atColumn: 0, row: first, makeIfNecessary: true))
        _ = controller.tableView.view(atColumn: 0, row: last, makeIfNecessary: true)
        controller.highlight(0)
        let rows = controller.rows
        document.append(Data("+another line".utf8))
        controller.update(document)
        #expect(controller.tableView.view(atColumn: 0, row: first, makeIfNecessary: true) === stable)
        #expect(controller.entries[1].added == 2)
        #expect(controller.rows == rows)
        #expect(controller.tableView.selectedRow == first)
        #expect(controller.highlighted == 0)
    }

    @Test func appendedFilesAndRenamedPathsKeepDiffIndices() throws {
        let controller = FileListController()
        var document = appendFile("src/a.swift", to: DiffDocument())
        controller.update(document)
        controller.highlight(0)
        document.append(Data("+another line".utf8))
        document = appendFile("src/b.swift", to: document)
        controller.update(document)
        #expect(controller.entries.map(\.added) == [2, 1])
        #expect(controller.rows == [.file(0, depth: 0), .file(1, depth: 0)])
        #expect(controller.tableView.numberOfRows == 2)
        #expect(controller.highlighted == 0)

        controller.layout = .tree
        var rename = DiffDocument()
        rename.append(Data("diff --git a/old.swift b/new/file.swift".utf8))
        controller.update(rename)
        rename.append(Data("rename from old.swift".utf8))
        rename.append(Data("rename to new/file.swift".utf8))
        controller.update(rename)
        #expect(controller.rows == [.folder("new", depth: 0), .file(0, depth: 1)])
        #expect(controller.entries[0].oldPath == "old.swift")
        #expect(controller.entries[0].status == .renamed)
        var selected: [Int] = []
        controller.onSelectFile = { selected.append($0) }
        controller.tableView.deselectAll(nil)
        controller.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        #expect(selected == [0])
        controller.update(nil)
        #expect(controller.rows.isEmpty)
        #expect(controller.highlighted == nil)
    }

    @Test func listControlsHaveNoFocusRing() {
        let controller = FileListController()
        #expect(controller.tableView.focusRingType == .none)
        #expect(controller.layoutSwitch.focusRingType == .none)
    }
}

@MainActor
private final class RowProbe: NSObject, NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSView()
    }
}
