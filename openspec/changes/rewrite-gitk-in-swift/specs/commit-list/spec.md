# Spec Delta

## Purpose

Defines the upper history pane: its three resizable columns, commit selection, keyboard and mouse navigation, back/forward history, go-to-commit, and the status bar. Muscle memory from gitk must carry over.

## ADDED Requirements

### Requirement: Three-column list
The history pane SHALL show three side-by-side columns that scroll together vertically: graph and subject, author, and date. The dividers between them SHALL be resizable. Only the first column SHALL scroll horizontally. Dates SHALL use the configured date/time format.

#### Scenario: Synchronized scrolling
- **WHEN** the user scrolls any of the three columns
- **THEN** all three stay aligned row by row

#### Scenario: Date format with timezone
- **WHEN** the date format contains `%z` or `%Z`
- **THEN** each date is shown in the commit's own timezone; otherwise dates are shown in local time

### Requirement: Selection
Clicking a row SHALL select that commit, highlight the row, show its details and diff, put its ID in the Commit ID field, and update "Row N / M". If "Copy commit ID to clipboard" is on, the first N characters of the ID SHALL be copied to the clipboard, where N is the configured length.

#### Scenario: Select a commit
- **WHEN** the user clicks row 42 of 1,000
- **THEN** the row counter shows "42 / 1000", the Commit ID field shows the full hash, and the lower panes show that commit

#### Scenario: Auto-copy
- **WHEN** clipboard auto-copy is on with length 12 and the user selects a commit
- **THEN** the clipboard holds the first 12 hex characters of its ID

#### Scenario: Default selection
- **WHEN** a view finishes its first screen of rows and nothing was requested with `--select-commit`
- **THEN** HEAD is selected if it is in the view; otherwise the first row is selected

### Requirement: Keyboard navigation
The list SHALL support gitk's bindings, with ⌘ as the modifier on macOS: Up/p/k and Down/n/j move the selection, Home/End select the first/last commit, PageUp/PageDown move a page, ⌘-Home/End/Up/Down/PageUp/PageDown scroll without changing the selection, and ⌘-1…9 goes to the n-th parent.

#### Scenario: j/k navigation
- **WHEN** focus is not in a text field and the user presses `j` three times
- **THEN** the selection moves down three rows and each newly selected commit is displayed

#### Scenario: Letter keys inside a field
- **WHEN** focus is in the find field and the user types `j`
- **THEN** `j` is inserted into the field and the selection does not move

#### Scenario: Go to parent
- **WHEN** a merge commit is selected and the user presses ⌘-2
- **THEN** the second parent is selected

### Requirement: Back/forward history
Every selection (commit, line click, or link) SHALL be recorded in a navigation history. Left/z/h and the ← button SHALL go back; Right/x/l and the → button SHALL go forward. Each button SHALL be disabled when it has nowhere to go. Going back SHALL restore the diff pane's scroll position.

#### Scenario: Back after following a link
- **WHEN** the user selects A, clicks the parent link to B, then presses Left
- **THEN** A is selected again and its diff is scrolled to where it was

### Requirement: Go to commit
The Commit ID field SHALL accept a full or abbreviated ID, or any revision git can resolve. Pressing Return, or pressing `g` then typing and pressing Return, SHALL select that commit. It SHALL report "Short commit ID %s is ambiguous", "Revision %s is not known", "Commit ID %s is not known" or "Revision %s is not in the current view" as appropriate.

#### Scenario: Abbreviated ID
- **WHEN** the user types a unique 7-character prefix and presses Return
- **THEN** that commit is selected

#### Scenario: Not in view
- **WHEN** the revision exists but is filtered out of the current view
- **THEN** the message "Revision <rev> is not in the current view" is shown and the selection does not change

### Requirement: Row context menu
Secondary-clicking a commit row SHALL open the commit context menu defined in `repository-actions` for that row. Local-changes rows SHALL get the reduced menu (diff against selected or marked, make patch).

#### Scenario: Context menu on a fake row
- **WHEN** the user secondary-clicks the "Local uncommitted changes" row
- **THEN** only "Diff this -> selected", "Diff selected -> this", "Make patch", "Diff this -> marked commit" and "Diff marked commit -> this" are offered

### Requirement: Status and progress
The status bar SHALL show a busy status ("Reading", "Searching", and so on) and a progress bar for long operations. The mouse cursor SHALL show a busy state while a blocking git operation runs.

#### Scenario: Status during load
- **WHEN** a view is loading
- **THEN** the status reads "Reading" and the progress bar advances until loading is done, then clears

### Requirement: Mouse scrolling
Scroll-wheel and trackpad scrolling SHALL work with native momentum, scaled by the "Wheel scrolling multiplier" preference. Dragging with the middle button SHALL pan the history pane.

#### Scenario: Wheel multiplier
- **WHEN** the multiplier is 3 and the user scrolls one wheel notch
- **THEN** the list moves three times as many lines as with multiplier 1
