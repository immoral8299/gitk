#!/usr/bin/env tclsh
# SPDX-License-Identifier: GPL-2.0-or-later
# gitk-swift: a native macOS port of gitk.
# Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.
#
# Differential-test oracle (design D5). Loads every top-level `proc` of
# gitk/gitk under plain tclsh (no Tk), stubs the UI procs, and runs gitk's own
# ordering and layout algorithms headless.
#
#   tclsh Tests/Oracle/oracle.tcl --selftest
#   tclsh Tests/Oracle/oracle.tcl --repo <dir> [git log args]   (task 5.2)
#
# Stub list and reasons: Tests/Oracle/README.md.

namespace eval oracle {
    variable here [file dirname [file normalize [info script]]]
    variable gitkPath [file join $here .. .. gitk gitk]
    variable procCount 0
    variable errors {}
}

# Split gitk into top-level commands the way Tcl itself would (accumulate
# lines until `info complete`), evaluate only the ones that are `proc`
# definitions at global level, and return how many were defined. Everything
# else (Tk setup, makewindow, argv parsing, `package require`, procs nested in
# `if` blocks such as the Tcl 9 `open` wrapper) is skipped on purpose.
proc oracle::loadProcs {} {
    variable gitkPath
    if {![file exists $gitkPath]} {
        puts stderr "oracle: $gitkPath not found (run: git submodule update --init gitk)"
        exit 2
    }
    set f [open $gitkPath r]
    fconfigure $f -encoding utf-8 -translation lf
    set count 0
    set cmd ""
    while {[gets $f line] >= 0} {
        append cmd $line "\n"
        if {![info complete $cmd]} continue
        # Do not use `lindex $cmd 0` here: a top-level command need not be a
        # well-formed list.
        if {[regexp {^\s*proc\s} $cmd]} {
            uplevel #0 $cmd
            incr count
        }
        set cmd ""
    }
    close $f
    if {$cmd ne ""} {
        puts stderr "oracle: trailing incomplete command in gitk"
        exit 2
    }
    return $count
}

# gitk defines `convertfrom` at top level inside an `if` (gitk 40-54), so
# loadProcs skips it. Reproduce the Tcl 9 flavour (-profile tcl8).
proc oracle::defineTopLevelHelpers {} {
    if {[package vcompare $::tcl_version 9.0] >= 0} {
        proc ::convertfrom args {
            return [encoding convertfrom -profile tcl8 {*}$args]
        }
    } else {
        proc ::convertfrom args {
            return [encoding convertfrom {*}$args]
        }
    }
}

# Stub every proc that would touch Tk, the event loop, or a dialog. Called
# AFTER loadProcs so that these definitions replace gitk's own.
proc oracle::installStubs {} {
    # msgcat's `mc`: format the string with its arguments, no translation.
    proc ::mc {fmt args} {
        if {[llength $args] == 0} {return $fmt}
        return [format $fmt {*}$args]
    }

    # Busy/status/progress feedback.
    proc ::nowbusy {args} {}
    proc ::notbusy {args} {}
    proc ::show_status {args} {}
    proc ::adjustprogress {args} {}
    proc ::doprogupdate {args} {}
    proc ::settooltipvisible {args} {}

    # Dialogs: record the message and keep going, so a test can look at it.
    proc ::error_popup {msg args} {
        lappend ::oracle::errors $msg
        puts stderr "oracle: error_popup: $msg"
    }
    proc ::show_error {w top msg args} {
        lappend ::oracle::errors $msg
        puts stderr "oracle: show_error: $msg"
    }
    proc ::info_popup {args} {}
    proc ::confirm_popup {msg args} {return 1}

    # Event loop and deferred work. The oracle is synchronous: it feeds
    # getcommitlines itself and drives layout explicitly, so nothing may be
    # scheduled behind its back.
    proc ::update {args} {}
    proc ::run {args} {}
    proc ::filerun {args} {}

    # Canvas drawing and scrolling.
    proc ::setcanvscroll {args} {}
    proc ::drawvisible {args} {}
    proc ::drawcommits {args} {}
    proc ::clear_display {args} {}
    proc ::redisplay {args} {}
    proc ::selectline {args} {}
    proc ::dispnexttag {args} {}
    proc ::dohidelocalchanges {args} {}
    proc ::doshowlocalchanges {args} {}
    proc ::dodiffindex {args} {}
    proc ::rereadrefs {args} {}
    proc ::setcoords {args} {}

    # A stand-in for the three canvas widgets: every subcommand is ignored
    # and `cget` answers 0, which is all initlayout and friends ask for.
    proc ::oracle_widget {args} {
        if {[lindex $args 0] eq "cget"} {return 0}
        return {}
    }
}

