#!/usr/bin/env bash
# Photographs the two things written this week that had only ever been proved by code: the Fairground's
# board beside a door, and a floor of the descent.
#
#   tools/descent_shots.sh [out_dir]
#
# Both need a real window, so this opens and closes one per shot. It exists because "the suite passes"
# and "it looks right" are different claims, and the second one had not been made: a board is an
# invisible entity wearing a nameplate, and every way that can fail (the entity culled, the plate not
# drawn, the body still visible) leaves the tests perfectly green. (2026-09-28)
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${1:-build/shots}"
PORT="${PORT:-24690}"
WORK="$(mktemp -d)"

cleanup() {
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$OUT"
# A server left behind by an interrupted run holds the port, the next one cannot bind, and the client
# then sits on "Connecting to..." for ever - which photographs as a graphics bug rather than as a stale
# process. An afternoon went into that once.
pkill -f "res://scenes/server.tscn" 2>/dev/null
sleep 1

wait_for_server() {
  for _ in $(seq 1 90); do
    grep -q "running game" "$1" && return 0
    sleep 1
  done
  return 1
}

# $1 name, $2 mods, $3.. screenshot arguments
shoot() {
  local name="$1"; shift
  local mods="$1"; shift
  echo "== $name"
  QW_USER_DIR="$WORK/user_$name" QW_DATA_DIR="$WORK/data_$name" QW_MODS="$mods" \
    QW_ADMINS=Camera QW_WORLD="shot_$name" QW_PORT="$PORT" QW_SEED=20260928 \
    "$GODOT" --headless --path . res://scenes/server.tscn >"$WORK/server_$name.log" 2>&1 &
  SERVER_PID=$!
  if ! wait_for_server "$WORK/server_$name.log"; then
    echo "   server never came up; tail of its log:"; tail -8 "$WORK/server_$name.log"
    kill "$SERVER_PID" 2>/dev/null; SERVER_PID=""; return 1
  fi
  sleep 3
  QW_USER_DIR="$WORK/client_$name" QW_GRAPHICS="${QW_GRAPHICS:-fancy}" \
    "$GODOT" --path . res://tests/screenshot.tscn -- \
    --port="$PORT" --out="$PWD/$OUT/$name.png" --name=Camera "$@" \
    >"$WORK/shot_$name.log" 2>&1
  kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""
  # The client's own complaints are the fastest way to tell a bad shot from a bad subject.
  grep -hE "SHADER ERROR|SCRIPT ERROR|Buffer full|could not|refused" "$WORK/shot_$name.log" | head -5
  [ -f "$OUT/$name.png" ] && echo "   $OUT/$name.png" || echo "   NO PICTURE"
}

# The hub: stand back from the first door and look at it, so the door and the board beside it are both
# in frame. Slot 0 sits at (12, 65, 0) - RADIUS 14 less two - and the board 1.6 to one side of it.
shoot fairground_board "fairground,lavagame,wordgame" \
  --stand=4,65,1 --look=12,66,2 --wait=6

# A floor of the descent, entered through the command rather than the doorway: a shot of a room is the
# point, and walking 93 blocks to a chamber is not something a camera should be asked to do.
shoot descent_floor "firstlight" \
  --commands="/descent" --wait=8 --pitch=-0.05 --warmup=60

echo
echo "shots in $OUT"
