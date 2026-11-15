// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Port of gitk proc `showrefs` (gitk/gitk 10209–10260): the "Tags and heads"
/// window. A single instance per main window; opening it again raises it.
@MainActor
final class RefListWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let source: () -> (refs: RefSet, inView: (ObjectID) -> Bool, subject: (ObjectID) -> String?)
    private let onSelect: (ObjectID) -> Void
    private let table = NSTableView()
    private let filterField = NSTextField(string: "*")
    private let sortButton = NSButton(checkboxWithTitle: L("Sort refs by type"), target: nil, action: nil)
    private var model = RefListModel()
    private(set) var entries: [RefListModel.Entry] = []
    private var subjects: [String] = []
    private var filterTask: Task<Void, Never>?

    init(repoName: String,
         source: @escaping () -> (refs: RefSet, inView: (ObjectID) -> Bool, subject: (ObjectID) -> String?),
         onSelect: @escaping (ObjectID) -> Void) {
        self.source = source
        self.onSelect = onSelect
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = L("Tags and heads: %s", repoName)
        window.isReleasedWhenClosed = false
        super.init(window: window)

        for (id, title, width) in [("name", "", 200.0), ("subject", "", 300.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: L("Filter") + ": ")
        filterField.delegate = self
        sortButton.target = self
        sortButton.action = #selector(sortChanged)
        let close = NSButton(title: L("Close"), target: self, action: #selector(closeWindow))
        close.keyEquivalent = "\u{1b}"
        let filterRow = NSStackView(views: [label, filterField])
        let stack = NSStackView(views: [scroll, filterRow, sortButton, close])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView?.addSubview(stack)
        guard let content = window.contentView else { return }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
            filterRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        close.setContentHuggingPriority(.required, for: .vertical)
        reload()
    }

    required init?(coder: NSCoder) { nil }

    /// Show the window, or raise it when already open (gitk `raise $top; refill_reflist`).
    func present() {
        reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Port of gitk proc `refill_reflist` (gitk/gitk 10321–10414).
    func reload() {
        let current = source()
        model.filter = filterField.stringValue
        model.sortByType = sortButton.state == .on
        entries = model.entries(refs: current.refs, inView: current.inView)
        subjects = entries.map { current.subject($0.id) ?? "" }
        table.reloadData()
    }

    @objc private func closeWindow() { window?.close() }
    @objc private func sortChanged() { reload() }

    /// Port of gitk proc `sel_reflist` (gitk/gitk 10262–10277). Entries are
    /// only listed when their commit is in the view, so the selection is valid.
    @objc private func rowClicked() {
        let row = table.clickedRow
        guard entries.indices.contains(row) else { return }
        onSelect(entries[row].id)
    }

    /// Port of gitk proc `reflistfilter_change` (gitk/gitk 10286–10291): 200 ms debounce.
    func controlTextDidChange(_ obj: Notification) {
        filterTask?.cancel()
        filterTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            if !Task.isCancelled { self?.reload() }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row) else { return nil }
        let text = tableColumn?.identifier.rawValue == "subject" ? subjects[row] : entries[row].name
        let field = NSTextField(labelWithString: text)
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}
