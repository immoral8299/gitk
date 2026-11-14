// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Owns the main window (gitk's `.`) and its `MainSplitView` (design D16).
@MainActor
final class MainWindowController: NSWindowController {
    nonisolated static let appName = "gitk"

    let startup: StartupContext
    let launch: LaunchArguments
    var settings: UISettings
    let splitController: MainSplitController
    /// The content column: search row (no unified titlebar), list, diff, status.
    var splitView: MainSplitView { splitController.content }
    private var searchToolbar: SearchToolbar?
    let session: ViewSession
    let listController: CommitListController
    let searchBar: SearchBar
    let diffPane: DiffPane
    var sidebar: DetailsSidebar { splitController.sidebar }
    var statusBar: StatusBar { splitView.statusBar }
    /// True when the search bar is in a unified titlebar rather than a content row.
    let unifiedTitlebar: Bool
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
        listController.settings = settings
        searchBar = SearchBar(session: session)
        diffPane = DiffPane(settings: settings, hashLength: startup.repo.hashLength)
        let metrics = MainLayoutMetrics(mainFont: settings.mainFont)
        splitController = MainSplitController(metrics: metrics)
        unifiedTitlebar = Chrome.usesUnifiedTitlebar(environment: environment)
        let window = KeyRouter(
            contentRect: NSRect(origin: .zero, size: metrics.windowContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.contentViewController = splitController
        window.setContentSize(metrics.windowContentSize)
        window.contentMinSize = NSSize(width: 360, height: 200)
        window.isReleasedWhenClosed = false
        Chrome.decorate(window)
        if unifiedTitlebar {
            let toolbar = SearchToolbar(bar: searchBar)
            searchToolbar = toolbar
            Chrome.installUnifiedTitlebar(window, toolbar: toolbar.toolbar)
        } else {
            splitController.content.installSearchRow(searchBar)
        }
        super.init(window: window)
        searchToolbar?.onToggleSidebar = { [weak self] in self?.perform(.toggleDetailsSidebar) }
        splitView.installList(listController.scrollView)
        splitView.installDiff(diffPane.view)
        sidebar.settings = settings
        sidebar.onCommitLink = { [weak self] in self?.followLink($0) }
        sidebar.fileList.settings = settings
        if environment["GITK_SWIFT_FILE_LAYOUT"] == "tree" { sidebar.fileList.layout = .tree }
        sidebar.fileList.onSelectFile = { [weak self] in self?.diffPane.jumpToFile($0) }
        if let options = environment["GITK_SWIFT_DIFF_OPTIONS"] { diffPane.applySnapshotOptions(options) }
        diffPane.onSectionsChanged = { [weak self] in self?.sidebar.fileList.update($0) }
        diffPane.onTopSectionChanged = { [weak self] in self?.sidebar.fileList.highlight($0) }
        currentDiffScrollPosition = { [weak self] in
            Double(self?.diffPane.scrollView.contentView.bounds.minY ?? 0)
        }
        restoreDiffScrollPosition = { [weak self] y in
            guard let clip = self?.diffPane.scrollView.contentView else { return }
            clip.scroll(to: NSPoint(x: 0, y: y))
            self?.diffPane.scrollView.reflectScrolledClipView(clip)
        }
        listController.onSelection = { [weak self] in self?.select($0) }
        searchBar.onCommand = { [weak self] in self?.perform($0) }
        searchBar.onGo = { [weak self] value in Task { await self?.goToCommit(value) } }
        searchBar.onDismiss = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.listController.tableView)
        }
        searchBar.onSelect = { [weak self] in self?.select($0) }
        searchBar.onMatches = { [weak self] ids, query in
            guard let self else { return }
            self.listController.highlightedIDs = ids
            self.listController.findQuery = query
            self.listController.refresh()
            self.onFindQueryChanged?(query)
        }
        searchBar.onBusy = { [weak self] searching in
            guard let self else { return }
            if searching { self.statusBar.setSearching() }
            else { self.statusBar.setReading(self.session.isLoading) }
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
        mainMenu?.isChecked = { [weak self] command in
            command == .toggleDetailsSidebar ? (self?.splitController.isSidebarShown ?? true) : nil
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResize(_:)), name: NSWindow.didResizeNotification, object: window)
        DispatchQueue.main.async { [weak self] in self?.splitController.applyDefaultSidebarWidth() }
    }

    @objc private func windowDidResize(_ notification: Notification) { fitToolbar() }

    /// Gives the titlebar search field the width of the content column.
    func fitToolbar() {
        searchToolbar?.fit(contentWidth: splitView.bounds.width)
    }

    /// View→Details Sidebar and the toolbar toggle.
    func setSidebarHidden(_ hidden: Bool) {
        splitController.sidebarHiddenByUser = hidden
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
             .goToParent, .scrollList, .focusFind, .findNext, .findPrev, .toggleDetailsSidebar: return true
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
        case .focusFind: searchBar.enterSearchMode(focus: true)
        case .findNext(let wrap):
            window?.makeFirstResponder(listController.tableView)
            searchBar.step(forward: true, wrap: wrap)
        case .findPrev(let wrap):
            window?.makeFirstResponder(listController.tableView)
            searchBar.step(forward: false, wrap: wrap)
        case .focusCommitID: searchBar.enterGoToCommitMode()
        case .toggleDetailsSidebar: setSidebarHidden(splitController.isSidebarShown)
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
                searchBar.applySnapshotQuery(snapshotQuery)
            } else { searchBar.refresh() }
        }
    }

    func stop() async {
        searchBar.cancel()
        loadTask?.cancel()
        await session.cancel()
    }

    func waitForSnapshot(early: Bool) async {
        if early {
            while session.rowCount == 0 && !initialLoadFinished && session.errorMessage == nil {
                if loadTask?.isCancelled == true { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
        } else {
            await loadTask?.value
            await searchBar.waitForSearch()
            await diffPane.waitUntilLoaded()
        }
        fitToolbar()
        window?.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
    }

    private func rowIDs() -> [ObjectID] { (0..<session.rowCount).compactMap { session.id(at: $0) } }

    private func handle(_ event: ViewSession.Event) {
        switch event {
        case .loadStarted: statusBar.setReading(true)
        case .loadProgress(let count): statusBar.setReading(true, count: count)
        case .rowsChanged:
            listController.refresh()
            if let selected = session.selection.selectedID, session.row(of: selected) != nil {
                refreshBars()
            } else if let first = session.id(at: 0) {
                let preferred = requestedID ?? session.refs.mainHeadID
                select(preferred.flatMap { session.row(of: $0) != nil ? $0 : nil } ?? first, record: false)
            }
        case .loadFinished:
            listController.refresh()
            if let requestedID, session.row(of: requestedID) != nil { select(requestedID, record: false) }
            else if session.selection.selectedID == nil, let first = session.id(at: 0) { select(first, record: false) }
            refreshBars()
            statusBar.setReading(false)
        case .loadFailed(let message):
            statusBar.setReading(false)
            Alerts(environment: environment).errorPopup(message, parent: window)
        case .refsChanged: listController.refresh()
        }
    }

    func select(_ id: ObjectID, record: Bool = true) {
        guard session.row(of: id) != nil else { return }
        session.selection = session.selection.selecting(id, scrollPosition: currentDiffScrollPosition(), record: record || session.selection.history.entries.isEmpty)
        listController.restoreSelection(scroll: true)
        splitView.showsDiffPane = true
        refreshBars()
        showDetails(id)
        if settings.autoCopy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(id.abbreviated(settings.autoSelLen), forType: .string)
        }
        onSelection?(id)
    }

    /// Port of the display half of gitk proc `selectline` (gitk/gitk 7560–7666):
    /// fill the sidebar and stream the patch into the diff pane.
    private func showDetails(_ id: ObjectID) {
        guard sidebar.shownID != id || diffPane.ids != [id], let index = session.store.index(of: id) else { return }
        sidebar.show(DetailsHeaderBuilder.build(commit: index, session: session, dateFormat: settings.dateTimeFormat), session: session)
        diffPane.show(id, session: session)
    }

    /// A commit link in the sidebar (commit-details "Revert message link").
    private func followLink(_ id: ObjectID) {
        guard session.row(of: id) != nil else { return }
        select(id)
    }

    private func refreshBars() {
        if session.selection.selectedID.flatMap({ session.row(of: $0) }) == nil {
            splitView.showsDiffPane = false
            sidebar.clear()
            diffPane.clear()
        }
        statusBar.refresh(session: session)
        searchBar.refresh(session: session)
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
