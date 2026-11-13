# Tcl oracle

`oracle.tcl` runs gitk's own ordering and layout procs under plain `tclsh`
(no Tk) and prints JSON, so Swift ports can be diffed against the original
(design D5).

```
tclsh Tests/Oracle/oracle.tcl --selftest        # prints "ok <procs loaded>"
tclsh Tests/Oracle/oracle.tcl --repo <dir> ...  # tasks 5.2, 5.3
tclsh Tests/Oracle/oracle.tcl --allcommits <dir> # task 12.1
```

It needs the `gitk/` submodule (`git submodule update --init gitk`) and never
modifies it.

## How it loads gitk

1. `gitk/gitk` is read line by line; lines are accumulated until
   `info complete` is true, which yields one top-level command.
2. Only commands that start with `proc` are evaluated, at global level.
   Everything else is skipped: Tk setup, `makewindow`, argv parsing,
   `package require`, config reads, and procs nested in an `if`.
3. The stubs below are defined **after** loading, so they replace gitk's own
   versions.
4. Globals the algorithms read are set by `oracle::initGlobals` (values copied
   from the gitk lines cited in the script).

gitk 6fc42f7 has 427 top-level `proc` definitions; `--selftest` requires at
least 420.

## Not a `proc`, so reproduced by hand

- `convertfrom` (gitk 40-54): gitk defines it at top level inside an
  `if` on the Tcl version. The oracle defines the Tcl 9 form
  (`encoding convertfrom -profile tcl8`).
- `open` wrapper (same block): not needed. The oracle reads git output through
  its own pipe.
- Config globals (`hashlength`, `nullid`, `colors`, `mingaplen`, ...): set in
  `oracle::initGlobals`. `oracle::setHashAlgorithm sha256` switches the hash
  length.

## Stubs and why

| Stub | Why |
|---|---|
| `mc` | msgcat is not loaded; returns `format fmt args...`, i.e. the English text |
| `nowbusy`, `notbusy` | busy cursor and progress bar (Tk) |
| `show_status`, `settooltipvisible` | status line / tooltip widgets |
| `adjustprogress`, `doprogupdate` | progress bar widget |
| `error_popup`, `show_error` | would open a dialog; the oracle records the message in `::oracle::errors` and prints it to stderr |
| `info_popup` | dialog |
| `confirm_popup` | dialog; answers yes |
| `update` | `update` is a Tk command; no event loop is wanted |
| `run` | defers a script with `after idle`; the oracle is synchronous and drives layout itself |
| `filerun` | installs a `fileevent` reader; the oracle feeds `getcommitlines` directly |
| `setcanvscroll` | sets canvas scroll regions |
| `drawvisible` | derives the visible rows from the canvas scroll position and calls `drawcommits`; the oracle computes the same arithmetic itself (see `--layout`) |
| `drawcommits` | stubbed, but the real proc is kept as `::oracle::realDrawcommits`: its `layoutrows`/`optimize_rows` half is how gitk lays rows out, and the oracle calls it |
| `drawcmitrow`, `drawparentlinks`, `drawlineseg` | the painting calls inside `drawcommits`; no-ops (`drawlineseg` returns `{}`) |
| `clear_display`, `redisplay` | canvas redraw |
| `selectline` | selects a row, touches the text widgets |
| `dispnexttag` | tag display in the detail pane |
| `dohidelocalchanges`, `doshowlocalchanges`, `dodiffindex`, `rereadrefs` | start `git diff-index` / `git for-each-ref` readers and mutate the view; local changes are not part of the oracle |
| `setcoords` | computes canvas metrics from fonts |
| `::oracle_widget` | stands in for `$canv`, `$canv2`, `$canv3`: `initlayout` calls `$canv cget -width`, and `setcanvscroll`-like code calls `$canv conf`; every subcommand is ignored and `cget` returns 0 |

## `--repo` mode (tasks 5.2, 5.3)

```
tclsh Tests/Oracle/oracle.tcl --repo <dir> [--layout=chunked|oneshot] [--window N] [--step N] [git log args] [-- files]
```

Arguments are passed to gitk's own `parseviewargs`/`start_rev_list`, so
`--all`, `--date-order`, path limits, etc. behave as in gitk (no arguments
means `HEAD`). The oracle runs the real `initlayout`, `start_rev_list` (which
spawns `git log --no-color -z --pretty=raw --show-notes --parents --boundary
... --stdin`) and `getcommitlines`; only the non-blocking `filerun` event loop
is replaced by a blocking read loop. Output (view 0), keys sorted, one entry
per line for `rows`, `ranges` and `colors`:

```
{"colors": {id: n, ...},        // index into gitk's `colors` list (7 entries)
 "order": [id, ...],            // commitonrow 0..n-1: gitk's row order
 "ranges": {id: [int, ...]},    // rowranges $id, ids sorted
 "rows": [{"col": int, "id": id, "idlist": [id|"", ...]}, ...],
 "varcs": {                     // one entry per arc, index 0 = sentinel arc
   "varccommits": [[id, ...], ...], "varcrow": [int|null, ...],
   "varcstart": [id, ...], "varctok": [string, ...], "vbackptr": [int, ...],
   "vdownptr": [int, ...], "vleftptr": [int, ...], "vupptr": [int, ...]}}
```

