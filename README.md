# VoxelCraft

A voxel game **engine** in Godot 4.7 (GDScript + Rust) with a Roblox-style universal client. The
server is authoritative and loads **mods** that define the game: blocks, 3D models, textures, world
generation, rules, machines, commands and UI. The client has no game content built in; it downloads
everything from whichever server it joins, so one client can play a sandbox, a skyblock server or a
tech-modded world.

## Running

Build the native extension once (`tools/build_native.sh`), then open the folder in Godot and press
Play. **Host game** starts a local server for the selected game
and joins it; **Join server** connects to an address.

```sh
# Dedicated server (mods are comma-separated; dependencies load automatically)
godot --headless --path . res://scenes/server.tscn -- --mods=vanilla,industry --metrics=10
godot --headless --path . res://scenes/server.tscn -- --mods=skyblock --world=myworld --mods-dir=/srv/mods --admins=Steve

# Client straight into a server / host from the command line
godot --path . -- --connect=127.0.0.1 --name=Steve
godot --path . -- --host=skyblock --name=Steve
```

Worlds save to `user://worlds/<world>`, downloaded assets to `user://cache/assets` and the player's
identity key to `user://identity/`
(on macOS under `~/Library/Application Support/Godot/app_userdata/VoxelCraft/`).

**Controls:** WASD move, Space jump/swim, Shift sprint, LMB break, RMB place / use a machine / use
the held item, C crafting, 1–9 / wheel slot, T chat and `/commands`, F3 debug, F4 graphics preset,
Esc menu.

## Layout

```
engine/
  main.gd / server_main.gd  client menu / dedicated server entry points
  net/net.gd                autoload: ENet peer + every RPC
  shared/                   identical on both sides
    block_registry.gd       runtime block table (built from mods, replicated as data)
    player_physics.gd       deterministic movement; tunables come from the server
    world_time.gd           day/night curve
    identity.gd             RSA identity keys, login challenge signing and verification
    inventory.gd item_registry.gd chunk.gd voxel_world.gd voxel_raycast.gd protocol.gd native.gd
  server/
    game_server.gd          tick, content delivery, validation, events, chunk jobs, delta saves
    mod_loader.gd mod_api.gd server_player.gd mod.gd ore_pass.gd
    js_mod.gd js/            JavaScript mod host, prelude and TypeScript declarations
  client/
    game_client.gd          download → build content → play; prediction, meshing, models, HUD
    chunk_mesher.gd         mesh jobs (native lit greedy mesher, GDScript fallback)
    voxel_material.gd       block shader: tiling across merged quads, sky/block light, daylight
    model_library.gd        glTF block models → MultiMesh-ready meshes
    content_cache.gd texture_atlas.gd server_ui.gd remote_player.gd
native/                     Rust GDExtension (meshing + lighting, physics, snapshots, signals, JS)
mods/
  base/                     shared blocks + textures (not a game)
  vanilla/                  generated terrain, creative building, day/night, /time
  skyblock/                 per-player void islands, survival, generator block, challenges
  industry/                 power networks: generators, solar, cables, batteries, lamps, auto-miner
  arcana/                   mana: crystal ore generation pass, mana pool HUD, pylons, spell wands
  guild/                    JavaScript mod: quest boards, coins, shop, gold ore, meteors, leaderboard
tests/                      end-to-end, auth, multiplayer, host flow, persistence, sandbox, benchmarks
tools/                      run_tests.sh, build_native.sh, export.sh, texture/model generators
export_presets.cfg          macOS / Windows / Linux clients, Linux dedicated servers (x86_64, arm64)
.github/workflows/ci.yml    native builds, tests, exports and the server image
```

## How a join works

1. `c_hello(protocol, name, public key)`: version checked, name checked against this server's claims.
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

## Writing a mod

Mods are GDScript (`main.gd`) or JavaScript (`main.js`); both use the same API and can depend on and
interoperate with each other.

### JavaScript mods

