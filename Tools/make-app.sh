#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# gitk-swift: a native macOS port of gitk.
# Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.
#
# Usage: Tools/make-app.sh [output-dir]
#
# Builds the release executable and assembles "<output-dir>/gitk (Native).app"
# (default: "out/gitk (Native).app") with Info.plist, the app icon, the
# executable and the SwiftPM resource bundles. The generated Bundle.module
# accessor checks Bundle.main.resourceURL first, which is Contents/Resources in
# an app bundle, so the bundles go there.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
outdir=${1:-$root/out}
case "$outdir" in
    /*) ;;
    *) outdir="$(pwd)/$outdir" ;;
esac

swift=${SWIFT:-swift}
(cd "$root" && "$swift" build -c release >&2)
binDir=$(cd "$root" && "$swift" build -c release --show-bin-path)

exe="$binDir/gitk-swift"
if [ ! -x "$exe" ]; then
    echo "make-app.sh: no executable at $exe" >&2
    exit 1
fi

version=0.1.1

app="$outdir/gitk (Native).app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$exe" "$app/Contents/MacOS/gitk-swift"
chmod 755 "$app/Contents/MacOS/gitk-swift"

# Resource bundles produced by SwiftPM. Test-target bundles are skipped.
found=0
for bundle in "$binDir"/*.bundle; do
    [ -d "$bundle" ] || continue
    case "$bundle" in *Tests.bundle) continue ;; esac
    cp -R "$bundle" "$app/Contents/Resources/"
    found=1
done
if [ "$found" -eq 0 ]; then
    echo "make-app.sh: no resource bundle in $binDir" >&2
    exit 1
fi

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>gitk-swift</string>
    <key>CFBundleIconFile</key>
    <string>icon</string>
    <key>CFBundleIconName</key>
    <string>icon</string>
    <key>CFBundleIdentifier</key>
    <string>org.gitk-swift.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>gitk (Native)</string>
    <key>CFBundleDisplayName</key>
    <string>gitk (Native)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>$version</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# App icon: Tools/icon.icon (Icon Composer) compiled by actool into
# Assets.car (the macOS 26 layered icon) and icon.icns (earlier releases).
# The --app-icon name is the .icon file's name, and Info.plist refers to it.
if ! xcrun --find actool >/dev/null 2>&1; then
    echo "make-app.sh: actool not found; install Xcode 26 or later" >&2
    exit 1
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/gitk-swift-icon.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
xcrun actool "$root/Tools/icon.icon" --compile "$app/Contents/Resources" \
    --app-icon icon --platform macosx --target-device mac \
    --minimum-deployment-target 14.0 --enable-on-demand-resources NO \
    --development-region en --output-partial-info-plist "$tmp/icon.plist" \
    --output-format human-readable-text >/dev/null
for f in Assets.car icon.icns; do
    if [ ! -f "$app/Contents/Resources/$f" ]; then
        echo "make-app.sh: actool did not produce $f" >&2
        exit 1
    fi
done

echo "$app"
