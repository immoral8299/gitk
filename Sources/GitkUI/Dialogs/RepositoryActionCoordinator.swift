// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

/// Serializes repository writes and refreshes refs/local rows after success or failure.
@MainActor
final class RepositoryActionCoordinator {
    let session: ViewSession
    let actions: RepoActions
    let alerts: Alerts
    weak var parentWindow: NSWindow?
    var onBusy: ((String?) -> Void)?
    var onSelect: ((ObjectID) -> Void)?
    /// Called after the mark changed (old, new) so the list can redraw the marked row.
    var onDiffCommits: ((TwoCommitDiff) -> Void)?
    var onMarkChanged: ((ObjectID?, ObjectID?) -> Void)?
    /// Receives the "Compare with marked commit" report for the diff pane.
    var onShowReport: ((NSAttributedString) -> Void)?
    /// Replaces spawning `git <arguments>` (tests only), receiving the base commit for the author.
    var toolLauncher: (([String], ObjectID?) -> Void)?
    private(set) var isBusy = false
    private var externalTasks: [Task<Void, Never>] = []
    private var dialog: RepositoryDialog?
    private var patchNumber = 1

    init(session: ViewSession, alerts: Alerts? = nil) {
        self.session = session
        actions = RepoActions(runner: session.runner)
        self.alerts = alerts ?? Alerts()
    }

    private func run(status: String = "", history: Bool = false,
                     operation: () async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        onBusy?(status)
        defer { isBusy = false; onBusy?(nil) }
        var succeeded = false
        do { try await operation(); succeeded = true }
        catch {
            if !Task.isCancelled { alerts.errorPopup(error.localizedDescription, parent: parentWindow) }
        }
        guard !Task.isCancelled else { return false }
        if history { await session.update() }
        else { await session.readReferences() }
        return succeeded
    }

    /// Port of gitk proc `mkbrgo` / `mvbrgo` (gitk/gitk 9772–9856).
    func branch(name: String, at id: ObjectID, renameFrom oldName: String? = nil) async -> Bool {
        guard !name.isEmpty else {
            alerts.errorPopup(oldName == nil ? L("Please specify a name for the new branch")
                : L("Please specify a new name for the branch"), parent: parentWindow)
            return false
        }
        if name == oldName { return true }
        let exists = session.refs.headIDs[name] != nil
        let force = exists && alerts.confirmPopup(L("Branch '%s' already exists. Overwrite?", name), parent: parentWindow)
        if exists && !force { return false }
        return await run {
            if let oldName {
                if force { _ = try await session.runner.run(["branch", "-M", oldName, name]) }
                else { try await actions.renameBranch(from: oldName, to: name) }
            } else { try await actions.createBranch(name: name, at: id.hex, force: force) }
        }
    }

    /// Entry point for the head label menu (task 16.13): opens the Rename branch dialog for
    /// the head `name` pointing at `id`. Port of gitk proc `mvbranch` (gitk/gitk 9718–9730).
    func showRenameBranch(_ name: String, at id: ObjectID) {
        guard !isBusy else { return }
        dialog?.close()
        dialog = BranchDialog(id: id, renameFrom: name, coordinator: self)
        dialog?.present(relativeTo: parentWindow)
    }

    /// Port of gitk proc `domktag` (gitk/gitk 9554–9586).
    func tag(name: String, at id: ObjectID, message: String) async -> Bool {
        guard !name.isEmpty else {
            alerts.errorPopup(L("No tag name specified"), parent: parentWindow); return false
        }
        guard session.refs.tagIDs[name] == nil else {
            alerts.errorPopup(L("Tag \"%s\" already exists", name), parent: parentWindow); return false
        }
        return await run { try await actions.createTag(name: name, at: id.hex, message: message) }
    }

    /// Port of gitk procs `cherrypick` and `revert` (gitk/gitk 9884–10006).
    func pick(_ id: ObjectID, revert: Bool = false) async -> Bool {
        let included = (try? await session.runner.run(["merge-base", "--is-ancestor", id.hex, "HEAD"])) != nil
        let branch = session.refs.mainHeadName ?? "HEAD"
        if revert && !included {
            guard alerts.confirmPopup(L("Commit %s is not included in branch %s -- really revert it?",
                id.abbreviated(8), branch), parent: parentWindow) else { return false }
        } else if !revert && included {
            guard alerts.confirmPopup(L("Commit %s is already included in branch %s -- really re-apply it?",
                id.abbreviated(8), branch), parent: parentWindow) else { return false }
        }
        var resultID: ObjectID?
        let success = await run(status: revert ? L("Reverting") : L("Cherry-picking"), history: true) {
            do {
                let result = try await (revert ? actions.revert(id.hex) : actions.cherryPick(id.hex))
                switch result {
                case .noChanges: alerts.errorPopup(L("No changes committed"), parent: parentWindow)
                case .committed(_, let newHead): resultID = ObjectID(hex: newHead)
                }
            } catch let error as RepoActionError {
                switch error {
                case .localChanges(let files, _):
                    let message = revert
                        ? L("Revert failed because of local changes to the following files:%s Please commit, reset or stash  your changes and try again.", "\n" + files.joined(separator: "\n"))
                        : L("Cherry-pick failed because of local changes to file '%s'.\nPlease commit, reset or stash your changes and try again.", files.first ?? "")
                    alerts.errorPopup(message, parent: parentWindow)
                case .conflict:
                    let message = revert
                        ? L("Revert failed because of merge conflict.\n Do you wish to run git citool to resolve it?")
                        : L("Cherry-pick failed because of merge conflict.\nDo you wish to run git citool to resolve it?")
                    if alerts.confirmPopup(message, parent: parentWindow) {
                        try? FileManager.default.removeItem(at: URL(fileURLWithPath: session.repo.gitDir, relativeTo: session.runner.cwd).appendingPathComponent("GITGUI_MSG"))
                        launchGitTool(["citool"], authorOf: id)
                    }
                default: throw error
                }
            }
        }
        if let resultID { onSelect?(resultID) }
        return success && resultID != nil
    }

