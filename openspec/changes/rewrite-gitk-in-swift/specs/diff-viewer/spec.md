# Spec Delta

## Purpose

Defines the diff pane below the history list, which shows a selected commit's patch, or a file's contents in tree mode, and the controls that change how it is rendered or searched.

## ADDED Requirements

### Requirement: Diff pane placement
The diff pane SHALL sit below the history list and above the status strip, spanning the list's width. It SHALL default to about half the window content height and SHALL be resizable. It SHALL keep its height when the selection changes. When the details sidebar is closed, the pane SHALL widen with the list.

#### Scenario: Selection shows the diff
- **WHEN** the user clicks a commit in the history list
- **THEN** its patch appears in the bottom pane and the details sidebar shows that commit

### Requirement: Patch display
In Patch mode, selecting a commit SHALL stream its diff into the bottom pane, using the same diff options as gitk (`-p --textconv --submodule -C --cc --no-commit-id -U<context>`, plus `--root` when `log.showRoot` is true). Each file SHALL start with a full-width file separator header. Removed, added and hunk-header lines SHALL use the configured diff colours and backgrounds.

#### Scenario: Ordinary commit
- **WHEN** a commit changing two files is selected
- **THEN** two separator headers appear, each followed by its hunks, with `-` lines in the old-line colours and `+` lines in the new-line colours

#### Scenario: Rename
- **WHEN** a commit renames a file with small edits
- **THEN** the diff is shown as a rename with the old and new paths, not as a delete plus an add

#### Scenario: Large diff
- **WHEN** a commit's patch is several megabytes
- **THEN** the first hunks appear quickly while the rest streams in, and the UI stays responsive

### Requirement: Merge diffs
Merge commits SHALL show a combined diff, with one marker column per parent, coloured by the parents' merge colours.

#### Scenario: Octopus merge
- **WHEN** a merge with three parents is selected
- **THEN** each combined-diff line has three marker columns, coloured by the first three merge colours

### Requirement: Local-changes and two-commit diffs
For the local-changes rows, and when diffing two chosen commits, the diff SHALL compare the right states: work tree vs index, index vs HEAD, work tree or index vs a commit, or commit vs commit.

#### Scenario: Unstaged row
- **WHEN** the "Local uncommitted changes" row is selected
- **THEN** the pane shows the work tree compared to the index

#### Scenario: Index row
- **WHEN** the "Local changes checked in to index" row is selected
- **THEN** the pane shows the index compared to HEAD, ignoring dirty submodules

### Requirement: Diff controls
The pane SHALL provide: Diff / Old version / New version (show both sides, only removed+context lines, or only added+context lines); a "Lines of context" number field; "Ignore space change"; and "Line diff" / "Markup words" / "Color words". Changing any of these SHALL re-render the current diff, keeping the scroll position where possible.

#### Scenario: Old version
- **WHEN** the user picks "Old version"
- **THEN** added lines are hidden and the pane reads as the pre-change file excerpts

#### Scenario: Context lines
- **WHEN** the user sets "Lines of context" to 10
- **THEN** the diff is re-fetched with 10 lines of context

#### Scenario: Color words
- **WHEN** "Color words" is chosen
- **THEN** changes are shown inline, word by word, with removed words in the old-line colour and added words in the new-line colour, and no `+`/`-` lines

### Requirement: Path-limited diffs
When "Limit diffs to listed paths" is on and the view has path limits, the patch SHALL only include files within those paths.

#### Scenario: Limited view
- **WHEN** the view is limited to `src/` and the commit also touches `docs/`
- **THEN** only the `src/` files appear in the patch and the Changed Files section

### Requirement: Text search in the pane
The pane SHALL have a search field. Typing in it SHALL highlight all matches incrementally. "Search" / ⌘-S SHALL go to the next match, ⌘-R SHALL go to the previous match, and the current match SHALL use the current-search-hit colour.

#### Scenario: Incremental search
- **WHEN** the user types `TODO` in the pane's search field
- **THEN** every `TODO` in the pane is highlighted and the first one after the cursor is scrolled into view

### Requirement: Pane scrolling keys
Space SHALL scroll the pane down a page and Delete/Backspace up a page. d/u SHALL scroll down/up 18 lines. f SHALL jump to the next file and b to the previous file; this follows gitk's actual binding, not its help text, which lists b as page-up. These keys are active whenever focus is not in a text field.

#### Scenario: Next file
- **WHEN** the user presses `f`
- **THEN** the pane scrolls so the next file separator is at the top, and the Changed Files section highlights that file

### Requirement: Tree mode
In Tree mode, selecting a file in the tree SHALL show that file's contents at the selected commit, decoded with the file's encoding.

#### Scenario: View a file at a revision
- **WHEN** Tree mode is on and the user clicks `src/main.c`
- **THEN** the pane shows the blob contents of `src/main.c` as of the selected commit

### Requirement: Per-file encodings
When "Support per-file encodings" is on, each file's text SHALL be decoded with the `encoding` gitattribute for its path, falling back to `gui.encoding`, then the system encoding.

#### Scenario: Shift-JIS file
- **WHEN** a file has the gitattribute `encoding=shift_jis`
- **THEN** its diff lines show the Japanese text correctly

### Requirement: Line origin
The pane's context menu SHALL offer "Show origin of this line", which finds the commit that introduced the clicked line (via blame on the right parent), selects that commit and highlights the line. It SHALL also offer "Run git gui blame on this line".

#### Scenario: Origin of an added line
- **WHEN** the user right-clicks a context line in a diff and chooses "Show origin of this line"
- **THEN** the commit that last changed that line is selected and the line is marked in its diff
