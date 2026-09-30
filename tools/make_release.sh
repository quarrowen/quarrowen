#!/usr/bin/env bash
# Builds everything a release publishes, and lays it out exactly as the download site serves it:
#
#   build/release/index.html                      the download page (GitHub Pages)
#   build/release/update.json                     what the game's updater reads
#   build/release/mods.json                       the mod index (for the in-game mod list)
#   build/release/v<version>/Quarrowen-...zip    the Mac app
#   build/release/v<version>/mods/<id>-<v>.zip    one zip per mod
#
#   tools/make_release.sh                                    # zips served from the site itself
#   BASE_URL=https://github.com/<org>/<repo>/releases/download/v<version> tools/make_release.sh
#                                                            # zips attached to the GitHub release
#   NOTES="Flying, maps and graves." tools/make_release.sh
#
# BASE_URL is where these files end up *publicly* (see docs/distribution.md): a private repository's
# release assets need a token to download, which the game cannot carry, so the site has to be public.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
version="$(sed -n 's/^const GAME_VERSION := "\(.*\)"$/\1/p' engine/shared/protocol.gd)"

# **Import the project first, or half of this runs without the native extension.**
#
# `.godot/` is not in the repository, so a fresh clone has no import cache and - the part that actually
# bites - no `extension_list.cfg`, which is the file that tells Godot to load a GDExtension at all. The
# Mac package does not notice, because it exports from a staged copy and the export imports as it goes.
# Everything after it does: `mod_tool` runs against *this* checkout, finds no extension, and every mod
# fails to validate with "NativeVoxelWorld does not exist".
#
# It never showed up locally because a working checkout has been imported long ago, and it never showed
# up in CI because this job had never once run. The first time it did, it signed and notarised a build
# and then fell over packing the mods. Done here rather than in the workflow so a fresh clone on
# somebody's laptop behaves the same, and done before the Mac build so it fails in seconds rather than
# after a notarisation. (2026-09-29)
if [ ! -f .godot/extension_list.cfg ]; then
	echo "== importing the project (no .godot yet)"
	"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
	if [ ! -f .godot/extension_list.cfg ]; then
		echo "!! import did not produce .godot/extension_list.cfg - mods will fail to validate." >&2
		exit 1
	fi
