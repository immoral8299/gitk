// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class CommitListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let session: ViewSession
    let scrollView = NSScrollView()
    let tableView = NSTableView()
    var onSelection: ((ObjectID) -> Void)?
    var dateFormat = "%Y-%m-%d %H:%M:%S"
    var font: NSFont
    var highlightedIDs = Set<ObjectID>()
    var findQuery = FindQuery()
    /// Colours, circle colours and graph limits for the graph column.
    var settings = UISettings()
    private var updatingSelection = false
    private var colors: GraphColors?

    init(session: ViewSession, font: NSFont) {
        self.session = session
        self.font = font
        super.init()
        for (name, width) in [("subject", 560.0), ("author", 200.0), ("date", 220.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
            column.width = width
            column.minWidth = 40
            tableView.addTableColumn(column)
        }
        tableView.headerView = nil
        tableView.rowHeight = ceil(font.ascender - font.descender + font.leading) + 2
        tableView.intercellSpacing = NSSize(width: 8, height: 0)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { session.rowCount }

    func values(at row: Int) -> [String]? {
        guard let index = session.commit(at: row) else { return nil }
        let store = session.store
        return [store.headline(at: index),
                store.author(at: index).components(separatedBy: " <").first ?? "",
                TclDateFormat.format(epoch: store.authorEpoch(of: index),
                    tzOffsetSeconds: store.authorTZOffset(of: index), format: dateFormat)]
    }

    /// The colour assigner for the current layout; a reload replaces the layout.
    private func graphColors() -> GraphColors {
        if let colors, colors.layout === session.layout { return colors }
        let made = GraphColors(layout: session.layout, palette: settings.colors)
        colors = made
        return made
    }

    /// Text of one cell, bold for find matches, with matched ranges highlighted.
    private func cellText(_ value: String, position: Int, row: Int) -> NSAttributedString {
        let cellFont = session.id(at: row).map { highlightedIDs.contains($0) } == true
            ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        let text = NSMutableAttributedString(string: value, attributes: [.font: cellFont, .foregroundColor: NSColor.labelColor])
        let eligible = (position < 2 && findQuery.field == .allFields) || (position == 0 && findQuery.field == .headline)
            || (position == 1 && findQuery.field == .author)
        if eligible {
            for range in findQuery.matches(in: value) {
                text.addAttribute(.backgroundColor, value: NSColor.yellow, range: NSRange(range, in: value))
            }
        }
        return text
    }

    /// Column 0: the graph, ref labels and headline (gitk's `canv`), drawn from
    /// `GraphRowGeometry`. Rows are laid out for the visible range first, as
    /// gitk's `drawvisible` does, so colours follow gitk's drawing order.
    private func graphCell(row: Int, column: NSTableColumn, headline: String) -> GraphCellView {
        let cell = (tableView.makeView(withIdentifier: column.identifier, owner: self) as? GraphCellView) ?? GraphCellView()
        cell.identifier = column.identifier
        let visible = tableView.rows(in: scrollView.contentView.documentVisibleRect)
        let first = min(row, visible.location)
        session.layout.ensureLaid(visibleRows: first..<max(row + 1, visible.location + visible.length))
        let lineSpacing = Double(tableView.rowHeight)
        let width = Double(column.width)
        let labelFont = font
        let geometry = GraphRowGeometry.make(
            row: row, layout: session.layout, colors: graphColors(), refs: session.refs,
            columnWidth: width, maxWidth: settings.maxWidth, maxGraphPct: settings.maxGraphPct,
            lineSpacing: lineSpacing)?
            .addingRefLabels(refs: session.refs, store: session.store, columnWidth: width, lineSpacing: lineSpacing) { text, bold in
                let measured = bold ? NSFontManager.shared.convert(labelFont, toHaveTrait: .boldFontMask) : labelFont
                return Double((text as NSString).size(withAttributes: [.font: measured]).width)
            }
        cell.font = font
        cell.settings = settings
        cell.geometry = geometry
        cell.attributedHeadline = cellText(headline, position: 0, row: row)
        return cell
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn,
              let position = tableView.tableColumns.firstIndex(of: column),
              let values = values(at: row) else { return nil }
        if position == 0 { return graphCell(row: row, column: column, headline: values[0]) }
        let identifier = column.identifier
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField)
            ?? NSTextField(labelWithString: "")
        field.identifier = identifier
        field.stringValue = values[position]
        field.attributedStringValue = cellText(values[position], position: position, row: row)
        field.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel(values[position])
        return field
    }

    /// Port of gitk proc `selectline` (selection notification only).
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection, let id = session.id(at: tableView.selectedRow) else { return }
        onSelection?(id)
    }

    func refresh() {
        updatingSelection = true
        let oldCount = tableView.numberOfRows
        let newCount = session.rowCount
        if newCount > oldCount {
            tableView.insertRows(at: IndexSet(integersIn: oldCount..<newCount), withAnimation: [])
        } else if newCount < oldCount {
            tableView.removeRows(at: IndexSet(integersIn: newCount..<oldCount), withAnimation: [])
        }
        if newCount > 0 {
            tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<newCount),
                                 columnIndexes: IndexSet(integersIn: 0..<3))
        }
        restoreSelection(scroll: false)
        updatingSelection = false
    }

    func restoreSelection(scroll: Bool) {
        updatingSelection = true
        if let id = session.selection.selectedID, let row = session.row(of: id) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if scroll { tableView.scrollRowToVisible(row) }
        } else { tableView.deselectAll(nil) }
        updatingSelection = false
    }

    var pageSize: Int { max(1, Int(scrollView.contentView.bounds.height / tableView.rowHeight)) }

    func scroll(_ step: AppCommand.ScrollStep) {
        let clip = scrollView.contentView
        var y = clip.bounds.minY
        switch step {
        case .lines(let n): y += CGFloat(n) * tableView.rowHeight
        case .pages(let n): y += CGFloat(n) * clip.bounds.height
        case .toStart: y = 0
        case .toEnd: y = tableView.bounds.height
        }
        y = max(0, min(y, max(0, tableView.bounds.height - clip.bounds.height)))
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
    }
}
