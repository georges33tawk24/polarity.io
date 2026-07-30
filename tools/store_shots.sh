#!/usr/bin/env bash
# Generates the store screenshot set from the real game — no mockups, no
# compositing. Play/Apple both want a handful of portrait shots; these are the
# five screens that actually sell the game.
#
# KNOWN LIMIT: the capture is the game window's framebuffer, and macOS clamps a
# window to the physical display. On a 1600x1000-ish laptop screen a request for
# 1290x2796 comes back 1290x1570, so these are NOT yet submittable at Apple's 6.7"
# size. They are correct in composition and content — what is missing is pixels.
#
# Two ways to finish it, neither done here:
#   1. Run this on a machine with a display taller than the target, or
#   2. Render the screen into a SubViewport of the exact target size and grab that
#      texture instead of the window framebuffer (the real fix; it makes the tool
#      display-independent).
# The dimensions are printed below so a wrong-sized set cannot be shipped by
# accident.
#
#   tools/store_shots.sh [path-to-godot]
#
# Output: store/screenshots/<size>/<n>_<screen>.png
set -uo pipefail
GODOT="${1:-/Applications/Godot.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")/.."

# Play Store wants 1080x1920 minimum; App Store 6.7" is 1290x2796.
declare -a SIZES=("1080x1920" "1290x2796")
declare -a SCREENS=("menu" "shop" "missions" "pass" "results")

for size in "${SIZES[@]}"; do
  out="store/screenshots/$size"
  mkdir -p "$out"
  i=1
  for scr in "${SCREENS[@]}"; do
    "$GODOT" res://tests/menu_shot.tscn -- --noconsent --locale=en \
      --screen="$scr" --size="$size" --shot="$PWD/$out/${i}_${scr}.png" \
      2>&1 | grep -E "save=|SCRIPT ERROR"
    i=$((i+1))
  done
  # A live match is the one shot that has to come from gameplay rather than a menu.
  "$GODOT" res://tests/smoke.tscn -- --shot-at=7 \
    --shot="$PWD/$out/0_match.png" 2>&1 | grep -E "screenshot|deadline"
done
echo
echo "--- actual dimensions (compare against the folder name) ---"
python3 - <<'PYEOF'
import struct, glob, os
for p in sorted(glob.glob("store/screenshots/*/*.png")):
    d = open(p, "rb").read()
    w, h = struct.unpack(">II", d[16:24])
    want = os.path.basename(os.path.dirname(p))
    got = "%dx%d" % (w, h)
    print("%-46s %-12s %s" % (p, got, "OK" if got == want else "!! SHORT"))
PYEOF
echo
echo "store screenshots written to store/screenshots/"
