# Spec Delta

## Purpose

Defines named views: saved sets of revision, filter and path arguments that select which commits are shown. Users can create, edit, switch, delete and remember them across sessions.

## ADDED Requirements

### Requirement: Command-line view
The view built from the command-line arguments SHALL be the initial view. It SHALL appear in the View menu as "Command line" when arguments were given; otherwise the initial view is "All files" (view 0), which cannot be edited or deleted.

#### Scenario: No arguments
- **WHEN** the app is started with no arguments
- **THEN** the View menu shows "All files" selected, and "Edit view..." and "Delete view" are disabled

### Requirement: View editor
"New view..." (Shift-F4) and "Edit view..." (F4) SHALL open a view editor titled "<title> -- criteria for selecting revisions". It SHALL have OK, "Apply (F5)" and Cancel buttons. OK and Apply SHALL turn the fields into git log arguments and (re)load the view.

#### Scenario: Create a view
- **WHEN** the user creates a view named "Alice since March" with Author `alice` and Since `2026-03-01`
- **THEN** the view is added to the View menu, selected, and loaded with `--author=alice --since=2026-03-01`

#### Scenario: Apply without closing
- **WHEN** the user clicks "Apply (F5)" in the editor
- **THEN** the view reloads with the new criteria and the editor stays open

### Requirement: View editor fields
The editor SHALL show gitk's fields in gitk's order:
- name and "Remember this view"
- branches & tags, plus all refs, local branches, tags and remote branches
- author, committer and message, with match-all and match-none
- pickaxe string as fixed or regexp
- since and until
- number to show and number to skip
- date order, left-right, first parent and simplify-by-decoration
- extra args, paths, and an args command

#### Scenario: Pickaxe as regexp
- **WHEN** the user enters `foo.*bar` as the search string and selects "Regular Expression"
- **THEN** the view is loaded with `-Sfoo.*bar --pickaxe-regex`

#### Scenario: Paths field
- **WHEN** the user enters `src/` and `docs/` on separate lines
- **THEN** the view is limited to those two paths

### Requirement: Round-trip of view arguments
Opening the editor on an existing view SHALL split its stored argument list back into the editor fields using gitk's option patterns. Unrecognized arguments SHALL be put in "Additional arguments", and leading `-<n>` SHALL be read as the number to show.

#### Scenario: Edit a command-line view
- **WHEN** the app was started with `--author=bob -20 --no-merges` and the user presses F4
- **THEN** Author shows `bob`, Number to show shows `20`, and Additional arguments shows `--no-merges`

### Requirement: Switching and deleting views
Choosing a view in the View menu SHALL load it and keep the selected commit if it is in the new view. "Delete view" SHALL remove the current view, forget it if it was remembered, and switch to "All files".

#### Scenario: Switch keeps selection
- **WHEN** commit X is selected and the user switches to a view that contains X
- **THEN** X is still selected after the new view loads

### Requirement: Remembered views
Views with "Remember this view" checked SHALL be saved and shown in the View menu on later launches, with their name, paths, arguments and args command. On first launch, remembered views from the legacy gitk config SHALL be imported.

#### Scenario: Persist across launches
- **WHEN** the user creates a remembered view and relaunches the app
- **THEN** the view is in the View menu with the same criteria

#### Scenario: Unchecked view not saved
- **WHEN** a view is created without "Remember this view"
- **THEN** it is gone from the View menu after relaunch

### Requirement: Merge-conflict view
A view argument of `--merge` SHALL limit the view to files that are currently unmerged. If no files are unmerged, the app SHALL show "No files selected: --merge specified but no files are unmerged.". If there are unmerged files but none is within the view's path limit, the message SHALL be "...no unmerged files are within file limit.".

#### Scenario: Merge in progress
- **WHEN** a merge has conflicts in `a.c` and the user runs `gitk-swift --merge`
- **THEN** the view shows commits touching `a.c` from both sides of the merge
