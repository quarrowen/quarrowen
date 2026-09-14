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
  per-player data and mod storage, cancellable events and drop rewriting, commands, timers, other
  mods' items, sounds, a monster-hunting quest (`entity_death`) and `/guild bounty`, which spawns a
  zombie carrying entity data worth 5 coins.

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
- **Players:** `teleport`, `give` / `take` / `count_of` / `drop`, `set_creative`, `set_hotbar`,
  `send_message`, `show_title`, `show_ui` / `hide_ui`, `data` (persisted), `kick`, `health` /
  `max_health` / `damage` / `heal` / `set_health` / `kill`, `spawn_point`, `push`, `play_sound`.
- **Entities, combat & sound:** `register_entity`, `spawn_entity`, `spawn_projectile`, `drop_item`,
  `get_entities`, `add_spawn_rule`, `register_sound`, `play_sound`, `set_gameplay` (see below).
- **Events:** `player_join`, `player_leave`, `tick`, `block_break` (cancellable, editable drops),
  `block_broken`, `block_place` (cancellable), `block_placed`, `block_interact`, `item_use`,
  `item_crafted`, `chat` (cancellable), `ui_action`, `item_drop`, `item_pickup`, `player_attack`,
  `player_damage`, `player_death`, `player_respawn`, `entity_spawned`, `entity_removed`,
  `entity_damage`, `entity_death`, `entity_interact`, `entity_natural_spawn`, `projectile_hit`
  (most cancellable or editable; see the header of `mod_api.gd`).
- **Other:** `register_command`, `after` / `every` / `cancel`, `storage` (persisted per mod),
  `broadcast`, `set_server_info`.

### Items and crafting

Every block is also an item (same id); `register_item` adds non-block items with ids from 65536. The
engine provides a crafting menu (C) listing every `register_recipe` recipe, greyed out when the player
lacks inputs. Drops may name items (`"drops": "base:coal"`). Right-clicking with a `usable` item fires
`item_use` with the target block, face normal and look direction.

### Tools, weapons, armor and progression

The engine supplies the pieces: item definitions with tool, weapon and armor stats, per-item data,
equipment slots, a stat system with modifiers, timed mining with tiers, durability, and events. How
items progress (experience, kills, upgrades, sockets) is entirely up to mods.

```gdscript
api.register_item("ruby_pickaxe", {
	"icon": "textures/ruby_pickaxe.png", "durability": 900,
	"tool": {"type": "pickaxe", "tier": 4, "speed": 9},       # breaks blocks up to tier 4, 9x faster
	"weapon": {"damage": 4, "cooldown": 0.5},
	"modifiers": [{"stat": "move_speed", "amount": 0.05, "op": "multiply"}],   # while held
})
api.register_item("ruby_helmet", {"equip_slot": "head", "durability": 400, "armor": {"armor": 3, "toughness": 2}})
api.register_block("ruby_ore", {"textures": "textures/ruby_ore.png", "hardness": 4, "tier": 3, "tool": "pickaxe"})
api.register_equipment_slot("ring", {"display_name": "Ring"})
api.register_stat("mana_regen", 1.0)

# Progression is just item data + events: this sword levels up with kills.
api.on("entity_death", func(ev):
	var p = ev.attacker
	if p == null or p.get("peer_id") == null or p.get_item(p.selected_slot).item != api.item("my_mod:blade"):
		return
	var data: Dictionary = p.get_item(p.selected_slot).data.duplicate(true)
	data.kills = int(data.get("kills", 0)) + 1
	data.name = "Blade +%d" % (data.kills / 10)
	data.lore = ["%d kills" % data.kills]
	data.modifiers = [{"stat": "attack_damage", "amount": data.kills / 10}]
	p.set_item_data(p.selected_slot, data))
```

- **Mining:** blocks have `hardness` (seconds by hand is about hardness x 1.5), a `tier` needed for
  drops and an effective `tool` type; tools have `type`, `tier` and `speed`. Survival players hold the
  button while a crack animation plays (others nearby see it too); the server checks the time before
  accepting the break, and a tool that is too weak mines slowly and yields nothing. Creative is instant.
- **Item data:** every stack can carry a Dictionary (`get_item`, `set_item_data`, `give(item, count,
  data)`). The engine reads `damage` (wear), `name`, `lore` and `modifiers`; mods keep anything else
  there (xp, level, sockets, owner). Stacks only merge when their data matches; data survives drops,
  deaths and saves.