fi
out=build/release
base_url="${BASE_URL:-https://quarrowen.com}"
# GitHub release assets are one flat list under the tag, so their URLs have no folders below it; the
# Pages layout keeps the v<version>/ folder. The base URL says which of the two this build is for, and
# tools/publish_site.sh refuses to publish a manifest that points somewhere the zips are not.
flat=0
case "$base_url" in */releases/download/*) flat=1 ;; esac
notes="${NOTES:-A new version of Quarrowen.}"
files="v$version"

# **The page lists the mods that are in the build**, read from each mod.json, rather than describing
# games in hardcoded HTML. It did the latter until 2026-09-24, and a guard sat here refusing to build
# because the four games it described had been deleted three days earlier - so the page would have
# advertised games nobody could play, quietly, because a stale <section> is still valid HTML.
#
# The guard is gone because the thing it guarded against is: the hand-written "Four games, one
# download" section has been removed, the hero image no longer carries a deleted game's name, and the
# only mods the page names are the ones whose zips are beside it. A page generated from the build
# cannot go stale the way one written by hand does, which is the actual fix. (2026-09-24)

rm -rf "$out"
mkdir -p "$out/$files/mods"

echo "== version $version"
tools/package_mac.sh
# **Found, not assumed.** This named the file `-mac-arm64` while `package_mac.sh` decided the suffix,
# so the day the Mac build became universal this would have failed with "no such file" at the end of a
# notarisation - or, worse, quietly picked up a stale arm64 zip from a previous run and published it.
# Two names for one file in two scripts is a pair that drifts; asking the directory is not. (2026-09-28)
# Read from the run that just happened rather than guessed at or globbed: build/macos keeps every
# release ever cut, so a glob finds old ones too - and `-mac-arm64` sorts before `-mac-universal`.
if [ ! -f build/macos/.last-package ]; then
  echo "make_release: package_mac.sh left no build/macos/.last-package" >&2
  exit 1
fi
mac_zip="build/macos/$(cat build/macos/.last-package)"
if [ ! -f "$mac_zip" ]; then
  echo "make_release: $mac_zip does not exist" >&2
  exit 1
fi
case "$mac_zip" in
  *"-$version-"*) ;;
  *) echo "make_release: $mac_zip is not version $version - package_mac.sh did not run?" >&2; exit 1 ;;
esac
cp "$mac_zip" "$out/$files/"
mac_name="$(basename "$mac_zip")"
# The disk image is what a person downloads; the zip is what the updater swaps in. update.json keeps
# pointing at the zip, so an unattended update never has to mount anything.
mac_dmg="${mac_zip%.zip}.dmg"
dmg_name=""
if [ -f "$mac_dmg" ]; then
  cp "$mac_dmg" "$out/$files/"
  dmg_name="$(basename "$mac_dmg")"
fi

# Windows. Nobody builds it here - there is no Windows machine - so it comes from the tag's CI run, which
# is the only artifact of CI's that reaches a player. It is unsigned (SmartScreen may warn) and it is NOT
# offered through update.json: the updater's install step writes a /bin/sh script, so a Windows client
# that accepted an update could not install it. Download link only, until that is written.
win_zip="build/windows/Quarrowen-$version-windows-x86_64.zip"
win_setup="build/windows/Quarrowen-$version-Setup.exe"
win_name=""
setup_name=""
if [ ! -f "$win_zip" ] && [ "${QUARROWEN_SKIP_WINDOWS:-0}" != "1" ] && command -v gh >/dev/null 2>&1; then
  run_id="$(gh run list --workflow CI --branch "v$version" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  if [ -n "$run_id" ]; then
    echo "== fetching the Windows build from CI run $run_id"
    tmp="$(mktemp -d)"
    if gh run download "$run_id" -n windows-unsigned-untested -D "$tmp" >/dev/null 2>&1; then
      mkdir -p build/windows
      # The artifact unpacks to a folder called "windows", which is a poor thing to find in Downloads.
      # Give it the game's name and version, so extracting it produces something recognisable.
      # The installer is built beside the game folder in the same artifact; take it out before the
      # folder is renamed and zipped, or it ends up inside the zip of the thing it installs.
      if [ -f "$tmp/installer/Quarrowen-$version-Setup.exe" ]; then
        mkdir -p build/windows
        mv "$tmp/installer/Quarrowen-$version-Setup.exe" "$win_setup"
        rmdir "$tmp/installer" 2>/dev/null || true
        echo "   got $win_setup"
      fi
      inner="$tmp/Quarrowen-$version"
      if [ -d "$tmp/windows" ]; then mv "$tmp/windows" "$inner"; else mkdir -p "$inner" && find "$tmp" -maxdepth 1 -mindepth 1 ! -name "Quarrowen-$version" -exec mv {} "$inner/" \; ; fi
      (cd "$tmp" && zip -qr "$OLDPWD/$win_zip" "Quarrowen-$version") && echo "   got $win_zip"
    else
      echo "   no Windows artifact on that run; the page will not offer it"
    fi
    rm -rf "$tmp"
  fi
fi
if [ -f "$win_zip" ]; then
  cp "$win_zip" "$out/$files/"
  win_name="$(basename "$win_zip")"
fi
if [ -f "$win_setup" ]; then
  cp "$win_setup" "$out/$files/"
  setup_name="$(basename "$win_setup")"
fi

OUT="$out/$files/mods" tools/package_mods.sh >/dev/null
cp assets/icon.png "$out/icon.png"
# The page is led by pictures of the game (site/screenshots, taken with the interface hidden - F1).
mkdir -p "$out/shots" && cp site/screenshots/*.jpg "$out/shots/" 2>/dev/null || true
echo "== packaged $(ls -1 "$out/$files/mods" | wc -l | tr -d ' ') mods"

digest() { shasum -a 256 "$1" | cut -d' ' -f1; }
size_of() { wc -c < "$1" | tr -d ' '; }
human() { du -h "$1" | cut -f1 | tr -d ' '; }

# GitHub release assets are one flat list; the Pages layout keeps the v<version> folder.
if [ "$flat" -eq 1 ]; then mac_url="$base_url/$mac_name"; else mac_url="$base_url/$files/$mac_name"; fi
if [ -n "$dmg_name" ]; then
  if [ "$flat" -eq 1 ]; then dmg_url="$base_url/$dmg_name"; else dmg_url="$base_url/$files/$dmg_name"; fi
else
  dmg_url="$mac_url"
fi
download_name="${dmg_name:-$mac_name}"
win_url=""
setup_url=""
win_button=""
if [ -n "$setup_name" ]; then
  if [ "$flat" -eq 1 ]; then setup_url="$base_url/$setup_name"; else setup_url="$base_url/$files/$setup_name"; fi
fi
if [ -n "$win_name" ]; then
  if [ "$flat" -eq 1 ]; then win_url="$base_url/$win_name"; else win_url="$base_url/$files/$win_name"; fi
fi
# Quieter than the Mac button on purpose: it is unsigned, so Windows shows a warning the first time,
# and it does not update itself. Saying so here is better than somebody finding out.
#
# **The installer leads and the zip stays.** The zip is a folder and cannot stop being one - the
# GDExtension is a .dll loaded from disk and `mods/` is loose so players can add to it - so the choice
# was to make somebody unzip and go looking, or to offer a setup. Both are here, because somebody who
# would rather not run an installer should not be made to. (2026-09-29)
# **Windows gets a button, not a footnote.** It was a line of small text under the Mac button, decided
# when it was an afterthought - unsigned, untested, no auto-update. Two of those are still true and are
# said plainly right beneath it, but "second-class" is not the same as "hard to find", and a player on
# Windows should not have to read the small print to discover the game runs on their machine.
# (2026-09-29)
win_cta=""
if [ -n "$setup_name" ]; then
  win_cta="<a class=\"btn\" href=\"$setup_url\">Download for Windows <small>$version · $(human "$out/$files/$setup_name")</small></a>"
elif [ -n "$win_name" ]; then
  win_cta="<a class=\"btn\" href=\"$win_url\">Download for Windows <small>$version · $(human "$out/$files/$win_name")</small></a>"
fi
if [ -n "$setup_name" ] && [ -n "$win_name" ]; then
  win_button="<details class=\"under\"><summary><b>On Windows?</b> One extra click the first time</summary><p class=\"under\"><b>On Windows:</b> download the setup and run it. Windows asks once before running a program it has not seen before - choose <i>More info</i>, then <i>Run anyway</i>. It does not update itself yet, so come back here when there is a new version. Prefer a zip? <a href=\"$win_url\">Take the folder instead ($(human "$out/$files/$win_name"))</a> and run Quarrowen.exe from inside it.</p></details>"
elif [ -n "$setup_name" ]; then
  win_button="<details class=\"under\"><summary><b>On Windows?</b> One extra click the first time</summary><p class=\"under\"><b>On Windows:</b> download the setup and run it. Windows asks once before running a program it has not seen before - choose <i>More info</i>, then <i>Run anyway</i>. It does not update itself yet, so come back here when there is a new version.</p></details>"
elif [ -n "$win_name" ]; then
  win_button="<details class=\"under\"><summary><b>On Windows?</b> One extra click the first time</summary><p class=\"under\"><b>On Windows:</b> unpack the whole folder and run Quarrowen.exe from inside it. Windows asks once before running a program it has not seen before - choose <i>More info</i>, then <i>Run anyway</i>. It does not update itself yet.</p></details>"
fi

cat > "$out/update.json" <<EOF
{
	"version": "$version",
	"notes": "$notes",
	"builds": {
		"macos": {
			"url": "$mac_url",
			"sha256": "$(digest "$out/$files/$mac_name")",
			"size": $(size_of "$out/$files/$mac_name")
		}
	}
}
EOF

# Sign the manifest so a client only trusts a release that came from the project (see tools/release_key.gd).
key="${QUARROWEN_RELEASE_KEY:-$HOME/.config/quarrowen/release_key.pem}"
sign() {
	if [ -f "$key" ]; then
		"$GODOT" --headless --path . -s tools/release_key.gd -- sign --file="$1" --key="$key" | tail -1
	fi
}
if [ -f "$key" ]; then
	sign "$out/update.json"
	# **And check a client would accept it.** Signing proves the key was readable, not that it is the key
	# this build's updater trusts - and those come apart the moment one is rotated, or a release is cut on
	# a machine holding an older key. The failure is silent and late: the site looks right, the manifest
	# looks right, and every installed game quietly refuses the update. Cheap to ask now. (2026-09-29)
	if QW_VERIFY_FILE="$out/update.json" "$GODOT" --headless --path . -s tools/verify_signature.gd \
			>"$out/.verify.log" 2>&1; then
		grep -h "^verify:" "$out/.verify.log" | tail -1
	else
		grep -h "^verify:" "$out/.verify.log" | tail -1 >&2
		echo "!! the manifest is signed with a key no shipped client trusts - see updater.gd RELEASE_KEYS." >&2
		exit 1
	fi
	rm -f "$out/.verify.log"
else
	echo "!! no release key at $key: the manifest is unsigned, and clients that expect a signature will"
	echo "!! ignore this release. Make one with: godot --headless --path . -s tools/release_key.gd -- new"
fi

# The mod index the game's mod screen reads, built from the packed zips themselves (so what it claims and
# what it ships cannot drift), and signed like the update manifest.
if [ "$flat" -eq 1 ]; then mods_base="$base_url"; else mods_base="$base_url/$files/mods"; fi
"$GODOT" --headless --path . res://tools/mod_tool.tscn -- index "$out/$files/mods" \
	--base-url="$mods_base" --out="$out/mods.json" --version="$version" | tail -1
sign "$out/mods.json"

# The rows the download page shows, from the same zips.
# Only the games reach the page now; `kind` comes from each mod.json and the other kinds are listed on
# the release page instead (see docs/mods_plan.md for what the kinds mean).
# **The same manifest, read once**, and **sorted by the `order` field in it**. The section that tells a
# player what there is to play is built here rather than written into the template, because a
# hand-written list is how the README spent a week naming three games that had been deleted
# (2026-09-29) - and hand-ordering it in the template is the same mistake one step later, so the order
# is a fact in each mod.json beside the name it belongs to. (2026-09-30)
#
# The zip tables that used to be built here are gone: they were for somebody adding a mod by hand,
# which the in-game Mods page already does, and sitting beside the games they read as "these games are
# a few kilobytes". The release page carries them now.
game_cards=""
for zip in $(for z in "$out/$files"/mods/*.zip; do
		gid="$(basename "$z")"; gid="${gid%-*}"
		printf '%s\t%s\n' "$(sed -n 's/.*"order"[ ]*:[ ]*\([0-9]*\).*/\1/p' "mods/$gid/mod.json" | head -1)" "$z"
	done | sort -n | cut -f2); do
	file="$(basename "$zip")"
	id="${file%-*}"
	description="$(sed -n 's/.*"description"[ ]*:[ ]*"\(.*\)",*/\1/p' "mods/$id/mod.json" | head -1)"
	name="$(sed -n 's/.*"name"[ ]*:[ ]*"\(.*\)",*/\1/p' "mods/$id/mod.json" | head -1)"
	kind="$(sed -n 's/.*"kind"[ ]*:[ ]*"\(.*\)",*/\1/p' "mods/$id/mod.json" | head -1)"
	case "$kind" in
		# **A game with no picture yet gets a card without one**, rather than a broken image or a
		# stand-in from another game. One Block is the case: a world a harness just made is a single
		# block over the void, so it photographs as empty sky, and the picture has to come from a world
		# somebody has played. (2026-09-30)
		game)
			if [ -f "$out/shots/$id.jpg" ]; then
				game_cards="$game_cards<div class=\"game\"><div class=\"shot\"><img src=\"shots/$id.jpg\" alt=\"$name\"></div><div><h3>${name:-$id}</h3><p>$description</p></div></div>"
			else
				game_cards="$game_cards<div class=\"game\"><div class=\"shot pending\"><span>picture coming</span></div><div><h3>${name:-$id}</h3><p>$description</p></div></div>"
			fi ;;
	esac
