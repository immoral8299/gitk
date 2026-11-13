# Spec Delta

## Purpose

Defines the user-configurable settings, the preferences window, how settings and window geometry persist, and the one-way import of an existing Tcl gitk configuration.

## ADDED Requirements

### Requirement: Preferences window
gitk-swift→Settings… (⌘-,) SHALL open a preferences window with General, Colors and Fonts pages and OK/Cancel buttons. OK SHALL apply and save the edited settings. Cancel SHALL discard them.

#### Scenario: Change a colour
- **WHEN** the user changes "New line background" and clicks OK
- **THEN** added lines in the diff pane use the new colour immediately

#### Scenario: Cancel
- **WHEN** the user changes several settings and clicks Cancel
- **THEN** none of them take effect and none are saved

### Requirement: General settings page
The General page SHALL edit: maximum graph width (lines and %), show local changes, hide remote refs, refs to hide, copy commit ID to clipboard, copy length, wheel multiplier, tab spacing, wrap comment text, wrap other text, display nearby tags/heads, maximum tags/heads, limit diffs to listed paths, per-file encodings, external diff tool (with a file chooser), web browser and date/time format.

#### Scenario: Toggle local changes
- **WHEN** the user turns off "Show local changes" and clicks OK
- **THEN** the local-changes rows disappear from the current view

### Requirement: Colour and font settings pages
The Colors page SHALL edit the background, main text, selected text background, link text, old/new line text and background, hunk header text and marked line background colours, each with a colour picker. The Fonts page SHALL edit the main, text and UI fonts with the system font picker.

#### Scenario: Change the text font
- **WHEN** the user picks Menlo 12 as the text font and clicks OK
- **THEN** the diff pane is redrawn in Menlo 12

### Requirement: Defaults match gitk on macOS
With no saved or imported settings, every setting SHALL have the value gitk uses on macOS: the same colours, graph limits, diff context of 3, tab stop 8, date format `%Y-%m-%d %H:%M:%S`, external diff tool `opendiff`, web browser `open`, and copy length equal to the hash length. The default fonts SHALL be the closest current macOS equivalents of gitk's aqua fonts.

#### Scenario: Fresh install
- **WHEN** a user with no gitk config launches the app
- **THEN** the head label is green, the tag label is yellow, the diff context is 3, and "Show local changes" is on

### Requirement: Persistence
Settings, remembered views and window geometry (window frame, pane split positions, reference-list frame) SHALL be saved in the app's own settings store when they change and when the app quits, and restored on the next launch. Saving SHALL be atomic, so a crash never leaves a corrupt settings file.

#### Scenario: Geometry restored
- **WHEN** the user resizes the window and moves the pane dividers, then quits and relaunches
- **THEN** the window and dividers come back at the same sizes

#### Scenario: Corrupt settings
- **WHEN** the settings file cannot be parsed at launch
- **THEN** the app starts with defaults, writes a warning to stderr, and does not overwrite the bad file until a setting changes

### Requirement: Legacy gitk config import
On launch with no settings of its own, the app SHALL read the Tcl gitk config: `$XDG_CONFIG_HOME/git/gitk`, else `~/.config/git/gitk`, else `~/.gitk`. It SHALL import every variable it supports, plus `permviews` and `geometry(...)`, by parsing Tcl `set` commands and list quoting without running any Tcl. Unsupported variables (theme, themeloader, ui colours) SHALL be ignored. The legacy file SHALL never be modified.

#### Scenario: Import existing config
- **WHEN** `~/.config/git/gitk` has `set mainfont {Menlo 11}`, `set diffcontext 5` and two remembered views
- **THEN** on first launch the main font is Menlo 11, the context is 5, and both views are in the View menu

#### Scenario: Config with code
- **WHEN** the legacy file contains Tcl that is not a plain `set` (for example `proc` or `exec`)
- **THEN** those lines are skipped, the rest is imported, and nothing is executed

#### Scenario: Legacy file untouched
- **WHEN** the user changes settings in the app
- **THEN** the legacy gitk config file's bytes and modification time stay the same

### Requirement: Font size shortcuts
⌘-plus, ⌘-equal and ⌘-keypad-plus SHALL make all three fonts one point bigger. ⌘-minus and ⌘-keypad-minus SHALL make them one point smaller, down to a minimum of 1. The change SHALL be saved.

#### Scenario: Increase font
- **WHEN** the user presses ⌘-plus twice
- **THEN** the list, details and diff text are 2 points bigger, and stay that size after relaunch

### Requirement: Quit and close
⌘-Q and File→Quit SHALL save state, stop background git processes, remove temporary files and quit. ⌘-W in the main window SHALL quit. ⌘-W in any other window SHALL close that window.

#### Scenario: Quit during load
- **WHEN** the user presses ⌘-Q while a view is loading
- **THEN** the app quits promptly and no `git` child processes remain
