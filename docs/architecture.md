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
  Legacy import takes only a font's family: Tk sizes (gitk saves 8–9 pt) are
  far too small next to native macOS text, so size and style stay the app's.
  gitk's own default families (Lucida Grande, Monaco, sans, monospace,
  Helvetica, Courier) are not imported, since gitk writes them on every save.
  This differs from the preferences "Import existing config" scenario, which
  expects `Menlo 11`; the user chose families only on 2026-11-15.
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
- 2026-11-16, 18.3: ⌘-0 resets all three fonts to the default 12 pt, keeping the families, weights and slants chosen in Preferences; gitk has no reset, so zooming out is the only way back.
- 2026-11-14, cli-launch: `gitk-swift <path-to-repo> [args]` opens that repository when the path is a repository's top level, or when the working directory is not in a repository (`RepositoryArgument`). gitk always uses the working directory; a subdirectory of the current repository is still a path limit.
- 2026-11-14, 11.1/11.5: A colour setting that still has gitk's default value (window, text, diff, link, find, graph line, merge, commit dot and ref label colours) is drawn with the app's pastel theme (Catppuccin Latte in light mode, Mocha in dark mode), so the app reads well in both appearances. A colour set in Preferences or `settings.json` is used exactly (`Palette`, `Theme`).
- 2026-11-15, 10.1: The history list has a header row (Headline, Author, Date) whose dividers resize the columns, and the author and date columns fit their content with the headline taking the rest (`ColumnSizing`). gitk has no header and places the three panes at fixed sash positions (`pwsash0`, `pwsash1`), so its date pane can be cut off in a narrow window.
- 2026-11-16, 10.8: While reading or searching, the pointer shows macOS's native spinning wait cursor (`NSCursor`'s `busyButClickableCursor`, which has no public API) rather than gitk's hourglass; the hourglass remains the fallback when the system cursor is unavailable. The status strip's progress bar still says what the operation is.
- 2026-11-16, 10.10: The first column's horizontal scroll keeps the graph lanes and dots fixed and scrolls the ref labels and headline underneath them, and the headline is drawn at its full width rather than clipped to the column width. gitk scrolls that whole canvas, so its graph leaves the view while reading a long message.
- 2026-11-16, 10.10: When the graph is wider than the width limit (`maxwidth`, `maxgraphpct`), the lanes, arrows and dots past the limit are clipped where the ref labels or headline begin, so they are not drawn through the text (`GraphCellView.graphClipRect`).
- 2026-11-16, cli-launch: Launched outside a repository with no revisions or paths (only options, or nothing), the app opens a window saying "Cannot find a git repository here." and shows a folder chooser as a sheet on it (`RepositoryPickerWindowController`); the chosen repository then opens with those options. Cancelling leaves the window with an Open Repository button, and closing it quits. gitk exits straight away. With `GITK_SWIFT_HEADLESS_ERRORS=1`, or when revisions or paths were given, the app still exits with gitk's error. The chooser is a sheet, not `runModal()`, because a modal run loop inside the async start-up task blocks the main actor.
- 2026-11-16, cli-launch: `--default-settings` (not in gitk) starts with the built-in settings, reads neither `settings.json` nor the Tcl gitk config, and saves nothing on quit. It is removed from the options before they reach git.
- 2026-11-16, launch: When `DYLD_LIBRARY_PATH` or `DYLD_FALLBACK_LIBRARY_PATH` is set, gitk-swift re-executes itself without them. On macOS 27 those paths make ImageIO load Homebrew's libpng/libtiff and crash (SIGBUS) whenever CoreText draws an emoji; gitk draws its text through Tk, so it never hits that decoder. A terminal launch prints one line saying why it restarted.
- 2026-11-16, ui: Ref labels in the history list have no outline (gitk draws one in the head and tag outline colours), heads have rounded corners, and tags keep gitk's pointed left end but have rounded right corners and 3 pt more width after the name. A remote branch's prefix colour fills the label edge to edge up to the branch name. The sidebar's ref labels are rounded boxes too.
- 2026-11-16, ui: The sidebar's commit ID sits on a dim rounded fill, brightens on hover and shows a "Copy" hint at once instead of a delayed tooltip with the full ID; clicking it copies the ID and shows "Copied!" for half a second.

## New strings

User-visible strings with no gitk msgid. These have no translations.

- `Settings…`
- `Copy`
- `Copied!`
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
- `Diff options`
- `Diff mode`
- `Choose a repository to open.`
- `Open Repository…`
- `Open`

## Performance

Measured results of `GITK_PERF=1 swift test -c release --filter PerfTests` on
the `huge` fixture (task 8.9).

| Date | Machine | First 100 rows | Full load | Peak RSS |
|---|---|---|---|---|
| 2026-11-14 | MacBookPro18,3 (M1 Pro, 16 GB) | 0.08 s | 1.43 s | 439 MB (RSS after load) |

### Commit search (task 14.7)

`SearchIndex` keeps the decoded searchable text of every loaded commit in
immutable chunks, built on a background task from raw bytes that
`CommitStore.searchSource(at:)` hands over in slices of 1,000 commits (the
only main-actor work). `SearchScanner` scans the chunks in parallel off the
main actor, delivers the visible rows first, narrows when the pattern extends
the previous Exact/IgnCase one (only the previous matches and newly indexed
commits are tested; Regexp is never narrowed), reads only the selected field,
and supersedes older searches by generation. `SearchBar` waits 100 ms after a
keystroke before scanning. Exact and IgnCase compare UTF-8 bytes, which is the
same test as gitk's glob `*text*`.

Measured with `GITK_PERF=1 swift test -c release --filter FindPerfTests` on the
`huge` fixture (200,000 commits), 2026-11-15, MacBookPro18,3 (M1 Pro, 16 GB).
"Stall" is the longest delay of a 1 ms timer on the main actor while the
search was consumed there.

| Search | First visible results | Full result | Main-actor stall | Matches |
|---|---|---|---|---|
| Headline, IgnCase `commit` (common) | 0.2 ms | 38 ms | 11.4 ms | 200,000 |
| All fields, Exact `Alice` | 0.6 ms | 35 ms | 6.3 ms | 196,000 |
| All fields, Exact no-match text | 0.1 ms | 6 ms | 2.9 ms | 0 |
| Narrowed `commit` to `commit 1` | | 22 ms | | 111,111 |
| Index build (once per load) | | 0.69 s | 12.1 ms | |
| Superseded search stops | 1.2 ms | | | |

Budgets: first visible ≤ 120 ms, full ≤ 1 s, superseded search stops ≤ 50 ms,
main actor never blocked > 16 ms.
