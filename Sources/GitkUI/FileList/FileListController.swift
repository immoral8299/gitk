// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// The sidebar's Changed Files section (design D16; gitk's `cflist`): the
/// changed files in diff order, as a flat list or grouped into folders, with
/// the file count, the +/− totals and the List/Tree switch in the section
/// header. Clicking a file scrolls the diff pane to it.
///
/// The entries come from the streamed diff's file sections rather than a
/// separate `git diff-tree` call, so the list and the diff pane always agree,
/// renames included (docs/architecture.md, Deviations).
@MainActor
final class FileListController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    enum Layout: Int { case list, tree }

    /// gitk's `cmitmode`: the Patch/Tree radio buttons. Patch lists the changed
    /// files; Tree shows the commit's whole tree as an outline (task 13.3).
    enum Mode: Int { case patch, tree }

    struct Entry: Equatable {
        var path: String
        var oldPath: String?
        var status: DiffFileStatus
        var added: Int
        var removed: Int
    }

    /// One table row: a file (by entry index) or, in Tree layout, a folder.
    enum Row: Equatable {
        case file(Int, depth: Int)
        case folder(String, depth: Int)
        /// A row of the Tree-mode outline.
        case outline(TreeOutline.Row)
    }

    let view = NSStackView()
    let titleLabel = NSTextField(labelWithString: "")
    let totalsLabel = NSTextField(labelWithString: "")
    /// One three-way switch: changed files as a List or a Tree (Patch mode),
    /// or All files of the commit (gitk's Tree mode).
    let layoutSwitch = NSSegmentedControl()
    let tableView = NSTableView()
    private var heightConstraint: NSLayoutConstraint?
    private(set) var entries: [Entry] = []
    private(set) var rows: [Row] = []
    private(set) var highlighted: Int?
    private var updatingSelection = false
    private(set) var outline = TreeOutline()
    /// The file shown in the diff pane in Tree mode.
    private(set) var selectedBlob: String?

    var settings = Settings() { didSet { tableView.reloadData() } }
    var onSelectFile: ((Int) -> Void)?
    /// Tree mode: a file was clicked (path, blob).
    var onSelectBlob: ((String, ObjectID) -> Void)?
    /// The Patch/Tree switch changed (gitk `changemode`/`cmitmode` trace).
    var onModeChange: ((Mode) -> Void)?
    var mode: Mode = .patch {
        didSet {
            guard mode != oldValue else { return }
            syncSwitch()
            selectedBlob = nil
            rebuildRows()
            onModeChange?(mode)
        }
    }
    /// Context menu: "Highlight this too/only" (path, only).
    var onHighlight: ((String, Bool) -> Void)?
    /// Context menu: "Blame parent commit" (path).
    var onBlameParent: ((String) -> Void)?
    /// The section title ("N Changed Files") changed.
    var onTitleChange: ((String) -> Void)?
    var layout: Layout = .list {
        didSet {
            syncSwitch()
            rebuildRows()
        }
    }

    static let rowHeight: CGFloat = 22
    static let indent: CGFloat = 14

    override init() {
        super.init()
        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        totalsLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)

        layoutSwitch.segmentCount = Self.switchSegments.count
        layoutSwitch.trackingMode = .selectOne
        layoutSwitch.controlSize = .small
        layoutSwitch.focusRingType = .none
        for (index, (symbol, label)) in Self.switchSegments.enumerated() {
            layoutSwitch.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: label), forSegment: index)
            layoutSwitch.setToolTip(label, forSegment: index)
            layoutSwitch.setWidth(26, forSegment: index)
        }
        layoutSwitch.selectedSegment = 0
        layoutSwitch.target = self
        layoutSwitch.action = #selector(switchChanged)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.focusRingType = .none
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu
        tableView.translatesAutoresizingMaskIntoConstraints = false
        let height = tableView.heightAnchor.constraint(equalToConstant: 0)
        height.isActive = true
        heightConstraint = height

        view.orientation = .vertical
        view.alignment = .leading
        view.addArrangedSubview(tableView)
        tableView.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        update(nil)
    }

    /// Port of gitk's file list filling in `gettreediffs`/`addtocflist`, from
    /// the diff's file sections; nil empties the list.
    func update(_ document: DiffDocument?) {
        guard mode == .patch else { return }
        let sections = document?.sections ?? []
        let new = sections.enumerated().map { index, section in
            Entry(path: section.newPath ?? section.oldPath ?? "", oldPath: section.oldPath == section.newPath ? nil : section.oldPath,
                  status: section.status, added: document?.addedPerFile[safe: index] ?? 0,
                  removed: document?.removedPerFile[safe: index] ?? 0)
        }
        guard new != entries || totalsLabel.attributedStringValue.length == 0 else { return }
        if new.count != entries.count || titleLabel.stringValue.isEmpty {
            titleLabel.stringValue = Self.title(fileCount: new.count)
            onTitleChange?(titleLabel.stringValue)
        }
        totalsLabel.attributedStringValue = Self.totals(added: document?.totalAdded ?? 0, removed: document?.totalRemoved ?? 0,
                                                       settings: settings)
        let old = entries
        entries = new
        if new.isEmpty { highlighted = nil }
        if old.isEmpty || new.count < old.count || (layout == .tree && new.map(\.path) != old.map(\.path)) {
            rebuildRows()
            return
        }
        if new.count > old.count {
            rows += (old.count..<new.count).map { .file($0, depth: 0) }
            tableView.insertRows(at: IndexSet(integersIn: old.count..<new.count), withAnimation: [])
            heightConstraint?.constant = CGFloat(rows.count) * Self.rowHeight
        }
        let changed = IndexSet(old.indices.compactMap { index in
            new[index] != old[index] ? row(ofFile: index) : nil
        })
        tableView.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
    }

    /// Tree mode: the outline of `ls-tree -r` for the selected commit (nil empties it).
    func setOutline(_ new: TreeOutline?, selecting path: String? = nil) {
        outline = new ?? TreeOutline()
        selectedBlob = path
        if mode == .tree { rebuildRows() }
    }

    private func rebuildRows() {
        if mode == .tree {
            rows = outline.rows.map { .outline($0) }
            tableView.reloadData()
            heightConstraint?.constant = CGFloat(rows.count) * Self.rowHeight
            if let selectedBlob, let row = rows.firstIndex(where: { if case .outline(let r) = $0 { r.path == selectedBlob } else { false } }) {
                updatingSelection = true
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                updatingSelection = false
            }
            return
        }
        switch layout {
        case .list:
            rows = entries.indices.map { .file($0, depth: 0) }
        case .tree:
            rows = ChangedFileTree.rows(paths: entries.map(\.path)).map { row in
                row.fileIndex.map { .file($0, depth: row.depth) } ?? .folder(row.name, depth: row.depth)
            }
        }
        tableView.reloadData()
        heightConstraint?.constant = CGFloat(rows.count) * Self.rowHeight
        let current = highlighted
        highlighted = nil
        highlight(current)
    }

    /// "N Changed Files" (file-list "Change totals").
    static func title(fileCount: Int) -> String {
        fileCount == 1 ? L("1 Changed File") : L("%d Changed Files", fileCount)
    }

    /// "+A −R" in the diff colours.
    static func totals(added: Int, removed: Int, settings: Settings) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        let result = NSMutableAttributedString(string: "+\(added)", attributes: [.font: font, .foregroundColor: Palette.diff(settings, 1)])
        result.append(NSAttributedString(string: " −\(removed)", attributes: [.font: font, .foregroundColor: Palette.diff(settings, 0)]))
        return result
    }

    /// The table row showing file `index` (its diff section), if any.
    func row(ofFile index: Int) -> Int? {
        rows.firstIndex { if case .file(index, _) = $0 { true } else { false } }
    }

    /// Port of gitk proc `highlightfile` (gitk/gitk 8549–8558): `index` is the file's diff section.
    func highlight(_ index: Int?) {
        guard mode == .patch, index != highlighted else { return }
        highlighted = index
        updatingSelection = true
        if let index, let row = row(ofFile: index) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        updatingSelection = false
    }

    /// The switch's segments: (SF Symbol, tooltip).
    static let switchSegments = [("list.bullet", L("List")), ("list.bullet.indent", L("Tree")), ("folder", L("All files"))]

    /// The segment for a layout and mode: 0 List, 1 Tree, 2 All files.
    static func segment(layout: Layout, mode: Mode) -> Int { mode == .tree ? 2 : layout.rawValue }

    /// The layout and mode a segment selects (All files keeps the layout).
    static func selection(segment: Int, layout: Layout) -> (Layout, Mode) {
        segment == 2 ? (layout, .tree) : (Layout(rawValue: segment) ?? .list, .patch)
    }

    private func syncSwitch() { layoutSwitch.selectedSegment = Self.segment(layout: layout, mode: mode) }

    @objc private func switchChanged() {
        let (newLayout, newMode) = Self.selection(segment: layoutSwitch.selectedSegment, layout: layout)
        if newLayout != layout { layout = newLayout }
        mode = newMode
    }

    /// Port of gitk proc `treeclick` (gitk/gitk 3447–3472) for directories: a
    /// click opens or closes them. Files are handled by the selection change.
    @objc private func rowClicked() {
        let clicked = tableView.clickedRow
        guard mode == .tree, rows.indices.contains(clicked), case .outline(let row) = rows[clicked], row.isDirectory else { return }
        outline.toggle(row.path)
        rebuildRows()
    }

    // MARK: Context menu

    /// The file path of table row `row`; nil for folders and directory rows.
    func path(ofRow row: Int) -> String? {
        guard rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case .file(let index, _): return entries[index].path
        case .outline(let r): return r.isDirectory ? nil : r.path
        case .folder: return nil
        }
    }

    /// Port of gitk proc `pop_flist_menu` (gitk/gitk 3662–3686): no menu on directories.
    func menuItems(forRow row: Int) -> [NSMenuItem] {
        guard let path = path(ofRow: row) else { return [] }
        return [
            ClosureMenuItem(title: L("Highlight this too")) { [weak self] in self?.onHighlight?(path, false) },
            ClosureMenuItem(title: L("Highlight this only")) { [weak self] in self?.onHighlight?(path, true) },
            ClosureMenuItem(title: L("Blame parent commit")) { [weak self] in self?.onBlameParent?(path) },
            ClosureMenuItem(title: L("Copy path")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            },
        ]
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in menuItems(forRow: tableView.clickedRow) { menu.addItem(item) }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: FileRowView.id, owner: self) as? FileRowView) ?? FileRowView()
        cell.identifier = FileRowView.id
        switch rows[row] {
        case .file(let index, let depth):
            cell.configure(entries[index], depth: depth, showDirectory: layout == .list, settings: settings)
        case .folder(let name, let depth):
            cell.configureFolder(name, depth: depth)
        case .outline(let row):
            cell.configureOutline(row)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        switch rows[row] {
        case .file: true
        case .folder: false
        case .outline(let row): !row.isDirectory
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection, rows.indices.contains(tableView.selectedRow) else { return }
        switch rows[tableView.selectedRow] {
        case .file(let index, _):
            highlighted = index
            onSelectFile?(index)
        case .outline(let row):
            guard !row.isDirectory, let blob = row.objectID else { return }
            selectedBlob = row.path
            onSelectBlob?(row.path, blob)
        case .folder: break
        }
    }
}

