#!/usr/bin/env bash
# Generates the Xcode project for the iPad build:
#   build/ios/Quarrowen.xcodeproj
#
# Godot's iOS export does not produce a finished app. It produces an Xcode project which you then
# open, pick a signing team in, and run on a device or archive for TestFlight. So this script's job
# ends where Xcode's begins.
#
#   tools/package_ios.sh              # generate the Xcode project
#   tools/package_ios.sh --release    # release export rather than debug
#
# **Your Apple Team ID is not in this repository.** `export_presets.cfg` is committed and this repo is
# public, so the preset carries an empty team id and the real one lives in `apple.env` (gitignored;
# see apple.env.example). This script exports from a throwaway copy of the project with the value
# patched in, which is the same trick package_mac.sh uses to keep local editor addons out of the app.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"

mode="--export-debug"
[ "${1:-}" = "--release" ] && mode="--export-release"

[ -f apple.env ] || { echo "no apple.env - copy apple.env.example and fill in your Team ID" >&2; exit 1; }
# shellcheck disable=SC1091
set -a; . ./apple.env; set +a
[ -n "${APPLE_TEAM_ID:-}" ] || { echo "APPLE_TEAM_ID is empty in apple.env" >&2; exit 1; }

# The frameworks the extension needs on iOS. Device only by default; the simulator build is a
# separate framework and Xcode picks whichever the destination wants, so build both.
tools/build_native.sh ios
tools/build_native.sh ios-sim

out="$(pwd)/build/ios"
rm -rf "$out"
mkdir -p "$out"

stage="$(mktemp -d "${TMPDIR:-/tmp}/quarrowen-ios.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
rsync -a --exclude ".git/" --exclude "addons/" --exclude "build/" --exclude "native/target/" \
	--exclude "services/" --exclude ".godot/" . "$stage/"

# Patch the team id (and the bundle id, if one is set) into the copy's preset only.
python3 - "$stage/export_presets.cfg" "$APPLE_TEAM_ID" "${APPLE_BUNDLE_ID:-}" <<'PY'
import sys
path, team, bundle = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
s = s.replace('application/app_store_team_id=""', 'application/app_store_team_id="%s"' % team, 1)
if bundle:
	s = s.replace('application/bundle_identifier="com.quarrowen.client"',
		'application/bundle_identifier="%s"' % bundle)
open(path, 'w').write(s)
PY

# **The export is allowed to fail, and usually will the first time.** Godot's iOS exporter finishes by
# running `xcodebuild archive`, which needs a provisioning profile - and a profile cannot exist until
# the device is registered, which does not happen headlessly however correct the account, the
# certificate and the team are (2026-09-23, an evening of finding that out). The Xcode project is
# written *before* the archive step, so a failed archive still leaves exactly what this script's own
# header promises: something to open. Judge on whether the project exists, not on the exit code.
set +e
"$GODOT" --headless --path "$stage" "$mode" "iOS" "$out/Quarrowen.xcodeproj"
set -e
[ -d "$out/Quarrowen.xcodeproj" ] || { echo "export produced no Xcode project - see the output above" >&2; exit 1; }

# **Godot writes a contradiction into the Release configuration**: `CODE_SIGN_STYLE = Automatic` and a
# hardcoded `CODE_SIGN_IDENTITY = "Apple Distribution"`. Both cannot be true - automatic signing is
# what chooses the identity - so Xcode refuses the target with "conflicting provisioning settings"
# before it will build anything, including Debug, which was already correct. Development signing is
# what a build run from here is for; a distribution build will set its own identity deliberately
# rather than inherit this one.
/usr/bin/sed -i '' 's/CODE_SIGN_IDENTITY = "Apple Distribution";/CODE_SIGN_IDENTITY = "Apple Development";/g' \
	"$out/Quarrowen.xcodeproj/project.pbxproj"

# **The mods go into the app bundle, exactly as they do on the Mac.** `ModLoader.search_dirs` looks in
# `<executable dir>/mods` before anything else, and on iOS the executable lives inside `Quarrowen.app` -
# so the folder only has to be there. They are kept out of the `.pck` on every platform for the same
# reason (an export would repack the raw textures and models the server streams to clients), which is
# why this is a copy and not an include filter.
#
# Adding files invalidates the signature, so the app is signed again with the identity and the
# entitlements read back out of what Xcode produced - and then rezipped. Verified on an iPad Air on
# 2026-09-27: without this the menu offers no games at all. It costs 2.8 MB. (2026-09-27)
if [ -f "$out/Quarrowen.ipa" ]; then
	work="$(mktemp -d "${TMPDIR:-/tmp}/quarrowen-ipa.XXXXXX")"
	( cd "$work" && unzip -q "$out/Quarrowen.ipa" )
	app="$work/Payload/Quarrowen.app"
	if [ -d "$app" ]; then
		identity="$(codesign -dvv "$app" 2>&1 | sed -n 's/^Authority=\(Apple Development:.*\)$/\1/p' | head -1)"
		codesign -d --entitlements "$work/ents.plist" --xml "$app" 2>/dev/null
		rsync -a --exclude "*.import" --exclude "*.uid" --exclude ".DS_Store" mods/ "$app/mods/"
		for extra in ${QW_EXTRA_MODS:-}; do
			[ -d "$extra" ] && rsync -a --exclude "*.import" --exclude "*.uid" --exclude ".DS_Store" "$extra" "$app/mods/"
		done
		if [ -n "$identity" ] && [ -s "$work/ents.plist" ]; then
			codesign -f -s "$identity" --entitlements "$work/ents.plist" --timestamp=none "$app" >/dev/null 2>&1
			codesign --verify "$app" 2>/dev/null && rm -f "$out/Quarrowen.ipa" && ( cd "$work" && zip -qr "$out/Quarrowen.ipa" Payload ) \
				&& echo "bundled $(du -sh "$app/mods" | cut -f1) of mods into the app"
		else
			echo "WARNING: could not read the signing identity or entitlements; the .ipa has no mods" >&2
		fi
	fi
	rm -rf "$work"
fi

echo "Xcode project at $out/Quarrowen.xcodeproj ($(du -sh "$out" | cut -f1))"
# **Once a device has been registered, the archive stops failing and this produces an .ipa** - which
# the header above did not expect, because the first time it was written no device was registered and
# the export never got that far. When there is one, say so and print the command that installs it,
# because the useful artefact is then the .ipa and not the project. (2026-09-27)
if [ -f "$out/Quarrowen.ipa" ]; then
	echo "Installable build at $out/Quarrowen.ipa ($(du -h "$out/Quarrowen.ipa" | cut -f1))"
	echo "  xcrun devicectl list devices                  # find the device id"
	echo "  xcrun devicectl device install app --device <id> $out/Quarrowen.ipa"
else
	echo "Open it, choose your team under Signing & Capabilities, and run on a device."
	echo "The first device needs this: Xcode registers it, and only the GUI can."
fi
# **The games are in the bundle now, and the tablet still cannot host.** Those are two different
# things and the second is the platform's: starting a local world forks a second copy of the
# executable, and iOS does not allow that - `create_process` returns ERR_CANT_FORK whatever is in the
# bundle.
#
# **A joining client does not need these**, which is worth being clear about: the server streams the
# content it is running, which is how the iPad played Firstlight on 25 September with an empty bundle.
# They are here for the day the tablet can host, and meanwhile for the menu's game list and backdrop.
# See PROGRESS, 2026-09-27.
echo "Note: this build can join worlds. Starting one locally needs a second process, which iOS forbids."
