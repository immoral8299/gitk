// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// The titlebar search strip (design D16), replacing gitk's Commit ID bar and
/// find bar. Left to right: back/forward, the search field, the Advanced (`Aa`)
/// button, the match counter and previous/next match.
///
/// The field has two modes: commit search (gitk's find bar) and go-to-commit
/// (gitk's Commit ID entry), entered with `g` and left with Escape.
@MainActor
final class SearchBar: NSView, NSSearchFieldDelegate, NSPopoverDelegate {
    enum Mode { case search, goToCommit }

    let field = NSSearchField()
    let back = SearchBar.symbolButton("chevron.left", fallback: "←")
    let forward = SearchBar.symbolButton("chevron.right", fallback: "→")
    let advanced = NSButton(title: "Aa", target: nil, action: nil)
    let counter = NSTextField(labelWithString: "")
    let previous = SearchBar.symbolButton("chevron.up", fallback: "↑")
    let next = SearchBar.symbolButton("chevron.down", fallback: "↓")
    /// The Advanced popover's choices (gitk's find type, match mode and field).
    let type = NSPopUpButton()
    let mode = NSPopUpButton()
    let location = NSPopUpButton()

    private(set) var fieldMode: Mode = .search
    private let stack = NSStackView()
    private let popover = NSPopover()
    private let session: ViewSession
    private let engine: FindEngine
    private var task: Task<Void, Never>?
    private var serial = 0
    private var searchText = ""
    private(set) var matches = Set<ObjectID>()

    var onMatches: ((Set<ObjectID>, FindQuery) -> Void)?
    var onSelect: ((ObjectID) -> Void)?
    var onBusy: ((Bool) -> Void)?
    var onGo: ((String) -> Void)?
    var onCommand: ((AppCommand) -> Void)?
    /// Called when Escape leaves the field, so focus can return to the list.
    var onDismiss: (() -> Void)?

    /// Leading space kept free for the traffic lights when the bar is a content row.
    var leadingInset: CGFloat = 0 { didSet { stack.edgeInsets.left = 8 + leadingInset } }

