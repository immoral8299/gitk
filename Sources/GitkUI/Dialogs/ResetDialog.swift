// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

@MainActor
final class ResetDialog: RepositoryDialog {
    let typePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    var resetType: ResetType { [.soft, .mixed, .hard][max(0, min(2, typePopup.indexOfSelectedItem))] }

    /// Port of gitk proc `resethead` (gitk/gitk 10008–10048).
    init(id: ObjectID, coordinator: RepositoryActionCoordinator) {
        super.init(title: L("Confirm reset"), accept: L("OK"))
        stack.addArrangedSubview(NSTextField(labelWithString:
            L("Reset branch %s to %s?", coordinator.session.refs.mainHeadName ?? "HEAD", id.abbreviated(8))))
        typePopup.addItems(withTitles: [
            L("Soft: Leave working tree and index untouched"),
            L("Mixed: Leave working tree untouched, reset index"),
            L("Hard: Reset working tree and index\n(discard ALL local changes)"),
        ])
        typePopup.selectItem(at: 1)
        row(label: L("Reset type:"), control: typePopup)
        finishForm()
        onAccept = { [weak self] in
            guard let self else { return false }
            return await coordinator.reset(to: id, type: self.resetType)
        }
    }
    required init?(coder: NSCoder) { nil }
}
