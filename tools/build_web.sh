#!/usr/bin/env bash
# Exports the Web build to build/web/ and zips it to build/fizz-fling-web.zip
# (index.html at the top of the zip, the way itch.io wants it).
# tools/web/head.html is packed into export_presets.cfg first, so the page code stays readable.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
/usr/bin/python3 tools/web/write_presets.py
mkdir -p build/web
find build/web -type f -delete
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Web" build/web/index.html >/dev/null 2>&1
cp tools/web/frame_test.html build/web/frame_test.html
[ -f build/web/index.html ] || { echo "Export failed"; exit 1; }
(cd build/web && zip -qr ../fizz-fling-web.zip . -x '.*')
echo "Zip: build/fizz-fling-web.zip ($(du -h build/fizz-fling-web.zip | cut -f1))"
