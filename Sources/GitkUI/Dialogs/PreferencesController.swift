// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

import AppKit
import GitkCore

extension Notification.Name {
    /// Posted after the preferences window's OK applies new settings. The
    /// notification object is the new `Settings` value; observers (task 18.5)
    /// apply it live.
    static let gitkSettingsDidChange = Notification.Name("GitkSettingsDidChange")
}

/// Target object that forwards a control's action to a closure.
@MainActor
final class ClosureTarget: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}

/// A number field with a stepper, the equivalent of gitk's `ttk::spinbox`.
@MainActor
final class SpinnerField: NSView {
    let field = NSTextField()
    let stepper = NSStepper()
    var onChange: ((Int) -> Void)?

    var value: Int {
        get { Int(stepper.intValue) }
        set { stepper.integerValue = newValue; field.integerValue = newValue }
    }

    init(value: Int, range: ClosedRange<Int>) {
        super.init(frame: .zero)
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(stepped)
        field.target = self
        field.action = #selector(typed)
        field.alignment = .right
        field.widthAnchor.constraint(equalToConstant: 56).isActive = true
        self.value = min(max(value, range.lowerBound), range.upperBound)
        let stack = NSStackView(views: [field, stepper])
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func stepped() {
        field.integerValue = Int(stepper.intValue)
        onChange?(value)
    }

    /// Typed text is clamped to the range; non-numbers revert to the old value.
    @objc private func typed() {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        if let n = Int(text) {
            value = min(max(n, Int(stepper.minValue)), Int(stepper.maxValue))
        } else {
            field.integerValue = Int(stepper.intValue)
        }
        onChange?(value)
    }
}

/// Port of gitk proc `doprefs` (gitk/gitk 11914–11961), `prefspage_general`
/// (11704–11801), `choose_extdiff` (11963–11970), `prefscan` and `prefsok`
/// (12078–12150).
///
/// The window edits `draft`, a copy of the settings. OK hands the draft to
/// `onApply` (which applies and saves it) and posts `.gitkSettingsDidChange`;
/// Cancel throws it away. Tabs come from `pageBuilders`: tasks 18.2 and 18.3
/// replace the Colors and Fonts entries and bind their controls to `draft` the
/// same way `makeGeneralPage()` does.
@MainActor
final class PreferencesController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private(set) var draft: Settings
    let original: Settings
    let hashLength: Int
    var onApply: ((Settings) -> Void)?
    var onClose: (() -> Void)?
    private let notificationCenter: NotificationCenter

    let tabView = NSTabView()
    private(set) var showLocalChangesCheckbox: NSButton?
    private(set) var extDiffToolField: NSTextField?
    private(set) var spinners: [String: SpinnerField] = [:]
    /// The Colors page wells, keyed by `ColorSetting.id`.
    private(set) var colorWells: [String: NSColorWell] = [:]
    /// The Fonts page rows, keyed by `FontSetting.id`: the family label and the button.
    private(set) var fontLabels: [String: NSTextField] = [:]
    private(set) var fontButtons: [String: NSButton] = [:]
    /// The row whose font the system font panel is editing.
    private var activeFontRow: String?
    private(set) var okButton = NSButton()
    private(set) var cancelButton = NSButton()

    /// (title, toolbar symbol, builder) for each pane, in gitk's order.
    private(set) var pageBuilders: [(title: String, symbol: String, build: (PreferencesController) -> NSView)] = [
        (L("General"), "gearshape", { $0.makeGeneralPage() }),
        (L("Colors"), "paintpalette", { $0.makeColorsPage() }),
        (L("Fonts"), "textformat", { $0.makeFontsPage() }),
    ]
    /// Pins the tab view to the selected pane's height so the window fits it.
    private var tabHeight: NSLayoutConstraint?