- **Equipment:** head, chest, legs, feet and offhand slots plus any a mod registers, shown beside the
  inventory. Shift-click or right-click wears armor.
- **Stats:** `max_health`, `armor`, `toughness`, `attack_damage`, `attack_cooldown`, `reach`,
  `crit_chance`, `crit_multiplier`, `knockback`, `knockback_resistance`, `mining_speed`, `move_speed`,
  and mod stats from `register_stat`. They come from worn items, the held tool or weapon, modifiers in
  item data and timed modifiers (`player.add_modifier(id, stat, amount, op, seconds)`), and the
  `player_stats` event can adjust the result. Armor reduces attack, mob and projectile damage;
  `move_speed` changes that player's physics (predicted on the client).
- **Combat:** weapon damage and cooldown, jump-attack criticals, `crit_chance`, sweeps that hit mobs
  around the target, and knockback.
- **Durability** (on by default; `set_gameplay({"durability": false})` turns it off): tools wear when
  mining, weapons when hitting, armor when hit; `item_durability` can change or cancel wear and
  `item_break` fires when an item wears out. Hotbar and inventory slots show a wear bar; tooltips list
  stats, durability and lore.
- **Bundled:** wooden, stone and iron pickaxes, axes, shovels and swords, iron armor (base), leather
  armor from pigs (vanilla), the Soul Blade that levels with kills (Arcana, GDScript) and the
  Prospector's Pick that mines faster as it gains experience (Guild, JavaScript).

### Blocks over time, light and plants

Blocks can change on their own: crops grow, farmland dries, saplings become trees. Mods register a
tick handler per block type; the engine only visits blocks of those types, and when a chunk comes back
after being unloaded each block gets the ticks it missed in one call, so farms keep growing while
nobody is near. Scheduled ticks run once at a set time and survive restarts.

```gdscript
api.register_block_tick("my_mod:mushroom", func(ctx):
	# ctx: position, block, state, ticks (> 1 when catching up), reason ("random" | "scheduled"), payload
	if api.get_light(ctx.position) < 8:
		api.set_block(ctx.position, api.block("my_mod:big_mushroom")),
	{"interval": 60})                                       # about once a minute per block
api.schedule_block_tick(position, 5.0, {"fuse": true})    # the block's handler runs in 5 s
api.register_block("my_mod:mushroom", {"textures": "textures/mushroom.png", "render": "plant",
	"support": ["base:dirt", "base:grass"]})               # breaks when its support goes
```

- `api.get_light(pos)` (0-15, block light or daylight-scaled sky light) and `get_light_levels(pos)`
  estimate light on the server from column heights and nearby light sources.
- Block keys: `render: "plant"` (two crossed quads), `support` ("solid" or block names it must stand
  on; it cannot be placed elsewhere and pops off as items when that block goes), `replaceable`
  (placing a block there replaces it, like tall grass). `api.break_block(pos)` breaks a block
  without a player and fires `block_destroyed` (drops may be changed).
- **Bundled farming (base):** hoes till grass or dirt into farmland; wheat seeds (from tall grass)
  grow through four stages with light, twice as fast on farmland near water; ripe wheat makes bread;
  farmland dries back to dirt when bare and dry; saplings (from leaves) grow into trees. Vanilla
  terrain grows tall grass and flowers.

### Containers, crafting stations and smelting

Container blocks (chests, furnaces, machines) keep their slots in block data, so contents are saved
with the world and spill out when the block breaks. Right-clicking one opens it beside the inventory
with the usual click rules; shift-click moves stacks between the container and the backpack, and
everyone viewing sees changes live.

```gdscript
api.register_container("kiln", {"title": "Kiln", "groups": [
	{"name": "input", "count": 2, "label": "Clay"},
	{"name": "fuel", "count": 1, "label": "Fuel", "accepts": "fuel"},        # or [item names] / Callable
	{"name": "output", "count": 2, "label": "Pots", "take_only": true}],   # players can only take
	"progress": [{"name": "fire", "label": "Firing", "color": "#ff8a3c"}]})
api.register_block("kiln", {"textures": "textures/kiln.png", "container": "kiln"})
api.on("container_changed", func(ev):                  # a player moved items in or out
	var c = ev.container                               # get_item, set_item, add, take, group, state
	c.set_progress("fire", 0.5))
api.register_block("anvil", {"textures": "textures/anvil.png", "station": "anvil"})
api.register_recipe({"base:iron_ingot": 3}, "my_mod:blade", 1, {"station": "anvil"})
api.register_process("firing", "my_mod:clay", "my_mod:pot", 1, 12.0)   # api.get_process("firing", id)
api.set_fuel("my_mod:peat", 40.0)                                        # api.get_fuel(id)
```