```js
// mods/my_mod/main.js   (mod.json: {"id": "my_mod", "depends": ["base"], "main": "main.js"})
export function setup(api) {
  const ruby = api.registerBlock("ruby_ore", { textures: "textures/ruby.png", light: 5 });
  api.addOrePass({ ore: "my_mod:ruby_ore", veins: 2, min_y: 5, max_y: 30 });
  api.on("block_broken", ({ player, block }) => {
    if (block === ruby) player.showTitle("Shiny!");
  });
  api.command("rubies", "Count your rubies", (player) => player.sendMessage(`${player.countOf(ruby)} rubies`));
}
```

- Runs in QuickJS-NG (ES2023: classes, modules, destructuring, `async`) embedded in the native
  extension. Types for editors/TypeScript: `engine/server/js/voxelcraft.d.ts`; API surface:
  `engine/server/js/prelude.js`.
- **Sandboxed:** only ECMAScript built-ins exist (no filesystem, network or process access), the heap
  is capped at 64 MB and each callback is interrupted after 200 ms. Script errors are logged and never
  crash the server (`tests/js_sandbox_test.tscn`).
- Values cross the boundary as JSON: positions are `{x, y, z}`, players are `Player` objects,
  `getBlockData` returns a copy (save with `setBlockData`). JavaScript can't run on world-generation
  threads, so JS mods use `addOrePass` for world generation.
- The example `mods/guild` uses models, items, recipes, an ore pass, server UI with a shop, saved
  per-player data and mod storage, cancellable events and drop rewriting, commands, timers and other
  mods' items.

### GDScript mods

```
mods/my_mod/mod.json   {"id": "my_mod", "name": "My Mod", "depends": ["base"], "game": false}
mods/my_mod/main.gd
```

```gdscript
extends "res://engine/server/mod.gd"

func setup(api) -> void:
	var crystal = api.register_block("crystal", {
		"model": "models/crystal.glb",          # 3D model block (bake with tools/bake_model.py)
		"textures": "textures/crystal_icon.png", # hotbar icon
		"light": 12, "interactive": true,
	})
	api.on("block_placed", func(ev):
		if ev.block == crystal:
			api.set_block_data(ev.position, {"charge": 0}))
	api.on("block_interact", func(ev):
		var data = api.get_block_data(ev.position)
		data.charge += 1                         # saved with the world
		ev.player.show_title("Charge %d" % data.charge, "", 1.5))
```

The API (`engine/server/mod_api.gd`, `server_player.gd`) covers:
- **Content:** `register_block` (cube textures, `render`, `light`, `interactive`, `model`,
  `orientation`, `connect_group` + `model_arm`, `drops`), `register_item` (`icon`, `usable`,
  `max_stack`), `register_recipe`, `register_asset`, `block("base:stone")`, `item("base:coal")`,
  `get_drops`, `is_solid`, `is_breakable`.
- **World:** `set_world_generator` and `add_generation_pass` (both run on worker threads),
  `set_spawn_handler`, `set_physics`
  (including `void_below`), `get_block` / `get_loaded_block` / `set_block` / `fill`, `surface_y`,
  `sees_sky`, `set_world_time` / `get_time_of_day` / `get_daylight`.
- **Block state:** `get_block_state`, `set_block(pos, id, keep_data, state)`, `facing_from_yaw`,
  `facing_direction`. Oriented blocks get a facing automatically when placed.
- **Block data (block entities):** `set_block_data` / `get_block_data` / `clear_block_data`,
  `find_block_data`. Saved with the world and removed when the block is broken or replaced.
- **Players:** `teleport`, `give` / `take` / `count_of`, `set_creative`, `set_hotbar`,
  `send_message`, `show_title`, `show_ui` / `hide_ui`, `data` (persisted), `kick`.
- **Events:** `player_join`, `player_leave`, `tick`, `block_break` (cancellable, editable drops),
  `block_broken`, `block_place` (cancellable), `block_placed`, `block_interact`, `item_use`,
  `item_crafted`, `chat` (cancellable), `ui_action`.
- **Other:** `register_command`, `after` / `every` / `cancel`, `storage` (persisted per mod),
  `broadcast`, `set_server_info`.

### Items and crafting

