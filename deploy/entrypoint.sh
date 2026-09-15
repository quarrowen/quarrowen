#!/bin/sh
# Starts the dedicated server with the mods that live on the host.
#
# The image carries the engine plus a seed copy of the mods it shipped with (base, vanilla and the
# add-ons). The mods the server actually loads come from $VOXEL_MODS_DIR (/mods), which is a volume:
# add, edit or remove mods there without rebuilding the image.
#
# On every start each bundled mod is refreshed in /mods so an engine update cannot leave stale engine
# content behind. Anything else in /mods is left alone. VOXEL_SEED_MODS:
#   update (default) refresh the bundled mods, keep everything else
#   missing          only copy bundled mods that are not there yet (your edits to them survive)
#   never            copy nothing; /mods is entirely yours
set -e

seed_dir=/opt/voxelcraft/mods-seed
mods_dir="${VOXEL_MODS_DIR:-/mods}"
mode="${VOXEL_SEED_MODS:-update}"

if [ "$mode" != "never" ] && [ -d "$seed_dir" ]; then
  mkdir -p "$mods_dir"
  copied=""
  for mod in "$seed_dir"/*; do
    [ -d "$mod" ] || continue
    id="$(basename "$mod")"
    if [ "$mode" = "missing" ] && [ -d "$mods_dir/$id" ]; then
      continue
    fi
    if [ -d "$mods_dir/$id" ] && [ "$mode" = "update" ]; then
      rm -rf "$mods_dir/$id"
    fi
    cp -R "$mod" "$mods_dir/$id"
    copied="$copied $id"
  done
  [ -n "$copied" ] && echo "[entrypoint] mods in $mods_dir refreshed from the image:$copied"
fi
echo "[entrypoint] loading mods from $mods_dir: $(ls "$mods_dir" 2>/dev/null | tr '\n' ' ')"

exec /opt/voxelcraft/voxelcraft_server --headless "$@"
