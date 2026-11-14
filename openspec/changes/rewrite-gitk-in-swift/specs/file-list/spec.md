# Spec Delta

## Purpose

Defines the Changed Files section of the details sidebar, which lists the files changed by the selected commit (Patch mode) or the commit's full tree (Tree mode), and its file-level actions.

## ADDED Requirements

### Requirement: Changed Files section
The details sidebar SHALL contain a Changed Files section below the message. Its header SHALL show the number of changed files and the added/removed line totals, and SHALL contain a Patch/Tree switch. In Patch mode the section SHALL list each changed file in diff order. Clicking a file SHALL scroll the bottom diff pane to that file's separator.

#### Scenario: Jump to file
- **WHEN** the user clicks the third file in the list
- **THEN** the diff pane scrolls so that file's separator header is at the top

#### Scenario: Change totals
- **WHEN** a commit changes one file and adds 10 lines while removing 4
- **THEN** the section header reads "1 Changed File" and "+10 −4"

### Requirement: Linked highlighting
As the diff pane scrolls, the Changed Files section SHALL highlight the file whose section is at the top of the diff pane.

#### Scenario: Scroll the diff
- **WHEN** the user scrolls the diff pane from file 1 into file 2
- **THEN** the highlight in the changed-files list moves from file 1 to file 2

### Requirement: Tree mode
In Tree mode the section SHALL show the commit's tree as an expandable directory hierarchy (directories closed by default, expanded or collapsed by clicking). Clicking a file SHALL show its contents in the diff pane. Files touched by the search bar's "touching paths" pattern SHALL be highlighted.

#### Scenario: Expand a directory
- **WHEN** the user clicks the `src/` entry
- **THEN** its children appear indented beneath it

### Requirement: File context menu
Secondary-clicking a file SHALL offer:
- "Highlight this too": add the path to the touching-paths search pattern.
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
- **THEN** the search bar switches to "touching paths:" with pattern `lib/util.c`, and the matching occurrences in the list are shown in match boxes

#### Scenario: Copy path
- **WHEN** the user chooses "Copy path"
- **THEN** the clipboard holds the file's path relative to the repository root

### Requirement: Temporary file cleanup
Temporary files created for external diffs SHALL be deleted when the app quits.

#### Scenario: Quit after external diff
- **WHEN** the user has opened two external diffs and then quits
- **THEN** the temporary directory created by the app no longer exists