- `rows[r].idlist` is `rowidlist[r]` after layout and `optimize_rows`; padding
  entries are `""`. `col` is `lsearch -exact idlist id` (not `idcol`, which
  finds an insertion position).
- `colors`: gitk assigns colours while drawing, in drawing order. The oracle
  calls `assigncolor` once per commit in row order after layout, so the result
  depends on the final `rowidlist` and on `nextcolor` (reset by `initlayout`).

### Layout modes

gitk never lays rows out in one go. `drawvisible` (gitk 6557-6612) turns the
scroll position into `row`/`endrow` and `drawcommits` (6459-6539) then runs
`layoutrows` on rows not yet final and `optimize_rows` on a window around
them. The oracle runs the real `drawcommits` with the painting stubbed:

- `--layout=chunked` (default): `drawcommits` for a window of `--window` rows
  (default 50) that advances by `--step` rows (default 50) from the top to
  the bottom, with `drawvisible`'s arithmetic and `linespc` = 18. This is what
  happens when a user opens the repository and scrolls to the end.
- `--layout=oneshot`: a single `drawcommits 0 end`.

Finding (task 5.3): on all twelve non-`huge` fixtures, on `huge -n 4000`, and
for windows/steps 1/1, 7/7, 13/5, 20/7, 30/30, 50/1, 50/25, 50/50, 100/100,
200/200, `chunked` and `oneshot` are byte-identical. On random graphs of 1,500 commits (one ref per commit; 40% of commits have
a second or third parent, taken up to 80 commits back) they are **not**: with
chunked 50/50, 27-49 rows per graph differ in padding and column (8-14 of
them in `col`); with 100/100, 11-15 rows; with 7/7, about 250; with 50/1,
about 96% of rows. The set of ids in each `idlist` and the `ranges` are always
the same, and `colors` differ in some chunkings. So the layout does depend on the
scroll pattern for graphs bigger and messier than the fixtures; chunked
(50, 50) is the default as the closest model of normal use. The Swift port's
`ensureLaid(upTo:)` must reproduce `drawcommits`' arithmetic, and parity tests
on the fixtures hold for any chunking.

`ORACLE_TRACE_LAYOUT=1` logs the `realDrawcommits`, `layoutrows` and
`optimize_rows` calls to stderr.

Exit status: 0 on success, 1 if gitk reported an error through `error_popup`
(also printed on stderr), 2 on usage errors. If gitk cannot parse the git log
output it calls `exit 1` itself.

## `--allcommits` mode (task 12.1)

```
tclsh Tests/Oracle/oracle.tcl --allcommits <dir>
```

Runs gitk's own `readrefs` and `getallcommits` (which spawns
`git rev-list --parents --all` and feeds it to `getallclines`) and dumps the
ancestry arc tables of the whole repository. Keys are sorted; one entry per
line for `arcs` and the id maps:

```
{"allchildren": {id: [id, ...]},   // allchildren($id)
 "allcommits": 0,                  // load counter: 0 once finished
 "allparents": {id: [id, ...]},    // allparents($id)
 "arcnos": {id: [arc, ...]},       // arcnos($id)
 "arcout": {id: [arc, ...]},       // arcout($id), only ids that have it
 "arcs": [{"a": n, "start": id, "end": id|null, "ids": [id, ...],
           "growing": bool, "tags": [id, ...], "heads": [id, ...]}, ...],
 "nextarc": n,
 "seeds": [id, ...]}
```

- `arcs` lists arcs 1..`nextarc`; `end` is null while the arc is growing (it
  never is after a complete load).
- `tags`/`heads` come from `arctags`/`archeads`, which `getallclines` and
  `splitarc` fill from `idtags`/`idheads` as filled by the real `readrefs`
  (`git show-ref -d`, remotes shown).
- No cache is read or written. gitk looks for `$gitdir/gitk.cache` and saves
  it with `run savecache`; the oracle sets `gitdir` to a fresh temporary
  directory (removed afterwards) so there is nothing to read, and stubs
  `run` (already a no-op) and `savecache`. The repository is never written.
- `filerun` is redefined for this mode: it makes the pipe blocking and calls
  the script until it returns 0 (or the empty result of gitk's error path),
  which is what `dorunq` does one event at a time.
- The update path of `getallcommits` (`seeds` not empty) is not reachable from
  this mode; Swift tests cover it against `git`.

## Known gaps

- `showlocalchanges` is 0 (gitk defaults to 1). The oracle does not start a
  view, so no fake "Local uncommitted changes" rows appear.
- Stubs are listed from a call-graph scan of what `getcommitlines`,
  `layoutrows`, `initlayout` and `assigncolor` can reach. If a later task hits
  a Tk command, add the offending proc here and to `installStubs`.
