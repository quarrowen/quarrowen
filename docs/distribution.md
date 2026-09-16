# Getting the game (and mods) to players

How a build reaches a Mac, how it updates itself, and how mods are found, installed, configured and
chosen for a world. Written before alpha 2 so the first public release already works this way.

## 1. What a release publishes

`tools/make_release.sh` builds everything and writes the two files the game reads:

```
VoxelCraft-<version>-mac-arm64.zip     the app
mods/<id>-<version>.zip                one zip per mod (base, vanilla, arcana, industry, guild,
                                       skyblock, oneblock)
update.json                            {version, notes, builds: {macos: {url, sha256, size}}}
mods.json                              the mod index: [{id, version, url, sha256, size}]
```

Both JSON files carry a checksum for every download. Nothing is installed without matching it.

## 2. Where it is published: GitHub Pages

A plain static site, so a kid can open one page and press Download:

```
https://<org>.github.io/voxelcraft/
  index.html            what it is, Download for Mac, "first launch" instructions
  update.json           the updater's manifest (same file the release attaches)
  mods.json             the mod index
  v<version>/...        the zips
```

**The repository is public** (2026-09-16), so Pages and release assets both download without an
account - a private repository's release assets need a token, which a game cannot carry. The address is
baked into the client (`engine/client/updater.gd`), never taken from a server, and `project.godot`'s
`voxelcraft/update_manifest_url` can point a fork somewhere else.

`tools/publish_site.sh` pushes the page, `update.json` and `mods.json` to the `gh-pages` branch, and
with `--with-release` attaches the zips to the GitHub release (release assets do not count against the
repository size, which matters at ~62 MB per build). Without a release it serves the zips from the
branch instead.

## 3. Updating

The client checks the manifest when the menu opens (Settings → Network turns it off, Settings →
Account has a "Check for updates" button). When a newer version exists the menu banner offers it:
download → checksum → a small script waits for the game to quit, unpacks the zip, swaps the app,
clears the macOS quarantine flag and starts the new one. A failed swap puts the old app back.

Servers never hand the client a download address. A server can only say which protocol version it
needs; the client then offers the update from its own pinned source.

## 4. Mods: the problem

Today the app carries `base`, `vanilla` and the add-ons inside `VoxelCraft.app/Contents/Resources/mods`,
and a dedicated server keeps its own copy in `/mods`. That covers the bundled games, but not:

- a player wanting a mod that does not ship with the game,
- a host choosing which mods a *local* world runs beyond the bundled list,
- a mod needing settings (difficulty, rates, feature switches) without editing its code.

Joining a server never needs an install: mods run on the server, and clients already download the
textures, models and sounds they need. The mod list matters for **hosting**.

## 5. Mods: the plan (Factorio-style)

### 5.1 Where mods live

| Place | What it is |
|---|---|
| inside the app | the mods that ship with a release; refreshed on update |
| `user://mods/` | mods the player installed; survives updates, per computer |
| a server's `/mods` volume | what that server runs (already how the Docker image works) |

`ModLoader.search_dirs` already looks in all three, so nothing changes in the engine's loading.

### 5.2 The in-game mod list (menu → Create → Mods)

- **Installed**: everything found, with version, size, what it is, and Remove for ones in `user://mods`.
- **Available**: the entries from `mods.json` that are not installed (name, description, size, author),
  with Install: download → checksum → unzip into `user://mods/<id>/`.
- **Updates**: an installed mod with a newer version in the index gets an Update button.
- Dependencies come from each `mod.json` (`depends`, `optional_depends`) and are installed with it;
  the existing validator already reports a missing or out-of-range dependency clearly.

### 5.3 Choosing mods for a world

The New world dialog already picks a game (vanilla, skyblock, One Block) plus add-ons. It grows into:
the game list is every installed mod with `"game": true`, the add-on list every other installed mod, and
the choice is saved in `world.json` (it already is). Nothing changes for servers: their mod list stays
`VOXEL_MODS` in the compose file, and the same zips drop into their `/mods` folder.

### 5.4 Safety

A GDScript mod is code that runs on whoever hosts the world. So:

- the **curated index** (`mods.json` from our own site) is what the browser offers by default;
- installing from a file or another address is behind an "Advanced" toggle with a plain warning that a
  mod can do anything the game can;
- JavaScript mods stay sandboxed (they already are) - the natural home for community content;
- every download is checksummed against the index, and an installed mod records where it came from.

## 6. Mod settings

Mods need values a host can change without touching code (spawn rates, whether a feature is on, a
difficulty). The design mirrors the client's own settings, which are already schema-driven:

```gdscript
api.register_settings({
    "monster_rate": {"label": "How many monsters", "type": "float", "default": 1.0, "min": 0.0, "max": 3.0,
                     "help": "Multiplies how often monsters appear."},
    "keep_tools":   {"label": "Keep tools when you die", "type": "bool", "default": true},
    "difficulty":   {"label": "Difficulty", "type": "choice", "default": "normal",
                     "choices": [["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]]},
})

var rate: float = api.setting("monster_rate")      # read anywhere
api.on("settings_changed", func(ev): ...)          # react while the server runs
```

- **Values live with the world** (`world.json`, `mod_settings: {mod_id: {key: value}}`), so a world keeps
  its own rules and a backup restores them. Defaults come from the schema.
- **Admins change them in game**: the Server settings screen grows a section per mod, built from the
  schema exactly like the engine's own rules - no new UI work per mod.
- **Servers can set them without a UI**: `mod_settings.json` in the data dir (and `VOXEL_MOD_SETTINGS`
  for compose) is read at start; the file wins over the schema default, and a change in game wins over
  the file (and is saved).
- **Per-player client preferences** (a mod's HUD position, say) come later through the same schema on
  the client's settings screen; the server-side values are the piece that matters now.

## 7. Order of work

1. **Distribution** (before alpha 2): `make_release.sh`, the Pages site, the public distribution repo,
   the download page, and the updater pointed at it. Alpha 2 is then downloaded, not handed over.
2. **Mod settings**: schema, storage in the world, the Server settings section, the data-dir file.
3. **Mod list in game**: installed/available/updates from the index, install and remove, and the New
   world dialog listing installed mods.
4. **Community mods**: the advanced install path, and what a public index would need (submissions,
   review, a "verified" mark).
