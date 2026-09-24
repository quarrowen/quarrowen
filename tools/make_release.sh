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

# Windows. Nobody builds it here - there is no Windows machine - so it comes from the tag's CI run, which
# is the only artifact of CI's that reaches a player. It is unsigned (SmartScreen may warn) and it is NOT
# offered through update.json: the updater's install step writes a /bin/sh script, so a Windows client
# that accepted an update could not install it. Download link only, until that is written.
win_zip="build/windows/Quarrowen-$version-windows-x86_64.zip"
win_name=""
if [ ! -f "$win_zip" ] && [ "${QUARROWEN_SKIP_WINDOWS:-0}" != "1" ] && command -v gh >/dev/null 2>&1; then
  run_id="$(gh run list --workflow CI --branch "v$version" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  if [ -n "$run_id" ]; then
    echo "== fetching the Windows build from CI run $run_id"
    tmp="$(mktemp -d)"
    if gh run download "$run_id" -n windows-unsigned-untested -D "$tmp" >/dev/null 2>&1; then
      mkdir -p build/windows
      # The artifact unpacks to a folder called "windows", which is a poor thing to find in Downloads.
      # Give it the game's name and version, so extracting it produces something recognisable.
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
win_button=""
if [ -n "$win_name" ]; then
  if [ "$flat" -eq 1 ]; then win_url="$base_url/$win_name"; else win_url="$base_url/$files/$win_name"; fi
  # Quieter than the Mac button on purpose: it is unsigned, so Windows shows a warning the first time,
  # and it does not update itself. Saying so here is better than a child finding out.
  win_button="<p class=\"under\"><a href=\"$win_url\">Windows ($(human "$out/$files/$win_name"))</a> — unsigned, so Windows asks before running it, and it does not update itself yet.</p>"
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
[ -n "$library_rows" ] && mod_sections="$mod_sections<h3>Packs</h3><p class=\"dim\">What a game is built from. A game names the ones it wants.</p><table>$library_rows</table>"

