// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Port of gitk procs `find_change`, `dofind`, `stopfinding` and the find bar
/// in `makewindow` (gitk/gitk 2560–2580, 4892–4936, 6964–7004).
@MainActor
final class FindBar: NSStackView, NSTextFieldDelegate {
    let field = NSTextField()
    let type = NSPopUpButton()
    let mode = NSPopUpButton()
    let location = NSPopUpButton()
    private let next = NSButton(title: "↓", target: nil, action: nil)
    private let previous = NSButton(title: "↑", target: nil, action: nil)
    let session: ViewSession
    private let engine: FindEngine
    private var task: Task<Void, Never>?
    private var serial = 0
    private(set) var matches = Set<ObjectID>()
    var onMatches: ((Set<ObjectID>, FindQuery) -> Void)?
    var onSelect: ((ObjectID) -> Void)?
    var onBusy: ((Bool) -> Void)?

    init(session: ViewSession) {
        self.session = session
        engine = FindEngine(runner: session.runner)
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 5
        edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        type.addItems(withTitles: [L("containing:"), L("touching paths:"), L("adding/removing string:"), L("changing lines matching:")])
        mode.addItems(withTitles: [L("Exact"), L("IgnCase"), L("Regexp")])
        location.addItems(withTitles: [L("All fields"), L("Headline"), L("Comments"), L("Author"), L("Committer")])
        field.delegate = self
        field.target = self
        field.action = #selector(findNext)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        for popup in [type, mode, location] { popup.target = self; popup.action = #selector(changed) }
        next.target = self
        next.action = #selector(findNext)
        previous.target = self
        previous.action = #selector(findPrevious)
        for view in [NSTextField(labelWithString: L("Find")), next, previous,
                     NSTextField(labelWithString: L("commit")), type, field, mode, location] {
            addArrangedSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var query: FindQuery {
        FindQuery(type: [.containing, .touchingPaths, .addingRemovingString, .changingLinesMatching][max(0, type.indexOfSelectedItem)],
                  matchMode: [.exact, .ignoreCase, .regexp][max(0, mode.indexOfSelectedItem)],
                  field: [.allFields, .headline, .comments, .author, .committer][max(0, location.indexOfSelectedItem)],
                  pattern: field.stringValue)
    }

    func controlTextDidChange(_ obj: Notification) { refresh() }
    @objc private func changed() { refresh() }
    @objc private func findNext() { step(forward: true, wrap: true) }
    @objc private func findPrevious() { step(forward: false, wrap: true) }

    func applySnapshotQuery(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return }
        let kinds = ["containing", "touching paths", "adding/removing string", "changing lines matching"]
        type.selectItem(at: kinds.firstIndex(of: parts[0]) ?? 0)
        mode.selectItem(at: ["Exact", "IgnCase", "Regexp"].firstIndex(of: parts[1]) ?? 0)
        location.selectItem(at: ["All fields", "Headline", "Comments", "Author", "Committer"].firstIndex(of: parts[2]) ?? 0)
        field.stringValue = parts.dropFirst(3).joined(separator: ":")
        refresh()
    }

    func refresh() {
        cancel()
        let generation = serial
        let query = query
        matches = []
        onMatches?(matches, query)
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
                    }
                }
                guard generation == serial else { return }
                onMatches?(matches, query)
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
               let id = session.id(at: row) { onSelect?(id) }
            else { NSSound.beep() }
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