- **Crafting screen:** C (or right-clicking a station) opens a recipe book with search, category tabs,
  a craftable filter, what you have and still need (including items in chests within 4 blocks of a
  station, which crafting draws from), stats compared with what you hold or wear, Craft / Craft all and
  Pin (a HUD tracker that updates as you gather). R / U over any item opens how it is made / what it
  is used in; ingredients link to their own recipes. `register_recipe(..., {station, category, id})`,
  `register_recipe_category(name, {display_name, icon})`, event `item_crafted {player, item, count, recipe}`.
- **Stations:** blocks with `station: "<name>"` unlock recipes that need that station (plus the ones
  crafted anywhere). Creative players craft everything anywhere.
- **Discovery:** with the `recipe_discovery` gameplay rule (on by default) players learn recipes. Each
  recipe's `unlock` is "known" (from the start), "pickup" (default: the first time you hold one of its
  ingredients), "blueprint" (items with `teaches: [recipe ids]`, or any item whose data carries
  `teaches`, teach it when used), "experiment" (the crafting grid) or "secret" (hidden until taught).
  The recipe book counts "Discovered 28 / 51", shows undiscovered recipes as silhouettes with how to
  find them and an optional `hint`, and bookshelves around a station reveal an ingredient, then all of
  them, then the result. New recipes pop a toast. `player.learn_recipe(id)`, `player.knows_recipe(id)`,
  event `recipe_learned {player, recipe, source}`. Creative players know everything. Bundled: forge
  plans (skeletons, Guild shop) teach the forge and anvil, workbench plans (zombies, shop) the
  reinforced frame. (Clients receive every recipe so the book works offline of the server; a modified
  client could read undiscovered ones.)
- **Experimentation grid:** the crafting screen's Experiment tab has a 3x3 grid. Players arrange items
  they hold (nothing is used up) and Try: a recipe with exactly those ingredients (and, for recipes
  with a `pattern`, that arrangement, shifted or mirrored) is discovered if its unlock is "experiment"
  or "pickup", can be crafted right away if known, and blueprint recipes say plans are needed. Near
  misses hint: wrong arrangement, amounts off, something missing (bookshelves name it), something
  extra. Experiments are rate-limited and need the items in hand. Shaped recipes:
  `register_recipe({}, "base:torch", 4, {"pattern": ["C", "S"], "key": {"C": "base:coal", "S": "base:stick"}, "unlock": "experiment"})`.
  Bundled: torches (coal or charcoal over a stick) and hay bales (a grid of wheat).
- **Tools from parts:** alongside the fixed tools, a Tool Forge makes parts (pickaxe/axe/shovel heads,
  sword blades, handles, grips, bindings, guards) from any registered material and assembles them in
  the crafting screen's Assemble tab. The head decides tier, mining speed and damage, the handle's
  material scales durability, and every material adds its trait (stat modifiers, durability, speed,
  damage, glow). The result is the tool item with item data (`tool`, `weapon`, `durability`,
  `modifiers`, `icon_layers`, lore), and its icon and held model are composed from the part sprites
  tinted by material. Part recipes are generated for every material × part type. Bundled materials:
  wood, stone, iron (base), bone (vanilla), gold coins (guild, JS) and mana shards (arcana, glows).

```gdscript
api.register_material("iron", {"item": "base:iron_ingot", "color": "#dcdce2", "tier": 3, "speed": 6.0, "durability": 250,
	"damage": 2.0, "handle": 1.2, "trait": {"name": "Balanced", "description": "+10% mining speed", "speed_mult": 0.1}})
api.register_part_type("pickaxe_head", {"sprite": "textures/parts/pickaxe_head.png", "cost": 3, "station": "tool_forge"})
api.register_assembly("forged_pickaxe", {"display_name": "Pickaxe", "tool_type": "pickaxe", "damage": 2.0, "station": "tool_forge",
	"slots": [{"name": "head", "part": "pickaxe_head"}, {"name": "handle", "part": "tool_handle"}, {"name": "binding", "part": "binding"}]})
```

  Any item's data can override its definition's `tool`, `weapon` and `durability`.
