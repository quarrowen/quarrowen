#!/usr/bin/env bash
# Photographs the same world under each rendering method, so the Mobile-versus-Forward+ question is
# answered by looking rather than by reasoning.
#
#   tools/renderer_shots.sh [out_dir]
#   METHODS="forward_plus mobile gl_compatibility" tools/renderer_shots.sh
#
# **Why this exists.** `rendering_method.mobile = mobile` is Godot's default and nothing in this
# project overrides it, so an iOS or Android build *already* runs the Mobile renderer while every
# desktop build runs Forward+. That split was never chosen and never measured - which means the
# voxel shader has been carrying an untested second target the whole time. (2026-09-25)
#
# The failure this is looking for is not a crash. Godot prints a shader error and then draws the
# surface with its default material, which is opaque white - so the symptom is a lake rendered as a
# flat white sheet, and eight rounds of work once went into the water's *look* before anybody read
# the log. Hence: every run greps for SHADER ERROR, and prints the count next to the picture.
#
# The fps figures here are coarse. The harness is fill-bound and moves about plus or minus 15 fps
# between runs, so a small difference between two methods means nothing; a large one is worth
# chasing. Do not bisect with it.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
OUT="${1:-build/renderers}"
PORT="${PORT:-24681}"
METHODS="${METHODS:-forward_plus mobile}"
MODS="${MODS:-base,simple_gear,simple_machines,creative}"
SEED="${SEED:-20260925}"
# Up in the air looking out, so the picture is of terrain, sky, water and fog - the things two
# renderers actually differ on - rather than of whatever block the spawn pressed the camera against,
# which is what the first run produced. `--stand` is not the way to do this: it only runs as part of
# `--look`, and on its own it is silently ignored. `/fly` before `/tp` or the camera simply falls back
# into the hole. (2026-09-25)
FLY_TO="${FLY_TO:-8 96 8}"
YAW="${YAW:-0.9}"
PITCH="${PITCH:--0.35}"
failed=0
WORK="$(mktemp -d)"

cleanup() {
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$OUT"
# A server left behind by an interrupted run holds the port and the next client sits on "Connecting
# to..." for ever, which reads as a graphics bug because what you are looking at is a screenshot of a
# client that never joined. (tools/look_shots.sh learned this the same way, 2026-09-22)
pkill -f "res://scenes/server.tscn" 2>/dev/null
sleep 1

# One server for every method: the world must be identical, or the comparison is of two worlds.
QW_USER_DIR="$WORK/user" QW_DATA_DIR="$WORK/data" QW_MODS="$MODS" \
  QW_ADMINS=Camera QW_WORLD=renderers QW_PORT="$PORT" QW_SEED="$SEED" \
  "$GODOT" --headless --path . res://scenes/server.tscn >"$WORK/server.log" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 60); do grep -q "running game" "$WORK/server.log" && break; sleep 1; done
if ! grep -q "running game" "$WORK/server.log"; then
  echo "server never came up; tail of its log:" >&2; tail -5 "$WORK/server.log" >&2; exit 1
fi

printf '%-18s %-9s %-7s %s\n' method shader-errors fps image
for method in $METHODS; do
  # A fresh client folder each time, so no cached chunk mesh is reused across methods - but **one
  # shared identity**, because a name belongs to the first key that claims it on a server. Give each
  # method its own identity folder and the second client is refused for calling itself Camera, sits on
  # "Handshaking...", and photographs the loading curtain. That happened on the first run of this
  # script and the numbers looked perfectly reasonable. (2026-09-25)
  QW_USER_DIR="$WORK/client_$method" QW_IDENTITY_DIR="$WORK/identity" \
    "$GODOT" --path . --rendering-method "$method" \
    res://tests/screenshot.tscn -- \
    --port="$PORT" --out="$PWD/$OUT/$method.png" --commands="/fly|/tp $FLY_TO" \
    --yaw="$YAW" --pitch="$PITCH" --wait=8 --fps=120 \
    >"$WORK/shot_$method.log" 2>&1
  # **A client that never joined still writes a PNG and still reports 60 fps**, because the loading
  # curtain renders at 60 fps very happily. Without this check the whole comparison is of two black
  # screens and nothing says so.
  if ! grep -q "Joined as peer" "$WORK/shot_$method.log"; then
    cp "$WORK/shot_$method.log" "$OUT/$method.log"
    printf '%-18s %s\n' "$method" "NEVER JOINED - the image is the loading curtain. See $OUT/$method.log"
    failed=1
    continue
  fi
  errors=$(grep -c "SHADER ERROR" "$WORK/shot_$method.log")
  fps=$(grep -hoE "^\[fps\].*" "$WORK/shot_$method.log" | head -1)
  cp "$WORK/shot_$method.log" "$OUT/$method.log"
  if [ -f "$OUT/$method.png" ]; then
    printf '%-18s %-9s %s\n' "$method" "$errors" "${fps:-no fps line} -> $OUT/$method.png"
  else
    printf '%-18s %-9s %s\n' "$method" "$errors" "NO IMAGE - see $OUT/$method.log"
  fi
  [ "$errors" -gt 0 ] && grep -m3 -A2 "SHADER ERROR" "$WORK/shot_$method.log" | sed 's/^/    /'
done

echo
echo "logs and images in $OUT"
[ "$failed" -eq 0 ] || { echo "at least one method never reached the world - the comparison is not valid" >&2; exit 1; }