/// A menu item that runs a closure.
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

/// One changed file (a status symbol, the name, the +/− counts) or a folder.
/// Text stays on one line and truncates.
@MainActor
final class FileRowView: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("fileRow")
    private let icon = NSImageView()
    private(set) var name = NSTextField(labelWithString: "")
    private(set) var counts = NSTextField(labelWithString: "")
    private var leading: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        for field in [name, counts] {
            field.maximumNumberOfLines = 1
            field.usesSingleLineMode = true
            field.cell?.wraps = false
            field.cell?.truncatesLastVisibleLine = true
        }
        name.lineBreakMode = .byTruncatingTail
        // Below the stack's clipping resistance (defaultLow): at equal priority
        // the stack may clip the counts off the row's end instead of truncating
        // the name, e.g. when a streamed diff makes the counts wider.
        name.setContentCompressionResistancePriority(.init(100), for: .horizontal)
        name.setContentHuggingPriority(.init(1), for: .horizontal)
        counts.alignment = .right
        counts.setContentCompressionResistancePriority(.required, for: .horizontal)
        let iconContainer = NSView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(icon)
        let stack = NSStackView(views: [iconContainer, name, counts])
        stack.spacing = 6
        stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let leading = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SidebarSection.padding)
        self.leading = leading
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 14),
            iconContainer.heightAnchor.constraint(equalTo: icon.heightAnchor),
            icon.widthAnchor.constraint(equalTo: iconContainer.widthAnchor),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor, constant: 2),
            // Rows span the sidebar; their content is padded like the other sections.
            leading,
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SidebarSection.padding),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func setDepth(_ depth: Int) {
        leading?.constant = SidebarSection.padding + CGFloat(depth) * FileListController.indent
    }

    /// Single-line, tail-truncated text: the file name stays whole and the
    /// folder after it is shortened.
    private static func attributes(_ font: NSFont, _ color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    func configureFolder(_ folder: String, depth: Int) {
        setDepth(depth)
        icon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        icon.contentTintColor = .secondaryLabelColor
        name.attributedStringValue = NSAttributedString(string: folder, attributes: Self.attributes(
            .systemFont(ofSize: NSFont.smallSystemFontSize), .secondaryLabelColor))
        name.toolTip = folder
        counts.attributedStringValue = NSAttributedString()
    }

    /// A Tree-mode row: a disclosure triangle for a directory, a document for a file.
    func configureOutline(_ row: TreeOutline.Row) {
        setDepth(row.depth)
        let symbol = row.isDirectory ? (row.isOpen ? "chevron.down" : "chevron.right") : "doc"
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        icon.contentTintColor = .secondaryLabelColor
        name.attributedStringValue = NSAttributedString(string: row.name, attributes: Self.attributes(
            .systemFont(ofSize: NSFont.smallSystemFontSize, weight: row.isDirectory ? .regular : .medium),
            row.isDirectory ? .secondaryLabelColor : .labelColor))
        name.toolTip = row.path
        counts.attributedStringValue = NSAttributedString()
    }

    func configure(_ entry: FileListController.Entry, depth: Int, showDirectory: Bool, settings: Settings) {
        setDepth(depth)
        let (symbol, color): (String, NSColor) = switch entry.status {
        case .added: ("plus.circle.fill", Palette.diff(settings, 1))
        case .deleted: ("minus.circle.fill", Palette.diff(settings, 0))
        case .renamed, .copied: ("arrow.right.circle.fill", Theme.blue)
        default: ("circle.fill", Theme.yellow)
        }
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        icon.contentTintColor = color
        let file = (entry.path as NSString).lastPathComponent
        let directory = (entry.path as NSString).deletingLastPathComponent
        let text = NSMutableAttributedString(string: file, attributes: Self.attributes(
            .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium), .labelColor))
        var detail = showDirectory ? directory : ""
        if let old = entry.oldPath { detail = "← " + (showDirectory ? old : (old as NSString).lastPathComponent) }
        if !detail.isEmpty {
            text.append(NSAttributedString(string: "  " + detail, attributes: Self.attributes(
                .systemFont(ofSize: NSFont.smallSystemFontSize), .secondaryLabelColor)))
        }
        name.attributedStringValue = text
        name.toolTip = entry.oldPath.map { "\($0) → \(entry.path)" } ?? entry.path
        counts.attributedStringValue = entry.added + entry.removed == 0 ? NSAttributedString()
            : FileListController.totals(added: entry.added, removed: entry.removed, settings: settings)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
