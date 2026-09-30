#!/usr/bin/env bash
# All headless checks: the physics rules, the models, then the game playing itself (solo, party,
# distance and target) for a few thousand frames, with any script error counted as a failure.
# With --web, also the real web build in headless Chrome fed synthetic phone motion.
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
fail=0
echo "== physics"
perl -e 'alarm 90; exec @ARGV' "$GODOT" --headless --path . -s tools/checks/physics_check.gd 2>&1 | grep -E "^(PASS|FAIL)|failed" || fail=1
echo "== models"
perl -e 'alarm 90; exec @ARGV' "$GODOT" --headless --path . -s tools/checks/models_check.gd 2>&1 | grep -E "^(PASS|FAIL)|failed" || fail=1
echo "== layout"
perl -e 'alarm 90; exec @ARGV' "$GODOT" --headless --path . tools/checks/layout_check.tscn 2>&1 | grep -E "^(PASS|FAIL)|failed" || fail=1
for mode in "--demo" "--demo --party" "--demo --target" "--demo --party --target"; do
  echo "== game plays itself ($mode)"
  out=$(perl -e 'alarm 120; exec @ARGV' "$GODOT" --headless --path . --quit-after 7000 -- $mode 2>&1)
  errs=$(echo "$out" | grep -c "SCRIPT ERROR\|Parse Error" || true)
  if [ "$errs" = "0" ]; then echo "PASS  no script errors in 7000 frames"; else echo "FAIL  $errs script errors"; echo "$out" | grep -A2 "SCRIPT ERROR" | head -12; fail=1; fi
done
if [ "${1:-}" = "--web" ]; then
  # the real web build in headless Chrome, fed synthetic phone motion (needs tools/build_web.sh first)
  echo "== motion in the browser"
  pgrep -f "serve_phone.py 8064" >/dev/null || { python3 tools/serve_phone.py 8064 > build/serve.log 2>&1 & sleep 1; }
  perl -e 'alarm 300; exec @ARGV' node tools/checks/motion_web.mjs || fail=1
  echo "== sharing in the browser"
  perl -e 'alarm 300; exec @ARGV' node tools/checks/share_web.mjs || fail=1
fi
exit $fail