    init(settings: Settings, hashLength: Int = 40, notificationCenter: NotificationCenter = .default) {
        original = settings
        draft = settings
        self.hashLength = hashLength
        self.notificationCenter = notificationCenter
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("Gitk preferences")
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Window

    /// Safari-style settings window: a toolbar picks the pane, the window
    /// takes the pane's title and resizes to fit it, and Cancel/OK sit below.
    private func buildContent(in window: NSWindow) {
        tabView.tabViewType = .noTabsNoBorder
        tabView.drawsBackground = false
        for (index, page) in pageBuilders.enumerated() {
            let item = NSTabViewItem(identifier: Self.toolbarID(index))
            item.label = page.title
            item.view = page.build(self)
            tabView.addTabViewItem(item)
        }
        okButton = NSButton(title: L("OK"), target: self, action: #selector(okAction))
        okButton.keyEquivalent = "\r"
        cancelButton = NSButton(title: L("Cancel"), target: self, action: #selector(cancelAction))
        cancelButton.keyEquivalent = "\u{1b}"
        for button in [okButton, cancelButton] {
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
        }
        let buttons = NSStackView(views: [cancelButton, okButton])
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false
        tabView.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        window.contentView = content
        content.addSubview(tabView)
        content.addSubview(buttons)
        let height = tabView.heightAnchor.constraint(equalToConstant: 0)
        tabHeight = height
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: content.topAnchor),
            tabView.widthAnchor.constraint(equalToConstant: Self.paneWidth),
            height,
            buttons.topAnchor.constraint(equalTo: tabView.bottomAnchor),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])

        let toolbar = NSToolbar(identifier: "GitkPreferences")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        selectPane(0, animate: false)
    }

    static let paneWidth: CGFloat = 600

