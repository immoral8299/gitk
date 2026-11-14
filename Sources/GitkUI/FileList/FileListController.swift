// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// The sidebar's Changed Files section (design D16; gitk's `cflist`): a header
/// with the file count, the +/− totals and the Patch/Tree switch, then the
/// changed files in diff order. Clicking a file scrolls the diff pane to it.
///
/// The entries come from the streamed diff's file sections rather than a
/// separate `git diff-tree` call, so the list and the diff pane always agree,
/// renames included (docs/architecture.md, Deviations).
@MainActor
final class FileListController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    enum Mode: Int { case patch, tree }

    struct Entry: Equatable {
        var path: String
        var oldPath: String?
        var status: DiffFileStatus
        var added: Int
        var removed: Int
    }

    let view = NSStackView()
    let titleLabel = NSTextField(labelWithString: "")
    let totalsLabel = NSTextField(labelWithString: "")
    let modeSwitch = NSSegmentedControl(labels: [L("Patch"), L("Tree")], trackingMode: .selectOne, target: nil, action: nil)
    let tableView = NSTableView()
    private var heightConstraint: NSLayoutConstraint?
    private(set) var entries: [Entry] = []
    private(set) var highlighted: Int?
    private var updatingSelection = false

    var settings = Settings() { didSet { tableView.reloadData() } }
    var onSelectFile: ((Int) -> Void)?
    var onModeChange: ((Mode) -> Void)?
    var mode: Mode { Mode(rawValue: modeSwitch.selectedSegment) ?? .patch }

    static let rowHeight: CGFloat = 22

    override init() {
        super.init()
        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        totalsLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        modeSwitch.selectedSegment = 0
        modeSwitch.controlSize = .small
        modeSwitch.target = self
        modeSwitch.action = #selector(modeChanged)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let header = NSStackView(views: [titleLabel, totalsLabel, spacer, modeSwitch])
        header.spacing = 8

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        let height = tableView.heightAnchor.constraint(equalToConstant: 0)
        height.isActive = true
        heightConstraint = height

        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = 6
        view.addArrangedSubview(header)
        view.addArrangedSubview(tableView)
        for child in [header, tableView] {
            child.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        }
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
        titleLabel.stringValue = Self.title(fileCount: new.count)
        totalsLabel.attributedStringValue = Self.totals(added: document?.totalAdded ?? 0, removed: document?.totalRemoved ?? 0,
                                                       settings: settings)
        guard new != entries else { return }
        let grew = new.count >= entries.count && Array(new.prefix(entries.count)) == entries
        let old = entries.count
        entries = new
        if grew, new.count > old {
            tableView.insertRows(at: IndexSet(integersIn: old..<new.count), withAnimation: [])
        } else {
            tableView.reloadData()
            if new.isEmpty { highlighted = nil }
        }
        heightConstraint?.constant = CGFloat(entries.count) * Self.rowHeight
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

    /// Port of gitk proc `highlightfile` (gitk/gitk 8549–8558).
    func highlight(_ index: Int?) {
        guard index != highlighted else { return }
        highlighted = index
        updatingSelection = true
        if let index, entries.indices.contains(index) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        updatingSelection = false
    }

    @objc private func modeChanged() { onModeChange?(mode) }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (tableView.makeView(withIdentifier: FileRowView.id, owner: self) as? FileRowView) ?? FileRowView()
        cell.identifier = FileRowView.id
        cell.configure(entries[row], settings: settings)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !updatingSelection, tableView.selectedRow >= 0 else { return }
        highlighted = tableView.selectedRow
        onSelectFile?(tableView.selectedRow)
    }
}

/// One changed file: a status symbol, the file name with its directory, and
/// the +/− counts.
@MainActor
final class FileRowView: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("fileRow")
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let counts = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.setContentHuggingPriority(.init(1), for: .horizontal)
        counts.alignment = .right
        counts.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = NSStackView(views: [icon, name, counts])
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ entry: FileListController.Entry, settings: Settings) {
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
        let text = NSMutableAttributedString(string: file, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium), .foregroundColor: NSColor.labelColor,
        ])
        var detail = directory
        if let old = entry.oldPath { detail = "← " + old }
        if !detail.isEmpty {
            text.append(NSAttributedString(string: "  " + detail, attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
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
