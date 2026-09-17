#!/usr/bin/env bash
# Runs the full automated test suite: starts headless servers, runs every end-to-end test against
# them, then the offline tests. Exit code 0 = everything passed.
#
#   tools/run_tests.sh                 # uses $GODOT or `godot` on PATH
#   GODOT=/path/to/godot tools/run_tests.sh
#   QW_NATIVE=0 tools/run_tests.sh  # exercise the GDScript fallbacks
#   ONLY=e2e:combat,gameplay tools/run_tests.sh   # just these tests (names as printed; "e2e:*" and globs work)
#   EXCEPT="e2e:*" tools/run_tests.sh  # everything but these (EXCEPT wins over ONLY)
#   REPEAT=10 ONLY=e2e:combat tools/run_tests.sh  # run each selected test 10 times (hunting flaky tests)
set -uo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/quarrowen-tests.XXXXXX")"
PORT_BASE="${PORT_BASE:-25600}"
ONLY="${ONLY:-}"
EXCEPT="${EXCEPT:-}"
REPEAT="${REPEAT:-1}"
SERVERS=()
FAILED=()
PASSED=()

cleanup() {
  for pid in "${SERVERS[@]}"; do kill -TERM "$pid" 2>/dev/null; done
  wait 2>/dev/null
}
trap cleanup EXIT

# Pin server certificates in a throwaway folder instead of the user's real known servers.
export QW_KNOWN_SERVERS_DIR="$WORK/known_servers"
export QW_SETTINGS="$WORK/settings.cfg"  # tests never touch the player's own settings
echo "godot: $GODOT"
echo "logs:  $WORK"
"$GODOT" --headless --path . --import >"$WORK/import.log" 2>&1

SERVER_GENERATION=0

start_server() { # name mods port
  local log="$WORK/server_$1.log"
  [ "$SERVER_GENERATION" -gt 0 ] && log="$WORK/server_$1_gen$SERVER_GENERATION.log"
  QW_DATA_DIR="$WORK/data" QW_MODS="$2" QW_WORLD="$1" QW_PORT="$3" QW_SEED=42 QW_MAX_PLAYERS=16 \
    QW_ADMINS="Admin,Bot_guild,Bot_industry,Bot_vanilla,Bot_combat" \
    "$GODOT" --headless --path . res://scenes/server.tscn >"$log" 2>&1 &
  SERVERS+=($!)
}

start_servers() {
  start_server all "vanilla,industry,arcana,guild" $((PORT_BASE + 1))
  start_server sky "skyblock" $((PORT_BASE + 3))
  wait_for_server all && wait_for_server sky || { echo "servers failed to start"; exit 1; }
}

# The end-to-end tests play as a fixed bot in a saved world: starter items, a first-time welcome, an
# undamaged pickaxe, unspent mana, a blueprint still to read. Playing the same world again would fail
# those on state left by the run before, so REPEAT starts from an empty world each time - otherwise it
# reports its own leftovers as flakiness.
restart_servers() {
  cleanup
  SERVERS=()
  SERVER_GENERATION=$((SERVER_GENERATION + 1))
  # The worlds go, but not the server's identity: clients pin it, and a new one looks like impersonation.
  find "$WORK/data" -mindepth 1 -maxdepth 1 ! -name identity -exec rm -rf {} +
  start_servers
}

wait_for_server() { # name
  local log="$WORK/server_$1.log"
  [ "$SERVER_GENERATION" -gt 0 ] && log="$WORK/server_$1_gen$SERVER_GENERATION.log"
  for _ in $(seq 1 120); do
    grep -q "running game" "$log" 2>/dev/null && return 0
    if grep -q "Startup failed" "$log" 2>/dev/null; then break; fi
    sleep 0.5
  done
  echo "server $1 did not start:"; tail -20 "$log"
  return 1
}

record() { # name exit_code log
  if [ "$2" -eq 0 ]; then PASSED+=("$1"); echo "PASS $1"; else FAILED+=("$1"); echo "FAIL $1 (see $3)"; grep -hE "FAIL|SCRIPT ERROR" "$3" | head -10; fi
}

