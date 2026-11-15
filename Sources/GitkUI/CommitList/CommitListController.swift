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
    /// Receives a row context-menu command and the commit it was opened on.
    /// Nil until the actions are wired (group 16); the items then do nothing.
    var onRowCommand: ((AppCommand, ObjectID) -> Void)?
    var dateFormat = "%Y-%m-%d %H:%M:%S" { didSet { measureColumns() } }
    var font: NSFont
    var highlightedIDs = Set<ObjectID>()
    var findQuery = FindQuery()
    /// Colours, circle colours and graph limits for the graph column.
    var settings = UISettings()
    private var updatingSelection = false
    private var colors: GraphColors?
    /// Widest sampled author and date values, padding included.
    private var authorContent: CGFloat = 0
    private var dateContent: CGFloat = 0
    /// Widths the user dragged the author and date columns to.
    private(set) var userAuthorWidth: CGFloat?
    private(set) var userDateWidth: CGFloat?
    private var fitting = false
    /// The widths `fitColumns` last applied.
    private var fitted = ColumnSizing(subject: 0, author: 0, date: 0)
    /// Rows measured for the author and date widths: the first ones plus the
    /// visible ones, never the whole history.
    static let measuredRows = 300
    /// A text cell's insets plus a little air.
    private static let cellPadding: CGFloat = 8

    init(session: ViewSession, font: NSFont) {
        self.session = session
        self.font = font
        super.init()
        for (name, title) in [("subject", L("Headline")), ("author", L("Author")), ("date", L("Date"))] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
            column.title = title
            column.minWidth = ColumnSizing.minColumn
            column.resizingMask = [.autoresizingMask, .userResizingMask]
            tableView.addTableColumn(column)
        }
        // The header is there for dragging column dividers; it neither sorts
        // nor selects columns.
        tableView.allowsColumnSelection = false
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        // Window and sidebar resizes go to the headline column first;
        // `fitColumns` then settles the exact widths.
        tableView.columnAutoresizingStyle = .reverseSequentialColumnAutoresizingStyle
        tableView.rowHeight = ceil(font.ascender - font.descender + font.leading) + 2
        tableView.intercellSpacing = NSSize(width: 8, height: 0)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        // The menu is filled per click in `menuNeedsUpdate`, once NSTableView
        // has set `clickedRow` to the row under the pointer.
        let rowMenu = NSMenu()
        rowMenu.delegate = self
        tableView.menu = rowMenu
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(listWidthChanged(_:)), name: NSView.frameDidChangeNotification,
            object: scrollView.contentView)
        measureColumns()
    }

    // MARK: Row context menu

    /// The commit context menu for a row (gitk `rowmenu`), or nil for a row
    /// that is not there. Local-changes rows get the reduced menu.
    func contextMenu(forRow row: Int) -> NSMenu? {
        guard row >= 0, let id = session.id(at: row) else { return nil }
        return RowMenus.commitMenu(id: id, selected: session.selection.selectedID,
                                   marked: session.selection.markedID, refs: session.refs) { [weak self] command in
            self?.onRowCommand?(command, id)
        }
    }

    // MARK: Column widths

    @objc private func listWidthChanged(_ notification: Notification) { fitColumns() }

    /// Width the three columns share: the list's width less intercell spacing
    /// and the table style's leading and trailing row insets.
    private var availableColumnWidth: CGFloat {
        let columns = tableView.tableColumns
        guard !columns.isEmpty else { return 0 }
        let leading = tableView.rect(ofColumn: 0).minX
        let spanned = tableView.rect(ofColumn: columns.count - 1).maxX - leading
        let spacing = spanned - columns.reduce(0) { $0 + $1.width }
        return scrollView.contentView.bounds.width - spacing - 2 * leading
    }

    /// Measures the widest author and date among the first `measuredRows`
    /// rows and the visible ones, in the list font (bold for find matches).
    private func measureColumns() {
        let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let count = session.rowCount
        var rows = IndexSet(integersIn: 0..<min(count, Self.measuredRows))
        let visible = tableView.rows(in: scrollView.contentView.documentVisibleRect)
        if visible.length > 0, visible.location < count {
            rows.insert(integersIn: visible.location..<min(count, visible.location + visible.length))
        }
        var author: CGFloat = 0
        var date: CGFloat = 0
        if rows.isEmpty {
            // Before the first rows arrive, size the date column for "now".
            let sample = TclDateFormat.format(epoch: Int64(Date().timeIntervalSince1970),
                tzOffsetSeconds: TimeZone.current.secondsFromGMT(), format: dateFormat)
            date = (sample as NSString).size(withAttributes: [.font: font]).width
        }
        for row in rows {
            guard let values = values(at: row) else { continue }
            let rowFont = session.id(at: row).map { highlightedIDs.contains($0) } == true ? bold : font
            author = max(author, (values[1] as NSString).size(withAttributes: [.font: rowFont]).width)
            date = max(date, (values[2] as NSString).size(withAttributes: [.font: rowFont]).width)
        }
        authorContent = ceil(author) + Self.cellPadding
        dateContent = ceil(date) + Self.cellPadding
        fitColumns()
    }

    /// Applies `ColumnSizing.fit` to the list's current width.
    func fitColumns() {
        let columns = tableView.tableColumns
        let available = availableColumnWidth
        guard !fitting, columns.count == 3, available > 0 else { return }
        let sizing = ColumnSizing.fit(available: available, authorContent: authorContent, dateContent: dateContent,
                                      userAuthor: userAuthorWidth, userDate: userDateWidth)
        fitted = sizing
        fitting = true
        defer { fitting = false }
        for (column, width) in zip(columns, [sizing.subject, sizing.author, sizing.date]) where column.width != width {
            column.width = width
        }
    }

    /// A divider dragged in the header: the author and date columns keep the
    /// widths the user gave them from then on; the headline takes the rest.
    func tableViewColumnDidResize(_ notification: Notification) {
        guard !fitting else { return }
        let columns = tableView.tableColumns
        if let header = tableView.headerView, header.resizedColumn >= 0, columns.count == 3 {
            let user = ColumnSizing.dragged(column: header.resizedColumn, to: columns[header.resizedColumn].width,
                                            from: fitted, available: availableColumnWidth)
            if header.resizedColumn <= 1 { userAuthorWidth = user.author }
            if header.resizedColumn >= 1 { userDateWidth = user.date }
        }
        fitColumns()
    }

    /// Double-clicking a divider fits the column to its content again.
    func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
        switch column {
        case 1: userAuthorWidth = nil
        case 2: userDateWidth = nil
        default: return tableView.tableColumns[column].width
        }
        let sizing = ColumnSizing.fit(available: availableColumnWidth, authorContent: authorContent,
                                      dateContent: dateContent, userAuthor: userAuthorWidth, userDate: userDateWidth)
        return column == 1 ? sizing.author : sizing.date
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
                text.addAttribute(.backgroundColor, value: Palette.found(settings), range: NSRange(range, in: value))
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
                // Measure with the font the labels are drawn in (monospaced).
                let measured = RefLabelDrawing.font(for: labelFont, bold: bold)
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
        measureColumns()
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
        case .toStart: y = -.infinity
        case .toEnd: y = .infinity
        }
        // The top inset covers the header and, with a unified titlebar, the
        // titlebar; the first row must not end up underneath them.
        let top = -clip.contentInsets.top
        y = max(top, min(y, max(top, tableView.bounds.height + clip.contentInsets.bottom - clip.bounds.height)))
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
    }
}

extension CommitListController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let built = contextMenu(forRow: tableView.clickedRow) else { return }
        // An NSMenuItem belongs to one menu at a time, so move the items over.
        for item in built.items {
            built.removeItem(item)
            menu.addItem(item)
        }
    }
}