    private static func toolbarID(_ index: Int) -> NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("pane\(index)")
    }

    /// Shows pane `index`, retitles the window after it and resizes the window
    /// to the pane's height, keeping its top edge in place.
    func selectPane(_ index: Int, animate: Bool = true) {
        guard pageBuilders.indices.contains(index), let window else { return }
        tabView.selectTabViewItem(at: index)
        window.toolbar?.selectedItemIdentifier = Self.toolbarID(index)
        window.title = pageBuilders[index].title
        let page = tabView.tabViewItem(at: index).view
        page?.layoutSubtreeIfNeeded()
        tabHeight?.constant = page?.fittingSize.height ?? 0
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content.fittingSize))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }

    @objc private func paneClicked(_ sender: NSToolbarItem) {
        if let index = Int(sender.itemIdentifier.rawValue.dropFirst(4)) { selectPane(index) }
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let index = Int(itemIdentifier.rawValue.dropFirst(4)), pageBuilders.indices.contains(index) else { return nil }
        let page = pageBuilders[index]
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = page.title
        item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
        item.target = self
        item.action = #selector(paneClicked(_:))
        return item
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        pageBuilders.indices.map(Self.toolbarID)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    /// Port of gitk proc `prefsok` minus applying each change (task 18.5).
    @objc func okAction() {
        window?.makeFirstResponder(nil)
        let new = draft
        close()
        onApply?(new)
        notificationCenter.post(name: .gitkSettingsDidChange, object: new)
    }

    /// Port of gitk proc `prefscan`: the draft is dropped.
    @objc func cancelAction() {
        draft = original
        close()
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    // MARK: General page

    /// Port of gitk proc `prefspage_general`. The X11 selection checkbox is
    /// omitted: macOS has no selection clipboard (`haveselectionclipboard`).
    func makeGeneralPage() -> NSView {
        let form = SettingsForm()

        func spinner(_ key: String, _ title: String, _ range: ClosedRange<Int>,
                     _ path: WritableKeyPath<Settings, Int>) {
            let s = SpinnerField(value: draft[keyPath: path], range: range)
            s.onChange = { [weak self] in self?.draft[keyPath: path] = $0 }
            spinners[key] = s
            form.row(title, s)
        }
        func check(_ title: String, _ path: WritableKeyPath<Settings, Bool>) -> NSButton {
            let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            b.state = draft[keyPath: path] ? .on : .off
            bind(b, ClosureTarget { [weak self, weak b] in
                self?.draft[keyPath: path] = b?.state == .on
            })
            form.row(nil, b)
            return b
        }
        func text(_ title: String, _ path: WritableKeyPath<Settings, String>, button: NSButton? = nil) -> NSTextField {
            let f = NSTextField(string: draft[keyPath: path])
            f.translatesAutoresizingMaskIntoConstraints = false
            bind(f, ClosureTarget { [weak self, weak f] in self?.draft[keyPath: path] = f?.stringValue ?? "" })
            if let button {
                f.widthAnchor.constraint(equalToConstant: SettingsForm.controlWidth - button.fittingSize.width - 8).isActive = true
                let s = NSStackView(views: [f, button])
                s.spacing = 8
                form.row(title, s)
            } else {
                f.widthAnchor.constraint(equalToConstant: SettingsForm.controlWidth).isActive = true
                form.row(title, f)
            }
            return f
        }
        func wrap(_ title: String, _ path: WritableKeyPath<Settings, String>) {
            let popup = NSPopUpButton()
            popup.addItems(withTitles: ["none", "char", "word"])
            popup.selectItem(withTitle: draft[keyPath: path])
            bind(popup, ClosureTarget { [weak self, weak popup] in
                self?.draft[keyPath: path] = popup?.titleOfSelectedItem ?? "none"
            })
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
            form.row(title, popup)
        }

        // gitk's "Commit list display options".
        spinner("maxWidth", L("Maximum graph width (lines)"), 0...100, \.maxWidth)
        spinner("maxGraphPct", L("Maximum graph width (% of pane)"), 1...100, \.maxGraphPct)
        form.gap()
        showLocalChangesCheckbox = check(L("Show local changes"), \.showLocalChanges)
        _ = check(L("Hide remote refs"), \.hideRemotes)
        _ = text(L("Refs to hide (space-separated globs)"), \.refsToHide)
        form.gap()
        _ = check(L("Copy commit ID to clipboard"), \.autoCopy)
        spinner("autoSelLen", L("Length of commit ID to copy"), 1...max(hashLength, 1), \.autoSelLen)
        form.gap()
        spinner("kscroll", L("Wheel scrolling multiplier"), 1...20, \.kscroll)
        _ = text(L("Date and time format"), \.dateTimeFormat)

        // gitk's "Diff display options".
        form.gap(24)
        spinner("tabStop", L("Tab spacing"), 1...20, \.tabStop)
        wrap(L("Wrap comment text"), \.wrapComment)
        wrap(L("Wrap other text"), \.wrapDefault)
        form.gap()
        _ = check(L("Display nearby tags/heads"), \.showNearTags)
        spinner("maxRefs", L("Maximum # tags/heads to show"), 1...1000, \.maxRefs)
        form.gap()
        _ = check(L("Limit diffs to listed paths"), \.limitDiffs)
        _ = check(L("Support per-file encodings"), \.perFileAttrs)
        form.gap()
        let choose = NSButton(title: L("Choose..."), target: nil, action: nil)
        bind(choose, ClosureTarget { [weak self] in self?.chooseExtDiff() })
        extDiffToolField = text(L("External diff tool"), \.extDiffTool, button: choose)
        _ = text(L("Web browser"), \.webBrowser)
        return form.page()
    }

    /// Port of gitk proc `choose_extdiff`: an open panel whose choice goes into
    /// the External diff tool field and the draft.
    func chooseExtDiff() {
        let panel = NSOpenPanel()
        panel.title = L("External diff tool")
        panel.allowsMultipleSelection = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let path = panel.url?.path else { return }
            self?.setExtDiffTool(path)
        }
    }

    func setExtDiffTool(_ path: String) {
        draft.extDiffTool = path
        extDiffToolField?.stringValue = path
    }

    // MARK: Colors page

    /// One colour setting edited on the Colors page.
    struct ColorSetting {
        let id: String
        let title: String
        let set: (inout Settings, String) -> Void
        let display: @MainActor (Settings) -> NSColor
    }

    /// Port of the `coloruielems` list in gitk proc `prefspage_colors`
    /// (gitk/gitk 11836–11866), in gitk's order, followed by the two search
    /// colours.
    static let colorSettings: [ColorSetting] = [
        ColorSetting(id: "bg", title: L("Background"), set: { $0.bgColor = $1 },
                     display: { Palette.background($0) }),
        ColorSetting(id: "fg", title: L("Main text"), set: { $0.fgColor = $1 },
                     display: { Palette.foreground($0) }),
        ColorSetting(id: "selbg", title: L("Selected text background"), set: { $0.selectBgColor = $1 },
                     display: { Palette.tk($0.selectBgColor) }),
        ColorSetting(id: "linkfg", title: L("Link text"), set: { $0.linkFgColor = $1 },
                     display: { Palette.link($0) }),
        ColorSetting(id: "diffold", title: L("Old line text"), set: { $0.setList(\.diffColors, 0, $1) },
                     display: { Palette.diff($0, 0) }),
        ColorSetting(id: "diffoldbg", title: L("Old line background"), set: { $0.setList(\.diffBgColors, 0, $1) },
                     display: { Palette.diffBackground($0, 0) }),
        ColorSetting(id: "diffnew", title: L("New line text"), set: { $0.setList(\.diffColors, 1, $1) },
                     display: { Palette.diff($0, 1) }),
        ColorSetting(id: "diffnewbg", title: L("New line background"), set: { $0.setList(\.diffBgColors, 1, $1) },
                     display: { Palette.diffBackground($0, 1) }),
        ColorSetting(id: "hunksep", title: L("Hunk header text"), set: { $0.setList(\.diffColors, 2, $1) },
                     display: { Palette.diff($0, 2) }),
        ColorSetting(id: "markbg", title: L("Marked line background"), set: { $0.markBgColor = $1 },
                     display: { Palette.tk($0.markBgColor) }),
        ColorSetting(id: "foundbg", title: L("Found text background"), set: { $0.foundBgColor = $1 },
                     display: { Palette.found($0) }),
        ColorSetting(id: "currenthit", title: L("Current search hit background"),
                     set: { $0.currentSearchHitBgColor = $1 }, display: { Palette.tk($0.currentSearchHitBgColor) }),
    ]

    /// Tk colour string (`#rrggbb`) for an `NSColor`, via sRGB.
    static func tkString(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        func byte(_ v: CGFloat) -> UInt8 { UInt8(min(max((v * 255).rounded(), 0), 255)) }
        return TkColor.hexString(RGBA(r: byte(c.redComponent), g: byte(c.greenComponent), b: byte(c.blueComponent)))
    }

    /// Port of gitk proc `prefspage_colors` (colour part) and `choosecolor`.
    /// A well edits the draft only; nothing applies until OK. The Themes
    /// section is omitted (no Tk themes; see Deviations).
    func makeColorsPage() -> NSView {
        let form = SettingsForm()
        for item in Self.colorSettings {
            let well = NSColorWell()
            well.color = item.display(draft)
            well.translatesAutoresizingMaskIntoConstraints = false
            well.widthAnchor.constraint(equalToConstant: 64).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
            bind(well, ClosureTarget { [weak self, weak well] in
                guard let self, let well else { return }
                item.set(&self.draft, Self.tkString(well.color))
            })
            colorWells[item.id] = well
            form.row(item.title, well)
        }
        return form.page()
    }

    // MARK: Fonts page

    /// One font edited on the Fonts page.
    struct FontSetting {
        let id: String
        let title: String
        let path: WritableKeyPath<Settings, FontSpec>
    }

    /// The `mkfontdisp` rows of gitk proc `prefspage_fonts`, in gitk's order.
    static let fontSettings: [FontSetting] = [
        FontSetting(id: "main", title: L("Main font"), path: \.mainFont),
        FontSetting(id: "text", title: L("Diff display font"), path: \.textFont),
        FontSetting(id: "ui", title: L("User interface font"), path: \.uiFont),
    ]

    /// Port of gitk proc `prefspage_fonts` (gitk/gitk 11903–11912) and
    /// `mkfontdisp` (11623–11633): a button per font that opens the system font
    /// panel, and a label showing the family in that font.
    func makeFontsPage() -> NSView {
        let form = SettingsForm()
        for item in Self.fontSettings {
            let button = NSButton(title: L("Choose..."), target: nil, action: nil)
            bind(button, ClosureTarget { [weak self] in self?.chooseFont(item.id) })
            let family = NSTextField(labelWithString: "")
            family.lineBreakMode = .byTruncatingTail
            family.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            // A fixed width keeps the Choose buttons in one column.
            family.translatesAutoresizingMaskIntoConstraints = false
            family.widthAnchor.constraint(equalToConstant: 130).isActive = true
            fontButtons[item.id] = button
            fontLabels[item.id] = family
            refreshFontRow(item)
            let stack = NSStackView(views: [family, button])
            stack.spacing = 12
            form.row(item.title, stack)
        }
        return form.page()
    }

    private func refreshFontRow(_ item: FontSetting) {
        let spec = draft[keyPath: item.path]
        let font = MainLayoutMetrics.nsFont(spec)
        // The system faces have private dotted family names; show the
        // public ones instead.
        let family: String
        switch spec.family {
        case FontSpec.systemFamily: family = "SF Pro"
        case FontSpec.monospacedSystemFamily: family = "SF Mono"
        default: family = font.familyName ?? spec.family
        }
        fontLabels[item.id]?.stringValue = family
        fontLabels[item.id]?.font = font
    }

    /// Port of gitk proc `choosefont`: shows the font panel for one row.
    func chooseFont(_ id: String) {
        guard let item = Self.fontSettings.first(where: { $0.id == id }) else { return }
        activeFontRow = id
        let manager = NSFontManager.shared
        manager.target = self
        manager.action = #selector(changeFont(_:))
        manager.setSelectedFont(MainLayoutMetrics.nsFont(draft[keyPath: item.path]), isMultiple: false)
        manager.fontPanel(true)?.title = item.title
        manager.orderFrontFontPanel(nil)
    }

    /// Called by the font panel when the user picks a font.
    @objc func changeFont(_ sender: NSFontManager?) {
        guard let id = activeFontRow, let item = Self.fontSettings.first(where: { $0.id == id }) else { return }
        let current = MainLayoutMetrics.nsFont(draft[keyPath: item.path])
        applyChosenFont((sender ?? NSFontManager.shared).convert(current), row: id)
    }

    /// Port of gitk procs `on_choosefont` and `fontok` (gitk/gitk 11643–11690):
    /// the chosen font replaces the row's font on the draft.
    func applyChosenFont(_ font: NSFont, row id: String) {
        guard let item = Self.fontSettings.first(where: { $0.id == id }) else { return }
        draft[keyPath: item.path] = Self.fontSpec(from: font)
        refreshFontRow(item)
    }

    /// The `FontSpec` for an `NSFont`; the system faces map to the sentinels (design D9).
    static func fontSpec(from font: NSFont) -> FontSpec {
        let traits = NSFontManager.shared.traits(of: font)
        let family: String
        if font.fontName.hasPrefix(".") || (font.familyName ?? "").hasPrefix(".") {
            family = font.isFixedPitch ? FontSpec.monospacedSystemFamily : FontSpec.systemFamily
        } else {
            family = font.familyName ?? font.fontName
        }
        return FontSpec(family: family, pointSize: Double(font.pointSize),
                        bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask))
    }

    // MARK: Helpers

    private var targets: [ClosureTarget] = []

    private func bind(_ control: NSControl, _ target: ClosureTarget) {
        targets.append(target)
        control.target = target
        control.action = #selector(ClosureTarget.fire)
    }
}