selected() { # name
  local pattern patterns
  if [ -n "$EXCEPT" ]; then
    IFS=',' read -ra patterns <<<"$EXCEPT"
    for pattern in "${patterns[@]}"; do
      # shellcheck disable=SC2053
      [[ "$1" == $pattern ]] && return 1
    done
  fi
  [ -z "$ONLY" ] && return 0
  IFS=',' read -ra patterns <<<"$ONLY"
  for pattern in "${patterns[@]}"; do
    # shellcheck disable=SC2053
    [[ "$1" == $pattern ]] && return 0
  done
  return 1
}

# NEEDS_FRESH_WORLD=1 before a run_scene call: this test plays a saved world, so every repeat gets a new one.
run_scene() { # name log scene [user args...]
  local name="$1" log="$2" scene="$3"; shift 3
  selected "$name" || return 0
  local i
  for ((i = 1; i <= REPEAT; i++)); do
    local run_log="$log"
    [ "$REPEAT" -gt 1 ] && run_log="${log%.log}_run$i.log"
    if [ "$REPEAT" -gt 1 ] && [ "${NEEDS_FRESH_WORLD:-0}" = "1" ] && [ "$i" -gt 1 ]; then restart_servers; fi
    timeout 240 "$GODOT" --headless --path . "$scene" -- "$@" >"$run_log" 2>&1
    local code=$?
    local label="$name"
    [ "$REPEAT" -gt 1 ] && label="$name #$i"
    record "$label" $code "$run_log"
  done
}

# Rust links through Apple's `cc`, which is a shim for whatever xcode-select points at. When that is a
# full Xcode whose licence has not been accepted, every tool it fronts refuses to run - including git and
# the linker - and the failure looks like a broken build rather than a missing agreement. The standalone
# Command Line Tools have no such gate, so use them when they are there.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Library/Developer/CommandLineTools ] \
    && ! xcrun --find cc >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  echo "note: using the Command Line Tools for Rust (Xcode's licence is unaccepted)"
fi

# The GDExtension is a built artifact checked in under native/bin, so a source edit does not reach the
# tests until somebody rebuilds it. Running anyway is worse than not running at all: the suite reports
# on a library nobody is writing any more, and a real divergence between the Rust and its GDScript twin
# passes green. So rebuild when the source is newer, and stop if that rebuild fails.
if [ "${QW_NATIVE:-1}" != "0" ] && command -v cargo >/dev/null 2>&1; then
  lib="$(command ls native/bin/*/libquarrowen_native.dylib native/bin/*/libquarrowen_native.so 2>/dev/null | head -1)"
  if [ -z "$lib" ] || [ -n "$(find native/src native/Cargo.toml -newer "$lib" 2>/dev/null)" ]; then
    echo "native library is behind native/src; rebuilding"
    if ! tools/build_native.sh >"$WORK/native_build.log" 2>&1; then
      echo "FAIL native build" && tail -25 "$WORK/native_build.log" && exit 1
    fi
  fi
fi

# Servers are only needed by the end-to-end tests.
needs_servers() {
  local t
  for t in e2e:vanilla e2e:industry e2e:arcana e2e:guild e2e:combat e2e:skyblock auth multiplayer; do selected "$t" && return 0; done
  return 1
}

if needs_servers; then
start_servers
fi

NEEDS_FRESH_WORLD=1
for game in vanilla industry arcana guild combat; do
  run_scene "e2e:$game" "$WORK/test_$game.log" res://tests/smoke_test.tscn --port=$((PORT_BASE + 1)) --game=$game
done
run_scene "e2e:skyblock" "$WORK/test_skyblock.log" res://tests/smoke_test.tscn --port=$((PORT_BASE + 3)) --game=skyblock
NEEDS_FRESH_WORLD=0
run_scene "auth" "$WORK/test_auth.log" res://tests/auth_test.tscn --port=$((PORT_BASE + 1))
if [ -f tests/multiplayer_test.tscn ]; then
  run_scene "multiplayer" "$WORK/test_multiplayer.log" res://tests/multiplayer_test.tscn --port=$((PORT_BASE + 1))