done

# Every picture in site/screenshots, named rather than a hard-coded two - so a shot added there appears
# in the facts table without anybody remembering to list it.
shots_list=""
for shot in "$out"/shots/*.jpg; do
	[ -f "$shot" ] || continue
	shots_list="$shots_list<a href=\"shots/$(basename "$shot")\">$(basename "$shot")</a> "
done

# **The page is a template now, not a heredoc.** Its prose lives in site/landing/ where it can be
# read, reviewed and edited by somebody who is not editing the release tooling; the values a release
# knows - what the files are called, how big they are, which games shipped - are worked out here and
# handed over as JSON. tools/build_landing.py refuses to merge if either side has something the other
# does not, so a placeholder cannot reach the live page unfilled and a value cannot be silently
# dropped. (2026-09-30)
python3 - "$out/landing_values.json" <<PYEOF
import json, sys
json.dump({
    "version": "$version",
    "released": "$(date -u +"%e %B %Y" | sed 's/^ //')",
    "mac_url": "$dmg_url",
    "mac_size": "$(human "$out/$files/$download_name")",
    "win_button": """$win_button""",
    "win_cta": """$win_cta""",
    "game_cards": """$game_cards""",
    "shots_list": """$shots_list""",
}, open(sys.argv[1], "w"))
PYEOF
tools/build_landing.py site/landing "$out/landing_values.json" "$out/index.html"
rm -f "$out/landing_values.json"

echo
echo "release folder $out:"
find "$out" -maxdepth 2 -type f | sed 's/^/   /'
echo
echo "publish the contents of $out at $base_url"
echo "(index.html, update.json, mods.json and $files/), then tag the commit and attach the same zips."
