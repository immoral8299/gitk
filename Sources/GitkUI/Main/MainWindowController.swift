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
    /// The ancestry index for nearby tags and heads (12.x), once loaded.
    private var ancestry: AncestryIndex?
    private var ancestryTask: Task<Void, Never>?
    private var treeTask: Task<Void, Never>?
    private var refListController: RefListWindowController?
    private let cwd: URL
    /// The per-run temp directory (gitk `gitknewtmpdir`), removed on quit.
    private(set) lazy var tempFiles: TempFiles? = try? TempFiles(environment: environment)
    let session: ViewSession
    /// The View menu's list of views and the current one (task 15.4).
    private(set) var viewManager: ViewManager
    private var viewEditor: ViewEditorController?
    /// The view the open editor works on; nil while it still describes a new view.
    private var editingViewNumber: Int?
    /// Runs the row-menu repository actions (cherry-pick, revert, ...), created on first use.
    private(set) lazy var actionCoordinator: RepositoryActionCoordinator = {
        let coordinator = RepositoryActionCoordinator(session: session)
        coordinator.parentWindow = window
        coordinator.onSelect = { [weak self] in self?.select($0) }
        coordinator.onDiffCommits = { [weak self] in self?.showTwoCommitDiff($0) }
        coordinator.onShowReport = { [weak self] in self?.diffPane.showReport($0) }
        coordinator.onMarkChanged = { [weak self] old, new in self?.listController.markChanged(old: old, new: new) }
        return coordinator
    }()
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
    /// The pending sidebar and diff load after keyboard navigation (debounced).
    private var detailsTask: Task<Void, Never>?
    private var requestedID: ObjectID?
    private var initialLoadFinished = false
    var commandHandler: ((AppCommand) -> Void)?
    var commandValidator: ((AppCommand) -> Bool)?
    private(set) var mainMenu: MainMenu?

    /// The store the settings came from; it keeps a corrupt file from being overwritten.
    let settingsStore: SettingsStore?
    /// The settings as loaded; quitting writes only if they changed.
    private let loadedSettings: UISettings

    convenience init(startup: StartupContext, launch: LaunchArguments, settingsStore: SettingsStore, cwd: URL,
                     environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(startup: startup, launch: launch, settings: settingsStore.loadImportingLegacy(), store: settingsStore, cwd: cwd, environment: environment)
    }

    init(startup: StartupContext, launch: LaunchArguments, settings: UISettings, store: SettingsStore? = nil, cwd: URL,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.settingsStore = store
        loadedSettings = settings
        self.startup = startup
        self.launch = launch
        self.settings = settings
        self.environment = environment
        self.cwd = cwd
        let runner = GitRunner(cwd: cwd, baseEnvironment: environment)
        let hasCommandLine = !(launch.revisionArgs.isEmpty && launch.paths.isEmpty)
        viewManager = ViewManager(commandLine: hasCommandLine
            ? ViewSpec(name: ViewManager.commandLineName, args: launch.revisionArgs, files: launch.paths, argsCmd: launch.argsCmd)
            : nil)
        session = ViewSession(repo: startup.repo, runner: runner, view: viewManager.currentView)
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
        sidebar.fileList.onHighlight = { [weak self] path, only in self?.highlightFile(path, only: only) }
        sidebar.fileList.onBlameParent = { [weak self] path in self?.blameParent(of: path) }
        sidebar.fileList.onModeChange = { [weak self] mode in
            self?.settings.cmitMode = mode == .tree ? "tree" : "patch"
            self?.reselectForMode()
        }
        sidebar.fileList.onSelectBlob = { [weak self] path, blob in
            guard let self, let id = session.selection.selectedID else { return }
            diffPane.showBlob(path: path, blob: blob, id: id, session: session)
        }
        if environment["GITK_SWIFT_CMIT_MODE"] == "tree" || settings.cmitMode == "tree" { sidebar.fileList.mode = .tree }
        if let options = environment["GITK_SWIFT_DIFF_OPTIONS"] { diffPane.applySnapshotOptions(options) }
        diffPane.onShowOrigin = { [weak self] id, path, line in
            self?.select(id)
            self?.diffPane.revealLine(path: path, lineNumber: line)
        }
        diffPane.onSectionsChanged = { [weak self] in self?.sidebar.fileList.update($0) }
        // While history is loading, the selected commit's diff goes first.
        diffPane.onLoadingChanged = { [weak self] loading in self?.session.historyPaused = loading }
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
        diffPane.onSelectCommit = { [weak self] in self?.select($0) }
        listController.onRowCommand = { [weak self] command, id in
            guard let self else { return }
            actionCoordinator.perform(command, id: id, selected: session.selection.selectedID)
        }
        listController.onHeadCommand = { [weak self] command, name, id in
            guard let self else { return }
            actionCoordinator.perform(command, id: id, selected: session.selection.selectedID, branchName: name)
        }
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
            self.sidebar.setFind(query, matches: ids)
            self.onFindQueryChanged?(query)
        }
        searchBar.onBusy = { [weak self] searching in
            guard let self else { return }
            if searching { self.statusBar.setSearching() }
            else { self.statusBar.setReading(self.session.isLoading) }
        }
        session.onEvent = { [weak self] in self?.handle($0) }
        window.center()
        restoreGeometry()
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
            if case .showView(let number) = command { return self?.viewManager.current == number }
            return command == .toggleDetailsSidebar ? (self?.splitController.isSidebarShown ?? true) : nil
        }
        refreshViewMenu()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResize(_:)), name: NSWindow.didResizeNotification, object: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidEndLiveResize(_:)), name: NSWindow.didEndLiveResizeNotification, object: window)
        DispatchQueue.main.async { [weak self] in self?.splitController.applyDefaultSidebarWidth() }
    }

    @objc private func windowDidResize(_ notification: Notification) { fitToolbar() }
    @objc private func windowDidEndLiveResize(_ notification: Notification) { saveSettings() }

    /// Puts back the saved window frame, diff height, sidebar width and state, and
    /// the column widths the user set (spec preferences "Persistence").
    private func restoreGeometry() {
        if let saved = settings.windowFrame, let window {
            var frame = NSRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height)
            if let screen = NSScreen.main ?? NSScreen.screens.first {
                frame = window.constrainFrameRect(frame, to: screen)
            }
            window.setFrame(frame, display: false)
        }
        splitView.initialDiffHeight = settings.diffHeight.map { CGFloat($0) }
        splitController.restoredSidebarWidth = settings.sidebarWidth.map { CGFloat($0) }
        if settings.sidebarHidden { splitController.sidebarHiddenByUser = true }
        listController.userAuthorWidth = settings.authorWidth.map { CGFloat($0) }
        listController.userDateWidth = settings.dateWidth.map { CGFloat($0) }
    }

    /// Copies the live geometry into `settings`.
    private func captureGeometry() {
        if let window, !window.isMiniaturized, !window.styleMask.contains(.fullScreen) {
            let f = window.frame
            settings.windowFrame = StoredFrame(x: f.origin.x, y: f.origin.y, width: f.width, height: f.height)
        }
        settings.diffHeight = splitView.diffHeight.map { Double($0) }
        settings.sidebarWidth = Double(splitController.sidebarWidth)
        settings.sidebarHidden = splitController.sidebarHiddenByUser
        settings.authorWidth = listController.userAuthorWidth.map { Double($0) }
        settings.dateWidth = listController.userDateWidth.map { Double($0) }
    }

    /// Writes the settings when they changed (gitk's `savestuff`), never in
    /// snapshot runs. Unchanged defaults are not written, so a first launch does
    /// not block the later legacy gitk config import.
    func saveSettings() {
        guard environment["GITK_SWIFT_SNAPSHOT"] == nil else { return }
        captureGeometry()
        guard settings != loadedSettings else { return }
        // A geometry-only difference must not replace a corrupt settings file.
        var withoutGeometry = settings
        withoutGeometry.geometry = loadedSettings.geometry
        if withoutGeometry != loadedSettings { settingsStore?.markChanged() }
        _ = try? settingsStore?.save(settings)
    }

    /// Port of gitk proc `incrfont` (gitk/gitk 8873–8901): all three fonts grow
    /// or shrink by `delta` points, are redrawn, and the new sizes are saved.
    func changeFontSize(by delta: Int) {
        settings = FontSizing.incremented(settings, by: delta)
        applyFonts()
        saveSettings()
    }

    /// Redraws the list, sidebar and diff pane with the fonts in `settings`
    /// (`setcoords`, `settabs` and `redisplay` of gitk's `incrfont`).
    func applyFonts() {
        let font = MainLayoutMetrics.nsFont(settings.mainFont)
        listController.font = font
        listController.tableView.rowHeight = ceil(font.ascender - font.descender + font.leading) + 2
        listController.settings = settings
        listController.refresh()
        sidebar.settings = settings
        sidebar.fileList.settings = settings
        diffPane.settings = settings
        diffPane.renderAgain()
    }

    private(set) var preferencesController: PreferencesController?

    /// Port of gitk proc `doprefs`: raises the window if it is already open. OK
    /// stores and saves the edited settings and posts `.gitkSettingsDidChange`
    /// (applying them live is task 18.5).
    @discardableResult
    func showPreferences() -> PreferencesController {
        if let existing = preferencesController {
            existing.window?.makeKeyAndOrderFront(nil)
            return existing
        }
        let controller = PreferencesController(settings: settings, hashLength: startup.repo.hashLength)
        controller.onApply = { [weak self] new in
            self?.settings = new
            self?.applyFonts()
            self?.saveSettings()
        }
        controller.onClose = { [weak self] in self?.preferencesController = nil }
        preferencesController = controller
        controller.window?.center()
        controller.showWindow(nil)
        return controller
    }

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
             .goToParent, .scrollList, .focusFind, .findNext, .findPrev, .toggleDetailsSidebar,
             .scrollPane, .nextFile, .prevFile, .listRefs, .preferences,
             .fontBigger, .fontSmaller: return true
        case .newView, .showView: return true
        case .editView: return viewManager.canEdit
        case .deleteView: return viewManager.canDelete
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
        case .listRefs: showRefList()
        case .findNext(let wrap):
            window?.makeFirstResponder(listController.tableView)
            searchBar.step(forward: true, wrap: wrap)
        case .findPrev(let wrap):
            window?.makeFirstResponder(listController.tableView)
            searchBar.step(forward: false, wrap: wrap)
        case .focusCommitID: searchBar.enterGoToCommitMode()
        case .toggleDetailsSidebar: setSidebarHidden(splitController.isSidebarShown)
        case .scrollPane(let step): diffPane.scroll(step)
        case .nextFile: diffPane.jumpFile(forward: true)
        case .prevFile: diffPane.jumpFile(forward: false)
        case .selectPrev, .selectNext, .selectFirst, .selectLast, .selectPageUp, .selectPageDown, .goToParent:
            let parents = session.selection.selectedID.flatMap { session.store.index(of: $0) }
                .map { session.store.parents(of: $0).map { session.store.id(at: $0) } } ?? []
            let next = session.selection.navigating(command, rows: rowIDs(), parents: parents, pageSize: listController.pageSize)
            if let id = next.selectedID { select(id, deferDetails: true) }
        case .scrollList(let step): listController.scroll(step)
        case .goBack: stepHistory(forward: false)
        case .goForward: stepHistory(forward: true)
        case .quit: NSApp.terminate(nil)
        // ⌘-W in the main window quits (gitk binds it to doquit); other windows close.
        case .closeWindow:
            if NSApp.keyWindow == nil || NSApp.keyWindow === window { NSApp.terminate(nil) }
            else { NSApp.keyWindow?.performClose(nil) }
        case .about: NSApp.orderFrontStandardAboutPanel(nil)
        case .preferences: showPreferences()
        case .fontBigger: changeFontSize(by: 1)
        case .fontSmaller: changeFontSize(by: -1)
        case .newView: openViewEditor(editing: nil)
        case .editView: openViewEditor(editing: viewManager.canEdit ? viewManager.current : nil)
        case .deleteView: deleteCurrentView()
        case .showView(let number):
            if let change = viewManager.switchTo(number, selected: session.selection.selectedID) { show(change) }
        default: commandHandler?(command)
        }
    }

    // MARK: Views

    /// Rebuilds the View menu's view entries; the names of the built-in views are translated.
    private func refreshViewMenu() {
        mainMenu?.setViews(viewManager.entries.map {
            ($0.number, $0.isBuiltIn ? L($0.spec.name) : $0.spec.name)
        })
    }

    /// The load half of gitk proc `showview` (gitk/gitk 4668–4765): the new view loads and
    /// the previously selected commit stays selected when the view contains it.
    private func show(_ change: ViewManager.Switch) {
        requestedID = change.requestedID
        refreshViewMenu()
        loadTask = Task { await session.load(view: change.view) }
    }

    /// Port of gitk procs `newview`, `editview` (gitk/gitk 4286–4303, 4440–4452).
    private func openViewEditor(editing number: Int?) {
        if let viewEditor { viewEditor.present(); return }
        let editor: ViewEditorController
        let alerts = Alerts(environment: environment)
        if let number, let entry = viewManager.entry(number) {
            editingViewNumber = number
            editor = ViewEditorController(view: entry.spec, alerts: alerts)
        } else {
            editingViewNumber = nil
            let prefill = ViewSpec(
                name: "\(L("View")) \(viewManager.nextNumber)", args: launch.revisionArgs,
                argsCmd: viewManager.currentView.argsCmd)
            editor = ViewEditorController(view: prefill, title: L("Gitk view definition"), alerts: alerts)
        }
        editor.onApply = { [weak self] in self?.applyView($0) }
        editor.onClose = { [weak self] in self?.viewEditor = nil }
        viewEditor = editor
        editor.present()
    }

    /// The model half of gitk proc `newviewok` (gitk/gitk 4576–4630): a new view is added and
    /// shown; an edited view is replaced and, being the current one, reloaded.
    private func applyView(_ spec: ViewSpec) {
        if let number = editingViewNumber {
            viewManager.replace(number, with: spec)
            requestedID = session.selection.selectedID
            refreshViewMenu()
            if number == viewManager.current { loadTask = Task { await session.load(view: spec) } }
        } else {
            let number = viewManager.add(spec)
            editingViewNumber = number
            if let change = viewManager.switchTo(number, selected: session.selection.selectedID) { show(change) }
        }
    }

    private func deleteCurrentView() {
        guard let result = viewManager.deleteCurrent(selected: session.selection.selectedID) else { return }
        show(result.switched)
    }

    func startLoading() {
        loadTask = Task {
            if let requested = launch.selectCommit {
                if let output = try? await session.runner.run(["rev-parse", "--verify", requested + "^{commit}"]) {
                    requestedID = ObjectID(hex: String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            await session.load()
            loadAncestry()
            initialLoadFinished = true
            if let snapshotQuery = environment["GITK_SWIFT_FIND"] {
                searchBar.applySnapshotQuery(snapshotQuery)
            } else { searchBar.refresh() }
            if environment["GITK_SWIFT_FIND_POPOVER"] == "1" { searchBar.showAdvanced() }
        }
    }

    /// Port of gitk proc `doquit` (gitk/gitk 11610–11623): stop the loaders and
    /// git children, save the settings, and remove the temp directory.
    func stop() async {
        detailsTask?.cancel()
        diffPane.cancel()
        searchBar.cancel()
        ancestryTask?.cancel()
        loadTask?.cancel()
        await session.cancel()
        saveSettings()
        try? tempFiles?.cleanup()
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
        case .refsChanged:
            listController.refresh()
            refListController?.reload()
        }
    }

    /// - Parameter deferDetails: keyboard navigation moves the selection at
    ///   once but loads the sidebar and diff only once the keys have been
    ///   quiet for `detailsDelay`, so holding an arrow key does not start a
    ///   `git diff-tree` and a sidebar rebuild for every row passed.
    func select(_ id: ObjectID, record: Bool = true, deferDetails: Bool = false) {
        guard session.row(of: id) != nil else { return }
        session.selection = session.selection.selecting(id, scrollPosition: currentDiffScrollPosition(), record: record || session.selection.history.entries.isEmpty)
        listController.restoreSelection(scroll: true)
        splitView.showsDiffPane = true
        refreshBars()
        detailsTask?.cancel()
        detailsTask = nil
        if deferDetails {
            let delay = Self.detailsDelay(keyRepeatInterval: NSEvent.keyRepeatInterval)
            detailsTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled, session.selection.selectedID == id else { return }
                detailsTask = nil
                showDetails(id)
            }
        } else {
            showDetails(id)
        }
        if settings.autoCopy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(id.abbreviated(settings.autoSelLen), forType: .string)
        }
        onSelection?(id)
    }

    /// How long keyboard navigation waits before loading details: two key
    /// repeats (so a held key never loads), at least 150 ms and at most 350 ms
    /// (so a single press still feels immediate with a slow repeat rate).
    nonisolated static func detailsDelay(keyRepeatInterval: TimeInterval) -> Duration {
        .milliseconds(Int((min(0.35, max(0.15, keyRepeatInterval * 2)) * 1000).rounded()))
    }

    /// Port of the display half of gitk proc `selectline` (gitk/gitk 7560–7666):
    /// fill the sidebar and stream the patch into the diff pane.
    private func showDetails(_ id: ObjectID) {
        guard sidebar.shownID != id || diffPane.ids != [id], let index = session.store.index(of: id) else { return }
        sidebar.show(DetailsHeaderBuilder.build(commit: index, session: session, dateFormat: settings.dateTimeFormat), session: session)
        sidebar.nearby = nearby(for: id)
        showFiles(id)
    }

    /// Port of gitk proc `flist_hl` (gitk/gitk 3700–3708).
    func highlightFile(_ path: String, only: Bool) {
        let query = searchBar.query
        let pattern = FileMenu.highlightPattern(path: path, only: only, currentPattern: query.pattern,
                                                currentIsTouchingPaths: query.type == .touchingPaths)
        searchBar.setSearch(type: 1, mode: searchBar.mode.indexOfSelectedItem,
                            field: searchBar.location.indexOfSelectedItem, pattern: pattern)
    }

    /// Port of gitk proc `external_blame` with parent index 1 (gitk/gitk 4003–4031).
    func blameParent(of path: String) {
        let parent = session.selection.selectedID.flatMap { LineOrigin.parents(of: $0, in: session).first }
        guard let arguments = FileMenu.blameArguments(base: parent, path: path, cdup: session.repo.cdup,
                                                      hashLength: session.repo.hashLength) else {
            Alerts().errorPopup(L("No such commit"), parent: window)
            return
        }
        actionCoordinator.launchGitTool(arguments)
    }

    /// The bottom pane and file list for `id` in the current Patch/Tree mode
    /// (gitk's `selectline` ending in `gettree`/`gettreediffs`).
    private func showFiles(_ id: ObjectID) {
        treeTask?.cancel()
        guard sidebar.fileList.mode == .tree else {
            diffPane.show(id, session: session)
            return
        }
        diffPane.showEmpty(id: id, session: session)
        sidebar.fileList.setOutline(nil)
        let runner = session.runner
        treeTask = Task { [weak self] in
            guard let outline = try? await TreeOutline.load(id: id, runner: runner), !Task.isCancelled,
                  let self, session.selection.selectedID == id, sidebar.fileList.mode == .tree else { return }
            sidebar.fileList.setOutline(outline)
            if let path = environment["GITK_SWIFT_TREE_FILE"], let blob = outline.objectID(ofFile: path) {
                var opened = outline
                opened.reveal(path)
                sidebar.fileList.setOutline(opened, selecting: path)
                diffPane.showBlob(path: path, blob: blob, id: id, session: session)
            }
        }
    }

    /// The Patch/Tree switch re-selects the commit (gitk's `changemode` → `reselectline`).
    private func reselectForMode() {
        guard let id = session.selection.selectedID else { return }
        showFiles(id)
    }

    private func nearby(for id: ObjectID) -> DetailsSidebar.Nearby {
        guard settings.showNearTags else { return .hidden }
        guard let ancestry, ancestry.isComplete else { return .pending }
        return .ready(NearbyRefs(id: id, index: ancestry, maxRefs: settings.maxRefs, visibleRefs: settings.visibleRefs))
    }

    /// Port of gitk proc `getallcommits` as used by `dispneartags`: build (or
    /// read from `<gitdir>/gitk-swift.cache`) the ancestry index in the
    /// background, then fill the selected commit's nearby refs (12.5).
    private func loadAncestry() {
        guard settings.showNearTags, ancestryTask == nil else { return }
        let gitDir = URL(fileURLWithPath: startup.repo.gitDir, relativeTo: cwd).standardizedFileURL
        let runner = GitRunner(cwd: cwd, baseEnvironment: environment)
        ancestryTask = Task { [weak self] in
            let refs = await RefParser.load(runner: runner)
            let index = AncestryIndex(refs: refs, gitDir: gitDir)
            _ = try? await index.load(runner: runner)
            guard let self, !Task.isCancelled else { return }
            ancestry = index
            if let id = sidebar.shownID { sidebar.nearby = nearby(for: id) }
        }
    }

    /// Port of gitk proc `doseldiff` (gitk/gitk 9399–9424): the sidebar names
    /// both commits and the bottom pane shows the diff between them.
    func showTwoCommitDiff(_ diff: TwoCommitDiff) {
        detailsTask?.cancel()
        detailsTask = nil
        treeTask?.cancel()
        splitView.showsDiffPane = true
        sidebar.show(diff: diff, session: session)
        diffPane.showDiff(from: diff.old, to: diff.new, session: session)
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

    /// Port of gitk proc `showrefs` (gitk/gitk 10209–10260): one window, raised if open.
    private func showRefList() {
        if refListController == nil {
            refListController = RefListWindowController(
                repoName: Self.repoName(gitDir: startup.repo.gitDir, cwd: cwd),
                source: { [unowned self] in
                    (session.refs, { [session] in session.row(of: $0) != nil },
                     { [session] id in session.store.index(of: id).map { session.store.headline(at: $0) } })
                },
                onSelect: { [unowned self] in select($0) })
            if let saved = settings.refListFrame, let refWindow = refListController?.window {
                refWindow.setFrame(NSRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height), display: false)
            }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(refListFrameChanged(_:)), name: name, object: refListController?.window)
            }
        }
        refListController?.present()
    }

    @objc private func refListFrameChanged(_ notification: Notification) {
        guard let f = refListController?.window?.frame else { return }
        settings.refListFrame = StoredFrame(x: f.origin.x, y: f.origin.y, width: f.width, height: f.height)
    }

    func setWindowTitle(cwd: URL) {
        window?.title = Self.windowTitle(
            repoName: Self.repoName(gitDir: startup.repo.gitDir, cwd: cwd),
            revisionArgs: launch.revisionArgs, allFiles: L("All files"))
    }
}
