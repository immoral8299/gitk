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

- (none yet)

## New strings

User-visible strings with no gitk msgid. These have no translations.

- (none yet)

## Performance

Measured results of `GITK_PERF=1 swift test -c release --filter PerfTests` on
the `huge` fixture (task 8.9).

| Date | Machine | First 100 rows | Full load | Peak RSS |
|---|---|---|---|---|
| | | | | |
