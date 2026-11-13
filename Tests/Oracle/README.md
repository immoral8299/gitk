# Tcl oracle

`oracle.tcl` runs gitk's own ordering and layout procs under plain `tclsh`
(no Tk) and prints JSON, so Swift ports can be diffed against the original
(design D5).

```
tclsh Tests/Oracle/oracle.tcl --selftest        # prints "ok <procs loaded>"
tclsh Tests/Oracle/oracle.tcl --repo <dir> ...  # task 5.2
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
| `drawvisible`, `drawcommits` | draw rows on the canvas (and lazily call `layoutrows`; the oracle calls `layoutrows` itself in task 5.3) |
| `clear_display`, `redisplay` | canvas redraw |
| `selectline` | selects a row, touches the text widgets |
| `dispnexttag` | tag display in the detail pane |
| `dohidelocalchanges`, `doshowlocalchanges`, `dodiffindex`, `rereadrefs` | start `git diff-index` / `git for-each-ref` readers and mutate the view; local changes are not part of the oracle |
| `setcoords` | computes canvas metrics from fonts |
| `::oracle_widget` | stands in for `$canv`, `$canv2`, `$canv3`: `initlayout` calls `$canv cget -width`, and `setcanvscroll`-like code calls `$canv conf`; every subcommand is ignored and `cget` returns 0 |

## Known gaps

- `showlocalchanges` is 0 (gitk defaults to 1). The oracle does not start a
  view, so no fake "Local uncommitted changes" rows appear.
- Stubs are listed from a call-graph scan of what `getcommitlines`,
  `layoutrows`, `initlayout` and `assigncolor` can reach. If a later task hits
  a Tk command, add the offending proc here and to `installStubs`.