# Globals that gitk's top level would have initialised before any of the
# ordering and layout procs run. Values are copied from the gitk lines named
# in the comments; keep them in sync if the pinned commit changes.
proc oracle::initGlobals {} {
    uplevel #0 {
        # gitk 12601-12609 and 12896-12897: object format. setHashAlgorithm
        # switches this to sha256 for a SHA-256 repository.
        set hashalgorithm sha1
        set hashlength 40
        set nullid "0000000000000000000000000000000000000000"
        set nullid2 "0000000000000000000000000000000000000001"
        # gitk 12632-12638: layout tunables.
        set maxwidth 16
        set maxgraphpct 50
        set revlistorder 0
        set fastdate 0
        set uparrowlen 5
        set downarrowlen 5
        set mingaplen 100
        # gitk sets this to 1 (12649). The oracle never starts a view, so no
        # fake local-changes rows are inserted; 0 keeps it explicit.
        set showlocalchanges 0
        # gitk 12664.
        set colors {"#00ff00" red blue magenta darkgrey brown orange}
        # gitk 12896-12950: run-time state.
        set runq {}
        set stopped 0
        set numcommits 0
        set nextcolor 0
        set lastscrollset 0
        set lastscrollrows 0
        set canvxmax 0
        set canvy0 0
        set linespc 1
        set curview 0
        set nextviewnum 1
        set selectedline {}
        set mainheadid {}
        set tclencoding {}
        set canv ::oracle_widget
        set canv2 ::oracle_widget
        set canv3 ::oracle_widget
    }
}

# Pick the object format the way gitk's top level does (12601-12609).
proc oracle::setHashAlgorithm {algo} {
    switch -- $algo {
        sha1 {set len 40}
        sha256 {set len 64}
        default {error "unsupported object format: $algo"}
    }
    set ::hashalgorithm $algo
    set ::hashlength $len
    set ::nullid [string repeat 0 $len]
    set ::nullid2 [string repeat 0 [expr {$len - 1}]]1
}

proc oracle::selftest {} {
    variable procCount
    set expected {
        getcommitlines newvarc fix_reversal vtokcmp modify_arc layoutrows
        layoutmore initlayout assigncolor findcrossings drawcommits
        start_rev_list readrefs safe_exec mc convertfrom
    }
    set missing {}
    foreach p $expected {
        if {[info commands ::$p] eq ""} {lappend missing $p}
    }
    if {[llength $missing]} {
        puts stderr "oracle: selftest: missing procs: $missing"
        return 1
    }
    # The stubs must have replaced gitk's versions.
    if {[::mc "%s-%d" a 3] ne "a-3"} {
        puts stderr "oracle: selftest: mc stub does not format"
        return 1
    }
    if {[info body ::drawcommits] ne ""} {
        puts stderr "oracle: selftest: drawcommits was not stubbed"
        return 1
    }
    if {$procCount < 420} {
        puts stderr "oracle: selftest: only $procCount procs loaded"
        return 1
    }
    puts "ok $procCount"
    return 0
}

# --- JSON -------------------------------------------------------------------

proc oracle::jstr {s} {
    # Escape per RFC 8259. Characters above U+007F are emitted as they are.
    set out ""
    foreach ch [split $s ""] {
        scan $ch %c code
        switch -- $ch {
            "\"" {append out "\\\""}
            "\\" {append out "\\\\"}
            "\n" {append out "\\n"}
            "\r" {append out "\\r"}
            "\t" {append out "\\t"}
            default {
                if {$code < 0x20} {
                    append out [format {\u%04x} $code]
                } else {
                    append out $ch
                }
            }
        }
    }
    return "\"$out\""
}

# Encode a Tcl list as a JSON array of strings, ints, or (ints or null).
proc oracle::jlist {kind items} {
    set parts {}
    foreach x $items {
        switch -- $kind {
            str {lappend parts [jstr $x]}
            int {lappend parts [expr {$x}]}
            intornull {lappend parts [expr {$x eq "" ? "null" : [expr {$x}]}]}
        }
    }
    return "\[[join $parts ,]\]"
}

