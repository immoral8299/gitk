// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import Testing
@testable import GitkCore
@testable import GitkUI

/// A long file name or folder truncates; the +/− counts stay whole and inside
/// the row.
@MainActor
@Suite struct FileRowTruncationTests {
    @Test(arguments: [
        "Sources/GitkCore/Ancestry/AncestryIndexWithAVeryLongName.swift",
        "Sources/GitkCore/Actions/ExternalDiff.swift",
        "Sources/GitkCore/Actions/PatchIDCompare.swift",
        "Sources/GitkCore/CLI/RepositoryArgument.swift",
    ])
    func countsStayInsideTheRowAtEveryWidth(path: String) {
        let row = FileRowView()
        let entry = FileListController.Entry(path: path, oldPath: nil, status: .added, added: 152, removed: 0)
        row.configure(entry, depth: 0, showDirectory: true, settings: Settings())
        for width in stride(from: 160.0, through: 420.0, by: 1) {
            row.frame = NSRect(x: 0, y: 0, width: width, height: FileListController.rowHeight)
            row.layoutSubtreeIfNeeded()
            let counts = row.convert(row.counts.bounds, from: row.counts)
            #expect(counts.maxX <= row.bounds.maxX - SidebarSection.padding + 2.5, "width \(width)")
            #expect(counts.width >= row.counts.intrinsicContentSize.width - 0.5, "width \(width)")
        }
    }
}

@MainActor
@Suite struct FileListReuseWidthTests {
    private func document(_ paths: [String], lines: Int = 1) -> DiffDocument {
        var document = DiffDocument()
        for path in paths {
            for line in ["diff --git a/\(path) b/\(path)", "@@ -0,0 +1,\(lines) @@"] + Array(repeating: "+new", count: lines) {
                document.append(Data(line.utf8))
            }
        }
        return document
    }

    /// Rows are reconfigured in place while a diff streams in; wider counts
    /// must truncate the name, not push the counts off the row.
    @Test func reusedAndStreamedRowsStayInside() throws {
        let sidebar = DetailsSidebar()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 324, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = sidebar
        let table = sidebar.fileList.tableView
        func check(_ label: String) {
            window.contentView?.layoutSubtreeIfNeeded()
            for row in 0..<table.numberOfRows {
                guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? FileRowView else { continue }
                cell.layoutSubtreeIfNeeded()
                let counts = cell.convert(cell.counts.bounds, from: cell.counts)
                #expect(counts.maxX <= cell.bounds.maxX - SidebarSection.padding + 2.5,
                        "\(label) row \(row) cell \(cell.frame.width) counts \(counts.maxX)")
            }
        }
        sidebar.fileList.update(document(["Makefile", "Package.swift", "README.md"]))
        check("short")
        let long = ["Makefile", "Sources/GitkCore/Actions/ExternalDiff.swift", "Sources/GitkCore/Actions/FileMenu.swift",
                    "Sources/GitkCore/Actions/PatchIDCompare.swift", "Sources/GitkCore/CLI/RepositoryArgument.swift"]
        sidebar.fileList.update(document(Array(long.prefix(2))))
        check("streamed part")
        sidebar.fileList.update(document(long))
        check("streamed all")
        sidebar.fileList.update(document(long, lines: 177))
        check("bigger counts")
    }
}
