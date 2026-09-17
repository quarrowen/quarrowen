#!/usr/bin/env bash
# Builds Quarrowen.app (a universal app; the native library is Apple silicon only) and zips it for sharing:
#   build/macos/Quarrowen.app
#   build/macos/Quarrowen-<version>-mac-arm64.zip
#
# The app carries the bundled mods in Contents/Resources/mods (so it can host worlds).
#
# Signing: with an Apple Developer ID certificate in the keychain the app is signed properly, hardened
# and notarized, and it opens with a double click like any other app. Without one it falls back to an
# ad-hoc signature, which works on your own Macs but makes the first launch a right-click > Open (or
# `xattr -dr com.apple.quarantine Quarrowen.app`). Set these to sign:
#
#   QUARROWEN_SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)", or "auto" to find it
#   QUARROWEN_NOTARY_PROFILE  the notarytool keychain profile (xcrun notarytool store-credentials ...)
#
# Notarizing needs the network and takes a few minutes; QUARROWEN_SKIP_NOTARIZE=1 signs without it.
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

# Adding the mods invalidated the export's signature, so the bundle is signed again either way.
identity="${QUARROWEN_SIGN_IDENTITY:-auto}"
if [ "$identity" = "auto" ]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
if [ -n "$identity" ]; then
  # A real signature: hardened runtime (notarization refuses without it) and a timestamp, inside out.
  echo "== signing as $identity"
  find "$app/Contents" -type f \( -name "*.dylib" -o -name "*.framework" \) -print0 |
    xargs -0 -I{} codesign --force --timestamp --options runtime --sign "$identity" {} 2>/dev/null || true
  codesign --force --deep --timestamp --options runtime --sign "$identity" "$app"
  codesign --verify --deep --strict "$app"
else
  echo "== no Developer ID certificate found: signing ad hoc (first launch needs right-click > Open)"
  codesign --force --deep --sign - "$app"
  codesign --verify --deep --strict "$app"
fi

zip="$out/Quarrowen-$version-mac-arm64.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

# Notarizing: Apple checks the build, then the ticket is stapled into the app so it opens offline too.
profile="${QUARROWEN_NOTARY_PROFILE:-quarrowen-notary}"
if [ -n "$identity" ] && [ "${QUARROWEN_SKIP_NOTARIZE:-0}" != "1" ] && xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  echo "== notarizing (a few minutes)"
  if xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait; then
    xcrun stapler staple "$app"
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"   # zip again so the download carries the stapled ticket
    echo "== notarized and stapled"
  else
    echo "!! notarization failed: the app is signed but macOS will still warn on first launch" >&2
  fi
elif [ -n "$identity" ]; then
  echo "== skipping notarization (no '$profile' notarytool profile; see the header of this script)"
fi
echo "built $app"
echo "zipped $zip ($(du -h "$zip" | cut -f1))"