# --- --repo mode ------------------------------------------------------------

# Load commits the way gitk does at start-up: `getcommits` runs `initlayout`
# and `start_rev_list` (which parses the arguments and runs
# `git log --parents --boundary -z --pretty=raw --stdin ...`). The oracle then
# feeds the pipe through `getcommitlines` until it returns 0 (EOF). gitk reads
# non-blocking from the event loop; the oracle makes the pipe blocking and
# loops instead.
proc oracle::loadRepo {dir logArgs} {
    cd $dir

    # Mirror gitk's argument split (12792-12840): revision args before `--`,
    # file limits after it.
    set revargs {}
    set files {}
    set sawdd 0
    foreach a $logArgs {
        if {!$sawdd && $a eq "--"} {
            set sawdd 1
        } elseif {$sawdd} {
            lappend files $a
        } else {
            lappend revargs $a
        }
    }

    setHashAlgorithm [string trim [exec git rev-parse --show-object-format]]

    set ::gitencoding utf-8
    set ::tclencoding [::tcl_encoding $::gitencoding]
    set ::selectheadid {}
    set ::mainheadid [string trim [exec git rev-parse HEAD]]
    set ::viewargs(0) $revargs
    set ::viewargscmd(0) {}
    set ::viewfiles(0) $files
    set ::viewname(0) "Command line"
    set ::curview 0

    ::initlayout
    if {![::start_rev_list 0]} {
        error "oracle: start_rev_list failed: $::oracle::errors"
    }
    # start_rev_list registered exactly one instance for view 0.
    set inst [lindex $::viewinstances(0) 0]
    set fd $::commfd($inst)
    fconfigure $fd -blocking 1
    while {[::getcommitlines $fd $inst 0 0] != 0} {}
    set ::numcommits $::commitidx(0)
}

# {order:[ids...], varcs:{...}} for view 0. `order` is gitk's row order, taken
# from `commitonrow` for rows 0..numcommits-1; `varcs` lists the arc tables,
# indexed by arc number (index 0 is gitk's sentinel arc).
proc oracle::dumpOrder {} {
    set n $::commitidx(0)
    set order {}
    for {set r 0} {$r < $n} {incr r} {
        lappend order [::commitonrow $r]
    }
    # make_disporder already refreshed varcrow for every arc it touched;
    # this makes the last arcs current too.
    ::update_arcrows 0

    set narcs [llength $::varctok(0)]
    set cm {}
    for {set a 0} {$a < $narcs} {incr a} {
        if {[info exists ::varccommits(0,$a)]} {
            lappend cm [jlist str $::varccommits(0,$a)]
        } else {
            lappend cm {[]}
        }
    }
    set varcs [join [list \
        "\"varcstart\":[jlist str $::varcstart(0)]" \
        "\"varccommits\":\[[join $cm ,]\]" \
        "\"varctok\":[jlist str $::varctok(0)]" \
        "\"vupptr\":[jlist int $::vupptr(0)]" \
        "\"vdownptr\":[jlist int $::vdownptr(0)]" \
        "\"vleftptr\":[jlist int $::vleftptr(0)]" \
        "\"vbackptr\":[jlist int $::vbackptr(0)]" \
        "\"varcrow\":[jlist intornull $::varcrow(0)]"] ,]
    return "{\"order\":[jlist str $order],\"varcs\":{$varcs}}"
}

proc oracle::repoMode {args} {
    if {[llength $args] < 1} {return [usage]}
    set dir [file normalize [lindex $args 0]]
    if {![file isdirectory $dir]} {
        puts stderr "oracle: not a directory: $dir"
        return 2
    }
    loadRepo $dir [lrange $args 1 end]
    puts [dumpOrder]
    return [expr {[llength $::oracle::errors] ? 1 : 0}]
}

proc oracle::usage {} {
    puts stderr "usage: oracle.tcl --selftest | --repo <dir> \[git log args\]"
    return 2
}

proc oracle::main {argv} {
    variable procCount
    set procCount [loadProcs]
    defineTopLevelHelpers
    installStubs
    initGlobals

    switch -- [lindex $argv 0] {
        --selftest {return [selftest]}
        --repo {return [repoMode {*}[lrange $argv 1 end]]}
        default {return [usage]}
    }
}

if {[info exists ::argv0] && [file normalize $::argv0] eq [file normalize [info script]]} {
    exit [oracle::main $::argv]
}
