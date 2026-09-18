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
out=build/release
base_url="${BASE_URL:-https://quarrowen.com}"
# GitHub release assets are one flat list under the tag, so their URLs have no folders below it; the
# Pages layout keeps the v<version>/ folder. The base URL says which of the two this build is for, and
# tools/publish_site.sh refuses to publish a manifest that points somewhere the zips are not.
flat=0
case "$base_url" in */releases/download/*) flat=1 ;; esac
notes="${NOTES:-A new version of Quarrowen.}"
files="v$version"

rm -rf "$out"
mkdir -p "$out/$files/mods"

echo "== version $version"
tools/package_mac.sh
mac_zip="build/macos/Quarrowen-$version-mac-arm64.zip"
cp "$mac_zip" "$out/$files/"
mac_name="$(basename "$mac_zip")"
# The disk image is what a person downloads; the zip is what the updater swaps in. update.json keeps
# pointing at the zip, so an unattended update never has to mount anything.
mac_dmg="build/macos/Quarrowen-$version-mac-arm64.dmg"
dmg_name=""
if [ -f "$mac_dmg" ]; then
  cp "$mac_dmg" "$out/$files/"
  dmg_name="$(basename "$mac_dmg")"
fi

OUT="$out/$files/mods" tools/package_mods.sh >/dev/null
cp assets/icon.png "$out/icon.png"
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
# The page groups mods the way the game's own list does: games to play, add-ons for a game, and the
# library everything is built on (see docs/mods_plan.md). `kind` comes from each mod.json.
games_rows=""
addon_rows=""
library_rows=""
for zip in "$out/$files"/mods/*.zip; do
	file="$(basename "$zip")"
	id="${file%-*}"
	description="$(sed -n 's/.*"description"[ ]*:[ ]*"\(.*\)",*/\1/p' "mods/$id/mod.json" | head -1)"
	name="$(sed -n 's/.*"name"[ ]*:[ ]*"\(.*\)",*/\1/p' "mods/$id/mod.json" | head -1)"
	kind="$(sed -n 's/.*"kind"[ ]*:[ ]*"\(.*\)",*/\1/p' "mods/$id/mod.json" | head -1)"
	row="<tr><td><b>${name:-$id}</b><br><span class=\"dim\">$description</span></td><td class=\"right\"><a href=\"$mods_base/$file\">$file</a><br><span class=\"dim\">$(human "$zip")</span></td></tr>"
	case "$kind" in
		game) games_rows="$games_rows$row" ;;
		library) library_rows="$library_rows$row" ;;
		*) addon_rows="$addon_rows$row" ;;
	esac
done
mod_sections=""
[ -n "$games_rows" ] && mod_sections="$mod_sections<h3>Games</h3><p class=\"dim\">A world runs one of these.</p><table>$games_rows</table>"
[ -n "$addon_rows" ] && mod_sections="$mod_sections<h3>Add-ons</h3><p class=\"dim\">Extra content on top of a game.</p><table>$addon_rows</table>"
[ -n "$library_rows" ] && mod_sections="$mod_sections<h3>Library</h3><p class=\"dim\">Blocks and items the others are built on; every game needs it.</p><table>$library_rows</table>"