- **Upgradable stations:** `register_station(name, def)` adds tiers (blocks upgraded in place with a kit
  item), workshop upgrades (blocks within a radius grant features, tier, speed, quality, chest reach,
  hints) and multiblock structures (a pattern around a core block, any rotation). Recipes ask for
  `tier` and `needs` (features). The station screen shows the tier, which workshop blocks were found
  and what the missing ones would add, the next tier's kit with an Upgrade button, and structure
  status with a build guide that shows ghost blocks where pieces go.

```gdscript
api.register_station("crafting_table", {
	"tiers": [{"block": "base:crafting_table"}, {"block": "base:sturdy_workbench", "kit": "base:reinforced_frame"}],
	"workshop": {"radius": 4, "upgrades": [{"block": "base:anvil", "grants": {"features": ["metalwork"], "quality": 0.1}}]}})
api.register_station("forge", {"grants": {"features": ["forging"]},
	"multiblock": {"core": "base:forge", "legend": {"B": "base:brick"}, "pattern": ["BCB", "BBB", " B "]}})
api.register_recipe({"base:iron_ingot": 8}, "base:iron_chestplate", 1, {"station": "crafting_table", "tier": 2, "needs": ["metalwork"]})
```

- **Co-op crafting:** everyone at a station shares a session: the screen lists who is there and which
  recipe each looks at, a 9-slot shared tray (stacks remember who put them in; you take back your
  own, the station's owner and their `player.team` take anything; gameplay rule `tray_access` =
  "anyone" opens it up) that crafting there can draw from, and a job queue. Recipes with `time` are
  crafted in the queue while players are present; each extra player adds 50% speed (up to 2.5x) on top
  of the station's workshop speed. Recipes with `project: true` are built together: anyone contributes
  ingredients over time, progress floats above the station for everyone nearby, and
  `project_completed {position, recipe, item, contributors}` lets mods reward who helped (the Guild
  Banner pays coins back to its contributors). Events: `craft_job_started`, `craft_job_finished`,
  `project_contributed`, `project_completed`.
- **Bundled progression (base):** crafting table → furnace → iron ingots → bricks → Forge (a brick
  structure) → anvil and reinforced frame. An anvil next to the table unlocks iron tools; the
  reinforced frame upgrades the table to a Sturdy Workbench for iron armor; tool racks speed crafting
  and reach chests further away; bookshelves will power recipe hints.
- **Bundled (base):** crafting table (tools, weapons, armor, hoes, chests and furnaces need one), chest
  (27 slots) and furnace. The furnace smelts ore into ingots, sand into glass, cobblestone into stone,
  logs into charcoal and (vanilla) raw into cooked porkchops; it glows while burning and keeps
  smelting while nobody watches, catching up after its chunk was unloaded. Coal, charcoal, wood and
  wooden tools are fuel.

### Effects: glows, trails and particles

Effects are data the server names and clients draw, so mods never ship client code. An effect mixes
particle emitters, a light flash, camera shake and a sound (see `engine/shared/effect_registry.gd`).
Built in: `engine:hit`, `engine:crit`, `engine:smoke`, `engine:sparkle`, `engine:magic`, `engine:heal`,
`engine:dust`, `engine:explosion`.

```gdscript
api.register_effect("frost_burst", {
	"emitters": [{"amount": 30, "lifetime": 0.8, "speed": [1, 4], "spread": 180, "gravity": 2, "drag": 2,
		"size": [0.15, 0.0], "colors": ["#ffffff", "#80d0ff", "#2060ff00"], "texture": "star"}],
	"light": {"color": "#80d0ff", "energy": 3, "range": 6, "seconds": 0.4},
	"shake": {"strength": 0.3, "seconds": 0.3, "radius": 8}})
api.play_effect("frost_burst", position, {"scale": 1.5, "follow": entity})

api.register_item("frost_blade", {"icon": "textures/frost_blade.png", "weapon": {"damage": 7},
	"glow": {"color": "#80d0ff", "energy": 0.8, "light": 3},        # emissive, lights its surroundings
	"trail": {"color": "#80d0ffa0", "seconds": 0.25},                 # ribbon while swinging
	"effects": {"hit": "frost_burst", "held": "engine:sparkle"}})     # swing, hit, use, held, break
```