    /// Port of gitk proc `resethead` (gitk/gitk 10008–10048).
    func reset(to id: ObjectID, type: ResetType) async -> Bool {
        let result = await run(status: L("Resetting"), history: true) {
            _ = try await actions.reset(to: id.hex, type: type)
        }
        if result { onSelect?(id) }
        return result
    }

    /// Port of gitk proc `cobranch` (gitk/gitk 10105–10139).
    func checkout(_ name: String) async -> Bool {
        await run(status: L("Checking out"), history: true) {
            _ = try await actions.checkout(head: name, localHeads: Set(session.refs.headIDs.keys))
        }
    }

    /// Port of gitk proc `rmbranch` (gitk/gitk 10176–10206).
    func removeBranch(_ name: String) async -> Bool {
        guard name != session.refs.mainHeadName else {
            alerts.errorPopup(L("Cannot delete the currently checked-out branch"), parent: parentWindow)
            return false
        }
        let contains = try? await session.runner.run(["for-each-ref", "--format=%(refname)", "--contains", name, "refs/heads", "refs/remotes"])
        let branches = contains.map { String(decoding: $0.stdout, as: UTF8.self).split(separator: "\n") } ?? []
        if branches.count <= 1 {
            guard alerts.confirmPopup(L("The commits on branch %s aren't on any other branch.\nReally delete branch %s?", name, name),
                                      parent: parentWindow) else { return false }
        }
        return await run { try await actions.deleteBranch(name) }
    }

    func makePatch(from: ObjectID, to: ObjectID, reverse: Bool, output: URL) async -> Bool {
        await run {
            let data = try await actions.makePatch(from: from.hex, to: to.hex, reverse: reverse)
            try data.write(to: output, options: .atomic)
        }
    }

    func writeCommit(_ id: ObjectID, command: String, output: URL) async -> Bool {
        await run {
            do { try await actions.writeCommit(id, command: command, to: output) }
            catch { throw WriteCommitError(message: L("Error writing commit:") + " " + error.localizedDescription) }
        }
    }

