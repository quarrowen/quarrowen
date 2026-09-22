#!/usr/bin/env bash
# Renders the Lookbook landscape once per style, so the pictures differ only by the look.
#
#   tools/look_shots.sh [out_dir]
#
# Needs a real window (the screenshot tool does), so this opens and closes one per style. It restores
# mods/base/textures from git when it finishes, including on failure - the styles are written over
# the real textures on purpose so the picture is of the game and not of a mock-up. (2026-09-21)
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${1:-build/looks}"
PORT="${PORT:-24680}"
STYLES="${STYLES:-current flat soft storybook crisp}"
WORK="$(mktemp -d)"

cleanup() {
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null
  git checkout -- mods/base/textures 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$OUT"
# A server left behind by an interrupted run holds the port, the new one fails to bind with "Couldn't
# create an ENet host", and the client then sits on "Connecting to..." for ever - which reads as a
# graphics bug, because what you are looking at is a screenshot of a client that never joined. An
# afternoon went into that on 2026-09-22.
pkill -f "res://scenes/server.tscn" 2>/dev/null
sleep 1

# Waits for the server to say it is up, rather than guessing with a fixed sleep.
wait_for_server() {
  for _ in $(seq 1 60); do
    grep -q "running game" "$1" && return 0
    sleep 1
  done
  return 1
}

for style in $STYLES; do
  echo "== $style"
  "$GODOT" --headless --path . -s tools/look_lab.gd -- --style="$style" >/dev/null 2>&1 || { echo "   could not paint $style"; continue; }
  # A fresh world each time: the terrain is seeded the same, but a cached chunk would keep the
  # previous style's blocks and quietly compare a style against itself.
  QW_USER_DIR="$WORK/user" QW_DATA_DIR="$WORK/data" QW_LOOK_SHAPE="${QW_LOOK_SHAPE:-0}" QW_LOOK_TREE="${QW_LOOK_TREE:-}" QW_LOOK_SHORE="${QW_LOOK_SHORE:-0}" QW_MODS=lookbook QW_MODS_DIR=res://tests/mods \
    QW_ADMINS=Camera QW_WORLD="look_$style" QW_PORT="$PORT" QW_SEED=20260921 \
    "$GODOT" --headless --path . res://scenes/server.tscn >"$WORK/server_$style.log" 2>&1 &
  SERVER_PID=$!
  if ! wait_for_server "$WORK/server_$style.log"; then
    echo "   server never came up; tail of its log:"; tail -5 "$WORK/server_$style.log"
    kill "$SERVER_PID" 2>/dev/null; SERVER_PID=""; continue
  fi
  sleep "${QW_LOOK_SLEEP:-3}"
  QW_USER_DIR="$WORK/client" QW_GRAPHICS="${QW_GRAPHICS:-fancy}" QW_REAL_OFF="${QW_REAL_OFF:-}" QW_SKY_DEBUG="${QW_SKY_DEBUG:-0}" QW_SKY_PHYSICAL="${QW_SKY_PHYSICAL:-0}" "$GODOT" --path . res://tests/screenshot.tscn -- \
    --port="$PORT" --out="$PWD/$OUT/$style.png" --yaw="${QW_LOOK_YAW:-0.9}" --pitch="${QW_LOOK_PITCH:--0.18}" --wait="${QW_LOOK_WAIT:-8}" --fps="${QW_LOOK_FPS:-0}" --hud="${QW_LOOK_HUD:-0}" --commands="${QW_LOOK_CMDS:-}" \
    >"$WORK/shot_$style.log" 2>&1
  kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""
  grep -hE "^\[(fps|sky)\]" "$WORK/shot_$style.log" || true
  [ -f "$OUT/$style.png" ] && echo "   $OUT/$style.png" || { echo "   no image; tail of its log:"; tail -5 "$WORK/shot_$style.log"; }
done
echo "done - $OUT"
