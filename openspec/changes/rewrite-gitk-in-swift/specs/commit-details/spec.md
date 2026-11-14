# Spec Delta

## Purpose

Defines the commit details sidebar on the right: identity, the gitk header rows, the message and notes, nearby refs, changed files, and clickable links. It explains where a commit sits in history.

## ADDED Requirements

### Requirement: Details sidebar
Selecting a commit SHALL fill a resizable right-hand sidebar and replace the previous commit's content. The sidebar SHALL have an identity header, a metadata group, a collapsible Message section and a Changed Files section. It SHALL have no close button; View → Details Sidebar and the toolbar's sidebar button SHALL hide and show it.

#### Scenario: Sidebar follows selection
- **WHEN** the user selects another commit
- **THEN** the identity header, metadata rows, message and changed files all replace the previous commit's

### Requirement: Identity and metadata
The identity header SHALL show the author's monogram, name, date and time, email, full commit ID and refs. The metadata group SHALL show "Author:" and "Committer:" rows, a "Tags:" row when present, "Parent:" rows in their merge colours, "Child:" rows, "Branch:", "Follows:" and "Precedes:".

#### Scenario: Merge commit
- **WHEN** a two-parent merge is selected
- **THEN** two "Parent:" rows appear, coloured with the first and second merge colours, each followed by that parent's subject

### Requirement: Message section
The Message section SHALL show the full commit message followed by any notes. Clicking its header SHALL collapse or expand the section.

#### Scenario: Commit with notes
- **WHEN** the commit has a `refs/notes/commits` note
- **THEN** the note text appears below the message

#### Scenario: Message section collapses
- **WHEN** the user clicks the Message section header
- **THEN** the message and notes fold away and the Changed Files section moves up, and clicking again restores them

### Requirement: Nearby refs
When "Display nearby tags/heads" is on, the sidebar's metadata group SHALL include "Branch:" (branches containing the commit), "Follows:" (nearest tags before it) and "Precedes:" (nearest tags after it). These SHALL be filled in asynchronously from a full-repository ancestry index, and limited to the configured maximum number of refs. Branches in "visible refs" are always shown.

#### Scenario: Nearby tags computed in the background
- **WHEN** the user selects a commit right after startup in a large repository
- **THEN** the sidebar appears at once, and the Branch/Follows/Precedes values fill in when the ancestry index is ready, without blocking the UI

#### Scenario: Too many branches
- **WHEN** more than the configured maximum number of branches contain the commit
- **THEN** only the always-visible refs are listed, followed by "and many more" (or just "many" if none are always-visible)

#### Scenario: Index reused across launches
- **WHEN** the app is started again in the same repository
- **THEN** the ancestry index is loaded from the app's cache in the git dir and only updated for new commits

### Requirement: Commit-ID links
Any hexadecimal string in the sidebar or message that is 6 to N characters long (N = hash length), or a `-g<hex>` describe suffix, SHALL be a link if it resolves to a commit. Clicking it SHALL select that commit and record the jump in the back/forward history.

#### Scenario: Revert message link
- **WHEN** a message contains "This reverts commit 1a2b3c4d…"
- **THEN** the hash is a link, and clicking it selects the reverted commit

#### Scenario: Unknown hash
- **WHEN** a hex string does not match any commit
- **THEN** it is shown as plain text

### Requirement: Web links
`http://` and `https://` URLs in the message SHALL be links. Clicking one SHALL open the URL using the configured web browser command, which defaults to the system default browser.

#### Scenario: Open a URL
- **WHEN** the user clicks `https://example.com/issue/1` in a message
- **THEN** that URL opens in the default browser

### Requirement: Comment wrapping
The commit message in the sidebar's Message section SHALL be wrapped according to the "Wrap comment text" preference (none, char or word).

#### Scenario: Word wrap
- **WHEN** wrapping is set to "word" and a message line is longer than the pane width
- **THEN** it wraps at a word boundary without horizontal scrolling

### Requirement: Annotated tag display
Clicking a tag label in the graph SHALL show the tag's name and the tag object's contents (tagger and message) in the details sidebar, with the tagged commit ID as a link.

#### Scenario: Click a tag
- **WHEN** the user clicks the `v1.0` label
- **THEN** the sidebar shows the tag message and tagger, and the Changed Files section is cleared
