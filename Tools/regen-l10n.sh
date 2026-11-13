#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# gitk-swift: a native macOS port of gitk.
# Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.
#
# Regenerates Sources/GitkUI/Resources/<lproj>.lproj/Localizable.strings from
# the committed po/*.po catalogs (copies of gitk/po). Output is deterministic,
# so running it twice leaves `git status` clean.
set -eu
cd "$(dirname "$0")/.."
swift run po2strings po Sources/GitkUI/Resources
