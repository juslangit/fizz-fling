#!/usr/bin/env bash
# Builds the web version and pushes it to itch.io (juslangit/fizz-fling, channel html5).
# The page must exist on itch.io first (Dashboard -> Create new project, kind: HTML).
# frame_test.html is left out of the zip but not out of build/web, so push the zip.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/build_web.sh
~/Documents/dev/tools/butler/butler push build/fizz-fling-web.zip juslangit/fizz-fling:html5 --userversion "0.1-$(git rev-parse --short HEAD)"
