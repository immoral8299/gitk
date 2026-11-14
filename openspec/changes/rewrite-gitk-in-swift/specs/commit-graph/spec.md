# Spec Delta

## Purpose

Defines how the commit graph is laid out and drawn beside the history list: lanes, lines, commit dots, ref labels and the interactions on them. It must look and behave like gitk's graph.

## ADDED Requirements

### Requirement: Lane layout parity
For a given ordered commit list, the app SHALL assign each commit and connecting line to the same column that gitk's layout algorithm assigns. The algorithm minimizes crossings and bends lines one column per row.

#### Scenario: Matches gitk on reference repositories
- **WHEN** the layout is computed for each fixture repository (linear, octopus merge, criss-cross merges, many parallel branches, path-limited view)
- **THEN** every row's commit column and line positions equal those produced by gitk's Tcl layout procedures on the same input

#### Scenario: Linear history
- **WHEN** the history is linear
- **THEN** all commits are in column 0, joined by a single vertical line

### Requirement: Long-line truncation
A line between a child and a parent separated by a long run of rows SHALL be shown as a short stub with a downward arrow below the child and a short stub with an upward arrow above the parent. The gap in between is not drawn. Clicking an arrow SHALL scroll to the matching arrow at the other end.

#### Scenario: Distant parent
- **WHEN** a merge's second parent is hundreds of rows below it
- **THEN** a short segment with a down arrow appears under the merge, a short segment with an up arrow appears above the parent, and nothing is drawn in between

#### Scenario: Arrow jump
- **WHEN** the user clicks a down arrow
- **THEN** the list scrolls so the matching up arrow is centred in the view

### Requirement: Commit markers
Each commit SHALL be drawn as a circle. Boundary commits, the main HEAD commit, and the local-changes rows SHALL be distinguished by the configured circle colours.

#### Scenario: HEAD marker
- **WHEN** the current HEAD commit is visible
- **THEN** its circle is filled with the "main head" colour

#### Scenario: Local-changes markers
- **WHEN** the unstaged and staged local-changes rows are shown
- **THEN** their circles use the "working files" and "index" colours respectively

### Requirement: Line colours
Lines SHALL be coloured from the configured palette. A first parent continuing a single-parent child SHALL keep the child's colour, and new lines SHALL avoid the colours of lines they cross or meet where possible.

#### Scenario: Straight branch keeps colour
- **WHEN** a commit has one child and that child has one parent
- **THEN** the line between them has the same colour as the line above the child

### Requirement: Graph width limit
The graph area SHALL be no wider than the configured maximum number of lines and the configured maximum percentage of the first column's width. Text SHALL start after the graph, or at the limit if the graph is wider.

#### Scenario: Very wide graph
- **WHEN** 40 branches are active at once and the maximum width is 16 lines
- **THEN** the subject text starts at the 16-line position and the list stays readable

### Requirement: Ref labels
Branch heads, remote-tracking branches, tags and other refs SHALL be drawn as labels before the commit subject, using the configured head, remote, tag and other colours. The current branch SHALL be shown in bold. Commits with notes SHALL show a notes marker.

#### Scenario: Current branch label
- **WHEN** `main` is checked out and points at a visible commit
- **THEN** that commit shows a bold `main` label in the head colour

#### Scenario: Remote label
- **WHEN** `origin/main` points at a commit
- **THEN** the label reads `remotes/origin/main`, with the `remotes/origin/` prefix on the remote colour and `main` on the head colour

#### Scenario: Many tags on one commit
- **WHEN** a commit has more than 3 tags and they do not fit in the available width
- **THEN** a single "<n> tags..." label is drawn instead, and clicking it shows all the tags in the details sidebar

#### Scenario: Context menu on a head label
- **WHEN** the user secondary-clicks a local branch label
- **THEN** the branch context menu (check out, rename, remove, copy branch name) opens for that branch

### Requirement: Line interaction
Hovering over a line SHALL show the subject of the line's parent commit in a tooltip. Clicking a line SHALL draw it thicker and show the parent and its children (with authors and dates) as links in the details sidebar. This line view SHALL be added to the back/forward history.

#### Scenario: Click a line
- **WHEN** the user clicks the line leading down from commit X to its parent P
- **THEN** the details sidebar lists P as "Parent" and each of P's children, each as a clickable link, and the line is drawn thicker until something else is selected
