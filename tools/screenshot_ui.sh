#!/usr/bin/env bash
# Render the trail store UI to PNGs under Xvfb: <prefix>_menu.png, _upload.png, _error.png.
#
#   heavy -- tools/screenshot_ui.sh <prefix>
set -uo pipefail
cd "$(dirname "$0")/.."
command -v Xvfb >/dev/null || { echo "Xvfb not installed" >&2; exit 3; }
[ $# -ge 1 ] || { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
OUT="$(realpath -m "$1")"
mkdir -p "$(dirname "$OUT")"
godot --headless --path . --import >/dev/null 2>&1
disp=$((90 + RANDOM % 8)); export DISPLAY=":$disp" LIBGL_ALWAYS_SOFTWARE=1
Xvfb ":$disp" -screen 0 1280x720x24 >/dev/null 2>&1 &
xpid=$!
sleep 2
rc=0
for view in menu upload error; do
  timeout 120 godot --path . --resolution 1280x720 --rendering-method gl_compatibility --rendering-driver opengl3 res://examples/ui_shot.tscn -- --shot "${OUT%.png}_$view.png" --view "$view" || rc=$?
done
kill $xpid 2>/dev/null
exit $rc
