// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit

@MainActor
final class StatusBar: NSStackView {
    let label = NSTextField(labelWithString: "")
    let progress = NSProgressIndicator()

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 6
        progress.style = .bar
        progress.isIndeterminate = true
        progress.isDisplayedWhenStopped = false
        addArrangedSubview(label)
        addArrangedSubview(progress)
        progress.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setSearching() {
        label.stringValue = L("Searching")
        progress.startAnimation(nil)
    }

    func setReading(_ reading: Bool, count: Int = 0) {
        label.stringValue = reading ? L("Reading") : ""
        if reading { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        progress.setAccessibilityValue(reading ? String(count) : "")
    }
}
