# Spec Delta

## Purpose

Defines the "List references" window (F2), which lists the repository's heads and tags so the user can filter them and jump to the commit a ref points at.

## ADDED Requirements

### Requirement: Reference list window
File→"List references" and F2 SHALL open a window titled "Tags and heads: <repo name>". It SHALL list every local head and tag (and remote heads unless hidden), each with its target commit's subject. If the window is already open, it SHALL be brought to the front instead.

#### Scenario: Open with F2
- **WHEN** the user presses F2
- **THEN** a window lists all heads and tags in the repository

### Requirement: Filtering and sorting
The window SHALL have a filter field that takes a glob pattern (default `*`) and lists only matching ref names. It SHALL have a "Sort refs by type" option that groups heads before tags; otherwise refs are sorted by name.

#### Scenario: Filter refs
- **WHEN** the user types `release*` in the filter
- **THEN** only refs whose names match `release*` are listed

### Requirement: Jump to reference
Clicking a ref SHALL select its commit in the main window if the commit is in the current view.

#### Scenario: Ref outside view
- **WHEN** the clicked ref's commit is not in the current view
- **THEN** the main selection does not change

### Requirement: Live updates and geometry
The list SHALL refresh when refs change (after Update, Reread references, or a branch/tag action). Its window size and position SHALL be remembered across launches. Escape and the Close button SHALL close it.

#### Scenario: Branch created while open
- **WHEN** the window is open and the user creates a branch from the commit context menu
- **THEN** the new branch appears in the list without reopening the window
