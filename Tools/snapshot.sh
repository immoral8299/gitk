#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# gitk-swift: a native macOS port of gitk.
# Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.
#
# Usage: Tools/snapshot.sh <fixture> <out.png> [gitk-swift args...]
#
# Builds the fixture (cached under $TMPDIR/gitk-swift-snapshot-fixtures), builds
# gitk-swift, runs it inside the fixture with GITK_SWIFT_SNAPSHOT set, and prints
# the PNG path. Set GITK_SWIFT_SNAPSHOT_SIZE=WxH to choose the window size and
# SNAPSHOT_TIMEOUT to change the 60 second limit.

set -eu

if [ "$#" -lt 2 ]; then
    echo "usage: $0 <fixture> <out.png> [gitk-swift args...]" >&2
    exit 2
fi
fixture=$1
out=$2
shift 2

root=$(cd "$(dirname "$0")/.." && pwd)
cache="${TMPDIR:-/tmp}/gitk-swift-snapshot-fixtures"
cache=${cache%/}
mkdir -p "$cache"

if [ ! -d "$cache/$fixture/.git" ] && [ ! -f "$cache/$fixture/HEAD" ]; then
    rm -rf "${cache:?}/$fixture"
    "$root/Tests/Fixtures/make-fixture.sh" "$fixture" "$cache" >/dev/null
fi

(cd "$root" && swift build >&2)
bin="$(cd "$root" && swift build --show-bin-path)/gitk-swift"

case "$out" in
    /*) ;;
    *) out="$(pwd)/$out" ;;
esac
mkdir -p "$(dirname "$out")"
rm -f "$out"

config=$(mktemp -d "${TMPDIR:-/tmp}/gitk-swift-snapshot-config.XXXXXX")
trap 'rm -rf "$config"' EXIT

cd "$cache/$fixture"
# An empty HOME and XDG_CONFIG_HOME keep the user's own gitk config from being
# imported on this first launch, so snapshots show the app's defaults.
HOME="$config" XDG_CONFIG_HOME="$config" GITK_SWIFT_CONFIG_DIR="$config" GITK_SWIFT_SNAPSHOT="$out" "$bin" "$@" &
pid=$!
(
    sleep "${SNAPSHOT_TIMEOUT:-60}"
    kill "$pid" 2>/dev/null
) &
watchdog=$!

status=0
wait "$pid" || status=$?
kill "$watchdog" 2>/dev/null || true
wait "$watchdog" 2>/dev/null || true

if [ "$status" -ne 0 ]; then
    echo "snapshot.sh: gitk-swift exited with status $status" >&2
    exit "$status"
fi
if [ ! -s "$out" ]; then
    echo "snapshot.sh: no PNG written to $out" >&2
    exit 1
fi
echo "$out"