fi

cleanup
SERVERS=()
for log in "$WORK"/server_*.log; do
  [ -f "$log" ] || continue
  if grep -qE "SCRIPT ERROR|script error" "$log"; then FAILED+=("clean-server-log:$(basename "$log")"); grep -hE "SCRIPT ERROR|script error" "$log" | head -5; fi
done

# Every bundled mod and every example must pass the validator (errors fail; warnings and hints printed).
# The examples are documentation that runs, so they rot the moment nothing checks them.
for mod_dir in mods/*/ examples/*/; do
  [ -f "$mod_dir/mod.json" ] || continue
  mod="$(basename "$mod_dir")"
  selected "validate:$mod" || continue
  timeout 240 "$GODOT" --headless --path . res://tools/mod_tool.tscn -- validate "${mod_dir%/}" >"$WORK/validate_$mod.log" 2>&1
  code=$?
  grep -h "^\[mod_tool\] \(ERROR\|WARNING\)" "$WORK/validate_$mod.log" | head -5
  record "validate:$mod" $code "$WORK/validate_$mod.log"
done

run_scene "persistence" "$WORK/persistence.log" res://tests/persistence_test.tscn
run_scene "identity" "$WORK/identity.log" res://tests/identity_test.tscn
run_scene "gameplay" "$WORK/gameplay.log" res://tests/gameplay_test.tscn
run_scene "ai" "$WORK/ai.log" res://tests/ai_test.tscn
# Mob AI on generated terrain: stuck, hopping in place, dithering, blind hits and failed chases stay under limits.
run_scene "ai-soak" "$WORK/ai_soak.log" res://tests/ai_soak.tscn --seconds=60 --sites=4 --check
if [ "${QW_NATIVE:-1}" != "0" ]; then
  run_scene "js-sandbox" "$WORK/js_sandbox.log" res://tests/js_sandbox_test.tscn
fi
for extra in tests/host_flow_test.tscn tests/reload_test.tscn tests/transfer_test.tscn tests/save_compat_test.tscn; do
  [ -f "$extra" ] && run_scene "$(basename "$extra" .tscn)" "$WORK/$(basename "$extra" .tscn).log" "res://$extra"
done
# The hub service (Rust) with a real game server; skipped when cargo is not installed.
if command -v cargo >/dev/null 2>&1 && (selected hub-unit || selected hub); then
  if cargo build --release --manifest-path services/hub/Cargo.toml >"$WORK/hub_build.log" 2>&1 \
      && cargo test --release --manifest-path services/hub/Cargo.toml >"$WORK/hub_unit.log" 2>&1; then
    record "hub-unit" 0 "$WORK/hub_unit.log"
    run_scene "hub" "$WORK/hub.log" res://tests/hub_test.tscn
    # A test that timed out cannot stop the processes it started: the hub and its game server.
    pkill -f "services/hub/target/release/quarrowen-hub" 2>/dev/null
    pkill -f -- "--name=Hub Test Server" 2>/dev/null
  else
    record "hub-unit" 1 "$WORK/hub_unit.log"
    tail -20 "$WORK/hub_build.log" "$WORK/hub_unit.log" 2>/dev/null
  fi
fi

# A script error inside a test can abort its remaining checks without failing it; treat it as a failure.
for log in "$WORK"/*.log; do
  case "$(basename "$log")" in server_*|import.log) continue ;; esac
  # tests/mods/buggy fails on purpose (the dev log tests); any other script error counts.
  if grep -A1 "SCRIPT ERROR" "$log" | grep "at:" | grep -v "tests/mods/buggy" | grep -qv "reload_mods\|__reload_probe"; then FAILED+=("clean-test-log:$(basename "$log")"); grep -h "SCRIPT ERROR" -A2 "$log" | head -6; fi
done

echo
echo "passed: ${#PASSED[@]}  failed: ${#FAILED[@]}"
[ ${#FAILED[@]} -eq 0 ] || { printf '  %s\n' "${FAILED[@]}"; exit 1; }