Every block is also an item (same id); `register_item` adds non-block items with ids from 65536. The
engine provides a crafting menu (C) listing every `register_recipe` recipe, greyed out when the player
lacks inputs. Drops may name items (`"drops": "base:coal"`). Right-clicking with a `usable` item fires
`item_use` with the target block, face normal and look direction.

### Example: the Industry mod

`--mods=vanilla,industry` (or add it to any game). `/industry kit` fills your hotbar,
`/industry demo` builds a powered showcase, `/time night` shows the lamps.

- **Coal generator** (burns coal ore / logs / planks, 40 FE/s) and **solar panel** (15 FE/s × daylight,
  needs open sky) produce energy.
- **Cables** and adjacent machines form networks, discovered by flood fill and cached until a
  network block changes.
- **Batteries** store surplus (20k FE); **lamps** draw 4 FE/s and switch to a light-emitting variant
  when powered; the **auto miner** spends 120 FE per block digging straight down and stores drops.
- Right-clicking a machine opens a live panel (energy bars, fuel, collected items, buttons).
- Machines are Kenney industrial models baked with `tools/bake_model.py`, rotated to face whoever
  placed them; runtime state lives in block data. Cables are box models (`tools/box_model.py`) whose
  arms connect to neighbouring cables and machines.
- Recipes for every machine; generators burn coal (mined from coal ore), logs or planks.

### Example: the Arcana mod

`--mods=vanilla,arcana`. A generation pass seeds glowing mana crystal ore into any world's stone;
mining it gives mana shards. Players have a mana pool in a HUD panel that regenerates, quickly near a
Mana Pylon. Usable items: shards restore mana, the Wand of Blink teleports you up to 8 blocks, the
Wand of Light conjures a temporary light orb. Craft wands and pylons with C, or `/arcana kit`.

## World saves (delta model)

Chunks are always regenerated from the seed, then saved edits are applied on top.
`chunks/x_z.json` stores only blocks that differ from generated terrain (by block name, with a
palette) plus that chunk's block data. Untouched chunks are never written, an edit that restores
the generated block is dropped, and changing world generation or mods flows into existing worlds
(edits referring to blocks from removed mods fall back to the generated terrain). Saves are
serialized on the main thread and written by a worker, atomically via rename.

## Identity and permissions

Every client has an RSA key (`user://identity/default.pem`, created on first launch). Its hash is the
player id: saved inventory, position and mod data follow the key, not the name. Each name belongs to
the first key that claims it on a server, so nobody can take over someone else's player by typing
their name.

Admins come from `VOXEL_ADMINS` (player ids from `/whoami`, or names), `/op <player>`, or the local
host via the token the menu's Host button passes to its server. Mods mark commands as admin-only
(`register_command(..., "admin")`, or `{ admin: true }` in JavaScript) or check `player.is_admin()`.
Built-in admin commands: `/op`, `/deop`, `/kick`; everyone has `/help`, `/players`, `/whoami`.

## Dedicated server & Docker

`scenes/server.tscn` (`engine/server_main.gd`) loads no client code. Every option is a CLI arg or an
environment variable: `VOXEL_PORT`, `VOXEL_MODS`, `VOXEL_MODS_DIR`, `VOXEL_DATA_DIR`, `VOXEL_WORLD`,
`VOXEL_SEED`, `VOXEL_MAX_PLAYERS`, `VOXEL_METRICS`, `VOXEL_ADMINS`, `VOXEL_ADMIN_TOKEN`.

```sh
docker build -t voxelcraft-server .
docker run -p 24565:24565/udp -v voxel-data:/data -e VOXEL_MODS=vanilla,industry voxelcraft-server
docker compose up        # vanilla on 24565, skyblock on 24566
```

The image compiles the Rust extension for the target architecture, exports the "Linux Server" preset
and ships only the exported server (about 250 MB). Mods are plain files beside the binary
(`/opt/voxelcraft/mods`); mount extra or overriding mods at `/mods`; worlds live in the `/data`
volume. SIGTERM and SIGINT trigger a save before exit, so `docker stop` is safe.

## Builds and CI

```sh
tools/build_native.sh            # native library for this machine -> native/bin/<platform>/
tools/run_tests.sh               # full test suite (VOXEL_NATIVE=0 for the GDScript fallbacks)
tools/export.sh                  # every preset -> build/ (needs Godot export templates)
tools/export.sh "Linux Server arm64" macOS
```

