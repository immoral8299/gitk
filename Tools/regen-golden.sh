#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# gitk-swift: a native macOS port of gitk.
# Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.
#
# Regenerates Tests/GitkCoreTests/Golden/<fixture>.json by running the Tcl
# oracle (Tests/Oracle/oracle.tcl) on every fixture except `huge`.
#
# Usage: Tools/regen-golden.sh [fixture ...]
#
# Without arguments all fixtures are regenerated. Needs tclsh and the gitk
# submodule (git submodule update --init gitk). The fixtures are built in a
# temporary directory with Tests/Fixtures/make-fixture.sh, so the output is
# the same on every run. Never edit the golden files by hand.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
GOLDEN="$ROOT/Tests/GitkCoreTests/Golden"
ORACLE="$ROOT/Tests/Oracle/oracle.tcl"

command -v tclsh >/dev/null 2>&1 || { echo "regen-golden: tclsh not found" >&2; exit 1; }
[ -f "$ROOT/gitk/gitk" ] || {
    echo "regen-golden: gitk/gitk not found (run: git submodule update --init gitk)" >&2
    exit 1
}

if [ $# -gt 0 ]; then
    NAMES="$*"
else
    NAMES=$("$ROOT/Tests/Fixtures/make-fixture.sh" --list | grep -v '^huge$')
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/gitk-golden.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$GOLDEN"

for name in $NAMES; do
    [ "$name" != huge ] || { echo "regen-golden: skipping huge" >&2; continue; }
    echo "regen-golden: $name" >&2
    "$ROOT/Tests/Fixtures/make-fixture.sh" "$name" "$WORK" >/dev/null
    tclsh "$ORACLE" --repo "$WORK/$name" > "$WORK/$name.json"
    mv "$WORK/$name.json" "$GOLDEN/$name.json"
done
