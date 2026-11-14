// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import Foundation

@MainActor
public final class ViewSession {
    public enum Event {
        case loadStarted
        case rowsChanged(Range<Int>)
        case refsChanged
        case loadProgress(Int)
        case loadFinished
        case loadFailed(String)
    }
    public let repo: RepoContext
    public let runner: GitRunner
    public private(set) var store: CommitStore
    public private(set) var ordering: VarcOrdering
    public private(set) var layout: GraphLayout
    public private(set) var refs = RefSet()
    public private(set) var view: ViewSpec
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var selection = SelectionModel()
    public var showLocalChanges = true
    public var hideRemotes = false
    public var refsToHide = ""
    public var onEvent: ((Event) -> Void)?
    private let loader: HistoryLoader
    private var request: UInt64 = 0
    private var resolved: ResolvedView?

    public init(repo: RepoContext, runner: GitRunner, view: ViewSpec) {
        self.repo = repo
        self.runner = runner
        self.view = view
        let store = CommitStore(fallbackEncoding: repo.gitEncoding)
        self.store = store
        let ordering = VarcOrdering(store: store, hashLength: repo.hashLength)
        self.ordering = ordering
        self.layout = GraphLayout(ordering: ordering)
        self.loader = HistoryLoader(runner: runner)
    }

    public var rowCount: Int { ordering.commitIdx }
    public func commit(at row: Int) -> CommitIndex? { ordering.commitOnRow(row) }
    public func row(of id: ObjectID) -> Int? {
        guard let index = store.index(of: id) else { return nil }
        return ordering.rowOfCommit(index)
    }
    public func id(at row: Int) -> ObjectID? { commit(at: row).map { store.id(at: $0) } }

    /// Port of gitk procs `getcommits`, `reloadcommits` (gitk/gitk 720–860).
    public func load(view newView: ViewSpec? = nil) async {
        request &+= 1
        let token = request
        await loader.cancel()
        guard token == request else { return }
        if let newView { view = newView }
        store = CommitStore(fallbackEncoding: repo.gitEncoding)
        ordering = VarcOrdering(store: store, hashLength: repo.hashLength)
        layout = GraphLayout(ordering: ordering)
        resolved = nil
        await readReferences()
        guard token == request else { return }
        await runLoad(token: token, incremental: false)
    }

    public func reload() async { await load() }

    /// Port of gitk proc `updatecommits` (gitk/gitk 735–817).
    public func update() async {
        if isLoading { await reload(); return }
        request &+= 1
        let token = request
        await readReferences()
        guard token == request else { return }
        removeLocalRows()
        await runLoad(token: token, incremental: true)
    }

    /// Port of gitk procs `rereadrefs`, `changedrefs` (gitk/gitk 11482–11538).
    public func readReferences() async {
        let token = request
        let next = await RefParser.load(runner: runner, hideRemotes: hideRemotes, refsToHide: refsToHide)
        guard token == request else { return }
        refs = next
        onEvent?(.refsChanged)
    }

    public func cancel() async {
        request &+= 1
        isLoading = false
        await loader.cancel()
    }

    public func ingest(batch: HistoryBatch) {
        let oldCount = rowCount
        for commit in batch.commits { ordering.add(commit) }
        onEvent?(.rowsChanged(0..<max(oldCount, rowCount)))
        onEvent?(.loadProgress(rowCount))
    }

    private func runLoad(token: UInt64, incremental: Bool) async {
        isLoading = true
        layout.viewComplete = false
        errorMessage = nil
        onEvent?(.loadStarted)
        do {
            var next = try await view.resolve(hashLength: repo.hashLength, runner: runner)
            guard token == request else { return }
            let original = next
            ordering.vdateMode = next.parsed.dateMode
            if incremental, let previous = resolved, next.parsed.canOpt,
               previous.negIDs == next.negIDs {
                next.revs += previous.posIDs.map { "^" + $0 }
            }
            let stream = await loader.start(resolved: next, hashLength: repo.hashLength)
            guard token == request else { return }
            for try await batch in stream {
                guard token == request else { return }
                ingest(batch: batch)
            }
            guard token == request else { return }
            ordering.closeVarcs()
            layout.viewComplete = true
            resolved = original
            guard token == request else { return }
            await refreshLocalChanges()
            guard token == request else { return }
            onEvent?(.rowsChanged(0..<rowCount))
            isLoading = false
            onEvent?(.loadFinished)
        } catch {
            guard token == request else { return }
            ordering.closeVarcs()
            layout.viewComplete = true
            isLoading = false
            if error is CancellationError { return }
            let detail = (error as? GitError)?.stderr ?? String(describing: error)
            errorMessage = "Error executing git log: \(detail)"
            onEvent?(.loadFailed(errorMessage ?? detail))
        }
    }

    private func removeLocalRows() {
        for id in [ObjectID.localUnstaged(hashLength: repo.hashLength), ObjectID.localStaged(hashLength: repo.hashLength)].compactMap({ $0 }) {
            if let index = store.index(of: id), ordering.commitInView(index) { ordering.removeFakeRow(index) }
        }
    }

    public func refreshLocalChanges() async {
        let token = request
        removeLocalRows()
        guard showLocalChanges, let head = refs.mainHeadID else { return }
        let files = resolved?.fileLimit ?? view.files
        do {
            let changes = try await LocalChanges.read(repo: repo, files: files, runner: runner)
            guard token == request else { return }
            var viewHead = head
            if !files.isEmpty {
                let output = try await runner.run(["rev-list", "-1", head.hex, "--"] + files)
                guard token == request, let id = ObjectID(hex: String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                viewHead = id
            }
            guard let index = store.index(of: viewHead), ordering.commitInView(index), let tree = store.tree(of: index) else { return }
            for commit in changes.commits(head: viewHead, tree: tree, hashLength: repo.hashLength) {
                let index = store.insert(commit)
                ordering.insertFakeRow(index, store.intern(commit.parents[0]))
            }
        } catch {
            guard token == request else { return }
            onEvent?(.loadFailed(String(describing: error)))
        }
    }
}
