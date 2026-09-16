#!/usr/bin/env bash
# Builds Quarrowen.app (a universal app; the native library is Apple silicon only) and zips it for sharing:
#   build/macos/Quarrowen.app
#   build/macos/Quarrowen-<version>-mac-arm64.zip
#
# The app carries the bundled mods in Contents/Resources/mods (so it can host worlds) and is signed
# ad hoc, which is enough for your own Macs: the first launch needs right-click > Open (or
# `xattr -dr com.apple.quarantine Quarrowen.app`). Sharing widely needs an Apple Developer ID and
# notarization.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
version="$(sed -n 's/^const GAME_VERSION := "\(.*\)"$/\1/p' engine/shared/protocol.gd)"
out=build/macos
app="$out/Quarrowen.app"

tools/build_native.sh
rm -rf "$app"
mkdir -p "$out"
# Export from a clean copy: local editor plugins (addons/) would otherwise add their autoloads to the app.
stage="$(mktemp -d "${TMPDIR:-/tmp}/quarrowen-export.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
rsync -a --exclude ".git/" --exclude "addons/" --exclude "build/" --exclude "native/target/" --exclude "services/" \
  --exclude ".godot/editor/" --exclude "tests/" ./ "$stage/"
sed -i '' '/^\[editor_plugins\]/,/^enabled=/d' "$stage/project.godot"
"$GODOT" --headless --path "$stage" --import >/dev/null 2>&1 || true
log="$(mktemp)"
"$GODOT" --headless --path "$stage" --export-release "macOS" "$PWD/$app" >"$log" 2>&1 || true
if [ ! -d "$app/Contents/MacOS" ] || [ -z "$(ls -A "$app/Contents/MacOS" 2>/dev/null)" ] || ! ls "$app"/Contents/Resources/*.pck >/dev/null 2>&1; then
  grep -E "ERROR|error" "$log" | head -20 >&2
  echo "export failed (see $log)" >&2
  exit 1
fi
rm -f "$log"
rsync -a --delete --exclude "*.import" --exclude "*.uid" --exclude ".DS_Store" mods/ "$app/Contents/Resources/mods/"
# Adding files invalidated the export's signature: sign the whole bundle again (ad hoc).
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
zip="$out/Quarrowen-$version-mac-arm64.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
echo "built $app"
echo "zipped $zip ($(du -h "$zip" | cut -f1))"
