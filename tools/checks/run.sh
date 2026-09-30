#!/usr/bin/env bash
# All headless checks: the physics rules, then the game playing itself (solo and party)
# for a few thousand frames with any script error counted as a failure.
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
fail=0
echo "== physics"
perl -e 'alarm 90; exec @ARGV' "$GODOT" --headless --path . -s tools/checks/physics_check.gd 2>&1 | grep -E "^(PASS|FAIL)|failed" || fail=1
echo "== models"
perl -e 'alarm 90; exec @ARGV' "$GODOT" --headless --path . -s tools/checks/models_check.gd 2>&1 | grep -E "^(PASS|FAIL)|failed" || fail=1
for mode in "--demo" "--demo --party"; do
  echo "== game plays itself ($mode)"
  out=$(perl -e 'alarm 120; exec @ARGV' "$GODOT" --headless --path . --quit-after 7000 -- $mode 2>&1)
  errs=$(echo "$out" | grep -c "SCRIPT ERROR\|Parse Error" || true)
  if [ "$errs" = "0" ]; then echo "PASS  no script errors in 7000 frames"; else echo "FAIL  $errs script errors"; echo "$out" | grep -A2 "SCRIPT ERROR" | head -12; fail=1; fi
done
exit $fail
