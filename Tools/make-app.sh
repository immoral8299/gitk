#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# gitk-swift: a native macOS port of gitk.
# Derived from gitk, Copyright © 2005-2016 Paul Mackerras and contributors.
#
# Usage: Tools/make-app.sh [output-dir]
#
# Builds the release executable and assembles <output-dir>/gitk-swift.app
# (default: out/gitk-swift.app) with Info.plist, a placeholder icon, the
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

version=0.1.0

app="$outdir/gitk-swift.app"
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
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>org.gitk-swift.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>gitk-swift</string>
    <key>CFBundleDisplayName</key>
    <string>gitk-swift</string>
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

# Placeholder icon: a flat square with a plain ring, generated with the
# Python standard library and converted with iconutil.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/gitk-swift-icon.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
python3 -I - "$tmp/icon-1024.png" <<'PY'
import struct, sys, zlib

size = 1024
bg = (0x3A, 0x6E, 0xA5)
fg = (0xF2, 0xF2, 0xF2)
rows = []
for y in range(size):
    row = bytearray([0])  # filter type: none
    for x in range(size):
        dx, dy = x - size / 2, y - size / 2
        d2 = dx * dx + dy * dy
        inside_ring = (size * 0.28) ** 2 <= d2 <= (size * 0.36) ** 2
        row += bytes(fg if inside_ring else bg)
    rows.append(bytes(row))

def chunk(tag, data):
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
png += chunk(b"IEND", b"")
with open(sys.argv[1], "wb") as f:
    f.write(png)
PY

iconset="$tmp/AppIcon.iconset"
mkdir -p "$iconset"
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
            128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 \
            512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
    px=${spec%%:*}
    name=${spec#*:}
    sips -z "$px" "$px" "$tmp/icon-1024.png" --out "$iconset/$name.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

echo "$app"
