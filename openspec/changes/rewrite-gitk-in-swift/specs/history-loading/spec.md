# Spec Delta

## Purpose

Defines how commits and references are read from git for the current view, ordered for display, and refreshed. Large histories must stay usable while they are still loading.

## ADDED Requirements

### Requirement: Streaming commit load
The app SHALL load a view's commits by running `git log --no-color -z --pretty=raw --show-notes --parents --boundary` with the view's arguments, feeding revisions and paths on stdin. Commits SHALL appear in the list while git is still producing output, without blocking the UI.

#### Scenario: Large repository
- **WHEN** the app opens a repository with over 1,000,000 commits
- **THEN** the first screen of commits is shown before the load finishes, the UI keeps responding to scrolling and selection, and the progress indicator shows "Reading" until the load completes

#### Scenario: git log fails
- **WHEN** the `git log` process exits with an error
- **THEN** the app shows "Error executing git log:" with git's stderr, and keeps any commits it already loaded

### Requirement: Display ordering
Commits SHALL be shown in gitk's ordering: every commit above all of its parents, with each line of development kept as contiguous as git's output allows. Arguments that set an explicit order (for example `--date-order`) SHALL be honoured.

#### Scenario: Parents below children
- **WHEN** any view has finished loading
- **THEN** every commit is shown on a row above all of its parents that are in the view

#### Scenario: Late-arriving child
- **WHEN** git outputs a commit whose parent is already displayed
- **THEN** the child is inserted above the parent without losing the current selection

### Requirement: Boundary and parent rewriting
Boundary commits SHALL be shown as boundary rows. When path limiting is active, parents SHALL be the simplified parents git reports.

#### Scenario: Range view
- **WHEN** the view is `A..B`
- **THEN** the commits reachable from B but not A are shown as normal rows, and the boundary commits git marks are shown as boundary rows

### Requirement: Commit metadata parsing
For each commit the app SHALL parse the parents, tree, author and committer (name, email, timestamp, timezone), the encoding header, the message, and notes from git's raw output. It SHALL decode text using the commit's encoding, falling back to `i18n.logOutputEncoding`, then `i18n.commitEncoding`, then UTF-8. Bytes that are invalid in the chosen encoding SHALL be shown rather than dropped.

#### Scenario: Non-UTF-8 commit
- **WHEN** a commit has `encoding ISO-8859-1` and a Latin-1 author name
- **THEN** the author name is shown correctly in the list and the details

#### Scenario: Unsupported encoding
- **WHEN** the configured encoding is not supported on the platform
- **THEN** the app writes a warning to stderr and decodes as UTF-8, showing invalid bytes rather than dropping them

### Requirement: References
The app SHALL read all refs (local heads, remote-tracking branches, tags, peeled annotated tags, and other refs) and the current branch (HEAD). It SHALL hide remote refs when "Hide remote refs" is set and hide refs matching the configured "Refs to hide" globs.

#### Scenario: Annotated tag
- **WHEN** an annotated tag points at a commit
- **THEN** the tag label is attached to the tagged commit, not to the tag object

#### Scenario: Detached HEAD
- **WHEN** HEAD is detached
- **THEN** no branch is marked as current, and the HEAD commit is still marked as the main head

### Requirement: Update, reload and reread references
File→Update (F5) SHALL add commits that are new since the last load without reloading the whole view. File→Reload (Shift-F5) SHALL clear and reload the view. "Reread references" SHALL refresh ref labels only. In all three, the selected commit SHALL stay selected if it is still in the view.

#### Scenario: New commit then Update
- **WHEN** a commit is made in another terminal and the user presses F5
- **THEN** the new commit appears at the top, connected to its parent, and the previous selection is kept

#### Scenario: Reload after a ref moved away
- **WHEN** a branch was force-moved and the user presses Shift-F5
- **THEN** the view is rebuilt from scratch, and commits that are no longer reachable from the view's revisions disappear

### Requirement: Local-changes rows
When "Show local changes" is on and a work tree exists, the app SHALL show a row "Local changes checked in to index but not committed" as a child of the view's HEAD commit if staged changes exist. It SHALL show "Local uncommitted changes, not checked in to index" as a child of the index row, or of HEAD if there is no index row, if unstaged changes exist. Both checks SHALL respect the view's path limits and ignore dirty submodules.

#### Scenario: Staged and unstaged changes
- **WHEN** the work tree has both staged and unstaged edits
- **THEN** the unstaged row appears first, the staged row second, and HEAD third, connected in that order

#### Scenario: Changes resolved
- **WHEN** the user commits everything and presses F5
- **THEN** both local-changes rows are removed

#### Scenario: Path-limited view
- **WHEN** the view is limited to `docs/` and only `src/` has local edits
- **THEN** no local-changes rows are shown

### Requirement: Cancellation
Switching views, reloading or quitting SHALL stop any git processes still running for the previous load and SHALL ignore output that arrives late from them.

#### Scenario: Switch view mid-load
- **WHEN** the user switches views while a large load is still running
- **THEN** the old `git log` process is terminated and none of its commits appear in the new view