    /// Port of gitk proc `exec_citool` and File→Start git gui (gitk/gitk 2403, 9858–9882).
    /// Detached like gitk's `&`: the task is not kept in `externalTasks`, so closing
    /// the window does not terminate a running `git gui`. A tool that cannot start,
    /// or exits with an error, reports git's message in an alert.
    func launchGitTool(_ arguments: [String] = ["gui"], authorOf id: ObjectID? = nil) {
        if let toolLauncher { toolLauncher(arguments, id); return }
        let runner = session.runner
        let repo = session.repo
        Task { [weak self] in
            do {
                var environment = ProcessInfo.processInfo.environment
                if let id {
                    let output = try await runner.run(["show", "-s", "--format=%an%x00%ae%x00%aI", id.hex])
                    let fields = String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .newlines).split(separator: "\0", omittingEmptySubsequences: false)
                    if fields.count == 3 {
                        environment["GIT_AUTHOR_NAME"] = String(fields[0])
                        environment["GIT_AUTHOR_EMAIL"] = String(fields[1])
                        environment["GIT_AUTHOR_DATE"] = String(fields[2])
                    }
                }
                _ = try await GitRunner(gitURL: runner.gitURL, cwd: runner.cwd ?? URL(fileURLWithPath: repo.worktree),
                                        baseEnvironment: environment).run(arguments)
            } catch {
                guard !Task.isCancelled else { return }
                self?.alerts.errorPopup(error.localizedDescription, parent: self?.parentWindow)
            }
        }
    }

    private var patchCompare: PatchIDCompare?

    /// Port of gitk proc `compare_commits` (gitk/gitk 9241–9248): needs a mark that is in the view.
    func compareWithMarked(_ id: ObjectID) {
        guard let marked = session.selection.markedID, let index = session.store.index(of: marked),
              session.ordering.commitInView(index) else { return }
        let compare = patchCompare ?? PatchIDCompare(runner: session.runner, graph: PatchIDGraph(session: session))
        patchCompare = compare
        externalTasks.append(Task { [weak self] in
            guard let lines = try? await compare.compare(marked, id), let self else { return }
            onShowReport?(Self.renderReport(lines))
        })
    }

    /// The report text of gitk proc `do_cmp_commits`; short IDs carry `gitk-commit:` links.
    static func renderReport(_ lines: [PatchIDReportLine]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func plain(_ text: String) { out.append(NSAttributedString(string: text)) }
        func link(_ id: ObjectID, pre: String = "", post: String = "") {
            plain(pre)
            out.append(NSAttributedString(string: id.abbreviated(8),
                                          attributes: [.link: LinkHandling.commitScheme + id.hex]))
            plain(post)
        }
        for line in lines {
            switch line {
            case .skippingMerge(let id): link(id, pre: L("Skipping merge commit "), post: "\n")
            case .patchIDError(let id): link(id, pre: L("Error getting patch ID for "), post: L(" - stopping\n"))
            case .samePatch(let a, let b, let headA, let headB):
                if headA == headB {
                    link(a, pre: L("Commit ")); link(b, pre: " == ", post: "  \(headA)\n")
                } else {
                    link(a, pre: L("Commit "), post: "  \(headA)\n")
                    link(b, pre: L(" is the same patch as\n       "), post: "  \(headB)\n")
                }
            case .differs(let a, let b, let headA, let headB):
                plain("\n")
                link(a, pre: L("Commit "), post: "  \(headA)\n")
                link(b, pre: L(" differs from\n       "), post: "  \(headB)\n")
                plain(L("Diff of commits:\n\n"))
            case .tooManyChildren(let id, let count, let leadingBlank):
                if leadingBlank { plain("\n") }
                link(id, pre: L("Commit "), post: L(" has %s children - stopping\n", String(count)))
            }
        }
        return out
    }

    /// Returns false for commands handled by navigation/diff controllers.
    @discardableResult
    func perform(_ command: AppCommand, id: ObjectID?, selected: ObjectID?, branchName: String? = nil,
                 copyLength: Int = 40) -> Bool {
        if command == .startGitGui { launchGitTool(); return true }
        switch command {
        case .markCommit:
            guard let id else { return true }
            let old = session.selection.markedID
            session.selection = session.selection.marking(id)
            onMarkChanged?(old, id)
            return true
        case .returnToMark:
            if let target = session.selection.markTarget { onSelect?(target) }
            return true
        case .findDescendantAndMark:
            if let id, let found = session.findCommonDesc(marked: session.selection.markedID, menuID: id) { onSelect?(found) }
            return true
        case .diffThisToSelected, .diffSelectedToThis, .diffThisToMarked, .diffMarkedToThis:
            if let id, let diff = TwoCommitDiff.make(command: command, menuID: id, selected: selected,
                                                     marked: session.selection.markedID) { onDiffCommits?(diff) }
            return true
        case .compareWithMarked:
            if let id { compareWithMarked(id) }
            return true
        default: break
        }
        guard !isBusy else { return true }
        guard let id else { return false }
        let nextDialog: RepositoryDialog?
        switch command {
        case .makePatch:
            guard let selected else { return true }
            nextDialog = PatchDialog(from: selected, to: id, number: patchNumber, coordinator: self)
            patchNumber += 1
        case .createTag: nextDialog = TagDialog(id: id, coordinator: self)
        case .writeCommitToFile: nextDialog = WriteCommitDialog(id: id, coordinator: self)
        case .createBranch: nextDialog = BranchDialog(id: id, coordinator: self)
        case .renameBranch:
            guard let branchName else { return true }
            nextDialog = BranchDialog(id: id, renameFrom: branchName, coordinator: self)
        case .resetHeadToHere: nextDialog = ResetDialog(id: id, coordinator: self)
        case .cherryPickCommit, .revertCommit:
            externalTasks.append(Task { [weak self] in _ = await self?.pick(id, revert: command == .revertCommit) })
            return true
        case .checkoutBranch:
            if let branchName { externalTasks.append(Task { [weak self] in _ = await self?.checkout(branchName) }) }
            return true
        case .removeBranch:
            if let branchName { externalTasks.append(Task { [weak self] in _ = await self?.removeBranch(branchName) }) }
            return true
        case .copyBranchName:
            if let branchName { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(branchName, forType: .string) }
            return true
        case .copyCommitReference:
            externalTasks.append(Task { [weak self] in
                guard let self else { return }
                do {
                    let text = try await actions.copyReference(id, abbrevLength: copyLength, hashLength: session.repo.hashLength)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } catch { alerts.errorPopup(error.localizedDescription, parent: parentWindow) }
            })
            return true
        default: return false
        }
        dialog?.close()
        dialog = nextDialog
        dialog?.present(relativeTo: parentWindow)
        return true
    }

    func cancel() {
        dialog?.close()
        externalTasks.forEach { $0.cancel() }
        externalTasks.removeAll()
    }
}

/// gitk's `wrcomgo` prefixes failures with "Error writing commit:".
struct WriteCommitError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
