#!/usr/bin/env bash
# Exports every preset in export_presets.cfg (or the ones named as arguments) into build/, with the
# bundled mods copied beside each build.
# Needs Godot ${GODOT_VERSION:-4.7.2} export templates installed and native libraries in native/bin/.
#
#   tools/export.sh
#   tools/export.sh "Linux Server x86_64" macOS
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"

presets=("$@")
if [ ${#presets[@]} -eq 0 ]; then
  while IFS= read -r line; do presets+=("$line"); done < <(sed -n 's/^name="\(.*\)"$/\1/p' export_presets.cfg)
fi

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
status=0
for preset in "${presets[@]}"; do
  path="$(awk -v name="$preset" '
    $0 ~ /^\[preset\.[0-9]+\]$/ { current = "" }
    $0 == "name=\"" name "\"" { current = name }
    current != "" && /^export_path=/ { sub(/^export_path="/, ""); sub(/"$/, ""); print; exit }
  ' export_presets.cfg)"
  mkdir -p "$(dirname "$path")"
  echo "== exporting $preset -> $path"
  log="$(mktemp)"
  "$GODOT" --headless --path . --export-release "$preset" "$path" >"$log" 2>&1 || true
  if grep -qE "export for preset .* failed|Cannot export project" "$log" || [ ! -e "$path" ]; then
    grep -E "ERROR|error" "$log" | head -20 >&2
    echo "FAILED: $preset" >&2
    status=1
  else
    # Mods ship as plain files beside the binary (see ModLoader.search_dirs).
    rm -rf "$(dirname "$path")/mods"
    rsync -a --exclude "*.import" --exclude "*.uid" --exclude ".DS_Store" mods/ "$(dirname "$path")/mods/"
    echo "ok: $preset"
  fi
  rm -f "$log"
done
exit $status
