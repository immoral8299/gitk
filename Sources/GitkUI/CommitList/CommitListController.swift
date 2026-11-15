// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class CommitListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let session: ViewSession
    let scrollView = CommitScrollView()
    let tableView = NSTableView()
    var onSelection: ((ObjectID) -> Void)?
    /// The parent whose line is drawn thicker, and the receiver of its details (task 10.9).
    var thickLine: CommitIndex?
    var onLineDetails: ((LineDetails) -> Void)?
    /// Receives a row context-menu command and the commit it was opened on.
    /// Nil until the actions are wired (group 16); the items then do nothing.
    var onRowCommand: ((AppCommand, ObjectID) -> Void)?
    /// Receives a head label menu command, the head's name and the commit it labels.
    var onHeadCommand: ((AppCommand, String, ObjectID) -> Void)?
    var dateFormat = "%Y-%m-%d %H:%M:%S" { didSet { measureColumns() } }
    var font: NSFont
    var highlightedIDs = Set<ObjectID>()
    var findQuery = FindQuery()
    /// Colours, circle colours and graph limits for the graph column.
    var settings = UISettings()
    private var updatingSelection = false
    /// The row the current-match box was last drawn for.
    private var shownSelectedRow = -1
    private var colors: GraphColors?
    /// Widest sampled author and date values, padding included.
    private var authorContent: CGFloat = 0
    private var dateContent: CGFloat = 0
    /// Widths the user dragged the author and date columns to.
    var userAuthorWidth: CGFloat?
    var userDateWidth: CGFloat?
    private var fitting = false
    /// The widths `fitColumns` last applied.
    private var fitted = ColumnSizing(subject: 0, author: 0, date: 0)
    /// Horizontal scroll of the first column's content (graph and headline),
    /// and the widest such content seen so far.
    private var firstColumnOffset: CGFloat = 0
    private var firstColumnContent: CGFloat = 0
    /// The pointer position and clip origin when a middle-button pan began.
    private var panStart: (mark: NSPoint, origin: NSPoint)?
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
        scrollView.owner = self
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
    /// rows and the visible ones, in the list font.
    private func measureColumns() {
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
            author = max(author, (values[1] as NSString).size(withAttributes: [.font: font]).width)
            date = max(date, (values[2] as NSString).size(withAttributes: [.font: font]).width)
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

    /// Text of one cell. Rows keep their normal weight; matched ranges carry
    /// `MatchBoxes.key` and are drawn as rounded boxes behind the glyphs, in the
    /// current-search-hit colour on the selected row and the found colour
    /// elsewhere (design D17).
    private func cellText(_ value: String, position: Int, row: Int) -> NSAttributedString {
        let text = NSMutableAttributedString(string: value, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let eligible = (position < 2 && findQuery.field == .allFields) || (position == 0 && findQuery.field == .headline)
            || (position == 1 && findQuery.field == .author)
        guard eligible, let id = session.id(at: row), highlightedIDs.contains(id) else { return text }
        // Only the first occurrence in the selected row is the current match.
        var currentHere = false
        if id == session.selection.selectedID, let values = values(at: row) {
            let fields = (0..<2).filter { p in
                findQuery.field == .allFields || (p == 0 && findQuery.field == .headline) || (p == 1 && findQuery.field == .author)
            }
            let counts = fields.map { findQuery.matches(in: values[$0]).count }
            currentHere = FindStepper.currentOccurrence(counts: counts).map { fields[$0.field] == position } ?? false
        }
        for (n, range) in findQuery.matches(in: value).enumerated() {
            let colour = currentHere && n == 0 ? Palette.tk(settings.currentSearchHitBgColor) : Palette.found(settings)
            text.addAttribute(MatchBoxes.key, value: colour, range: NSRange(range, in: value))
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
            lineSpacing: lineSpacing, thickLine: thickLine)?
            .addingRefLabels(refs: session.refs, store: session.store, columnWidth: width, lineSpacing: lineSpacing) { text, bold in
                // Measure with the font the labels are drawn in (monospaced).
                let measured = RefLabelDrawing.font(for: labelFont, bold: bold)
                return Double((text as NSString).size(withAttributes: [.font: measured]).width)
            }
        cell.font = font
        cell.settings = settings
        cell.geometry = geometry
        configureLineInteraction(cell)
        cell.onHeadMenu = { [weak self] label, _ in
            guard let self, let id = session.id(at: row) else { return nil }
            return RowMenus.headMenu(name: label.name, refs: session.refs) { [weak self] command in
                self?.onHeadCommand?(command, label.name, id)
            }
        }
        cell.attributedHeadline = cellText(headline, position: 0, row: row)
        cell.setBoundsOrigin(NSPoint(x: firstColumnOffset, y: 0))
        let contentEnd = CGFloat(geometry?.textX ?? 0) + cell.attributedHeadline.size().width
        firstColumnContent = max(firstColumnContent, contentEnd)
        return cell
    }

    /// The marked row's background (gitk `make_idmark`, `markbgcolor`).
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = (tableView.makeView(withIdentifier: MarkedRowView.identifier, owner: self) as? MarkedRowView) ?? MarkedRowView()
        view.identifier = MarkedRowView.identifier
        view.markColor = isMarked(row: row) ? Palette.tk(settings.markBgColor) : nil
        return view
    }

    func isMarked(row: Int) -> Bool {
        guard let marked = session.selection.markedID else { return false }
        return session.id(at: row) == marked
    }

    /// Redraws the rows that gained or lost the mark.
    func markChanged(old: ObjectID?, new: ObjectID?) {
        for id in [old, new].compactMap({ $0 }) {
            guard let row = session.row(of: id), row < tableView.numberOfRows,
                  let view = tableView.rowView(atRow: row, makeIfNecessary: false) as? MarkedRowView else { continue }
            view.markColor = isMarked(row: row) ? Palette.tk(settings.markBgColor) : nil
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn,
              let position = tableView.tableColumns.firstIndex(of: column),
              let values = values(at: row) else { return nil }
        if position == 0 { return graphCell(row: row, column: column, headline: values[0]) }
        let identifier = column.identifier
        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? MatchLabel) ?? MatchLabel()
        field.identifier = identifier
        field.stringValue = values[position]
        field.attributedStringValue = cellText(values[position], position: position, row: row)
        field.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel(values[position])
        return field
    }

    /// Port of gitk proc `selectline` (selection notification only).
    func tableViewSelectionDidChange(_ notification: Notification) {
        // The current match box follows the selection.
        if !highlightedIDs.isEmpty {
            let rows = IndexSet([shownSelectedRow, tableView.selectedRow].filter { $0 >= 0 && $0 < session.rowCount })
            if !rows.isEmpty { tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integersIn: 0..<3)) }
        }
        shownSelectedRow = tableView.selectedRow
        if tableView.selectedRow >= 0 { setThickLine(nil) }
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
            if scroll { reveal(row: row) }
        } else { tableView.deselectAll(nil) }
        updatingSelection = false
    }

    /// Scrolls the least distance that shows `row` in full below the header
    /// (and titlebar) inset, without animation. `scrollRowToVisible` ignores
    /// the content insets and animates, so holding an arrow key made the list
    /// jump and drift.
    func reveal(row: Int) {
        guard row >= 0, row < tableView.numberOfRows else { return }
        let clip = scrollView.contentView
        let rect = tableView.rect(ofRow: row)
        guard let y = Self.revealOffset(rowMinY: rect.minY, rowMaxY: rect.maxY, boundsMinY: clip.bounds.minY,
                                        boundsHeight: clip.bounds.height, insetTop: clip.contentInsets.top,
                                        insetBottom: clip.contentInsets.bottom) else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    /// The clip origin that brings the row span `rowMinY...rowMaxY` into the
    /// visible area (the bounds minus the insets), or nil when it is already
    /// fully visible. A row above the area lands at its top edge, a row below
    /// at its bottom edge.
    nonisolated static func revealOffset(rowMinY: CGFloat, rowMaxY: CGFloat, boundsMinY: CGFloat, boundsHeight: CGFloat,
                                         insetTop: CGFloat, insetBottom: CGFloat) -> CGFloat? {
        let visibleTop = boundsMinY + insetTop
        let visibleBottom = boundsMinY + boundsHeight - insetBottom
        if rowMinY < visibleTop { return rowMinY - insetTop }
        if rowMaxY > visibleBottom { return rowMaxY - boundsHeight + insetBottom }
        return nil
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

    // MARK: Wheel, first-column scroll and middle-button pan

    /// Scales the list's wheel and trackpad deltas by the "Wheel scrolling
    /// multiplier" (gitk `kscroll`) and scrolls the list. Returns false when
    /// the event is left to NSScrollView, which is the case at multiplier 1
    /// away from the first column.
    func handleWheel(_ event: NSEvent) -> Bool {
        let location = tableView.convert(event.locationInWindow, from: nil)
        let multiplier = settings.kscroll
        let precise = event.hasPreciseScrollingDeltas
        let firstColumn = tableView.rect(ofColumn: 0)
        let inFirstColumn = location.x >= firstColumn.minX && location.x < firstColumn.maxX
        if inFirstColumn, Self.scrollsFirstColumn(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                                  shift: event.modifierFlags.contains(.shift)) {
            let horizontal = event.scrollingDeltaX == 0 ? event.scrollingDeltaY : event.scrollingDeltaX
            let points = Self.wheelPointDelta(horizontal, precise: precise, lineHeight: tableView.rowHeight,
                                              multiplier: multiplier)
            let limit = max(0, firstColumnContent - firstColumn.width)
            firstColumnOffset = Self.clampedOffset(firstColumnOffset - points, lower: 0, upper: limit)
            applyFirstColumnOffset()
            return true
        }
        // Trackpads and Magic Mouse scroll natively (momentum, rubber-banding);
        // gitk's multiplier is for line-based mouse wheels only.
        guard multiplier != 1, !precise else { return false }
        let clip = scrollView.contentView
        let points = Self.wheelPointDelta(event.scrollingDeltaY, precise: precise, lineHeight: tableView.rowHeight,
                                          multiplier: multiplier)
        let y = Self.clampedOffset(clip.bounds.minY - points, lower: verticalLower(clip), upper: verticalUpper(clip))
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(clip)
        return true
    }

    /// Starts a middle-button pan at the event's pointer position.
    func beginPan(_ event: NSEvent) -> Bool {
        guard event.buttonNumber == 2 else { return false }
        panStart = (tableView.convert(event.locationInWindow, from: nil), scrollView.contentView.bounds.origin)
        return true
    }

    /// Moves the clip so the content follows the pointer from where the pan began.
    func continuePan(_ event: NSEvent) -> Bool {
        guard let panStart else { return false }
        let now = tableView.convert(event.locationInWindow, from: nil)
        let clip = scrollView.contentView
        let x = Self.panOrigin(start: panStart.origin.x, mark: panStart.mark.x, now: now.x)
        let y = Self.panOrigin(start: panStart.origin.y, mark: panStart.mark.y, now: now.y)
        let maxX = max(0, tableView.bounds.width - clip.bounds.width)
        clip.scroll(to: NSPoint(x: Self.clampedOffset(x, lower: 0, upper: maxX),
                                y: Self.clampedOffset(y, lower: verticalLower(clip), upper: verticalUpper(clip))))
        scrollView.reflectScrolledClipView(clip)
        return true
    }

    /// Ends a middle-button pan; returns false when no pan was running.
    func endPan(_ event: NSEvent) -> Bool {
        guard panStart != nil, event.buttonNumber == 2 else { return false }
        panStart = nil
        return true
    }

    /// The vertical clip origin range: the first row must not end up under
    /// the header or titlebar inset, and the last row must not leave a gap.
    private func verticalLower(_ clip: NSClipView) -> CGFloat { -clip.contentInsets.top }

    private func verticalUpper(_ clip: NSClipView) -> CGFloat {
        max(verticalLower(clip), tableView.bounds.height + clip.contentInsets.bottom - clip.bounds.height)
    }

    /// Sets the first column's content offset on the rows now shown.
    private func applyFirstColumnOffset() {
        let visible = tableView.rows(in: scrollView.contentView.documentVisibleRect)
        for row in visible.location..<min(tableView.numberOfRows, visible.location + visible.length) {
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? GraphCellView else { continue }
            cell.setBoundsOrigin(NSPoint(x: firstColumnOffset, y: 0))
            cell.needsDisplay = true
        }
    }

    /// Whether a wheel or trackpad event over the first column scrolls that
    /// column sideways: Shift-scrolling, or a gesture that is mostly horizontal.
    nonisolated static func scrollsFirstColumn(deltaX: CGFloat, deltaY: CGFloat, shift: Bool) -> Bool {
        shift || abs(deltaX) > abs(deltaY)
    }

    /// Points to scroll for one wheel or trackpad delta, scaled by the wheel
    /// multiplier. Port of gitk procs `scrollval` and `precisescrollval`
    /// (gitk/gitk 2306–2314) on macOS, where `scroll_D0` is 1: a non-precise
    /// delta counts lines, a precise one is already in points. A multiplier
    /// below 1 counts as 1.
    nonisolated static func wheelPointDelta(_ delta: CGFloat, precise: Bool, lineHeight: CGFloat, multiplier: Int) -> CGFloat {
        // Precise (trackpad) deltas are already points and stay 1:1.
        precise ? delta : delta * lineHeight * CGFloat(max(1, multiplier))
    }

    /// The clip origin for a middle-button pan: the content moves with the
    /// pointer, so the origin moves against the pointer's travel. Port of gitk
    /// proc `canvscan` (gitk/gitk 2925–2935).
    nonisolated static func panOrigin(start: CGFloat, mark: CGFloat, now: CGFloat) -> CGFloat {
        start - (now - mark)
    }

    /// `value` limited to `lower...upper`; an inverted range collapses to `lower`.
    nonisolated static func clampedOffset(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}

/// The list's scroll view. It hands wheel and middle-button events to
/// `CommitListController` first, so the wheel multiplier, the first column's
/// own scroll and the middle-button pan apply; anything it declines goes to
/// NSScrollView as before.
@MainActor
final class CommitScrollView: NSScrollView {
    weak var owner: CommitListController?

    override func scrollWheel(with event: NSEvent) {
        if owner?.handleWheel(event) == true { return }
        super.scrollWheel(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        if owner?.beginPan(event) == true { return }
        super.otherMouseDown(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        if owner?.continuePan(event) == true { return }
        super.otherMouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        if owner?.endPan(event) == true { return }
        super.otherMouseUp(with: event)
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

/// Row view that paints gitk's marked-line background behind the cells.
final class MarkedRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("MarkedRowView")
    var markColor: NSColor? { didSet { needsDisplay = true } }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard let markColor else { return }
        markColor.setFill()
        bounds.fill()
    }
}
