#!/usr/bin/env bash
# Everything CI runs, runnable locally. There is no git remote yet, so this is the
# only way these checks actually execute today.
#
#   tools/verify.sh [path-to-godot]
#
# Exits non-zero on the first failure. Every stage fails on SCRIPT ERROR as well as
# on its own assertions — a runtime error during a screen build used to leave the
# suite reporting green (DECISIONS §12r: 30 errors, "267 checks, 0 failed").
set -uo pipefail

GODOT="${1:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.."
fail=0

step() { printf '\n=== %s ===\n' "$1"; }

# Runs a scene and fails on assertion failures OR on any SCRIPT ERROR / Parse Error.
run_scene() {
  local scene="$1" expect="$2" out
  out=$("$GODOT" --headless "$scene" 2>&1)
  echo "$out" | grep -vE '^\s*pass\s' | tail -25
  if ! echo "$out" | grep -qE "$expect"; then
    echo "!! $scene did not report success"; fail=1
  fi
  if echo "$out" | grep -qE 'SCRIPT ERROR|Parse Error'; then
    echo "!! $scene emitted SCRIPT ERROR / Parse Error"; fail=1
  fi
}

step "import"
"$GODOT" --headless --import --quit-after 200 >/dev/null 2>&1 || true

step "unit + integration"
run_scene res://tests/tests.tscn '^[0-9]+ checks, 0 failed'

step "match smoke"
run_scene res://tests/smoke.tscn '0 failures'

step "screen structure"
run_scene res://tests/screens.tscn '^[0-9]+ screen checks, 0 failed'

step "banned identifiers"
# Deprecated design tokens and the saturated hexes the art direction rules out.
# These are greps rather than assertions because they are about what must NOT be
# in the source, which no runtime check can see.
if grep -rEn 'UiKit\.(BG|PANEL|DIM|HOT|GOOD|RADIUS)\b' scripts/ ; then
  echo "!! deprecated UiKit token in use"; fail=1
fi
# Quoted only: a comment that NAMES a banned hex (to explain why it is banned)
# must not trip the check. Every real use is Color("#xxxxxx") or a JSON string.
if grep -rEn '"#(5ce1ff|ffc63f|3fa9ff|b45cff|ff4059|c98a12|2a86b8)"' scripts/ data/ ; then
  echo "!! banned saturated colour in source"; fail=1
fi

step "web export"
rm -rf build/web && mkdir -p build/web
if ! "$GODOT" --headless --export-release "Web" build/web/index.html 2>&1 | tail -3; then
  echo "!! web export failed"; fail=1
fi
[ -f build/web/index.wasm ] || { echo "!! no wasm produced"; fail=1; }

printf '\n'
if [ "$fail" -eq 0 ]; then echo "VERIFY OK"; else echo "VERIFY FAILED"; fi
exit $fail
