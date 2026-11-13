// SPDX-License-Identifier: GPL-2.0-or-later
// gitk-swift: a native macOS port of gitk.
// Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.

/// Every command reachable from a menu, keyboard shortcut, button or context
/// menu. All of them are dispatched through `MainWindowController.perform(_:)`
/// (design D8), so key bindings and menu items share one code path.
///
/// Commands that act on the commit or file under the pointer (context menus)
/// carry no payload: the UI records the clicked target before dispatching.
public enum AppCommand: Sendable, Hashable {

    /// How far a list or the diff pane scrolls.
    public enum ScrollStep: Sendable, Hashable {
        /// Scroll by a number of lines (negative is up).
        case lines(Int)
        /// Scroll by a number of pages (negative is up).
        case pages(Int)
        case toStart
        case toEnd
    }

    // MARK: Commit list navigation (commit-list spec)

    /// Up, p, k in gitk's commit list (selects the previous row).
    case selectPrev
    /// Down, n, j (selects the next row).
    case selectNext
    /// Home.
    case selectFirst
    /// End.
    case selectLast
    /// PageUp.
    case selectPageUp
    /// PageDown.
    case selectPageDown
    /// ⌘-Home, ⌘-End, ⌘-Up, ⌘-Down, ⌘-PageUp, ⌘-PageDown: scroll without changing the selection.
    case scrollList(ScrollStep)
    /// Left, z, h and the back button.
    case goBack
    /// Right, x, l and the forward button.
    case goForward
    /// ⌘-1…⌘-9: select the n-th parent of the selected commit (1-based).
    case goToParent(Int)

    // MARK: Commit find (commit-find spec)

    /// Return, ⌘-F and the down button when `wrap` is true; ⌘-G and Shift-Down when false.
    case findNext(wrap: Bool)
    /// `?` and the up button when `wrap` is true; Shift-Up when false.
    case findPrev(wrap: Bool)
    /// `/` and keypad divide: focus the find field.
    case focusFind
    /// `g`: clear the Commit ID field and focus it.
    case focusCommitID

    // MARK: Diff pane (diff-viewer spec)

    /// Space, Delete, Backspace, d, u.
    case scrollPane(ScrollStep)
    /// `f`: jump to the next file section.
    case nextFile
    /// `b`: jump to the previous file section (gitk's binding; its help text says page-up).
    case prevFile
    /// ⌘-S: next match of the pane's search field.
    case paneSearchNext
    /// ⌘-R: previous match of the pane's search field.
    case paneSearchPrev

    // MARK: Preferences (preferences spec)

    /// ⌘-plus, ⌘-equal, ⌘-keypad-plus.
    case fontBigger
    /// ⌘-minus, ⌘-keypad-minus.
    case fontSmaller

    // MARK: File menu, references and views

    /// F5 (File→Update).
    case update
    /// Shift-F5 (File→Reload).
    case reload
    /// File→Reread references.
    case rereadRefs
    /// File→List references and F2.
    case listRefs
    /// File→Start git gui.
    case startGitGui
    /// View→New view... and Shift-F4.
    case newView
    /// View→Edit view....
    case editView
    /// F4: gitk's `edit_or_newview`. Edits the current view, or creates one on "All files".
    case editOrNewView
    /// View→Delete view.
    case deleteView
    /// View menu item for the view at this index in the view list (0 is "All files").
    case showView(Int)

    // MARK: Application and window

    /// ⌘-Q, and ⌘-W in the main window.
    case quit
    /// ⌘-W in any other window closes it. The main window treats it as quit.
    case closeWindow
    /// ⌘-, (gitk-swift→Settings…, gitk's Edit→Preferences).
    case preferences
    /// Help→About gitk.
    case about
    /// Help→Key bindings.
    case keyBindings

    // MARK: Commit context menu (repository-actions spec)

    case diffThisToSelected
    case diffSelectedToThis
    case makePatch
    case createTag
    case copyCommitReference
    case writeCommitToFile
    case createBranch
    case cherryPickCommit
    case resetHeadToHere
    case markCommit
    case returnToMark
    case findDescendantAndMark
    case compareWithMarked
    case diffThisToMarked
    case diffMarkedToThis
    case revertCommit

    // MARK: Branch label context menu

    case checkoutBranch
    case renameBranch
    case removeBranch
    case copyBranchName

    // MARK: File list context menu (file-list spec)

    case highlightThisToo
    case highlightThisOnly
    case externalDiff
    case blameParentCommit
    case copyPath

    // MARK: Diff pane context menu (diff-viewer spec)

    case showOriginOfLine
    case blameLine
}
