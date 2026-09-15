#!/usr/bin/env bash
# Packages every mod (or the ones named as arguments) into build/mods/<id>-<version>.zip, the form a
# server loads from its mods folder and a release attaches so people can download one mod at a time.
#
#   tools/package_mods.sh
#   tools/package_mods.sh vanilla arcana
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
OUT="${OUT:-build/mods}"

mods=("$@")
if [ ${#mods[@]} -eq 0 ]; then
  for dir in mods/*/; do
    [ -f "$dir/mod.json" ] && mods+=("$(basename "$dir")")
  done
fi

mkdir -p "$OUT"
status=0
for mod in "${mods[@]}"; do
  log="$(mktemp)"
  if "$GODOT" --headless --path . res://tools/mod_tool.tscn -- pack "mods/$mod" "--out=$OUT" >"$log" 2>&1 && grep -q "^\[mod_tool\] packed" "$log"; then
    grep "^\[mod_tool\] packed" "$log" | sed 's/^\[mod_tool\] /ok: /'
  else
    grep -E "error|ERROR" "$log" | head -5 >&2
    echo "FAILED: $mod" >&2
    status=1
  fi
  rm -f "$log"
done
ls -1 "$OUT"/*.zip 2>/dev/null | sed 's/^/   /'
exit $status
