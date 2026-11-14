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
final class FileListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    enum Layout: Int { case list, tree }

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
    }

    let view = NSStackView()
    let titleLabel = NSTextField(labelWithString: "")
    let totalsLabel = NSTextField(labelWithString: "")
    let layoutSwitch = NSSegmentedControl()
    let tableView = NSTableView()
    private var heightConstraint: NSLayoutConstraint?
    private(set) var entries: [Entry] = []
    private(set) var rows: [Row] = []
    private(set) var highlighted: Int?
    private var updatingSelection = false

    var settings = Settings() { didSet { tableView.reloadData() } }
    var onSelectFile: ((Int) -> Void)?
    /// The section title ("N Changed Files") changed.
    var onTitleChange: ((String) -> Void)?
    var layout: Layout = .list {
        didSet {
            layoutSwitch.selectedSegment = layout.rawValue
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

        layoutSwitch.segmentCount = 2
        layoutSwitch.trackingMode = .selectOne
        layoutSwitch.controlSize = .small
        layoutSwitch.focusRingType = .none
        for (index, (symbol, label)) in [("list.bullet", L("List")), ("list.bullet.indent", L("Tree"))].enumerated() {
            layoutSwitch.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: label), forSegment: index)
            layoutSwitch.setToolTip(label, forSegment: index)
            layoutSwitch.setWidth(26, forSegment: index)
        }
        layoutSwitch.selectedSegment = 0
        layoutSwitch.target = self
        layoutSwitch.action = #selector(layoutChanged)

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

    private func rebuildRows() {
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
        guard index != highlighted else { return }
        highlighted = index
        updatingSelection = true
        if let index, let row = row(ofFile: index) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        updatingSelection = false
    }

    @objc private func layoutChanged() {
        layout = Layout(rawValue: layoutSwitch.selectedSegment) ?? .list
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
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .file = rows[row] { true } else { false }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection, rows.indices.contains(tableView.selectedRow),
              case .file(let index, _) = rows[tableView.selectedRow] else { return }
        highlighted = index
        onSelectFile?(index)
    }
}

/// One changed file (a status symbol, the name, the +/− counts) or a folder.
/// Text stays on one line and truncates.
@MainActor
final class FileRowView: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("fileRow")
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let counts = NSTextField(labelWithString: "")
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
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
