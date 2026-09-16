#!/usr/bin/env bash
# Builds everything a release publishes, and lays it out exactly as the download site serves it:
#
#   build/release/index.html                      the download page (GitHub Pages)
#   build/release/update.json                     what the game's updater reads
#   build/release/mods.json                       the mod index (for the in-game mod list)
#   build/release/v<version>/VoxelCraft-...zip    the Mac app
#   build/release/v<version>/mods/<id>-<v>.zip    one zip per mod
#
#   tools/make_release.sh
#   BASE_URL=https://omnivoxel-game.github.io/voxelcraft NOTES="Flying, maps and graves." tools/make_release.sh
#
# BASE_URL is where these files end up *publicly* (see docs/distribution.md): a private repository's
# release assets need a token to download, which the game cannot carry, so the site has to be public.
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(sed -n 's/^const GAME_VERSION := "\(.*\)"$/\1/p' engine/shared/protocol.gd)"
out=build/release
base_url="${BASE_URL:-https://omnivoxel-game.github.io/voxelcraft}"
notes="${NOTES:-A new version of VoxelCraft.}"
files="v$version"

rm -rf "$out"
mkdir -p "$out/$files/mods"

echo "== version $version"
tools/package_mac.sh
mac_zip="build/macos/VoxelCraft-$version-mac-arm64.zip"
cp "$mac_zip" "$out/$files/"
mac_name="$(basename "$mac_zip")"

OUT="$out/$files/mods" tools/package_mods.sh >/dev/null
cp assets/icon.png "$out/icon.png"
echo "== packaged $(ls -1 "$out/$files/mods" | wc -l | tr -d ' ') mods"

digest() { shasum -a 256 "$1" | cut -d' ' -f1; }
size_of() { wc -c < "$1" | tr -d ' '; }
human() { du -h "$1" | cut -f1 | tr -d ' '; }

cat > "$out/update.json" <<EOF
{
	"version": "$version",
	"notes": "$notes",
	"builds": {
		"macos": {
			"url": "$base_url/$files/$mac_name",
			"sha256": "$(digest "$out/$files/$mac_name")",
			"size": $(size_of "$out/$files/$mac_name")
		}
	}
}
EOF

# The mod index, and the rows the download page shows.
mod_rows=""
{
	echo "{"
	echo "	\"version\": \"$version\","
	echo "	\"mods\": ["
	first=1
	for zip in "$out/$files"/mods/*.zip; do
		file="$(basename "$zip")"
		id="${file%-*}"
		mod_version="${file##*-}"
		mod_version="${mod_version%.zip}"
		description="$(sed -n 's/.*"description"[ ]*:[ ]*"\(.*\)",*/\1/p' "mods/$id/mod.json" | head -1)"
		name="$(sed -n 's/.*"name"[ ]*:[ ]*"\(.*\)",*/\1/p' "mods/$id/mod.json" | head -1)"
		[ $first -eq 1 ] || echo "		},"
		first=0
		echo "		{"
		echo "			\"id\": \"$id\","
		echo "			\"name\": \"${name:-$id}\","
		echo "			\"version\": \"$mod_version\","
		echo "			\"description\": \"$description\","
		echo "			\"url\": \"$base_url/$files/mods/$file\","
		echo "			\"sha256\": \"$(digest "$zip")\","
		echo "			\"size\": $(size_of "$zip")"
		mod_rows="$mod_rows<tr><td><b>${name:-$id}</b><br><span class=\"dim\">$description</span></td><td class=\"right\"><a href=\"$files/mods/$file\">$file</a><br><span class=\"dim\">$(human "$zip")</span></td></tr>"
	done
	[ $first -eq 1 ] || echo "		}"
	echo "	]"
	echo "}"
} > "$out/mods.json"

cat > "$out/index.html" <<EOF
<!doctype html>
<meta charset="utf-8">
<title>VoxelCraft $version</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root { color-scheme: dark; }
  body { margin: 0; padding: 0 20px 60px; background: #11141c; color: #e8ecf4;
         font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; }
  .wrap { max-width: 720px; margin: 0 auto; }
  header { display: flex; align-items: center; gap: 18px; padding: 48px 0 8px; }
  header img { width: 96px; height: 96px; border-radius: 22px; }
  h1 { font-size: 34px; margin: 0; }
  .dim { color: #9aa4b8; font-size: 14px; }
  .get { display: inline-block; margin: 22px 0 8px; padding: 14px 26px; border-radius: 10px;
         background: #4c8dff; color: #08101f; font-weight: 700; text-decoration: none; }
  .get:hover { background: #6ba0ff; }
  h2 { font-size: 20px; margin: 40px 0 8px; }
  table { width: 100%; border-collapse: collapse; }
  td { padding: 10px 0; border-top: 1px solid #222838; vertical-align: top; }
  .right { text-align: right; white-space: nowrap; }
  code { background: #1b2130; padding: 2px 6px; border-radius: 5px; font-size: 14px; }
  ol { padding-left: 20px; }
</style>
<div class="wrap">
<header>
  <img src="icon.png" alt="">
  <div>
    <h1>VoxelCraft</h1>
    <div class="dim">Version $version &middot; $notes</div>
  </div>
</header>

<a class="get" href="$files/$mac_name">Download for Mac (Apple silicon)</a>
<div class="dim">$(human "$out/$files/$mac_name") &middot; macOS 11 or newer</div>

<h2>First time on a Mac</h2>
<ol>
  <li>Unzip it and drag <b>VoxelCraft</b> into your Applications folder.</li>
  <li>The first launch needs <b>right-click &rarr; Open</b>, then Open again: the app is signed by us, not
      by Apple, so macOS asks once.</li>
  <li>Type your name in the menu, then <b>Play</b> for your own world, or <b>Multiplayer</b> to join the
      family server.</li>
</ol>
<p class="dim">After this, the game updates itself: it checks this page when the menu opens and offers the
new version. You can turn that off in Settings &rarr; Network.</p>

<h2>Mods</h2>
<p class="dim">The games and add-ons that ship with this version. Servers put these in their mods folder;
the game will list them in its own mod browser.</p>
<table>$mod_rows</table>

<h2>Running a server</h2>
<p>The dedicated server is a Docker image built from the source; see <code>docs/playtest.md</code> in the
repository. Its mods live in a folder on the host, so a mod zip from this page can be dropped straight in.</p>
</div>
EOF

echo
echo "release folder $out:"
find "$out" -maxdepth 2 -type f | sed 's/^/   /'
echo
echo "publish the contents of $out at $base_url"
echo "(index.html, update.json, mods.json and $files/), then tag the commit and attach the same zips."
