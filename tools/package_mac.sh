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
# Extra mods to bundle, as paths: QW_EXTRA_MODS="tests/mods/lookbook".
#
# For a build somebody is meant to *stand in* rather than ship. `mods/` holds `base` alone until the
# 1.0 content is written, and base is a library with no game - so a plain package has nothing to load
# and nothing to measure a frame rate against. (2026-09-21)
for extra in ${QW_EXTRA_MODS:-}; do
  if [ -d "$extra" ]; then
    rsync -a --exclude "*.import" --exclude "*.uid" --exclude ".DS_Store" "$extra" "$app/Contents/Resources/mods/"
    echo "   bundled $extra"
  else
    echo "   QW_EXTRA_MODS: no such folder '$extra'" >&2
  fi
done

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
elif [ "${QUARROWEN_REQUIRE_SIGNING:-0}" = "1" ]; then
  # A release must never fall through to an ad-hoc signature: it would publish a build macOS refuses to
  # open, and the failure would be a child's, days later, not the build's.
  echo "no Developer ID certificate in the keychain search list, and this build requires one." >&2
  security find-identity -v -p codesigning >&2 || true
  exit 1
else
  echo "== no Developer ID certificate found: signing ad hoc (first launch needs right-click > Open)"
  codesign --force --deep --sign - "$app"
  codesign --verify --deep --strict "$app"
fi

zip="$out/Quarrowen-$version-mac-arm64.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

# Notarizing: Apple checks the build, then the ticket is stapled into the app so it opens offline too.
#
# Two ways to prove who we are. On a person's Mac it is a keychain profile, made once with
# `notarytool store-credentials`, so no secret is ever typed into a script. On a build machine it is an
# App Store Connect API key, because a keychain profile cannot travel: the key is scoped to notarisation
# and can be revoked on its own, where an app-specific password authenticates as the whole Apple Account.
profile="${QUARROWEN_NOTARY_PROFILE:-quarrowen-notary}"
notary_args=()
if [ -n "${QUARROWEN_NOTARY_KEY:-}" ] && [ -n "${QUARROWEN_NOTARY_KEY_ID:-}" ] && [ -n "${QUARROWEN_NOTARY_ISSUER:-}" ]; then
  notary_args=(--key "$QUARROWEN_NOTARY_KEY" --key-id "$QUARROWEN_NOTARY_KEY_ID" --issuer "$QUARROWEN_NOTARY_ISSUER")
elif xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  notary_args=(--keychain-profile "$profile")
fi
if [ -n "$identity" ] && [ "${QUARROWEN_SKIP_NOTARIZE:-0}" != "1" ] && [ ${#notary_args[@]} -gt 0 ]; then
  echo "== notarizing (a few minutes)"
  if xcrun notarytool submit "$zip" "${notary_args[@]}" --wait; then
    xcrun stapler staple "$app"
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"   # zip again so the download carries the stapled ticket
    echo "== notarized and stapled"
  else
    echo "!! notarization failed: the app is signed but macOS will still warn on first launch" >&2
  fi
elif [ -n "$identity" ]; then
  echo "== skipping notarization (no '$profile' keychain profile and no API key; see the header of this script)"
fi
# A disk image for people, the zip for the updater. Dragging an app into Applications is what a Mac
# download looks like; the updater wants something it can unpack unattended in one call, and mounting a
# disk image in a script that runs while the game is quitting is more to go wrong at bedtime.
dmg="$out/Quarrowen-$version-mac-arm64.dmg"
if command -v hdiutil >/dev/null 2>&1 && [ "${QUARROWEN_SKIP_DMG:-0}" != "1" ]; then
  staging="$(mktemp -d)"
  cp -R "$app" "$staging/"
  ln -s /Applications "$staging/Applications"
  rm -f "$dmg"
  if hdiutil create -volname "Quarrowen" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null; then
    [ -n "$identity" ] && codesign --force --sign "$identity" --timestamp "$dmg"
    # The app inside carries its own stapled ticket, but notarizing the image as well means the download
    # itself is trusted rather than only what comes out of it.
    if [ -n "$identity" ] && [ "${QUARROWEN_SKIP_NOTARIZE:-0}" != "1" ] && [ ${#notary_args[@]} -gt 0 ]; then
      echo "== notarizing the disk image"
      if xcrun notarytool submit "$dmg" "${notary_args[@]}" --wait; then
        xcrun stapler staple "$dmg"
      else
        echo "!! the disk image was not notarized; the zip still is" >&2
      fi
    fi
    echo "disk image $dmg ($(du -h "$dmg" | cut -f1))"
  else
    echo "!! could not make a disk image; the zip is still there" >&2
  fi
  rm -rf "$staging"
fi
echo "built $app"
echo "zipped $zip ($(du -h "$zip" | cut -f1))"
