# Spec Delta

## Purpose

Defines the search bar in the titlebar. It highlights every commit matching a text or path criterion and steps the selection through the matches.

## ADDED Requirements

### Requirement: Search kinds
The search bar SHALL offer "containing:" (commit text), "touching paths:", "adding/removing string:" (pickaxe `-S`) and "changing lines matching:" (`-G`).

#### Scenario: Pickaxe search
- **WHEN** the user picks "adding/removing string:" and enters `initFoo`
- **THEN** the commits git reports for `-S initFoo` within the current view are highlighted

### Requirement: Text matching options
For "containing:" the bar SHALL offer Exact / IgnCase / Regexp matching and a field choice: All fields, Headline, Comments, Author or Committer.

#### Scenario: Case-insensitive author search
- **WHEN** the user picks "containing:", "IgnCase" and "Author", then types `alice`
- **THEN** the commits whose author contains "Alice" in any letter case are highlighted

#### Scenario: Invalid regexp
- **WHEN** "Regexp" is chosen and the pattern does not compile
- **THEN** no commits are highlighted and no error dialog interrupts typing

### Requirement: Advanced search options
The bar SHALL show only the text field, an Advanced ("Aa") button, a match counter and previous/next buttons. The Advanced button SHALL open a popover with the search kind, match mode and field, defaulting to containing, Exact and All fields. Changes SHALL apply live; Escape or a click outside SHALL close the popover.

#### Scenario: Options stay out of the bar
- **WHEN** the search bar is at rest
- **THEN** no Exact, All fields or kind selector appears beside the text field

#### Scenario: Advanced filters
- **WHEN** the user opens Aa, picks IgnCase and Author, and types `alice`
- **THEN** the bar still shows only the text field, the Advanced button, the counter and the arrows, and author matches are highlighted

#### Scenario: Defaults
- **WHEN** the search bar first appears
- **THEN** the popover shows containing, Exact and All fields, and the Advanced button has no dot

### Requirement: Live highlighting
As the find criteria change, every occurrence of the pattern in the visible list rows SHALL be shown in a rounded match box. Path and pickaxe searches SHALL run asynchronously in git, and results SHALL appear as they arrive. Row text SHALL keep its normal weight and colour; rows SHALL NOT be bolded to show a match.

#### Scenario: Highlight while typing
- **WHEN** the user types a word into the search field
- **THEN** every visible occurrence gets a rounded box without pressing Return, and the boxes disappear when the field is cleared

### Requirement: Match boxes
Matches in the history list, the sidebar message and the diff pane SHALL use the configured "Found text background" colour in a rounded rectangle behind the matched characters. The current match SHALL use the "Current search hit background" colour. The boxes SHALL stay aligned with the text when the list is scrolled or a column is resized.

#### Scenario: Match boxes
- **WHEN** a commit's subject contains the pattern twice
- **THEN** both occurrences have rounded boxes, and the row text is not bold

#### Scenario: Current match box
- **WHEN** the user steps to the next match
- **THEN** the new match uses the current-search-hit colour, and the previous current match returns to the found colour

#### Scenario: Matches in visible text
- **WHEN** a "containing:" match is selected
- **THEN** the matching text is shown in match boxes in the list row and in the sidebar's message

### Requirement: Search performance
Search SHALL not block typing or scrolling, even in a view with hundreds of thousands of commits. Superseded searches SHALL be abandoned, and results from a superseded pattern SHALL never appear. When the pattern only grows, the previous matches SHALL be refined instead of the whole view being rescanned.

#### Scenario: Responsive search on a large repo
- **WHEN** the user types a word in a view with 200,000 commits
- **THEN** the first match boxes appear within 120 ms, the complete result arrives within 1 s, and typing and scrolling stay responsive throughout

#### Scenario: Stale results never appear
- **WHEN** the user types `mer` and then quickly `merge`
- **THEN** only the `merge` results are ever shown

#### Scenario: Prefix refinement reuses results
- **WHEN** the user adds a character to the current pattern
- **THEN** only the previous matches are rescanned, not the whole view

#### Scenario: Cancellation
- **WHEN** the pattern is cleared or replaced while a path or pickaxe search is running
- **THEN** the previous git process stops within 100 ms and no orphan process remains

### Requirement: Stepping through matches
Return, ⌘-F and the › button SHALL select the next match below the selection. `?` and the ‹ button SHALL select the previous match above. Stepping SHALL wrap at the end of the list. ⌘-G, Shift-Down and Shift-Up SHALL step without wrapping.

#### Scenario: Wraparound
- **WHEN** the selection is on the last match and the user presses Return
- **THEN** the first match from the top is selected

#### Scenario: No wrap with Shift
- **WHEN** the selection is on the last match and the user presses Shift-Down
- **THEN** the selection does not change

### Requirement: Match counter and progress
The counter SHALL read "N / M" for the current match and the total, or "0 / 0" when there is no pattern or no match. While searching, the status strip SHALL read "Searching" with progress.

#### Scenario: Match counter
- **WHEN** a search has 12 matches and the third is selected
- **THEN** the counter reads "3 / 12"

#### Scenario: Searching status
- **WHEN** a path search is running
- **THEN** the status strip reads "Searching" and shows progress

### Requirement: Touching-paths patterns
The "touching paths:" field SHALL accept shell-quoted paths separated by whitespace, relative to the repository root. A path SHALL match the file itself and, if it is a directory, everything below it. With Exact matching, backslashes SHALL be treated as forward slashes.

#### Scenario: Directory path
- **WHEN** the user enters `src/net`
- **THEN** commits touching `src/net` or any file under `src/net/` are highlighted

#### Scenario: Quoted path with spaces
- **WHEN** the user enters `"docs/user guide.md"`
- **THEN** commits touching that single file are highlighted

### Requirement: Focus shortcuts
`/` SHALL put keyboard focus in the titlebar search field. `g` SHALL clear that field, switch it to go-to-commit mode and put focus there.

#### Scenario: Slash to search
- **WHEN** focus is on the history list and the user presses `/`
- **THEN** the search field gets keyboard focus