cat > "$out/index.html" <<EOF
<!doctype html>
<meta charset="utf-8">
<title>Quarrowen</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="A voxel game where the server decides the game. Free to play, free to mod.">
<link rel="icon" href="icon.png">
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 0 20px 80px; background: #0f1219; color: #e8ecf4;
         font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; }
  a { color: #7fb2ff; }
  .wrap { max-width: 760px; margin: 0 auto; }
  header { display: flex; align-items: center; gap: 20px; padding: 56px 0 4px; flex-wrap: wrap; }
  header img { width: 104px; height: 104px; border-radius: 24px; }
  h1 { font-size: 40px; margin: 0; letter-spacing: -0.5px; }
  .tag { color: #9aa4b8; font-size: 17px; margin-top: 4px; }
  .dim { color: #9aa4b8; font-size: 14px; }
  .get { display: inline-block; margin: 24px 0 6px; padding: 15px 28px; border-radius: 11px;
         background: #4c8dff; color: #08101f; font-weight: 700; text-decoration: none; font-size: 17px; }
  .get:hover { background: #6ba0ff; }
  h2 { font-size: 21px; margin: 44px 0 10px; }
  pre { background: #161b26; border: 1px solid #222838; border-radius: 10px; padding: 12px 14px;
        overflow-x: auto; font-size: 13px; line-height: 1.5; }
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 14px; margin-top: 8px; }
  .card { background: #161b26; border: 1px solid #222838; border-radius: 12px; padding: 14px 16px; }
  .card b { display: block; margin-bottom: 4px; }
  .card span { color: #9aa4b8; font-size: 14px; }
  table { width: 100%; border-collapse: collapse; }
  td { padding: 11px 0; border-top: 1px solid #222838; vertical-align: top; }
  .right { text-align: right; white-space: nowrap; }
  code { background: #1b2130; padding: 2px 6px; border-radius: 5px; font-size: 14px; }
  ol, ul { padding-left: 20px; }
  footer { margin-top: 56px; padding-top: 20px; border-top: 1px solid #222838; color: #9aa4b8; font-size: 14px; }
</style>
<div class="wrap">
<header>
  <img src="icon.png" alt="">
  <div>
    <h1>Quarrowen</h1>
    <div class="tag">A voxel game where the server decides the game.<br>Build, survive, or start on a single block over the void.</div>
  </div>
</header>

<a class="get" href="$dmg_url">Download for Mac (Apple silicon)</a>
<div class="dim">Version $version &middot; $(human "$out/$files/$download_name") &middot; macOS 11 or newer &middot; $notes</div>
<div class="dim">An independent project &mdash; not affiliated with Mojang, Microsoft or Roblox.</div>

<h2>What it is</h2>
<div class="cards">
  <div class="card"><b>One client, many games</b><span>The client ships no content. It downloads the blocks, models and rules from whichever server you join - a sandbox, an island, a one-block challenge.</span></div>
  <div class="card"><b>Play together</b><span>Host a world from the menu and your family joins over the network, or run the dedicated server in Docker. Friends, parties and invite codes included.</span></div>
  <div class="card"><b>Made to be modded</b><span>A mod is a folder with a manifest and a script (GDScript, or sandboxed JavaScript). Blocks, mobs, machines, world generation, UI and commands are all mod territory.</span></div>
  <div class="card"><b>Keeps itself current</b><span>The game checks this page when it opens and offers the new version. Worlds and inventories survive updates.</span></div>
</div>

<h2>First time on a Mac</h2>
<ol>
  <li>Open the disk image and drag <b>Quarrowen</b> onto the Applications folder beside it.</li>
  <li>Open it. It is signed and notarized by Apple, so it opens by double-clicking - no right-click detour.</li>
  <li>Type your name in the menu, then <b>Play</b> for your own world, or <b>Multiplayer</b> to join a server.</li>
</ol>

<h2>Where to go next</h2>
<div class="cards">
  <div class="card"><b><a href="https://github.com/quarrowen/quarrowen/blob/master/docs/playing.md">Playing</a></b><span>Controls, your first hour, crafting, and how recipes are discovered.</span></div>
  <div class="card"><b><a href="https://github.com/quarrowen/quarrowen/blob/master/docs/hosting.md">Running a server</a></b><span>Three worlds and a hub on one Linux box, in about ten minutes, for the family.</span></div>
  <div class="card"><b><a href="https://github.com/quarrowen/quarrowen/blob/master/docs/modding.md">Making a mod</a></b><span>Blocks, creatures, machines and whole games, in GDScript or JavaScript.</span></div>
  <div class="card"><b><a href="https://github.com/quarrowen/quarrowen/blob/master/docs/faq.md">Questions</a></b><span>Is it safe for children, what does it cost, where are my worlds kept.</span></div>
</div>

<h2>Mods in this release</h2>
<p class="dim">The game comes with all of these - this is for adding one to a server, or installing it by
hand. In the game, the <b>Mods</b> page does it for you.</p>
$mod_sections

<h2>Running a server</h2>
<p>The dedicated server is a published Docker image, so the machine that runs it never compiles anything:
three files, <code>docker compose pull</code>, and it is up. You can run several worlds beside each other -
a survival world, an island, a story - and let players walk between them. The
<a href="https://github.com/quarrowen/quarrowen/blob/master/docs/hosting.md">hosting guide</a> is the whole
setup, including the Macs that join it.</p>
<p class="dim">The server for this release. A server and the games joining it must be the same version, so
these are pinned rather than following <code>:latest</code> - put them in your <code>.env</code>:</p>
<pre><code>QW_IMAGE=ghcr.io/quarrowen/quarrowen/server:$version
QW_HUB_IMAGE=ghcr.io/quarrowen/quarrowen/hub:$version</code></pre>

<h2>Source</h2>
<p>Everything lives at <a href="https://github.com/quarrowen/quarrowen">github.com/quarrowen/quarrowen</a>:
the engine, the mods, the tools that generate the art and sounds, and the tests. Free to use, modify and share
for anything noncommercial; commercial use needs a separate licence.</p>

<footer>
Built from scratch with <a href="https://claude.com/claude-code">Claude Code</a> - engine, renderer, server,
mod API, AI and tooling, from an empty folder.
<br><br>
Quarrowen is an independent project, not affiliated with, endorsed by or connected to Mojang Synergies AB,
Microsoft or Roblox Corporation. Minecraft is a trademark of Mojang Synergies AB; Roblox is a trademark of
Roblox Corporation.
</footer>
</div>
EOF

echo
echo "release folder $out:"
find "$out" -maxdepth 2 -type f | sed 's/^/   /'
echo
echo "publish the contents of $out at $base_url"
echo "(index.html, update.json, mods.json and $files/), then tag the commit and attach the same zips."