Exports keep mods out of the `.pck` and copy `mods/` beside each build: the server streams the raw
PNG and glTF files to clients, which an export would otherwise convert. The engine searches configured
mod folders, then a `mods` folder next to the executable (or in a macOS app's `Resources`), then the
project's `res://mods`.

`.github/workflows/ci.yml` builds the native library for Linux x86_64/arm64, Windows and macOS
(universal), runs the full suite (native and fallback) on Linux, exports all presets, and pushes a
multi-arch server image to GitHub Container Registry on pushes to the default branch.

## Graphics

Designed for integrated GPUs (baseline: base M1 MacBook Air). The shader-pack look is precomputed
into chunk meshes instead of being rendered per pixel:

- **Baked in the mesher:** flood-fill sky and block light, smooth lighting across block corners and
  ambient occlusion (per-vertex), plus flags for foliage, liquids and light sources.
- **Block shader:** one texture fetch; sway for leaves; water with analytic ripples, a Fresnel sky
  reflection and a sun glint; warm/cool sun tint through the day; emissive blocks feed bloom.
- **Post:** AgX tone mapping, a few low-resolution bloom mips, light colour grading; optional FXAA.
- **No** real-time shadow maps, SSAO, SSR or GI.

Presets (F4, saved; `VOXEL_GRAPHICS=fast|balanced|fancy`): `fast` renders at 70% with FSR and turns
off sway, fancy water and bloom; `balanced` (default) 85% with everything on; `fancy` native
resolution plus FXAA. At 2560x1600 on an M1 Max the balanced preset renders around 440 fps uncapped;
scaling by GPU core count suggests roughly 130 fps on a base M1 Air (not measured on that machine).

## Native extension (Rust)

`native/` is a godot-rust (gdext 0.5, `api-4-7`) library. Each feature has a GDScript twin used
automatically when the library is missing; `VOXEL_NATIVE=0` forces the fallbacks.

| Path | Native class | GDScript | Native |
|---|---|---|---|
| Chunk meshing | `NativeMesher` | 8.2 ms/chunk, per-face, approximate lighting (heightmap sky, unoccluded block light) | 1.1 ms/chunk with flood-fill light, smooth lighting, AO and greedy merging (2× fewer quads) |
| Player physics step | `NativeVoxelWorld.step_player` | 0.011 ms | 0.001 ms, identical results |
| Snapshots (100 clustered players) | `NativeSnapshots` | ~3.1 ms | 0.076 ms (spatial grid) |
| Signals | `NativeProcess` | hard kill | graceful save on SIGTERM/SIGINT |
| JavaScript mods | `NativeJsRuntime` | not available | QuickJS-NG, sandboxed |

```sh
tools/build_native.sh    # then open/import the project once to register it
```

## Tests & tooling

`tools/run_tests.sh` starts the servers and runs everything below. Individually:

```sh
# End-to-end against a running server (--game = vanilla | skyblock | industry | arcana | guild)
godot --headless --path . res://scenes/server.tscn -- --mods=vanilla,industry --port=24603 &
godot --headless --path . res://tests/smoke_test.tscn -- --port=24603 --game=industry
godot --headless --path . res://tests/auth_test.tscn -- --port=24603          # needs --admins=Admin
godot --headless --path . res://tests/multiplayer_test.tscn -- --port=24603   # launches a 2nd client
godot --headless --path . res://tests/host_flow_test.tscn                     # menu Host flow

godot --headless --path . res://tests/persistence_test.tscn   # delta saves + block data
godot --headless --path . res://tests/js_sandbox_test.tscn    # JavaScript limits
godot --headless --path . res://tests/bench.tscn              # worldgen, meshing, snapshots, physics
godot --headless --path . res://tests/bots.tscn -- --port=24603 --bots=100
godot --path . res://tests/screenshot.tscn -- --port=24603 --commands="/industry demo|/time night"
```

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
- **multiplayer:** two client processes see each other join, move, build, chat and leave.
- **host_flow:** Host launches a server, the host becomes admin, leaving stops the server.