- **Items:** `glow` (held items; armor lights up its texture), `trail`, and `effects` played on swing,
  hit (at the target; default `engine:hit`), use, while held and when the item breaks. Item data can
  override `glow`, `trail` and `effects` per stack, so progression can change looks (the Soul Blade glows
  brighter each level and trails wisps at level 4).
- **Mob attacks:** `windup_effect` (follows the mob while it telegraphs) and `effect` (when the attack
  lands); the Colossus stomp raises dust and shakes the camera.
- **Engine:** critical hits sparkle, broken blocks scatter debris from their texture, and the "fast"
  graphics preset halves particle counts.
- **Bundled:** Arcana blink, cast, spark impacts, Soul Blade glow/trail/aura and a glowing Crystal Helmet;
  Guild gold bursts, a shimmering levelled pick, quest sparkles and meteor explosions; iron swords trail.

### Avatars and cosmetics

Players are drawn with a rig of 10 boxes (head, torso, upper and lower arms and legs) textured in the
standard 64x64 Minecraft skin layout, animated procedurally (walking, running, jumping, swinging,
looking, getting hurt). Held items and worn armor show on everyone's avatar, F5 cycles first person,
behind and in front, and first person shows your arm and held item. Servers can replace the rig with
`api.set_player_rig(def)` (see `engine/shared/player_rig.gd`); outfits keep working because they are
drawn in layout regions, not per part.

A player's look is plain data: skin color (or per-part body colors) and one cosmetic per category
(face, pants, shoes, shirt, jacket, hair, hat, glasses, back). Esc > **Customize avatar** (or the main
menu) opens the editor with a turning preview.

- **Portable look:** built-in cosmetics are part of the engine; your choices are saved on your
  computer and appear on every server that allows them.
- **Server cosmetics:** mods register their own, free for everyone or granted to players (quest
  rewards, shops, ranks). Ownership and picks are saved per player with the world.
- **Armor or cosmetics:** a cosmetic that covers an armor slot (hats cover the head) shows instead of
  that armor piece; each player can choose per slot to show their armor instead.
- **Server control:** `set_cosmetics_policy` can disallow built-in cosmetics or recoloring, force armor
  or cosmetics to show, block categories or items, and dress everyone in a uniform;
  `player.set_avatar_override` and the `avatar_change` event change individual looks (teams, disguises).

Cosmetics are data, so they need no art tools: `paint` fills areas of the skin layout, `pixels` draws a
face, `boxes` builds a voxel accessory at the category's attachment point, or use a `texture` (64x64
layer) or glTF `model`.

```gdscript
api.register_cosmetic("pirate_hat", {"category": "hat", "color": "#2a2a2a", "unlocked": false,
	"boxes": [{"from": [-6, 0, -4], "size": [12, 2, 8]}, {"from": [-4, 2, -3], "size": [8, 3, 6]},
		{"from": [-1, 3, -3.2], "size": [2, 2, 0.3], "color": "#f0f0f0"}]})
api.register_cosmetic("sash", {"category": "jacket", "color": "#b03030",
	"paint": [{"region": "torso_overlay", "rows": [4, 6], "sides": ["front", "back", "left", "right"]}]})
api.set_cosmetics_policy({"armor": "player", "blocked": ["back"]})
player.grant_cosmetic("my_mod:pirate_hat")
player.set_avatar_override({"wear": {"shirt": {"id": "builtin:tshirt", "color": "#4a78d0"}}})   # blue team
```

Bundled: the Mage robe and the Archmage hat for a level 3 Soul Blade (Arcana, GDScript) and the Guild
cape for three completed quests (Guild, JavaScript). Uploading your own skins and 3D clothing is not
supported yet.

### Entities, combat, inventory and sound

