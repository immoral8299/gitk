# Spec Delta

## Purpose

Defines how the app is started from a terminal: which arguments it accepts, how it finds the repository, and how it reports startup failures. Existing gitk command lines must keep working unchanged.

## ADDED Requirements

### Requirement: gitk-compatible command line
The app SHALL accept `[options] [revision args] [-- paths]` with gitk's semantics. It SHALL recognize `--select-commit=<rev>` and `--argscmd=<command>`, skip empty arguments, and pass every other argument before `--` through to `git log` as revision arguments for the initial view.

#### Scenario: Revision range and paths
- **WHEN** the user runs `gitk-swift v1.0..v2.0 -- src/`
- **THEN** the initial view shows only commits in `v1.0..v2.0` that touch `src/`

#### Scenario: Select a commit at startup
- **WHEN** the user runs `gitk-swift --select-commit=abc123`
- **THEN** once commit `abc123` has loaded it is selected and scrolled into view

#### Scenario: HEAD as select-commit
- **WHEN** `--select-commit=HEAD` is given
- **THEN** the app behaves as if no `--select-commit` were given (HEAD is selected by default)

#### Scenario: Args command
- **WHEN** the user runs `gitk-swift --argscmd='git for-each-ref --format=%(refname) refs/heads/feature*'`
- **THEN** the command is run with `sh -c` each time the view is loaded, and each line of its output is added as a revision argument

### Requirement: Paths without a `--` separator
When there is no `--`, the app SHALL use `git rev-parse --no-revs --no-flags` to find out which trailing arguments are paths. An argument that names both a revision and an existing file SHALL be rejected as ambiguous.

#### Scenario: Bare path argument
- **WHEN** the user runs `gitk-swift README.md` and `README.md` is not a revision
- **THEN** `README.md` is used as a path limit, not as a revision

#### Scenario: Ambiguous argument
- **WHEN** an argument is both a valid revision and an existing file
- **THEN** the app shows "Ambiguous argument '<arg>': both revision and filename" and exits with a non-zero status

#### Scenario: Bad revision
- **WHEN** `git rev-parse` fails on the arguments
- **THEN** the app shows "Bad arguments to gitk:" followed by git's message with the text up to and including `fatal:` removed, and exits with a non-zero status

### Requirement: Repository discovery
The app SHALL find the repository the way git does from the current working directory, honouring `GIT_DIR` and `GIT_WORK_TREE`. It SHALL work in bare repositories, which have no local-changes rows, and in linked worktrees.

#### Scenario: Not a repository
- **WHEN** the app is started outside any git repository with revisions or paths, or with headless errors
- **THEN** it shows "Cannot find a git repository here." and exits with a non-zero status

#### Scenario: Not a repository, no revisions or paths
- **WHEN** the app is started outside any git repository with no arguments, or only options
- **THEN** it opens a window saying "Cannot find a git repository here." with a folder chooser on it, opens the chosen repository with those options, and asks again if the folder is not a repository; after a cancel the window offers an Open Repository button, and closing it quits

#### Scenario: Started from a subdirectory
- **WHEN** the app is started in a subdirectory of a work tree
- **THEN** the whole repository's history is shown, and repository-relative paths are handled correctly in path filters and external tools

### Requirement: Repository argument
As an addition to gitk's command line, the first argument SHALL open another repository when it comes before any `--`, does not start with `-`, names a directory where git finds a repository, and either that directory is the top level of its work tree (or a git directory) or the working directory is not inside a repository. The app SHALL then run in that directory and treat the remaining arguments as gitk arguments. A subdirectory of the current repository SHALL remain a path limit.

#### Scenario: Open a repository by path
- **WHEN** the user runs `gitk-swift ~/code/other-repo --all` from any directory
- **THEN** the window shows `other-repo` with all branches, as if started inside it

#### Scenario: Subdirectory stays a path
- **WHEN** the user runs `gitk-swift src` inside a repository whose `src` is an ordinary directory
- **THEN** `src` limits the history to that path, as in gitk

### Requirement: Environment and version checks
At startup the app SHALL check that `git` is version 2.20 or later. It SHALL detect the repository's object format (SHA-1 → 40 hex characters, SHA-256 → 64) and remove `GIT_TRACE` from the environment of the git processes it starts.

#### Scenario: Git too old
- **WHEN** `git version` reports a version below 2.20
- **THEN** the app shows a fatal error naming the minimum (2.20.0) and the version found, and exits

#### Scenario: SHA-256 repository
- **WHEN** the repository uses `sha256`
- **THEN** commit IDs are handled and shown as 64-character hashes everywhere, including the details sidebar and the default copy length

#### Scenario: Unknown hash algorithm
- **WHEN** `git rev-parse --show-object-format` reports anything other than `sha1` or `sha256`
- **THEN** the app writes "Unknown hash algorithm" to stderr and exits with a non-zero status

### Requirement: Foreground activation
When launched from a terminal, the app SHALL appear as a regular foreground application with a Dock icon and menu bar, and its main window SHALL have keyboard focus.

#### Scenario: Launch from terminal
- **WHEN** the user runs the executable from Terminal
- **THEN** the gitk window comes to the front with keyboard focus, and the terminal prompt returns only after the app quits
