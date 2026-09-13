#!/usr/bin/env bash
# Runs the full automated test suite: starts headless servers, runs every end-to-end test against
# them, then the offline tests. Exit code 0 = everything passed.
#
#   tools/run_tests.sh                 # uses $GODOT or `godot` on PATH
#   GODOT=/path/to/godot tools/run_tests.sh
#   VOXEL_NATIVE=0 tools/run_tests.sh  # exercise the GDScript fallbacks
set -uo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/voxelcraft-tests.XXXXXX")"
PORT_BASE="${PORT_BASE:-25600}"
SERVERS=()
FAILED=()
PASSED=()

cleanup() {
  for pid in "${SERVERS[@]}"; do kill -TERM "$pid" 2>/dev/null; done
  wait 2>/dev/null
}
trap cleanup EXIT

# Pin server certificates in a throwaway folder instead of the user's real known servers.
export VOXEL_KNOWN_SERVERS_DIR="$WORK/known_servers"
echo "godot: $GODOT"
echo "logs:  $WORK"
"$GODOT" --headless --path . --import >"$WORK/import.log" 2>&1

start_server() { # name mods port
  VOXEL_DATA_DIR="$WORK/data" VOXEL_MODS="$2" VOXEL_WORLD="$1" VOXEL_PORT="$3" VOXEL_SEED=42 VOXEL_MAX_PLAYERS=16 \
    VOXEL_ADMINS="Admin,Bot_guild,Bot_industry,Bot_vanilla" \
    "$GODOT" --headless --path . res://scenes/server.tscn >"$WORK/server_$1.log" 2>&1 &
  SERVERS+=($!)
}

wait_for_server() { # name
  for _ in $(seq 1 120); do
    grep -q "running game" "$WORK/server_$1.log" 2>/dev/null && return 0
    if grep -q "Startup failed" "$WORK/server_$1.log" 2>/dev/null; then break; fi
    sleep 0.5
  done
  echo "server $1 did not start:"; tail -20 "$WORK/server_$1.log"
  return 1
}

record() { # name exit_code log
  if [ "$2" -eq 0 ]; then PASSED+=("$1"); echo "PASS $1"; else FAILED+=("$1"); echo "FAIL $1 (see $3)"; grep -hE "FAIL|SCRIPT ERROR" "$3" | head -10; fi
}

run_scene() { # name log scene [user args...]
  local name="$1" log="$2" scene="$3"; shift 3
  timeout 240 "$GODOT" --headless --path . "$scene" -- "$@" >"$log" 2>&1
  record "$name" $? "$log"
}

start_server all "vanilla,industry,arcana,guild" $((PORT_BASE + 1))
start_server sky "skyblock" $((PORT_BASE + 2))
wait_for_server all && wait_for_server sky || { echo "servers failed to start"; exit 1; }

for game in vanilla industry arcana guild; do
  run_scene "e2e:$game" "$WORK/test_$game.log" res://tests/smoke_test.tscn --port=$((PORT_BASE + 1)) --game=$game
done
run_scene "e2e:skyblock" "$WORK/test_skyblock.log" res://tests/smoke_test.tscn --port=$((PORT_BASE + 2)) --game=skyblock
run_scene "auth" "$WORK/test_auth.log" res://tests/auth_test.tscn --port=$((PORT_BASE + 1))
if [ -f tests/multiplayer_test.tscn ]; then
  run_scene "multiplayer" "$WORK/test_multiplayer.log" res://tests/multiplayer_test.tscn --port=$((PORT_BASE + 1))
fi

cleanup
SERVERS=()
for log in "$WORK"/server_*.log; do
  if grep -qE "SCRIPT ERROR|script error" "$log"; then FAILED+=("clean-server-log:$(basename "$log")"); grep -hE "SCRIPT ERROR|script error" "$log" | head -5; fi
done

run_scene "persistence" "$WORK/persistence.log" res://tests/persistence_test.tscn
run_scene "identity" "$WORK/identity.log" res://tests/identity_test.tscn
if [ "${VOXEL_NATIVE:-1}" != "0" ]; then
  run_scene "js-sandbox" "$WORK/js_sandbox.log" res://tests/js_sandbox_test.tscn
fi
for extra in tests/host_flow_test.tscn; do
  [ -f "$extra" ] && run_scene "$(basename "$extra" .tscn)" "$WORK/$(basename "$extra" .tscn).log" "res://$extra"
done

echo
echo "passed: ${#PASSED[@]}  failed: ${#FAILED[@]}"
[ ${#FAILED[@]} -eq 0 ] || { printf '  %s\n' "${FAILED[@]}"; exit 1; }