/// A Safari-style settings form: right-aligned labels ending in a colon, the
/// controls left-aligned beside them, and groups set apart by space. The form
/// is centred in its pane.
@MainActor
final class SettingsForm {
    static let controlWidth: CGFloat = 260
    let grid = NSGridView()
    private var gapBeforeNext: CGFloat?

    init() {
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.rowAlignment = .none
        grid.yPlacement = .center
        grid.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Adds a row; `title` nil leaves the label column empty (checkboxes).
    func row(_ title: String?, _ control: NSView) {
        let label: NSView
        if let title {
            let field = NSTextField(labelWithString: title + ":")
            field.alignment = .right
            label = field
        } else {
            label = NSGridCell.emptyContentView
        }
        let row = grid.addRow(with: [label, control])
        if let gap = gapBeforeNext {
            row.topPadding = gap
            gapBeforeNext = nil
        }
    }

    /// Puts extra space before the next row.
    func gap(_ space: CGFloat = 12) { if grid.numberOfRows > 0 { gapBeforeNext = space } }

    func page() -> NSView {
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        let page = NSView()
        page.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: page.centerXAnchor),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: page.leadingAnchor, constant: 20),
            grid.topAnchor.constraint(equalTo: page.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -24),
        ])
        return page
    }
}

private extension Settings {
    /// `lset`: replaces entry `i` of a colour list, growing it if short.
    mutating func setList(_ path: WritableKeyPath<Settings, [String]>, _ i: Int, _ value: String) {
        while self[keyPath: path].count <= i { self[keyPath: path].append("") }
        self[keyPath: path][i] = value
    }
}
