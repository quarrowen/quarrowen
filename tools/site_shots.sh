#!/usr/bin/env bash
# The pictures the landing page is built around, taken on the Realistic preset with the interface
# hidden:
#
#   tools/site_shots.sh [out_dir]          # default site/screenshots
#
# One shot per game, plus the hero. Each needs a real window and its own world, so this starts a
# server, takes one picture and stops it again - the pattern from tools/descent_shots.sh, which exists
# because "the suite passes" and "it looks right" are different claims.
#
# **Grep the client log for SHADER ERROR before trusting any of these.** Godot prints the error and
# then draws the surface with its default material, which is opaque white - so a broken shader
# photographs as a flat white lake rather than as an error, and eight rounds of work once went into a
# lake's *look* before anybody read the log. `shoot` prints those lines itself. (2026-09-30)
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="${1:-site/screenshots}"
PORT="${PORT:-24691}"
WORK="$(mktemp -d)"
FAILED=0

cleanup() {
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$OUT"
# A server left behind by an interrupted run holds the port, the next one cannot bind, and the client
# then sits on "Connecting to..." for ever - which photographs as a graphics bug rather than as a stale
# process.
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
# ONLY=oneblock tools/site_shots.sh re-takes one picture rather than all five, because each costs a
# server, a window and about a minute.
shoot() {
  local name="$1"; shift
  local mods="$1"; shift
  if [ -n "${ONLY:-}" ] && [ "$ONLY" != "$name" ]; then return 0; fi
  echo "== $name"
  QW_USER_DIR="$WORK/user_$name" QW_DATA_DIR="$WORK/data_$name" QW_MODS="$mods" \
    QW_ADMINS=Robin QW_WORLD="site_$name" QW_PORT="$PORT" QW_SEED=20260930 \
    "$GODOT" --headless --path . res://scenes/server.tscn >"$WORK/server_$name.log" 2>&1 &
  SERVER_PID=$!
  if ! wait_for_server "$WORK/server_$name.log"; then
    echo "   server never came up; tail of its log:"; tail -8 "$WORK/server_$name.log"
    kill "$SERVER_PID" 2>/dev/null; SERVER_PID=""; FAILED=1; return 1
  fi
  sleep 3
  QW_USER_DIR="$WORK/client_$name" QW_GRAPHICS="${QW_GRAPHICS:-realistic}" \
    "$GODOT" --path . res://tests/screenshot.tscn -- \
    --port="$PORT" --out="$PWD/$OUT/$name.png" --name=Robin --hud=0 "$@" \
    >"$WORK/shot_$name.log" 2>&1
  kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""

  local bad
  bad="$(grep -hE "SHADER ERROR" "$WORK/shot_$name.log" | head -3)"
  if [ -n "$bad" ]; then
    echo "   !! SHADER ERROR - this picture cannot be trusted:"; echo "$bad"; FAILED=1
  fi
  grep -hE "SCRIPT ERROR|could not|refused" "$WORK/shot_$name.log" | head -3
  if [ -f "$OUT/$name.png" ]; then
    # The page wants JPG; sips ships with macOS.
    # **Resized, not just converted.** The window is 5120 wide on this display, so a straight
    # conversion gave 2.5 MB a picture and about 11 MB of images on one page - for a site whose whole
    # pitch to a host is that nothing is heavy. 1920 is wider than any layout here uses.
    sips -s format jpeg -s formatOptions 78 -Z 1920 "$OUT/$name.png" --out "$OUT/$name.jpg" >/dev/null 2>&1 \
      && rm -f "$OUT/$name.png" \
      && echo "   $OUT/$name.jpg ($(du -h "$OUT/$name.jpg" | cut -f1))"
  else
    echo "   NO PICTURE"; FAILED=1
  fi
}

# Firstlight: the meadow you wake in, with Wick beside you. Golden hour rather than noon, because the
# picture has to say "a story" and not "a block world".
# **Wick is summoned rather than hoped for.** He spawns beside the player and then wanders, so the
# same yaw gave him centre frame in one run and an empty meadow in the next - a coin flip, and the
# empty one is exactly the "block world" picture this shot exists to avoid. `/summon` puts one in
# front of the camera, so the composition is the same every time. (2026-09-30)
shoot firstlight "firstlight" \
  --commands="/time 0.28|/summon firstlight:wick 1" --wait=4 --yaw=2.62 --pitch=-0.12 --warmup=90

# The Fairground: stood back from the first door so the door and its board are both in frame. The
# coordinates are the hub's own - slot 0 at (12, 65, 0), RADIUS 14 less two.
shoot fairground "fairground,lavagame,wordgame" \
  --commands="/time 0.35" --stand=4,65,1 --look=12,66,2 --wait=8 --warmup=90

# One Block: the island, from far enough back that what has been built on it reads.
shoot oneblock "oneblock" \
  --commands="/time 0.35" --wait=8 --yaw=2.2 --pitch=-0.75 --warmup=90

# Creative: a world with everything in it and nothing to survive, seen wide.
shoot creative "creative" \
  --commands="/time 0.42" --wait=8 --yaw=1.4 --pitch=-0.12 --warmup=90

# The hero: the widest, calmest landscape of the four, on the survival world the page leads with.
shoot hero "firstlight" \
  --commands="/time 0.7" --wait=10 --yaw=1.15 --pitch=-0.06 --warmup=120

echo
echo "shots in $OUT"
[ "$FAILED" -eq 0 ] || { echo "!! at least one shot is suspect - read the lines above"; exit 1; }