```gdscript
api.register_sound("growl", ["sounds/growl1.ogg", "sounds/growl2.ogg"], {"range": 20})
api.register_entity("wolf", {
	"model": "models/wolf.glb",        # parts named leg_a*, leg_b*, arm_a*, arm_b*, head animate
	"width": 0.6, "height": 0.85, "health": 12, "speed": 4.0,
	"ai": {"preset": "hostile", "aggression": 0.8, "group": "wolves",   # see "Mob AI" below
		"attacks": [{"name": "bite", "type": "melee", "damage": 3, "windup": 0.3}]},
	"drops": [["base:coal", 1, 0.5]],  # [item, count, chance]
	"sounds": {"hurt": "growl", "ambient": "growl"},
	"persistent": false,              # true: saved with its chunk (animals); false: despawns far from players
})
api.add_spawn_rule({"entity": "wolf", "time": "night", "on": ["base:grass", "base:snow"], "max_nearby": 3})
api.register_item("club", {"icon": "textures/club.png", "max_stack": 1, "attack_damage": 6})
api.on("entity_death", func(ev):
	if ev.attacker != null and ev.entity.type_name == "my_mod:wolf":
		ev.attacker.send_message("You defeated a wolf"))
```

- **Entities** are simulated only on the server: gravity and voxel collision (batched in native code),
  engine mob AI (next section), knockback, hurt cooldowns and death drops. Projectiles
  (`kind: "projectile"`, e.g. Arcana's Wand of Sparks) sweep against blocks, mobs and players each
  tick and fire `projectile_hit`. Dropped item stacks (the built-in `engine:item`) are pulled toward
  nearby players, merge with neighbours and despawn after 5 minutes.
- **Replication:** each player receives spawn/despawn messages for entities within 64 blocks and
  compact unreliable position updates only for entities that moved (resting items and idle mobs
  cost nothing). Clients interpolate like remote players and animate model parts procedurally.
- **Health:** players have 20 health, shown as hearts in survival. Damage comes from mobs, projectiles,
  falls (landing speed, so low-gravity worlds hurt less), the void and mods; health regenerates after
  a few seconds without damage. Death shows a respawn screen and optionally drops the inventory.
  Left-click attacks the mob or player under the crosshair (server-checked reach, line of sight and
  cooldown; damage from the held item's `attack_damage`).
- **Gameplay rules** (`set_gameplay`, or `/gameplay rule value`): `item_drops` ("entity" or
  "inventory"; Skyblock uses inventory so drops don't fall into the void), `keep_inventory`, `pvp`,
  `fall_damage`, `natural_regeneration`, `mob_spawning`.
- **Inventory:** 36 slots. E opens the inventory screen (left click moves stacks, right click
  splits or places one, shift-click moves between hotbar and inventory, clicking outside drops); Q
  drops the held item (Ctrl+Q the whole stack). All clicks are resolved on the server.
- **Sound:** mods ship `.ogg` or `.wav` files that stream to clients like textures. Blocks name
  `sounds` for break, place and footsteps (the client plays its own actions immediately; the server
  sends them to everyone else nearby). A pool of 16 spatial voices keeps audio cheap; the pause menu
  has a volume slider. Engine sounds (hurt, pickup, swing) are built into the client.
  `tools/generate_sounds.py` synthesizes the bundled placeholder effects.
- **Admin commands:** `/give`, `/tp`, `/summon`, `/heal`, `/gamemode`, `/gameplay`; everyone has
  `/kill`. The vanilla game lets anyone use `/gamemode survival|creative`; at night zombies spawn
  (and burn at sunrise), pigs graze by day, and leaves sometimes drop apples.

### Mob AI

Mob AI is an engine capability; mods pick a preset and tune anything, per type or per mob.

```gdscript
api.register_entity("colossus", {
	"model": "models/colossus.glb", "width": 1.2, "height": 7.2, "health": 400, "speed": 2.4,
	"ai": {
		"preset": "boss",                      # hostile | neutral | passive | archer | boss | wander | none
		"aggression": 0.8, "intelligence": 0.9, "courage": 1.0,
		"sight_range": 40, "leash": 48, "step_up": 2, "boss": {"name": "Ancient Colossus"},
		"attacks": [
			{"name": "stomp", "type": "slam", "damage": 9, "radius": 5, "windup": 1.1, "cooldown": 5},
			{"name": "punch", "type": "melee", "damage": 11, "range": 2.2, "arc": 120, "windup": 0.7},
		],
		"phases": [{"health_below": 0.5, "message": "The Ancient Colossus roars in fury!", "speed_multiplier": 1.35,
			"add_attacks": [{"name": "charge", "type": "charge", "damage": 14, "min_range": 6, "range": 24}]}],
	},
})
var boss = api.spawn_entity("colossus", position)
boss.tune({"aggression": 1.0})                   # this one only
boss.set_target(player)
```

- **Navigation:** A* on the voxel grid for the mob's real size (a 1.2x7.2 boss needs a 2x2x8 gap),
  climbing up to `step_up` blocks, dropping at most `max_drop`, optional swimming, never entering
  blocks marked `"hazard": true`, and keeping away from lethal edges. Paths are string-pulled and
  re-planned when the target moves; a per-tick budget keeps the cost flat.
- **Senses and memory:** sight within `sight_range` and a `fov` cone, blocked by opaque blocks;
  hearing noises (block breaking and placing, fighting, sprinting, `make_noise`) within
  `hearing_range`; memory of where enemies were last seen and where they were heading, for
  `memory` seconds. Threat tables: whoever hurts a mob most becomes its target.
- **Decisions:** each think (4x a second) behaviours are scored and the best runs: idle, wander,
  investigate (a noise or an ally's call), engage, search (go where the target was last heading),
  flee (below `(1 - courage) / 2` health, or passive mobs hurt or approached within `skittish`),
  return home (past `leash`; bosses reset), scripted goals and mod behaviours.
- **Tactics:** melee mobs spread around a shared target instead of stacking and circle while their
  attacks recharge; ranged mobs keep `preferred_range`, strafe, retreat when approached and lead
  moving targets; `agility` sidesteps incoming projectiles; spotting or being hurt alerts allies of
  the same `group`; `enemy_groups` lets mobs fight other mobs; heavy hits stagger wind-ups; hurt mobs
  that fled stay away and recover before returning. `intelligence` scales prediction, flanking and
  shot leading; `aggression` scales pursuit distance and attack tempo.
- **Attacks** (`melee`, `ranged`, `leap`, `charge`, `slam`, `summon`, `custom`) all telegraph with a
  wind-up the client animates, so players can dodge, block line of sight or interrupt. Selection
  weighs range, cooldowns, health conditions and the situation (slams when several enemies are close,
  charges over open ground, summons when alone). `custom` attacks fire `mob_attack` for the mod to act.
- **Bosses:** `phases` change attacks, speed and aggression at health thresholds (`mob_phase`) and
  `boss` shows a health bar to nearby players.
- **Mod hooks:** `register_mob_behavior(name, {score, update, stop})` adds behaviours that compete
  with the engine's (JavaScript: `api.registerMobBehavior`); entity methods `set_target`, `add_threat`,
  `tune`, `alert`, `set_home`, `perform_attack`, `set_goal`; events `mob_target` (cancellable),
  `mob_attack` (cancellable) and `mob_phase`. Reference: `engine/server/ai/mob_config.gd`.
- **In the bundled games:** zombie packs (claw + lunge, they call each other in), skeleton archers
  that kite and dodge, pig herds that scatter together, the Ancient Colossus (`/colossus`), and in the
  guild mod an elite bounty zombie tuned from JavaScript and a treasure goblin whose loot-grabbing
  behaviour is written in JavaScript (`/guild goblin`).
- **Cost:** 300 mobs with about 130 hunting 10 players, plus 200 item stacks: 3.5 ms per tick with
  the native extension, 9.3 ms with the GDScript fallback (`tests/bench.tscn`).

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
Wand of Light conjures a temporary light orb, the Wand of Sparks shoots a glowing projectile that
hurts mobs. Craft wands and pylons with C, or `/arcana kit`.

## World saves (delta model)

Chunks are always regenerated from the seed, then saved edits are applied on top.
`chunks/x_z.json` stores only blocks that differ from generated terrain (by block name, with a
palette) plus that chunk's block data. Untouched chunks are never written, an edit that restores
the generated block is dropped, and changing world generation or mods flows into existing worlds
(edits referring to blocks from removed mods fall back to the generated terrain). Saves are
serialized on the main thread and written by a worker, atomically via rename.

### Backups

Every `VOXEL_BACKUP_INTERVAL` minutes (default 60; 0 turns it off; skipped while the world is idle)
the server flushes pending saves and zips the world on a worker thread into
`<data dir>/backups/<world>/<world>-<UTC timestamp>.zip`, keeping the newest `VOXEL_BACKUP_KEEP` (24).
Admins can run `/backup` and `/backups`. To restore, start with `--restore=latest` (or a file name or
path, `VOXEL_RESTORE`): the current world folder is moved aside to `<world>.before-restore-<time>`, never
deleted, and the archive is unpacked in its place.

## Identity and permissions

Every client has an RSA key (`user://identity/default.pem`, created on first launch). Its hash is the
player id: saved inventory, position and mod data follow the key, not the name. Each name belongs to
the first key that claims it on a server, so nobody can take over someone else's player by typing
their name.

Admins come from `VOXEL_ADMINS` (player ids from `/whoami`, or names), `/op <player>`, or the local
host via the token the menu's Host button passes to its server. Mods mark commands as admin-only
(`register_command(..., "admin")`, or `{ admin: true }` in JavaScript) or check `player.is_admin()`.
Built-in admin commands: `/op`, `/deop`, `/kick`, `/backup`, `/backups`; everyone has `/help`,
`/players`, `/whoami`.

**Moving your identity to another computer:** the key is your account, so it is exported encrypted
(PBKDF2-HMAC-SHA256 with 210k iterations, AES-256-CBC, HMAC-SHA256 over the ciphertext). Use the menu's
Export/Import identity buttons with a passphrase, or:

```sh
VOXEL_IDENTITY_PASSPHRASE='...' VoxelCraft -- --export-identity=my-identity.json
VOXEL_IDENTITY_PASSPHRASE='...' VoxelCraft -- --import-identity=my-identity.json   # old key kept as .bak
```

**Server identity:** each data dir holds `identity/server.key` and `server.crt` (self-signed, created
on first start). Keep them with the world (the Docker `/data` volume does): a server that loses them
looks like an impostor to returning players, who then have to delete the pin from `known_servers`.

## Dedicated server & Docker

`scenes/server.tscn` (`engine/server_main.gd`) loads no client code. Every option is a CLI arg or an
environment variable: `VOXEL_PORT`, `VOXEL_MODS`, `VOXEL_MODS_DIR`, `VOXEL_DATA_DIR`, `VOXEL_WORLD`,
`VOXEL_SEED`, `VOXEL_MAX_PLAYERS`, `VOXEL_METRICS`, `VOXEL_ADMINS`, `VOXEL_ADMIN_TOKEN`,
`VOXEL_BACKUP_INTERVAL`, `VOXEL_BACKUP_KEEP`, `VOXEL_RESTORE`.

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
| Entity physics (500 bodies) | `NativeVoxelWorld.step_entities` | 2.3 ms/tick | 1.0 ms/tick, one batched call |
| Mob pathfinding, sight | `NativeVoxelWorld.find_path` / `line_of_sight` | 350-node budget | 1500-node budget, ~50 µs per path |
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
godot --headless --path . res://tests/smoke_test.tscn -- --port=24603 --game=combat     # needs --admins=Bot_combat
godot --headless --path . res://tests/auth_test.tscn -- --port=24603          # needs --admins=Admin; also version + pinning
godot --headless --path . res://tests/multiplayer_test.tscn -- --port=24603   # launches a 2nd client
godot --headless --path . res://tests/host_flow_test.tscn                     # menu Host flow

godot --headless --path . res://tests/persistence_test.tscn   # delta saves, block data, backups + restore
godot --headless --path . res://tests/identity_test.tscn      # encrypted identity export / import
godot --headless --path . res://tests/gameplay_test.tscn      # inventory, entities, damage, equipment, cosmetics
godot --headless --path . res://tests/ai_test.tscn            # mob AI in a flat arena (tests/mods/ai_arena)
godot --headless --path . res://tests/js_sandbox_test.tscn    # JavaScript limits
godot --headless --path . res://tests/bench.tscn              # worldgen, meshing, snapshots, physics
godot --headless --path . res://tests/bots.tscn -- --port=24603 --bots=100
godot --path . res://tests/screenshot.tscn -- --port=24603 --commands="/industry demo|/time night"
godot --path . res://tests/screenshot.tscn -- --port=24603 --camera=2 --editor=hat   # avatar editor
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
- **multiplayer:** two client processes see each other join, move, build, chat and leave, and see each
  other's avatar cosmetics change.
- **host_flow:** Host launches a server, the host becomes admin, leaving stops the server.
