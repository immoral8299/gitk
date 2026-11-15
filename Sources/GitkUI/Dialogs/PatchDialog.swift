// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class PatchDialog: RepositoryDialog {
    let outputField = NSTextField(string: "")
    let fromField = NSTextField(labelWithString: "")
    let fromHeadField = NSTextField(labelWithString: "")
    let toField = NSTextField(labelWithString: "")
    let toHeadField = NSTextField(labelWithString: "")
    private(set) var fromID: ObjectID
    private(set) var toID: ObjectID
    private var fromHead: String
    private var toHead: String

    /// Port of gitk proc `mkpatch` (gitk/gitk 9424–9491).
    init(from: ObjectID, to: ObjectID, number: Int, coordinator: RepositoryActionCoordinator) {
        let store = coordinator.session.store
        fromID = from
        toID = to
        fromHead = store.index(of: from).map { store.headline(at: $0) } ?? ""
        toHead = store.index(of: to).map { store.headline(at: $0) } ?? ""
        super.init(title: L("Generate patch"), accept: L("Generate"))
        row(label: L("From:"), control: fromField)
        row(label: "", control: fromHeadField)
        row(label: L("To:"), control: toField)
        row(label: "", control: toHeadField)
        stack.addArrangedSubview(NSButton(title: L("Reverse"), target: self, action: #selector(reversePressed)))
        showEndpoints()
        let repo = coordinator.session.repo
        let base = URL(fileURLWithPath: repo.worktree.isEmpty ? repo.gitDir : repo.worktree)
        outputField.stringValue = base.appendingPathComponent("patch\(number).patch").path
        row(label: L("Output file:"), control: outputField)
        finishForm()
        onAccept = { [weak self] in
            guard let self else { return false }
            return await coordinator.makePatch(from: self.fromID, to: self.toID, reverse: false,
                                                output: URL(fileURLWithPath: self.outputField.stringValue))
        }
        window?.initialFirstResponder = outputField
    }
    required init?(coder: NSCoder) { nil }

    private func showEndpoints() {
        fromField.stringValue = fromID.hex
        fromHeadField.stringValue = fromHead
        toField.stringValue = toID.hex
        toHeadField.stringValue = toHead
    }

    /// Port of gitk proc `mkpatchrev` (gitk/gitk 9507–9519): swaps From and To.
    @objc func reversePressed() {
        swap(&fromID, &toID)
        swap(&fromHead, &toHead)
        showEndpoints()
    }
}