cat > "$out/index.html" <<EOF
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="A voxel game where the server decides the game. Free to play, free to mod, and free for your family.">
<link rel="icon" href="icon.png">
<title>Quarrowen</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600;700&family=Nunito+Sans:opsz,wght@6..12,400;6..12,600;6..12,700&display=swap">
<style>
  :root {
    /* The game's own palette (engine/client/menu/menu_theme.gd), so the site and the game match. */
    --ground: #1A212E;
    --panel: #0F141C;
    --panel-2: #172031;
    --edge: #2A3445;
    --ink: #F0F2F5;
    --muted: #97A0AE;
    --accent: #5CB86B;
    --accent-hover: #70CC80;
    --warn: #FFB880;
    --display: "Fredoka", system-ui, sans-serif;   /* headings and the name */
    --sans: "Nunito Sans", system-ui, sans-serif;  /* everything a player reads */
  }
  * { box-sizing: border-box; }
  html { -webkit-text-size-adjust: 100%; }
  body {
    margin: 0; padding: 0; background: var(--ground); color: var(--ink);
    font: 400 17px/1.65 var(--sans);
  }
  .wrap { max-width: 1060px; margin: 0 auto; padding-inline: 24px; }
  .narrow { max-width: 680px; }
  a { color: var(--accent); text-underline-offset: 3px; }
  a:focus-visible, .btn:focus-visible { outline: 3px solid var(--accent); outline-offset: 3px; }
  img { max-width: 100%; display: block; }

  /* --- Hero: the valley fills the screen, the words sit on it. --- */
  .hero { position: relative; min-height: 78vh; display: flex; align-items: flex-end; overflow: hidden; }
  .hero-img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; }
  .hero::after {
    content: ""; position: absolute; inset: 0;
    background: linear-gradient(180deg, rgba(26,33,46,0.34) 0%, rgba(26,33,46,0.1) 40%, rgba(26,33,46,0.92) 88%, var(--ground) 100%);
  }
  .hero .wrap { position: relative; z-index: 2; padding-block: 0 64px; width: 100%; }
  .name {
    font: 600 15px/1 var(--display); letter-spacing: 0.26em; text-transform: uppercase;
    color: var(--accent); margin: 0 0 18px; text-shadow: 0 2px 16px rgba(0,0,0,0.9);
  }
  h1 {
    font: 600 clamp(42px, 8vw, 86px)/0.98 var(--display);
    margin: 0; letter-spacing: -0.015em; max-width: 14ch; text-wrap: balance;
    text-shadow: 0 4px 32px rgba(0,0,0,0.75);
  }
  h1 span { color: var(--accent); }
  .hero p {
    font-size: clamp(17px, 2.1vw, 21px); margin: 20px 0 0; max-width: 40ch; color: #DCE2EA;
    text-shadow: 0 2px 18px rgba(0,0,0,0.85); text-wrap: pretty;
  }
  .cta { display: flex; flex-wrap: wrap; gap: 14px 16px; align-items: center; margin-top: 34px; }
  .btn {
    display: inline-flex; align-items: center; gap: 12px; text-decoration: none;
    font-family: var(--display); font-weight: 600; font-size: 19px;
    background: var(--accent); color: #08150C; padding: 16px 30px; border-radius: 12px;
    border: 2px solid var(--accent); box-shadow: 0 10px 40px rgba(92,184,107,0.28);
    transition: background 0.15s ease, transform 0.12s ease;
  }
  .btn:hover { background: var(--accent-hover); border-color: var(--accent-hover); }
  .btn:active { transform: translateY(2px); }
  .btn small { font: 400 13px/1 var(--sans); opacity: 0.72; }
  .btn.ghost {
    background: rgba(255,255,255,0.06); color: var(--ink); border-color: rgba(255,255,255,0.22);
    box-shadow: none;
  }
  .btn.ghost:hover { background: rgba(255,255,255,0.13); border-color: rgba(255,255,255,0.4); }
  .under { font-size: 14px; color: var(--muted); margin-top: 14px; }

  /* --- Sections --- */
  section { padding-block: 86px 0; }
  h2 {
    font: 600 clamp(28px, 4vw, 40px)/1.1 var(--display);
    margin: 0 0 16px; letter-spacing: -0.01em; text-wrap: balance;
  }
  h2 span { color: var(--accent); }
  .sub { color: var(--muted); font-size: 17.5px; margin: 0 0 40px; max-width: 54ch; text-wrap: pretty; }
  p { text-wrap: pretty; }

  /* A game: a big picture with its words beside it, alternating sides. */
  .game { display: grid; grid-template-columns: 1.15fr 1fr; gap: 40px; align-items: center; margin-bottom: 72px; }
  .game:nth-child(even) .shot { order: 2; }
  .shot { border-radius: 14px; overflow: hidden; border: 1px solid var(--edge); background: var(--panel); }
  .shot img { width: 100%; height: auto; }
  .game h3 { font: 600 27px/1.2 var(--display); margin: 0 0 4px; }
  .kind {
    font: 600 12px/1 var(--sans); letter-spacing: 0.14em; text-transform: uppercase;
    color: var(--accent); margin: 0 0 12px;
  }
  .game p { margin: 0; color: #C7CFDA; font-size: 16.5px; }
  .figures {
    display: flex; gap: 26px; margin-top: 20px; padding-top: 18px; border-top: 1px solid var(--edge);
    font-size: 14px; color: var(--muted); font-variant-numeric: tabular-nums;
  }
  .figures b { display: block; font-family: var(--display); font-weight: 600; font-size: 25px; color: var(--ink); line-height: 1.1; }

  /* What makes it different: plain statements, no cards fighting the games above. */
  .diffs { display: grid; grid-template-columns: repeat(auto-fit, minmax(290px, 1fr)); gap: 34px 40px; }
  .diff h3 {
    font: 600 20px/1.25 var(--display); margin: 0 0 8px; padding-top: 16px;
    border-top: 2px solid var(--accent);
  }
  .diff p { margin: 0; color: #C7CFDA; font-size: 15.5px; }
  .diff em { font-style: normal; color: var(--ink); font-weight: 600; }

  /* The mod zips: a plain table, since it is a reference rather than something to browse. */
  .mods { margin-top: 56px; padding-top: 28px; border-top: 1px solid var(--edge); }
  .mods h3 { font: 600 20px/1.25 var(--display); margin: 0 0 8px; }
  .mods h3 + p { margin-bottom: 14px; }
  .mods table { width: 100%; border-collapse: collapse; margin: 0 0 22px; font-size: 14.5px; }
  .mods td { padding: 9px 12px 9px 0; border-bottom: 1px solid var(--edge); vertical-align: top; }
  .mods td:last-child { text-align: right; color: var(--muted); white-space: nowrap; font-variant-numeric: tabular-nums; }
  .dim { color: var(--muted); font-size: 14px; margin: 0 0 8px; }

  /* Four lanes */
  .lanes { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 16px; }
  .lane {
    background: var(--panel); border: 1px solid var(--edge); border-radius: 14px; padding: 24px;
    transition: border-color 0.15s ease, background 0.15s ease;
  }
  .lane:hover { background: var(--panel-2); border-color: #3C4A61; }
  .lane h3 { font: 600 20px/1.25 var(--display); margin: 0 0 8px; }
  .lane p { font-size: 15px; color: var(--muted); margin: 0 0 14px; }
  .lane a { font-weight: 600; font-size: 15px; text-decoration: none; }
  .lane a:hover { text-decoration: underline; }

  /* Server */
  .server { background: var(--panel); border: 1px solid var(--edge); border-radius: 16px; padding: 34px; }
  .server h2 { font-size: clamp(25px, 3.4vw, 33px); }
  pre {
    background: #0A0E15; border: 1px solid var(--edge); border-radius: 10px; margin: 20px 0 0;
    padding: 16px 18px; overflow-x: auto;
    font: 400 13.5px/1.75 ui-monospace, SFMono-Regular, Menlo, monospace; color: #C7CFDA;
  }
  pre b { color: var(--accent); font-weight: 400; }

  .made { border-top: 1px solid var(--edge); margin-top: 96px; padding-top: 40px; }
  .made p { color: var(--muted); font-size: 16px; max-width: 62ch; }
  .made strong { color: var(--ink); font-weight: 600; }
  footer { padding-block: 40px 90px; color: #6F7A8A; font-size: 13.5px; }
  footer p { max-width: none; }

  @media (max-width: 760px) {
    .game { grid-template-columns: 1fr; gap: 22px; margin-bottom: 56px; }
    .game:nth-child(even) .shot { order: 0; }
    .hero { min-height: 72vh; }
    .server { padding: 24px; }
  }
</style>

<div class="hero">
  <img class="hero-img" src="shots/hero.jpg"
       alt="Green hills with an ore-streaked cliff, trees and a beach beyond.">
  <div class="wrap">
    <p class="name">Quarrowen</p>
    <h1>The server decides <span>the game</span>.</h1>
    <p>One app plays any world, because it carries no game of its own. Blocks, creatures, recipes and
    rules all arrive from whichever server you join.</p>
    <div class="cta">
      <a class="btn" href="$dmg_url">Download for Mac <small>$version · $(human "$out/$files/$download_name")</small></a>
      <a class="btn ghost" href="/docs/">Read the reference</a>
    </div>
    <p class="under">Apple silicon · signed and notarized · updates itself · $notes</p>
    $win_button
  </div>
</div>

<div class="wrap">

<section id="different">
  <h2>How this is <span>different</span></h2>
  <p class="sub">Block games are a genre, the way platformers are. What Quarrowen does differently is
  where the game lives and who is allowed to change it.</p>

  <div class="diffs">
    <div class="diff">
      <h3>The app has no game in it</h3>
      <p>Other block games ship a game and let you mod it. Quarrowen ships an <em>engine</em>: the client
      has no blocks, no creatures and no rules of its own. It downloads them from whichever server it
      joins, so the same app is a survival world on one server and a story on the next.</p>
    </div>
    <div class="diff">
      <h3>Nobody installs a mod</h3>
      <p>Mods are installed on the server only. A child joins and the content arrives — no launchers, no
      mod folders, no matching versions between friends, nothing to go wrong at bedtime. A mismatch is
      refused at the door with a sentence saying so, rather than breaking quietly.</p>
    </div>
    <div class="diff">
      <h3>A mod can change anything</h3>
      <p>Blocks, creatures and their AI, world generation, machines, crafting, UI panels, commands,
      whole games. Every game that ships with it is a mod too. The engine only supplies capabilities,
      which means anything a bundled game does, yours can do.</p>
    </div>
    <div class="diff">
      <h3>Two languages, one of them sandboxed</h3>
      <p>Write a mod in GDScript, or in JavaScript that runs in a sandbox. There is no marketplace, no
      approval queue and no revenue share — you write a folder with a manifest in it and put it on your
      server.</p>
    </div>
    <div class="diff">
      <h3>There is no platform</h3>
      <p>No account, no sign-up, no email, no telemetry, no store, no currency, no advertising. A player
      is a key on their own computer. Your worlds are files on your own machine or your own server, and
      they stay there.</p>
    </div>
    <div class="diff">
      <h3>You can read all of it</h3>
      <p>The whole engine is published — renderer, server, protocol, AI, tests. Free to play, modify and
      share for anything noncommercial. If you want to know how something works, the answer is a file,
      not a support ticket.</p>
    </div>
  </div>
</section>

<section>
  <h2>Made for a family to <span>play together</span></h2>
  <p class="sub">Your worlds live on your own machine or your own server. No accounts, no email, nothing
  collected, and only the people you allow can join.</p>
  <div class="shot" style="max-width:100%">
    <img src="shots/menu.jpg" alt="The Quarrowen main menu, with a world list over a living world backdrop.">
  </div>
</section>

<section>
  <h2>Where to go</h2>
  <div class="lanes">
    <div class="lane">
      <h3>Play</h3>
      <p>Controls, your first hour, and how recipes are discovered rather than looked up.</p>
      <a href="https://github.com/quarrowen/quarrowen/blob/master/docs/playing.md">Playing →</a>
    </div>
    <div class="lane">
      <h3>Run a server</h3>
      <p>Several worlds and a hub on one Linux box, in about ten minutes.</p>
      <a href="https://github.com/quarrowen/quarrowen/blob/master/docs/hosting.md">Hosting →</a>
    </div>
    <div class="lane">
      <h3>Make a mod</h3>
      <p>Blocks, creatures, machines, whole games — GDScript or JavaScript.</p>
      <a href="https://github.com/quarrowen/quarrowen/blob/master/docs/modding.md">Modding →</a>
    </div>
    <div class="lane">
      <h3>Questions</h3>
      <p>What it costs, whether it's safe for children, where your worlds are kept.</p>
      <a href="https://github.com/quarrowen/quarrowen/blob/master/docs/faq.md">FAQ →</a>
    </div>
  </div>
</section>

<section id="get">
  <div class="server">
    <h2>Running a server</h2>
    <p class="sub" style="margin-bottom:0">Three files and a pull. The machine never compiles anything,
    and several worlds can sit beside each other with players walking between them through portals.</p>
<pre><b>QW_IMAGE</b>=ghcr.io/quarrowen/quarrowen/server:$version
<b>QW_HUB_IMAGE</b>=ghcr.io/quarrowen/quarrowen/hub:$version

docker compose pull &amp;&amp; docker compose up -d</pre>
  </div>
  <div class="mods">
    <h3>Mods in this release</h3>
    <p class="sub" style="margin:0 0 18px">Every game comes with the download; these are for adding one to
    a server by hand. In the game, the Mods page does it for you.</p>
    $mod_sections
  </div>
</section>

<section class="made">
  <h2>Built with Claude Code</h2>
  <p><strong>Every line of this engine was written with <a href="https://claude.com/claude-code">Claude
  Code</a>, from an empty folder</strong> — the renderer and its Rust mesher, the authoritative server and
  its protocol, mob AI and pathfinding, the mod API and its sandbox, world generation, the tests and the
  tooling. No engine template and no asset packs: every texture, model and sound is generated by a script.</p>
  <p>It was built for one family's children, and it is free for yours. Free to play, modify and share for
  anything noncommercial; commercial use needs a separate licence.
  <a href="https://github.com/quarrowen/quarrowen">github.com/quarrowen/quarrowen</a></p>
</section>

<footer>
  <p>Quarrowen is an independent project, not affiliated with, endorsed by or connected to Mojang
  Synergies AB, Microsoft or Roblox Corporation. Minecraft is a trademark of Mojang Synergies AB; Roblox
  is a trademark of Roblox Corporation.</p>
</footer>

</div>


EOF

echo
echo "release folder $out:"
find "$out" -maxdepth 2 -type f | sed 's/^/   /'
echo
echo "publish the contents of $out at $base_url"
echo "(index.html, update.json, mods.json and $files/), then tag the commit and attach the same zips."
