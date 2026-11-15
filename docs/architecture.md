# Architecture notes

The design rationale lives in
`openspec/changes/rewrite-gitk-in-swift/design.md`. This file records what the
implementation actually does where that goes beyond, or departs from, the
design: deviations from gitk, new strings and measured performance. Keep each
entry short and dated.

## Deviations

Behaviour that intentionally differs from Tcl gitk. Each entry gives what gitk
does, what gitk-swift does, why, and which task introduced it.

Planned (from the proposal and design):

- No Tk themes or theme loader; no X11 PRIMARY-selection auto-copy; no
  Windows/Linux code paths.
- View and ancestry highlighting (`hlview`, `highlight_related`) are not
  ported, because no gitk UI reaches them.
- Default fonts are the system font, the monospaced system font and the bold
  system font at 12 pt, not Lucida Grande / Monaco at 9 pt (design D9).
  Imported fonts are used as they are.
- gitk-swift never writes the Tcl gitk config file, and caches the ancestry
  index in `<gitdir>/gitk-swift.cache`, not `gitk.cache`.
- The `b` key goes to the previous file in the diff (gitk's actual binding),
  even though gitk's key-help text lists it as page-up.

Recorded during implementation:

- 2026-11-13, 8.1: "Bad arguments to gitk:" strips git's text up to and including `fatal:` wherever it occurs. gitk strips only when the index is > 0, so it never strips git's usual `fatal: …` message; the spec asks for stripping.
- 2026-11-13, 8.2: Startup checks the repository before the hash algorithm. gitk runs `rev-parse --show-object-format` first, which fails with an uncaught Tcl error outside a repository; we show "Cannot find a git repository here." instead.
- 2026-11-13, 8.3: `path_filter` matches file limits as literal prefixes. gitk uses `string match "$p*"`, so glob characters in a limit act as wildcards there.
- 2026-11-13, 14.1: Find's Regexp mode uses ICU (`NSRegularExpression`), not Tcl ARE. Differences such as `\m \M \y`, `***=` and embedded options are listed in `FindQuery.doesMatch`'s doc comment.
- 2026-11-13, 16.1: Cherry-pick and revert also recognise current git's "files would be overwritten by merge:" list format for local-changes failures. gitk's `Entry '…'` pattern no longer matches git 2.54 output.
- 2026-11-13, 2.5: `gui.encoding` defaults to UTF-8, standing in for Tcl's `[encoding system]`.
- 2026-11-15, 11.13: The diff pane renders at most 200,000 lines of a patch, then shows "N more lines not shown. Show all". The whole patch is still read and parsed, so the Changed Files list, its counts and file jumps cover every file. gitk renders everything.
- 2026-11-15, 13.1: The Changed Files list is built from the streamed diff's file sections (with per-file +/− counts) instead of gitk's separate `git diff-tree -r` call, so it always matches the diff pane, renames and copies included (`-C`), and needs no extra git process. A clean merge, whose `--cc` diff is empty, therefore lists no files; gitk lists the files changed against the first parent.
- 2026-11-15, 18.3: ⌘-plus and ⌘-minus change the user interface font as well as the main and text fonts (the preferences spec says "all three fonts"). gitk's `incrfont` changes only the main and text fonts.
- 2026-11-14, cli-launch: `gitk-swift <path-to-repo> [args]` opens that repository when the path is a repository's top level, or when the working directory is not in a repository (`RepositoryArgument`). gitk always uses the working directory; a subdirectory of the current repository is still a path limit.
- 2026-11-14, 11.1/11.5: A colour setting that still has gitk's default value (window, text, diff, link, find, graph line, merge, commit dot and ref label colours) is drawn with the app's pastel theme (Catppuccin Latte in light mode, Mocha in dark mode), so the app reads well in both appearances. A colour set in Preferences or `settings.json` is used exactly (`Palette`, `Theme`).
- 2026-11-15, 10.1: The history list has a header row (Headline, Author, Date) whose dividers resize the columns, and the author and date columns fit their content with the headline taking the rest (`ColumnSizing`). gitk has no header and places the three panes at fixed sash positions (`pwsash0`, `pwsash1`), so its date pane can be cut off in a narrow window.

## New strings

User-visible strings with no gitk msgid. These have no translations.

- `Settings…`
- `Copy`
- `Paste`
- `Select all`
- `Search commits…`
- `Go to commit…`
- `Search in`
- `Matching`
- `Field`
- `Date and time format`
- `Details Sidebar`
- `Message`
- `Back`
- `Forward`
- `Previous match`
- `Next match`
- `1 Changed File`
- `Commit`
- `Show More`
- `Show Less`
- `List`
- `%d more lines not shown.`
- `Show all`
- `%d Changed Files`
- `Found text background`
- `Current search hit background`

## Performance

Measured results of `GITK_PERF=1 swift test -c release --filter PerfTests` on
the `huge` fixture (task 8.9).

| Date | Machine | First 100 rows | Full load | Peak RSS |
|---|---|---|---|---|
| 2026-11-14 | MacBookPro18,3 (M1 Pro, 16 GB) | 0.08 s | 1.43 s | 439 MB (RSS after load) |
