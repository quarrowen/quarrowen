# The engine

> **The bundled games were removed on 21 September 2026** and will be rebuilt for 1.0 (see
> `docs/roadmap.md`). Examples below that name `vanilla`, `hearthhold`, `industry`, `arcana`, `guild`,
> `skyblock` or `oneblock` describe how things *were*, and still illustrate the capability correctly -
> but you cannot run them as written. The mod the tests use now is `tests/mods/proving`, which uses
> every capability the engine has and is the best worked example there is.

How Quarrowen is put together, for anyone working on the engine itself rather than on a mod. See also
[CLAUDE.md](https://github.com/quarrowen/quarrowen/blob/master/CLAUDE.md) at the repository root, which lists the things that are easy to get wrong.

## Running

Build the native extension once (`tools/build_native.sh`), then open the folder in Godot and press
Play. The main menu shows a live generated world with your avatar, a sidebar and one page at a time:

- **Play**: your worlds (title, game and add-ons, last played). **New world…** picks a name, game,
  add-ons and an optional seed (a word or number); Play hosts it on a local server and joins it.
  Rename, delete (with its backups) and open the folder; Developer mode turns on the dev tools.
- **Multiplayer**: join by address (`host`, `host:port`) or invite code (`QW-XXXXX-XXXXX-X` for an
  address, `QW-ABC-123` for a server listed on a hub). Tabs: **Browse** (public servers from the hub,
  with search), **LAN** (servers on your network and this computer), **Favorites** (add, edit, remove)
  and **Recent**. Every row shows the name, message, game, players, ping and a version warning; Copy
  invite prefers the hub code.
- **Friends** (with a hub): your friend code, adding friends by code, requests, friends online and the
  server they are on (Join), parties (invite friends, join the leader's server, make leader, remove,
  leave). Also in game from the pause menu (Join switches servers). Settings → Network decides whether
  friends see your server; a world you host is shared by your local network address.
- **Avatar** opens the avatar editor; **Create** has the mod wizard, your mods folder, the API docs and
  one-click dev hosting of any installed mod; **Settings** has identity export/import and the hosting
  port (graphics, audio and controls are coming).
- **What's new** on the right: the hub's news, or `engine/client/menu/news.json` without one.
- The **live world** behind the menu is generated in this process by an offline server: the avatar stands
  in a meadow with animals (and a zombie or two) wandering around it. The middle of the view appears in a
  second or two and the rest fills in behind the fade; `assets/icon.png` (drawn by `tools/generate_icon.py`)
  is the app icon.

In game, the pause menu has **Worlds…** (the servers this one is linked to, with a Travel button - the
same trip a portal makes) and, for admins, **Server settings…**. **Invite friends…** shows the server's invite code (for a hosted world, the
computer's local network address). Menus scale up on high-density screens. Code: `engine/client/menu/`.

```sh
# Dedicated server (mods are comma-separated; dependencies load automatically)
godot --headless --path . res://scenes/server.tscn -- --mods=proving --metrics=10
godot --headless --path . res://scenes/server.tscn -- --mods=proving --world=myworld --mods-dir=/srv/mods --admins=Robin

# Client straight into a server / host from the command line
godot --path . -- --connect=127.0.0.1 --name=Robin
godot --path . -- --host=proving --name=Robin
```

Worlds save to `user://worlds/<world>` (world.json keeps the title, mods, game, seed and play times), downloaded assets to `user://cache/assets` and the player's
identity key to `user://identity/`
(on macOS under `~/Library/Application Support/Godot/app_userdata/Quarrowen/`).

Blocks can fill less than their cell: a `shape` ("slab", "stairs_north"..., "fence") names the boxes it
fills, and the same boxes are what players and mobs walk into. Walkers step up to half a block on their
own, so slabs and stairs are climbed by walking into them.

**Controls:** WASD move, Space jump/swim (double-tap to fly in creative), Shift crouch (sinks while
flying), Ctrl sprint, M map (everyone on the server, your home and your grave), LMB break, RMB place / use a machine / use
the held item, C crafting, 1–9 / wheel slot, T chat and `/commands`, F3 debug, F4 graphics preset,
Esc menu. Every key can be changed in Settings.

**Settings** (main menu, or **Settings** in the pause menu; saved to `user://settings.cfg`, applied at
once; each tab has a reset button):

- **Graphics:** quality preset or Custom (3D resolution, corner shadows, swaying plants, fancy water,
  glow, colour grading, FXAA), field of view, window (windowed, maximized, fullscreen), V-Sync, frame
  rate limit, the live world behind the menu.
- **Audio:** master, world sounds and interface sounds (separate audio buses).
- **Controls:** mouse sensitivity, invert up/down, sprint key toggles, and two keys or mouse buttons for
  every action (conflicts are pointed out).
- **Accessibility:** interface size (on top of the automatic high-density scaling, for menus and the
  HUD alike), camera shake, flashes, relaxed minigame timing, a still menu camera.
- **Account** (menu): identity export/import and the hosting port.

The schema lives in `engine/client/settings/client_settings.gd`; the screen is built from it.

## Layout

```
engine/
  main.gd / server_main.gd  client menu / dedicated server entry points
  net/net.gd                autoload: ENet peer + every RPC
  shared/                   identical on both sides
    block_registry.gd       runtime block table (built from mods, replicated as data)
    player_physics.gd       deterministic movement; tunables come from the server
    world_time.gd           day/night curve
    identity.gd             Ed25519 identity keys, challenge signing, encrypted export
    entity_registry.gd      entity types (mobs, projectiles, dropped items); network subset for clients
    entity_physics.gd       gravity + AABB-vs-voxel collision for entities
    sound_registry.gd       named sounds made of downloadable audio assets
    player_rig.gd           the player body as data (parts, skin layout regions, attachment points)
    cosmetics.gd            cosmetic categories, built-in catalog, avatar data rules, server policy
    inventory.gd item_registry.gd chunk.gd voxel_world.gd voxel_raycast.gd protocol.gd native.gd
  server/
    game_server.gd          tick, content delivery, validation, events, chunk jobs, delta saves
    entities.gd entity.gd   entity simulation, AI, projectiles, item stacks, spawn rules, replication
    mod_loader.gd mod_api.gd server_player.gd mod.gd ore_pass.gd world_backups.gd
    js_mod.gd js/            JavaScript mod host, prelude and TypeScript declarations
  client/
    game_client.gd          download → build content → play; prediction, meshing, models, HUD
    chunk_mesher.gd         mesh jobs (native lit greedy mesher, GDScript fallback)
    voxel_material.gd       block shader: tiling across merged quads, sky/block light, daylight
    model_library.gd        glTF block models → MultiMesh-ready meshes
    entity_view.gd          interpolated, animated entity visuals
    sound_player.gd         voice pool for downloaded and built-in sounds (sounds/)
    inventory_screen.gd     36-slot inventory UI (server-authoritative clicks)
    avatar/                 player avatars: rig animation, skin compositing, look builder, held items,
                            first-person arm, avatar editor
    content_cache.gd texture_atlas.gd server_ui.gd remote_player.gd
native/                     Rust GDExtension (meshing + lighting, physics, snapshots, signals, JS)
mods/
  base/                     shared blocks, textures, block sounds, swords, apples (not a game)
  vanilla/                  generated terrain, creative/survival, day/night, zombies and pigs
  skyblock/                 per-player void islands, survival, generator block, challenges
  industry/                 power networks: generators, solar, cables, batteries, lamps, auto-miner
  arcana/                   mana: crystal ore generation pass, mana pool HUD, pylons, spell wands
  guild/                    JavaScript mod: quest boards, coins, shop, gold ore, meteors, leaderboard
tests/                      end-to-end, combat, auth, multiplayer, host flow, persistence, identity, gameplay, sandbox, benchmarks
tools/                      run_tests.sh, build_native.sh, export.sh, texture/sound/model generators
export_presets.cfg          macOS / Windows / Linux clients, Linux dedicated servers (x86_64, arm64)
.github/workflows/ci.yml    native builds, tests, exports and the server image
```

## How a join works

0. Connection: ENet traffic is encrypted with DTLS. Before any RPC, SceneMultiplayer's auth step
   exchanges versions: a client with a different protocol gets a readable "please update" message
   instead of mismatched RPCs. The server also sends its certificate, which the client pins
   (trust on first use, like SSH `known_hosts`, in `user://known_servers`); on later connections the
   DTLS handshake verifies the server against that pin, so an impostor cannot complete a connection.
1. `c_hello(protocol, name, public key)`: name checked against this server's claims.
2. `s_challenge(nonce)` / `c_auth(signature)`: the client proves it holds the private key.
3. `s_server_info(info, content, manifest)`: server name/game, block definitions, physics rules,
   and `[asset name, sha256, size]` for every asset (textures and models).
4. `c_request_assets(missing)`: the client asks only for hashes it has not cached. Pieces stream at a
   capped rate; each file is verified against its hash before it is cached. Assets shared between
   servers (for example, the `base` textures) download once.
5. The client builds its registry, texture atlas, materials and models, then sends `c_ready`.
6. `s_welcome`, `s_time`, `s_inventory`, chunks and snapshots follow; mod `player_join` handlers run.

**Why the client is safe to point at any server:** servers send data only: block definitions,
PNG and glTF files, numbers and UI trees made of a fixed set of element types (label, button,
progress, image, boxes). The client never executes server code, caps sizes and counts, and
validates every payload.

## World saves (delta model)

Chunks are always regenerated from the seed, then saved edits are applied on top.
`chunks/x_z.json` stores only blocks that differ from generated terrain (by block name, with a
palette) plus that chunk's block data. Untouched chunks are never written, an edit that restores
the generated block is dropped, and changing world generation or mods flows into existing worlds
(edits referring to blocks from removed mods fall back to the generated terrain). Saves are
serialized on the main thread and written by a worker, atomically via rename.

### Backups

Every `QW_BACKUP_INTERVAL` minutes (default 60; 0 turns it off; skipped while the world is idle)
the server flushes pending saves and zips the world on a worker thread into
`<data dir>/backups/<world>/<world>-<UTC timestamp>.zip`, keeping the newest `QW_BACKUP_KEEP` (24).
Admins can run `/backup` and `/backups`. To restore, start with `--restore=latest` (or a file name or
path, `QW_RESTORE`): the current world folder is moved aside to `<world>.before-restore-<time>`, never
deleted, and the archive is unpacked in its place.

## Identity and permissions

Every client has an Ed25519 key (`user://identity/default.key`, created on first launch). Its hash is
the player id: saved inventory, position and mod data follow the key, not the name. Each name belongs
to the first key that claims it on a server, so nobody can take over someone else's player by typing
their name. A private key is 32 bytes, which is what makes it small enough to write down.

A server has one of the same kind (`<data dir>/identity/server.id`), and its hash is the server id that
other servers put in their `network.json` and that a joining client's signature is bound to. It is
separate from the DTLS certificate beside it: the certificate is how the server is reached and can be
regenerated, the identity is who it is and cannot.

Admins come from `QW_ADMINS` (player ids from `/whoami`, or names), `/op <player>`, or the local
host via the token the menu's Host button passes to its server. Mods mark commands as admin-only
(`register_command(..., "admin")`, or `{ admin: true }` in JavaScript) or check `player.is_admin()`.
Built-in admin commands: `/op`, `/deop`, `/kick`, `/backup`, `/backups`; everyone has `/help`,
`/players`, `/whoami`.

**Moving your identity to another computer:** the key is your account, so it is exported encrypted
(PBKDF2-HMAC-SHA256 with 210k iterations, AES-256-CBC, HMAC-SHA256 over the ciphertext). Use the menu's
Export/Import identity buttons with a passphrase, or:

```sh
QW_IDENTITY_PASSPHRASE='...' Quarrowen -- --export-identity=my-identity.json
QW_IDENTITY_PASSPHRASE='...' Quarrowen -- --import-identity=my-identity.json   # old key kept as .bak
```

**Server identity:** each data dir holds `identity/server.key` and `server.crt` (self-signed, created
on first start). Keep them with the world (the Docker `/data` volume does): a server that loses them
looks like an impostor to returning players, who then have to delete the pin from `known_servers`.

## Native extension (Rust)

`native/` is a godot-rust (gdext 0.5, `api-4-7`) library. Each feature has a GDScript twin used
automatically when the library is missing; `QW_NATIVE=0` forces the fallbacks.

| Path | Native class | GDScript | Native |
|---|---|---|---|
| Chunk meshing | `NativeMesher` | 8.2 ms/chunk, per-face, approximate lighting (heightmap sky, unoccluded block light) | 1.1 ms/chunk with flood-fill light, smooth lighting, AO and greedy merging (2× fewer quads) |
| Player physics step | `NativeVoxelWorld.step_player` | 0.011 ms | 0.001 ms, identical results |
| Entity physics (500 bodies) | `NativeVoxelWorld.step_entities` | 2.3 ms/tick | 1.0 ms/tick, one batched call |
| Mob pathfinding, sight | `NativeVoxelWorld.find_path` / `line_of_sight` | 350-node budget | 1500-node budget, ~50 µs per path |
| Snapshots (100 clustered players) | `NativeSnapshots` | ~3.1 ms | 0.076 ms (spatial grid) |
| Signals | `NativeProcess` | hard kill | graceful save on SIGTERM/SIGINT |
| JavaScript mods | `NativeJsRuntime` | not available | QuickJS-NG, sandboxed |

```sh
tools/build_native.sh    # then open/import the project once to register it
```

## Graphics

Designed for integrated GPUs (baseline: base M1 MacBook Air). The shader-pack look is precomputed
into chunk meshes instead of being rendered per pixel:

- **Baked in the mesher:** flood-fill sky and block light, smooth lighting across block corners and
  ambient occlusion (per-vertex), plus flags for foliage, liquids and light sources.
- **Block shader:** one texture fetch; sway for leaves; water with analytic ripples, a Fresnel sky
  reflection and a sun glint; warm/cool sun tint through the day; emissive blocks feed bloom.
- **Post:** AgX tone mapping, a few low-resolution bloom mips, light colour grading; optional FXAA.
- **No** real-time shadow maps, SSAO, SSR or GI.

Presets (F4 or Settings, saved; `QW_GRAPHICS=fast|balanced|fancy`; changing a single option makes it Custom): `fast` renders at 70% with FSR and turns
off sway, fancy water and bloom; `balanced` (default) 85% with everything on; `fancy` native
resolution plus FXAA. At 2560x1600 on an M1 Max the balanced preset renders around 440 fps uncapped;
scaling by GPU core count suggests roughly 130 fps on a base M1 Air (not measured on that machine).

## Tests & tooling

`tools/run_tests.sh` starts the servers and runs everything below. Individually:

```sh
# End-to-end against a running server (--game names the bot; there is one game now)
godot --headless --path . res://scenes/server.tscn -- --mods=proving --port=24603 &
godot --headless --path . res://tests/smoke_test.tscn -- --port=24603 --game=proving
godot --headless --path . res://tests/auth_test.tscn -- --port=24603          # needs --admins=Admin; also version + pinning
godot --headless --path . res://tests/multiplayer_test.tscn -- --port=24603   # launches a 2nd client
godot --headless --path . res://tests/host_flow_test.tscn                     # menu Host flow

godot --headless --path . res://tests/persistence_test.tscn   # delta saves, block data, backups + restore
godot --headless --path . res://tests/identity_test.tscn      # encrypted identity export / import
godot --headless --path . res://tests/gameplay_test.tscn      # inventory, entities, damage, equipment, cosmetics
godot --headless --path . res://tests/ai_test.tscn            # mob AI in a flat arena (tests/mods/ai_arena)
godot --headless --path . res://tests/ai_soak.tscn -- --seconds=180 --sites=8   # mobs on real terrain: stuck, hops, chases
godot --headless --path . res://tests/js_sandbox_test.tscn    # JavaScript limits
godot --headless --path . res://tests/bench.tscn              # worldgen, meshing, snapshots, physics
godot --headless --path . res://tests/bots.tscn -- --port=24603 --bots=100
godot --path . res://tests/screenshot.tscn -- --port=24603 --commands="/proving|/time night"
godot --path . res://tests/screenshot.tscn -- --port=24603 --camera=2 --editor=hat   # avatar editor
```

**Load testing.** `bots.tscn` connects many lightweight clients from one process; start the server with
`--metrics=5 --anticheat=log` to print, every 5 seconds, players, mobs, chunks, ticks per second, the
average cost of each tick section (players, streaming, mob AI and spawning, snapshots, entity
replication, saving...), the slowest tick's top sections, the slowest mod task and bandwidth per player.
On an M-series Mac with 100 bots crowded together, ticks average 8–12 ms (under the 16.7 ms budget) and
bandwidth is about 20–25 KB/s per player. One bot process tops out at about 120–140 clients (its UDP
buffer overflows), so run several for more.

- **vanilla:** creative mode, movement prediction, edits.
- **skyblock:** survival inventory, modal UI buttons, generator regrowth, mod veto, void teleport.
- **industry:** model blocks, `/industry kit`, machine orientation, cable arms, machine panel,
  fuelling powers a lamp through cables, breaking the cable cuts power.
- **arcana:** replicated items, crystal generation pass, mana HUD, Wand of Blink and Wand of Light.
- **guild** (JavaScript): ore pass, quest board UI, quest progress from crafting, coin payout, shop,
  meteor event, leaderboard from mod storage.
- **skyblock** also chops a log and crafts planks in survival.
- **All games:** server rollback of an invalid edit.
- **auth:** permissions, name claims, key-bound saved data, tampered signatures.
- **multiplayer:** two client processes see each other join, move, build, chat and leave, and see each
  other's avatar cosmetics change.
- **host_flow:** Host launches a server, the host becomes admin, leaving stops the server.

## Builds and CI

```sh
tools/build_native.sh            # native library for this machine -> native/bin/<platform>/
tools/run_tests.sh               # full test suite (QW_NATIVE=0 for the GDScript fallbacks)
tools/export.sh                  # every preset -> build/ (needs Godot export templates)
tools/package_mods.sh            # every mod -> build/mods/<id>-<version>.zip (release downloads)
tools/make_release.sh            # app + mod zips + download page + update manifest -> build/release/
tools/generate_icon.py           # the app icon -> assets/icon.png and icon.icns
tools/export.sh "Linux Server arm64" macOS
```

Exports keep mods out of the `.pck` and copy `mods/` beside each build: the server streams the raw
PNG and glTF files to clients, which an export would otherwise convert. The engine searches configured
mod folders, then a `mods` folder next to the executable (or in a macOS app's `Resources`), then the
project's `res://mods`.

`.github/workflows/ci.yml` builds the native library for Linux x86_64/arm64, Windows and macOS
(universal), runs the full suite (native and fallback) on Linux, exports all presets, and pushes a
multi-arch server image to GitHub Container Registry on pushes to the default branch.
