# Proposal

## Why

gitk is a single 13,000-line Tcl/Tk script (`gitk/gitk`, upstream commit `6fc42f7`). On macOS it depends on a separately installed Tcl/Tk and has non-native menus, fonts, scrolling and text rendering, and it is hard to extend. A native Swift/AppKit rewrite in this repository keeps the gitk workflow people already know (same command line, same panes, same keys, same saved views) and gives it a native, maintainable codebase.

## What Changes

- Add a new macOS application, written in Swift, that matches gitk's user-facing feature set. It is built with Swift Package Manager and launched from a terminal as `gitk-swift [rev-list args] [-- paths]`.
- Keep the Tcl source in `gitk/` as a read-only reference for behaviour, for differential tests and as the source of the translations. It is not built or shipped.
- Talk to git only through the `git` CLI, using the same commands gitk runs (`git log -z --pretty=raw --parents --boundary --show-notes …`, `diff-tree`, `diff-index`, `show-ref`, `rev-parse`, and so on). Requires git ≥ 2.20 and works with SHA-1 and SHA-256 repositories.
- Read existing gitk preferences and saved views from `~/.config/git/gitk` (or legacy `~/.gitk`) as a one-way import. The Swift app saves its own settings separately and never writes the Tcl config file.
- Convert the 16 existing `po/*.po` catalogs into the app's localized resources.
- Intentional deviations from gitk, all driven by the platform:
  - Tk theme selection and the theme-loader file are not supported.
  - X11 PRIMARY-selection auto-copy is not supported. The clipboard copy option is kept.
  - Menus follow macOS conventions (application menu, ⌘ shortcuts). No Windows or Linux build.
  - Code in gitk that no UI can reach (view-membership and ancestry highlighting) is not ported.
- Delivered in milestones: launch and history → graph and commit list → details and diff → find and highlight → views → repository actions → reference list → preferences and import → localization → parity and packaging.

## Capabilities

### New Capabilities

- `cli-launch`: command-line syntax, argument splitting between revisions and paths, repository and git-version checks, startup error reporting.
- `history-loading`: streaming commits from `git log` for the current view, display ordering, incremental update and reload, rereading references, and the local-changes pseudo-commits (unstaged and staged).
- `commit-graph`: the commit graph: lane assignment, line routing, merge and branch rendering, truncated long lines with arrows, lane colours, and ref labels (heads, tags, remotes) drawn beside commits.
- `commit-list`: the three-column history list (subject+graph, author, date), selection, keyboard and mouse navigation, back/forward history, go-to-commit, the row counter and the progress/status display.
- `commit-details`: the commit header pane: author/committer, parents/children/branches as links, nearby tags (Precedes/Follows), notes, hyperlinked commit IDs in messages, and annotated tag display.
- `diff-viewer`: the patch pane: streamed diffs, combined diffs for merges, the Diff/Old/New display modes, context lines, ignore-whitespace, word-diff modes, file separators, in-pane text search, per-file encodings, and browsing files at a revision in tree mode.
- `file-list`: the changed-files / tree list beside the diff, linked scrolling with the diff, and its context menu (highlight, external diff, blame, copy path).
- `commit-find`: the find bar (containing / touching paths / adding-removing string / changing lines matching; Exact / IgnCase / Regexp; field selection), bold highlighting of matching commits, and stepping through results.
- `views`: the view editor (refs, author/committer/message filters, pickaxe, dates, limits, ordering flags, paths, extra args, args command), switching views, and remembered views.
- `repository-actions`: write operations and tool launches from context menus, using gitk's dialogs and confirmations: create/rename/remove/check out branch, create tag, cherry-pick, revert, reset (soft/mixed/hard), make patch, write commit to file, mark/compare commits, diff against selected/marked, copy reference, and launching git gui, citool, external diff and blame.
- `reference-list`: the "List references" window: filter, sort by type, and jump to a ref.
- `preferences`: the preferences dialog (display, diff, colours and fonts), persistence of settings and window geometry, font-size shortcuts, and the one-way import of the legacy gitk config.
- `localization`: UI strings in the 16 languages gitk ships, chosen from the system language.

### Modified Capabilities

None. This repository has no existing specs.

## Impact

- **New code**: a Swift package (core library, AppKit UI library and executable) plus tests at the repository root. The `gitk/` checkout stays as a pinned reference.
- **Dependencies**: Xcode/Swift 6 toolchain, macOS 14 or later, `git` ≥ 2.20 at runtime. `tclsh` is needed only for optional differential tests. No third-party Swift packages are planned.
- **User files**: reads `~/.config/git/gitk` (or `$XDG_CONFIG_HOME/git/gitk`, `~/.gitk`) but does not modify it. Writes its own settings and a separate commit-graph cache in the repository's git dir, so it does not conflict with Tcl gitk's `gitk.cache`.
- **Licensing**: the port derives from gitk's code and translations, so it stays under GPL-2.0-or-later and keeps the original copyright notices.
- **Upstream**: this is a standalone project. The upstream README forbids AI-originated contributions, so none of this work will be submitted to git/gitk.