    init(session: ViewSession) {
        self.session = session
        engine = FindEngine(runner: session.runner)
        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 32))
        type.addItems(withTitles: [L("containing:"), L("touching paths:"), L("adding/removing string:"), L("changing lines matching:")])
        mode.addItems(withTitles: [L("Exact"), L("IgnCase"), L("Regexp")])
        location.addItems(withTitles: [L("All fields"), L("Headline"), L("Comments"), L("Author"), L("Committer")])
        for popup in [type, mode, location] { popup.target = self; popup.action = #selector(optionsChanged) }

        field.delegate = self
        field.placeholderString = L("Search commits…")
        field.sendsSearchStringImmediately = true
        field.target = self
        field.action = #selector(fieldAction)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        advanced.bezelStyle = .accessoryBarAction
        advanced.setButtonType(.pushOnPushOff)
        advanced.target = self
        advanced.action = #selector(toggleAdvanced)
        counter.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        counter.textColor = .secondaryLabelColor
        counter.alignment = .right
        counter.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        back.target = self; back.action = #selector(goBack)
        forward.target = self; forward.action = #selector(goForward)
        previous.target = self; previous.action = #selector(findPrevious)
        next.target = self; next.action = #selector(findNext)
        back.isEnabled = false
        forward.isEnabled = false

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.distribution = .fill
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        for view in [Self.cluster(back, forward), field, advanced, counter, Self.cluster(previous, next)] {
            stack.addArrangedSubview(view)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        buildPopover()
        updateCounter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Layout helpers

    private static func symbolButton(_ symbol: String, fallback: String) -> NSButton {
        let button: NSButton
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button = NSButton(image: image, target: nil, action: nil)
        } else {
            button = NSButton(title: fallback, target: nil, action: nil)
        }
        button.bezelStyle = .accessoryBarAction
        button.isBordered = true
        return button
    }

    /// Groups buttons into one tight cluster.
    private static func cluster(_ views: NSView...) -> NSStackView {
        let group = NSStackView(views: views)
        group.orientation = .horizontal
        group.spacing = 0
        return group
    }

    private func buildPopover() {
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: L("Search in")), type],
            [NSTextField(labelWithString: L("Matching")), mode],
            [NSTextField(labelWithString: L("Field")), location],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
        let controller = NSViewController()
        controller.view = content
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
    }

    func popoverDidClose(_ notification: Notification) { advanced.state = .off }

    @objc private func toggleAdvanced() {
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: advanced.bounds, of: advanced, preferredEdge: .maxY)
        advanced.state = .on
    }

    // MARK: Modes

    /// `g` (gitk's Commit ID entry): clear the field and resolve what is typed.
    func enterGoToCommitMode() {
        if fieldMode == .search { searchText = field.stringValue }
        fieldMode = .goToCommit
        field.stringValue = ""
        field.placeholderString = L("Go to commit…")
        window?.makeFirstResponder(field)
    }

    func enterSearchMode(focus: Bool = false) {
        if fieldMode == .goToCommit {
            fieldMode = .search
            field.stringValue = searchText
            field.placeholderString = L("Search commits…")
        }
        if focus { window?.makeFirstResponder(field) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        if fieldMode == .goToCommit {
            enterSearchMode()
        } else if !field.stringValue.isEmpty {
            return false  // NSSearchField clears the text first
        }
        onDismiss?()
        return true
    }

    func controlTextDidChange(_ obj: Notification) {
        if fieldMode == .search { refresh() }
    }

    @objc private func fieldAction() {
        switch fieldMode {
        case .goToCommit:
            let value = field.stringValue.trimmingCharacters(in: .whitespaces)
            enterSearchMode()
            onDismiss?()
            onGo?(value)
        case .search:
            // NSSearchField sends its action on every edit as well; only Return steps.
            if NSApp.currentEvent?.type == .keyDown { step(forward: true, wrap: true) }
        }
    }

    // MARK: Navigation state

    func refresh(session: ViewSession) {
        back.isEnabled = session.selection.history.canGoBack
        forward.isEnabled = session.selection.history.canGoForward
        updateCounter()
    }

    private func updateCounter() {
        guard fieldMode == .search, !query.pattern.isEmpty else {
            counter.stringValue = ""
            return
        }
        let rows = matches.compactMap { session.row(of: $0) }.sorted()
        let current = session.selection.selectedID.flatMap { session.row(of: $0) }
            .flatMap { rows.firstIndex(of: $0) }.map { $0 + 1 }
        counter.stringValue = "\(current ?? 0) / \(rows.count)"
    }

    @objc private func goBack() { onCommand?(.goBack) }
    @objc private func goForward() { onCommand?(.goForward) }
    @objc private func findNext() { step(forward: true, wrap: true) }
    @objc private func findPrevious() { step(forward: false, wrap: true) }
    @objc private func optionsChanged() { refresh() }

    // MARK: Find (gitk dofind/findmore, row level; see FindStepper)

    var query: FindQuery {
        FindQuery(type: [.containing, .touchingPaths, .addingRemovingString, .changingLinesMatching][max(0, type.indexOfSelectedItem)],
                  matchMode: [.exact, .ignoreCase, .regexp][max(0, mode.indexOfSelectedItem)],
                  field: [.allFields, .headline, .comments, .author, .committer][max(0, location.indexOfSelectedItem)],
                  pattern: fieldMode == .search ? field.stringValue : searchText)
    }

    /// Applies `kind:match:field:pattern` from `GITK_SWIFT_FIND` (snapshots).
    func applySnapshotQuery(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return }
        let kinds = ["containing", "touching paths", "adding/removing string", "changing lines matching"]
        type.selectItem(at: kinds.firstIndex(of: parts[0]) ?? 0)
        mode.selectItem(at: ["Exact", "IgnCase", "Regexp"].firstIndex(of: parts[1]) ?? 0)
        location.selectItem(at: ["All fields", "Headline", "Comments", "Author", "Committer"].firstIndex(of: parts[2]) ?? 0)
        enterSearchMode()
        field.stringValue = parts.dropFirst(3).joined(separator: ":")
        refresh()
    }

    func refresh() {
        cancel()
        let generation = serial
        let query = query
        matches = []
        onMatches?(matches, query)
        updateCounter()
        guard !query.pattern.isEmpty else { return }
        onBusy?(true)
        let ids = (0..<session.rowCount).compactMap { session.id(at: $0) }
        task = Task {
            do {
                if query.type == .containing {
                    for (offset, id) in ids.enumerated() {
                        guard !Task.isCancelled, generation == serial else { return }
                        if let index = session.store.index(of: id), query.matches(commit: index, in: session.store) { matches.insert(id) }
                        if offset % 500 == 0 { await Task.yield() }
                    }
                } else {
                    for try await id in engine.start(query: query, cdup: session.repo.cdup, commitIDs: ids) {
                        guard !Task.isCancelled, generation == serial else { return }
                        matches.insert(id)
                        onMatches?(matches, query)
                        updateCounter()
                    }
                }
                guard generation == serial else { return }
                onMatches?(matches, query)
                updateCounter()
                onBusy?(false)
            } catch {
                guard generation == serial else { return }
                onBusy?(false)
                Alerts().errorPopup((error as? GitError)?.stderr ?? String(describing: error), parent: window)
            }
        }
    }

    func step(forward: Bool, wrap: Bool) {
        let generation = serial
        Task {
            await task?.value
            guard generation == serial else { return }
            let rows = Set(matches.compactMap { session.row(of: $0) })
            let current = session.selection.selectedID.flatMap { session.row(of: $0) }
            if let row = FindStepper.nextRow(current: current, rowCount: session.rowCount, matchingRows: rows, forward: forward, wrap: wrap),
               let id = session.id(at: row) {
                onSelect?(id)
                updateCounter()
            } else { NSSound.beep() }
        }
    }

    func waitForSearch() async { await task?.value }

    func cancel() {
        serial += 1
        task?.cancel()
        engine.cancel()
        onBusy?(false)
    }
}
