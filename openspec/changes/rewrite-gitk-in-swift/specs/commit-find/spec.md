# Spec Delta

## Purpose

Defines the find bar under the history list. It highlights every commit matching a text or path criterion and steps the selection through the matches.

## ADDED Requirements

### Requirement: Find criteria
The find bar SHALL offer four kinds of search: "containing:" (commit text), "touching paths:", "adding/removing string:" (pickaxe `-S`) and "changing lines matching:" (`-G`). For "containing:" it SHALL also offer Exact / IgnCase / Regexp matching and a field choice: All fields, Headline, Comments, Author or Committer.

#### Scenario: Case-insensitive author search
- **WHEN** the user picks "containing:", "IgnCase" and "Author", then types `alice`
- **THEN** the commits whose author contains "Alice" in any letter case are highlighted

#### Scenario: Pickaxe search
- **WHEN** the user picks "adding/removing string:" and enters `initFoo`
- **THEN** the commits git reports for `-S initFoo` within the current view are highlighted

#### Scenario: Invalid regexp
- **WHEN** "Regexp" is chosen and the pattern does not compile
- **THEN** no commits are highlighted and no error dialog interrupts typing

### Requirement: Live highlighting
As the find criteria change, every matching commit in the view SHALL be shown in bold in the list. Path and pickaxe searches SHALL run asynchronously in git, and results SHALL appear as they arrive.

#### Scenario: Highlight while typing
- **WHEN** the user types a word into the find field
- **THEN** matching commits turn bold without pressing Return, and stop being bold when the field is cleared

### Requirement: Stepping through matches
Return, ⌘-F and the ↓ button SHALL select the next match below the selection. `?` and the ↑ button SHALL select the previous match above. When the search reaches the end of the list it SHALL wrap around to the other end. ⌘-G, Shift-Down and Shift-Up SHALL search (down, down, up) without wrapping. While searching, the status SHALL read "Searching" with progress.

#### Scenario: Wraparound
- **WHEN** the selection is on the last match and the user presses Return
- **THEN** the first match from the top is selected

#### Scenario: No wrap with Shift
- **WHEN** the selection is on the last match and the user presses Shift-Down
- **THEN** the selection does not change

#### Scenario: Matches in visible text
- **WHEN** a "containing:" match is selected
- **THEN** the matching text is highlighted in the list row and in the commit details

### Requirement: Touching-paths patterns
The "touching paths:" field SHALL accept shell-quoted paths separated by whitespace, relative to the repository root. A path SHALL match the file itself and, if it is a directory, everything below it. With Exact matching, backslashes SHALL be treated as forward slashes.

#### Scenario: Directory path
- **WHEN** the user enters `src/net`
- **THEN** commits touching `src/net` or any file under `src/net/` are highlighted

#### Scenario: Quoted path with spaces
- **WHEN** the user enters `"docs/user guide.md"`
- **THEN** commits touching that single file are highlighted

### Requirement: Focus shortcuts
`/` SHALL put keyboard focus in the find field. `g` SHALL clear the Commit ID field and put focus there.

#### Scenario: Slash to search
- **WHEN** focus is on the history list and the user presses `/`
- **THEN** the find field gets keyboard focus
