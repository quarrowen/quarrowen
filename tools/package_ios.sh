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

echo "Xcode project at $out/Quarrowen.xcodeproj ($(du -sh "$out" | cut -f1))"
echo "Open it, choose your team under Signing & Capabilities, and run on a device."
echo "The first device needs this: Xcode registers it, and only the GUI can."
