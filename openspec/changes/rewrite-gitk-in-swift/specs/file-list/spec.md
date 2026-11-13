# Spec Delta

## Purpose

Defines the lower-right pane, which lists the files changed by the selected commit (Patch mode) or the commit's full tree (Tree mode), and its file-level actions.

## ADDED Requirements

### Requirement: Patch-mode file list
In Patch mode the pane SHALL list "Comments" first, then each changed file in diff order. Clicking "Comments" SHALL scroll the diff pane to the top. Clicking a file SHALL scroll the diff pane to that file's separator.

#### Scenario: Jump to file
- **WHEN** the user clicks the third file in the list
- **THEN** the diff pane scrolls so that file's separator header is at the top

### Requirement: Linked highlighting
As the diff pane scrolls, the file list SHALL highlight the file whose section is at the top of the diff pane.

#### Scenario: Scroll the diff
- **WHEN** the user scrolls the diff pane from file 1 into file 2
- **THEN** the highlight in the file list moves from file 1 to file 2

### Requirement: Tree mode
In Tree mode the pane SHALL show the commit's tree as an expandable directory hierarchy (directories closed by default, expanded or collapsed by clicking). Clicking a file SHALL show its contents in the diff pane. Files touched by the find bar's "touching paths" pattern SHALL be highlighted.

#### Scenario: Expand a directory
- **WHEN** the user clicks the `src/` entry
- **THEN** its children appear indented beneath it

### Requirement: File context menu
Secondary-clicking a file SHALL offer:
- "Highlight this too": add the path to the touching-paths find pattern.
- "Highlight this only": replace the pattern with the path.
- "External diff": open the configured external diff tool on the old and new versions.
- "Blame parent commit": run `git gui blame` on the parent revision.
- "Copy path": copy the repository-relative path.

#### Scenario: External diff
- **WHEN** the user chooses "External diff" on `a.c` for commit C with parent P
- **THEN** the old and new versions of `a.c` are written to a temporary directory (under `GITK_TMPDIR` if set) and the external diff tool is started on them

#### Scenario: External diff with a renamed file
- **WHEN** the file was renamed in the commit
- **THEN** the old version is taken from the old path

#### Scenario: Highlight this only
- **WHEN** the user chooses "Highlight this only" on `lib/util.c`
- **THEN** the find bar switches to "touching paths:" with pattern `lib/util.c`, and the commits touching it are shown in bold

#### Scenario: Copy path
- **WHEN** the user chooses "Copy path"
- **THEN** the clipboard holds the file's path relative to the repository root

### Requirement: Temporary file cleanup
Temporary files created for external diffs SHALL be deleted when the app quits.

#### Scenario: Quit after external diff
- **WHEN** the user has opened two external diffs and then quits
- **THEN** the temporary directory created by the app no longer exists
