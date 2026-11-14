// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Owns the main window (gitk's `.`) and its `MainSplitView`.
@MainActor
final class MainWindowController: NSWindowController {
    nonisolated static let appName = "gitk"

    let startup: StartupContext
    let launch: LaunchArguments
    var settings: UISettings
    let splitView: MainSplitView
    let session: ViewSession
    let listController: CommitListController
    let commitIDBar: CommitIDBar
    let findBar: FindBar
    var onFindQueryChanged: ((FindQuery) -> Void)?
    let environment: [String: String]
    var onSelection: ((ObjectID) -> Void)?
    var currentDiffScrollPosition: () -> Double = { 0 }
    var restoreDiffScrollPosition: (Double) -> Void = { _ in }
    private var loadTask: Task<Void, Never>?
    private var requestedID: ObjectID?
    private var initialLoadFinished = false
    var commandHandler: ((AppCommand) -> Void)?
    var commandValidator: ((AppCommand) -> Bool)?
    private(set) var mainMenu: MainMenu?

    init(startup: StartupContext, launch: LaunchArguments, settings: UISettings, cwd: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.startup = startup
        self.launch = launch
        self.settings = settings
        self.environment = environment
        let runner = GitRunner(cwd: cwd, baseEnvironment: environment)
        session = ViewSession(repo: startup.repo, runner: runner,
            view: ViewSpec(name: launch.revisionArgs.isEmpty && launch.paths.isEmpty ? "All files" : "Command line",
                           args: launch.revisionArgs, files: launch.paths, argsCmd: launch.argsCmd))
        session.showLocalChanges = settings.showLocalChanges
        session.hideRemotes = settings.hideRemotes
        session.refsToHide = settings.refsToHide
        listController = CommitListController(session: session, font: MainLayoutMetrics.nsFont(settings.mainFont))
        listController.dateFormat = settings.dateTimeFormat
        findBar = FindBar(session: session)
        commitIDBar = CommitIDBar(font: MainLayoutMetrics.nsFont(settings.textFont))
        let metrics = MainLayoutMetrics(mainFont: settings.mainFont)
        splitView = MainSplitView(
            metrics: metrics, uiFont: MainLayoutMetrics.nsFont(settings.uiFont))
        let window = KeyRouter(
            contentRect: NSRect(origin: .zero, size: metrics.windowContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.contentView = splitView
        window.contentMinSize = NSSize(width: 200, height: 200)
        window.isReleasedWhenClosed = false
        Chrome.decorate(window)
        super.init(window: window)
        splitView.installHistory(listController.scrollView, commitBar: commitIDBar, findBar: findBar)
        listController.onSelection = { [weak self] in self?.select($0) }
        commitIDBar.onCommand = { [weak self] in self?.perform($0) }
        commitIDBar.onGo = { [weak self] value in Task { await self?.goToCommit(value) } }
        findBar.onSelect = { [weak self] in self?.select($0) }
        findBar.onMatches = { [weak self] ids, query in
            guard let self else { return }
            self.listController.highlightedIDs = ids
            self.listController.findQuery = query
            self.listController.refresh()
            self.onFindQueryChanged?(query)
        }
        findBar.onBusy = { [weak self] searching in
            guard let self else { return }
            if searching { self.commitIDBar.status.setSearching() }
            else { self.commitIDBar.status.setReading(self.session.isLoading) }
        }
        session.onEvent = { [weak self] in self?.handle($0) }
        window.center()
        setWindowTitle(cwd: cwd)
        window.commandHandler = { [weak self] command in
            guard let self, self.canPerform(command) else { return false }
            self.perform(command)
            return true
        }
        mainMenu = MainMenu(
            dispatch: { [weak self] in self?.perform($0) },
            isEnabled: { [weak self] in self?.canPerform($0) ?? false })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Port of gitk proc `reponame` (gitk/gitk 250–258): the last component of
    /// the normalized git directory, with a trailing `/.git` removed.
    nonisolated static func repoName(gitDir: String, cwd: URL) -> String {
        var path = URL(fileURLWithPath: gitDir, relativeTo: cwd).standardizedFileURL.path
        if path.hasSuffix("/.git") { path.removeLast(5) }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// Port of gitk proc `set_window_title` (gitk/gitk 4271–4286):
    /// `"<reponame>: <rev> - gitk"`. `<rev>` is "All files" for the default view,
    /// or the command-line revision arguments (the "Command line" view), with
    /// `--gitk-symmetric-diff-marker` shown as `--merge`.
    nonisolated static func windowTitle(repoName: String, revisionArgs: [String], allFiles: String) -> String {
        let rev: String
        if revisionArgs.isEmpty {
            rev = allFiles
        } else {
            rev = revisionArgs.joined(separator: " ")
                .replacingOccurrences(of: "--gitk-symmetric-diff-marker", with: "--merge")
        }
        return "\(repoName): \(rev) - \(appName)"
    }

    func canPerform(_ command: AppCommand) -> Bool {
        switch command {
        case .quit, .closeWindow, .about, .update, .reload, .rereadRefs, .focusCommitID,
             .selectPrev, .selectNext, .selectFirst, .selectLast, .selectPageUp, .selectPageDown,
             .goToParent, .scrollList, .focusFind, .findNext, .findPrev: return true
        case .goBack: return session.selection.history.canGoBack
        case .goForward: return session.selection.history.canGoForward
        default: return commandValidator?(command) ?? (commandHandler != nil)
        }
    }

    func perform(_ command: AppCommand) {
        switch command {
        case .update: loadTask = Task { await session.update() }
        case .reload: loadTask = Task { await session.reload() }
        case .rereadRefs: Task { await session.readReferences() }
        case .focusFind: window?.makeFirstResponder(findBar.field)
        case .findNext(let wrap):
            window?.makeFirstResponder(listController.tableView)
            findBar.step(forward: true, wrap: wrap)
        case .findPrev(let wrap):
            window?.makeFirstResponder(listController.tableView)
            findBar.step(forward: false, wrap: wrap)
        case .focusCommitID:
            commitIDBar.field.stringValue = ""
            window?.makeFirstResponder(commitIDBar.field)
        case .selectPrev, .selectNext, .selectFirst, .selectLast, .selectPageUp, .selectPageDown, .goToParent:
            let parents = session.selection.selectedID.flatMap { session.store.index(of: $0) }
                .map { session.store.parents(of: $0).map { session.store.id(at: $0) } } ?? []
            let next = session.selection.navigating(command, rows: rowIDs(), parents: parents, pageSize: listController.pageSize)
            if let id = next.selectedID { select(id) }
        case .scrollList(let step): listController.scroll(step)
        case .goBack: stepHistory(forward: false)
        case .goForward: stepHistory(forward: true)
        case .quit: NSApp.terminate(nil)
        case .closeWindow: NSApp.keyWindow?.performClose(nil)
        case .about: NSApp.orderFrontStandardAboutPanel(nil)
        default: commandHandler?(command)
        }
    }

    func startLoading() {
        loadTask = Task {
            if let requested = launch.selectCommit {
                if let output = try? await session.runner.run(["rev-parse", "--verify", requested + "^{commit}"]) {
                    requestedID = ObjectID(hex: String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            await session.load()
            initialLoadFinished = true
            if let snapshotQuery = environment["GITK_SWIFT_FIND"] {
                findBar.applySnapshotQuery(snapshotQuery)
            } else { findBar.refresh() }
        }
    }

    func stop() async {
        findBar.cancel()
        loadTask?.cancel()
        await session.cancel()
    }

    func waitForSnapshot(early: Bool) async {
        if early {
            while session.rowCount == 0 && !initialLoadFinished && session.errorMessage == nil {
                if loadTask?.isCancelled == true { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
        } else { await loadTask?.value; await findBar.waitForSearch() }
        window?.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
    }

    private func rowIDs() -> [ObjectID] { (0..<session.rowCount).compactMap { session.id(at: $0) } }

    private func handle(_ event: ViewSession.Event) {
        switch event {
        case .loadStarted: commitIDBar.status.setReading(true)
        case .loadProgress(let count): commitIDBar.status.setReading(true, count: count)
        case .rowsChanged:
            listController.refresh()
            if let selected = session.selection.selectedID, session.row(of: selected) != nil {
                commitIDBar.refresh(session: session)
            } else if let first = session.id(at: 0) {
                let preferred = requestedID ?? session.refs.mainHeadID
                select(preferred.flatMap { session.row(of: $0) != nil ? $0 : nil } ?? first, record: false)
            }
        case .loadFinished:
            listController.refresh()
            if let requestedID, session.row(of: requestedID) != nil { select(requestedID, record: false) }
            else if session.selection.selectedID == nil, let first = session.id(at: 0) { select(first, record: false) }
            commitIDBar.refresh(session: session)
            commitIDBar.status.setReading(false)
        case .loadFailed(let message):
            commitIDBar.status.setReading(false)
            Alerts(environment: environment).errorPopup(message, parent: window)
        case .refsChanged: listController.refresh()
        }
    }

    func select(_ id: ObjectID, record: Bool = true) {
        guard session.row(of: id) != nil else { return }
        session.selection = session.selection.selecting(id, scrollPosition: currentDiffScrollPosition(), record: record || session.selection.history.entries.isEmpty)
        listController.restoreSelection(scroll: true)
        commitIDBar.refresh(session: session)
        if settings.autoCopy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(id.abbreviated(settings.autoSelLen), forType: .string)
        }
        onSelection?(id)
    }

    private func stepHistory(forward: Bool) {
        let history = session.selection.history.stepping(forward: forward, saving: currentDiffScrollPosition())
        guard let entry = history.current else { return }
        let id: ObjectID
        switch entry.target { case .commit(let value), .link(let value), .line(let value, _): id = value }
        session.selection.history = history
        select(id, record: false)
        restoreDiffScrollPosition(entry.scrollPosition)
    }

    private func goToCommit(_ value: String) async {
        guard !value.isEmpty else { return }
        do {
            select(try await CommitResolver.resolve(value, inView: rowIDs(), runner: session.runner))
        } catch let error as CommitResolutionError {
            Alerts(environment: environment).errorPopup(L(error.msgid, error.value), parent: window)
        } catch {
            Alerts(environment: environment).errorPopup(String(describing: error), parent: window)
        }
    }

    func setWindowTitle(cwd: URL) {
        window?.title = Self.windowTitle(
            repoName: Self.repoName(gitDir: startup.repo.gitDir, cwd: cwd),
            revisionArgs: launch.revisionArgs, allFiles: L("All files"))
    }
}
