# Writing a mod

> **The bundled games were removed on 21 September 2026** and will be rebuilt for 1.0 (see
> `docs/roadmap.md`). Examples below that name `vanilla`, `hearthhold`, `industry`, `arcana`, `guild`,
> `skyblock` or `oneblock` describe how things *were*, and still illustrate the capability correctly -
> but you cannot run them as written. The mod the tests use now is `tests/mods/proving`, which uses
> every capability the engine has and is the best worked example there is.

A mod defines the game: blocks, items, entities, world generation, rules, recipes, machines, commands and
UI. The engine provides the capabilities; mods provide everything a player sees. Mods are written in
GDScript or JavaScript, and the full generated API reference is in [api/index.html](api/index.html).

## Writing a mod

**Quick start:** the menu's **Create a mod…** (or `godot --headless --path . res://tools/mod_tool.tscn -- new
my_mod [--lang=js] [--kind=game]`) writes a starter mod: a block, an item, recipes, an event handler with
logging and debug drawing, a command, a guide page, a tutorial, generated textures and a README, then
offers to host it in developer mode. Add-ons play with Vanilla; games generate their own world. The full
API reference is **docs/api/index.html**, generated from the engine's doc comments and TypeScript
declarations (`mod_tool.tscn -- docs`; a test fails if it is stale). The menu's **Developer mode** box
hosts any game with the dev tools and the file watcher on (`--host=proving,my_mod --dev` from the
command line). Mods created from an exported game go to `user://mods`, which servers search by default.

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
  extension. Types for editors/TypeScript: `engine/server/js/quarrowen.d.ts`; API surface:
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
  `get_entities`, `add_spawn_rule`, `set_spawn_caps`, `register_sound`, `play_sound`, `set_gameplay` (see below).
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

### Changing many blocks at once

Choosing the cells and changing them are two calls, because between them is where a tool shows a
preview, counts the cost, or asks whether the player meant it:

```gdscript
var cells: Array = api.area_cells("vein", {"position": at, "player": p, "max": 64})
api.show_area(p, cells, {"seconds": 3.0})            # outlines them for that player
var done: Dictionary = api.area_edit(p, cells, {"block": 0})   # 0 breaks; a block id places
p.send_message("Mined %d of %d." % [done.changed, cells.size()])
```

- `area_cells(shape, ctx)` — `"box"` (`{from, to}`), `"sphere"` (`{position, radius}`), `"vein"`
  (`{position, block, max}`), or a shape you registered. `max` caps what comes back.
- `register_area_rule(name, chooser)` — your own shape: a line, a wall, everything touching one face.
  The chooser is handed the context you passed and returns an Array of Vector3i.
- `area_edit(player, cells, {block, drops, realm})` — returns `{changed, skipped, refused, reason}`.
- `show_area(player, cells, {color, seconds})` — `seconds` 0 holds the outline until it is cleared;
  an empty list takes it away.

**This is not `fill`.** Every cell goes through the plot check, the block events, the loot roll, tool
wear, hunger and the player's edit budget — it calls the same code a hand-swung pick calls, so your
`block_broken` handler hears an area edit exactly as it hears a pickaxe. `api.fill` is the admin door
and asks none of that; use it for world generation and `/` commands, not for something a player holds.

A selection that reaches into somebody else's plot **does the part outside it** and reports the rest
as `skipped`, so a vein can run up to a boundary and stop rather than the whole thing being refused.
A solid block is never placed in a cell somebody is standing in. Reach is asked once, of the nearest
cell, at 24 blocks.

### Bags, and stores that are the same everywhere

Two kinds of container whose contents are not at a position.

A **bag** is an item whose definition names a `container` type, the way a chest block does:

```gdscript
api.register_container("satchel", {"title": "Satchel", "slots": 9})
api.register_item("satchel", {"display_name": "Satchel", "max_stack": 1, "usable": true,
    "container": "satchel"})
api.on("item_use", func(ev): api.open_bag(ev.player, ev.player.selected_slot))
```

Its contents live in the item's own data, so it holds what it holds wherever it goes — into a chest,
onto the floor, into somebody else's hands — with nothing to keep in step.

A **shared store** is the same contents wherever it is opened:

```gdscript
api.shared_store("vault", "vault_type")          # declare once, in setup
api.open_shared(player, "vault")                 # open it from anywhere
var v = api.get_shared("vault")                  # or read it without a screen
```

**Whose it is, is the name's business.** One vault for the whole server is `"vault"`; one each is
`"vault_" + player.player_id`. The engine keeps a table of names, so it never has to guess which you
meant. Contents are saved with the world, and survive their mod being uninstalled and reinstalled.

Two rules the engine enforces: **a bag cannot be put inside a bag** (the outer one holds the inner
one's data, so copying the stack copies the contents — every version of nesting is somebody's
duplication exploit), and **the slot holding an open bag is locked** while it is open, because the
bag's address is that slot.

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
- **Tools from parts:** alongside the fixed tools, a Toolsmith’s Bench makes parts (pickaxe/axe/shovel heads,
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
- **Crafting by hand (skill minigames):** recipes and assemblies with a `skill` show a "by hand" button
  next to Craft. It opens a short minigame and the result gets a quality: Standard (the same as
  crafting normally, also what you get for stopping early), Fine +10%, Superior +20% or Masterwork
  +30%. Quality raises durability, mining speed, weapon damage and armor, prefixes the name, adds a
  star line to the lore, and Masterwork also credits the makers and glows (`skill_crafted` event lets
  mods change the result). Ingredients are taken when the game starts. Minigame types: `timing` (strike
  while a marker is inside a shrinking zone; `cool` makes it speed up), `hold` (keep a gauge inside a
  drifting band) and `sequence` (press prompted directions in time). A station's `quality` grant
  widens zones. A "Relaxed timing" checkbox (server rule `minigame_assist`) slows markers and widens
  zones. Team `timing` games: "With a partner" invites others at the station from their co-op panel;
  the partner works the bellows (keep heat in the green band, pump just before strikes for a sync
  bonus, too hot burns a strike) while the starter hammers. The server replays inputs with the shared
  scoring code and clamps each input's time to the connection's latency. Bundled: forging (iron tools,
  iron armor, forged tools from parts), stitching (vanilla leather armor), channeling (Arcana soul
  blade and crystal helmet).

```gdscript
api.register_minigame("forging", {"title": "Forge by hand", "type": "timing", "rounds": 5, "speed": 0.75, "zone": 0.2, "cool": 9.0, "team": true})
api.register_recipe({"base:iron_ingot": 3, "base:stick": 2}, "base:iron_pickaxe", 1, {"station": "crafting_table", "skill": "base:forging"})
```
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

**Player creations (in progress):** the avatar editor (menu) has **Paint a skin…**: a 64x64 skin painter
with a turning 3D preview (pencil, eraser, fill with a small tolerance, picker, mirror, body and outer
layers, undo/redo, PNG import/export). Saved skins go to the local creation library (`user://creations`)
and are worn in the Skin category; a worn skin replaces the painted face and clothes, while 3D accessories
still show. In the hat, hair, glasses, back and face categories, **Build…** opens a voxel builder (layer
by layer on a top-down grid with body-part guides, mirror, copy layer, undo; voxels merge into at most 64
boxes) and **Import model…** places a GLB (size, offset and rotation sliders; refused if over 512 KB,
4,000 triangles or 256 px textures). Format and limits: `engine/shared/creations.gd`.

**Creations on servers:** when you join (or change your look) the game offers the creations you wear to
the server; it asks for the files it lacks and you upload them in pieces (paced, size-checked, only the
author may bring a creation). The server validates them again and stores them in `<world>/ugc/`. Policy
(`--ugc=auto|trusted|approval|off`, or `api.set_ugc_policy({accept, kinds, library, max_per_player,
max_bytes_per_player})`): with `auto` creations are approved at once, `trusted` approves admins' and
trusted players', `approval` keeps them hidden until approved, `off` refuses them. Approved creations
become cosmetics here; other players' clients fetch, re-check and cache what they need to draw
(`user://ugc_cache`). In game the avatar editor has your creation tools plus **Server library…**, which
lists approved creations for the category so you can wear other players' work (if `library` is on). Your
own creations stay in your portable look; library picks are remembered per server. Events
`ugc_uploaded {player, creation, cancelled, reason}` and `ugc_status {id, status, reason}`.

**Moderation:** players report a creation someone wears from the pause menu (**Report a creation…**) or
with `/report <player> [reason]`; each player reports a creation once, and after `report_hide` reports
(default 3, 0 = never) it is hidden until reviewed. Admins get **Review creations** in the pause menu
(filters for waiting, reported, approved, rejected and removed; skin and 3D previews; reports; approve,
reject, remove for good, clear reports, trust or ban the creator), the same in the dev dashboard's
**Creations** tab, and `/ugc list|approve|reject|remove <id prefix> [reason]`, `/ugc trust|untrust|ban|unban
<player>` and `/ugc policy <key> <value>`. Removed creations are blocklisted by content hash; trusted
creators skip the queue under `accept=trusted`; banned creators cannot upload and their creations are
hidden. Mods use `ugc_list`, `ugc_get`, `ugc_set_status`, `ugc_report`, `ugc_trust` and `ugc_ban`
(JavaScript: `ugcList`, `ugcGet`, `ugcSetStatus`, `ugcTrust`, `ugcBan`), and the `ugc_reported {player, id,
reason, details, reports, cancelled}` event can veto reports. `ugc_status` also carries `by`.

Players are drawn with a rig of 10 boxes (head, torso, upper and lower arms and legs) textured in the
standard 64x64 box-unwrap skin layout, animated procedurally (walking, running, jumping, swinging,
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

### Music

Music comes from the server, so what a player hears is the game's decision, not the client's:

```gdscript
api.register_music("valley", "music/valley.ogg", {
	"attribution": "Kevin MacLeod - Meadow (CC0)",   # required
	"volume": 0.9, "loop": true})

api.play_music(null, "valley", {"fade": 6.0})   # null = everybody; or a player
api.stop_music(player, {"fade": 3.0})
```

Three things worth knowing:

- **Asking for the track that is already playing does nothing.** So a mod can call `play_music` on a
  timer, on every biome change, every night - whatever decides the music - without restarting it.
- **Music never delays a join.** Its audio is registered as a *lazy* asset: listed for the client but
  not part of the download a player waits through to get in. It arrives afterwards and starts when it
  is ready. (`api.register_asset(path, {"lazy": true})` if you want that lane for something else. Use it
  only for things the world can be drawn without.)
- **`attribution` is required.** Running a server means redistributing whatever a mod put in it, to
  children and to anyone else who joins, and a track whose source nobody wrote down is one whose licence
  nobody can check later. A track without it is refused at registration, loudly, while the person who
  can fix it is still looking. `/music` shows the credits in game.

Only the game should drive the music. If your mod builds on another one, guard the timer with
`api.is_game()` - otherwise two mods fight over it and whoever ran last wins.

The bundled tracks are placeholders generated by `tools/generate_music.py`, like every texture and sound
effect here. Replacing them with real CC0 music is welcome; bring the attribution with it.

### A story to walk through

A story is a world people move through rather than rebuild. One line:

```gdscript
api.set_default_role("visitor")
```

`visitor` is a stock role: chat and interact, no build. So doors, chests, levers and stations all still
work, and the valley stays as its author left it. The engine already refuses a break or a place without
the `build` permission, tells the player why (once every few seconds, not once a click) and puts the
block back on the client that predicted it.

Give building back to whoever should have it — a builder role for yourself while authoring, say — with
`/role give <player> member`.

### Shipping a world

A mod can bring an authored world with it — a valley someone built for a story, rather than terrain the
generator made. Put the archive in the mod and name it in `mod.json`:

```json
{ "id": "myvalley", "kind": "game", "world": "world.zip" }
```

**There is no map format to learn, because a world save already is one.** Authoring a map is:

1. Play a world and build the thing.
2. `/backup` — that writes exactly the archive this wants.
3. Copy it into your mod as `world.zip` and add the `world` line.

So the editor is the game, and the distribution channel is the mod list.

Two rules it will not bend:

- **It only runs on the first start of a world.** A world somebody has played is never overwritten by a
  mod update — losing a child's building to a version bump is not something that may happen.
- **A missing or unreadable archive stops the server**, with the reason, rather than generating terrain
  instead. A story mod whose valley is absent is not a story mod, and starting anyway would strand
  players in a world the triggers do not fit.

`world.json` inside the archive carries the spawn, so where players arrive is part of the map. What
happens there is the mod's business — see `set_spawn_handler` and `set_rejoin_handler` above.

### Ambience

The occasional sound that tells you where you are, rather than one you caused:

```gdscript
api.register_ambience({"sound": "wind", "sky": true, "every": [22.0, 55.0], "volume": 0.45})
api.register_ambience({"sound": "drip", "sky": false, "depth": [0, 48], "every": [14.0, 40.0]})
api.register_ambience({"sound": "lapping", "near": ["base:water"], "radius": 7})
```

Conditions: `sky` (true outdoors, false under something), `depth` `[low, high]`, `biome` (one or a
list), `near` (block names — the sound then comes *from* one of them, so water laps from the water
rather than from inside your head), `radius`, `chance`. `every` is `[minimum, maximum]` seconds and is
kept **per player**, so two people in different places hear their own surroundings.

Keep it quiet and infrequent. This arrives unasked, and the job is to be noticed once and then stop
being noticed — a wind that announces itself is worse than silence.

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
api.add_spawn_rule({"entity": "wolf", "category": "monster", "light": [0, 7], "on": ["base:grass", "base:snow"], "max_nearby": 3, "group": [2, 4]})
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
- **Hunger and food:** survival players have hunger (0-20, drumsticks beside the hearts) and hidden
  saturation that is used up first. Sprinting, jumping, swimming, mining, fighting, taking damage and
  healing add exhaustion (4 exhaustion = 1 point). Natural regeneration needs 18+ hunger (faster when
  full and saturated); at 6 or less you cannot sprint; at 0 you starve down to
  `starvation_min_health` (default 1, 0 lets players starve to death). Items with `food` are eaten by
  holding use: `{hunger, saturation, eat_time, always, heal, remainder, color, effects}` where effects
  are timed stat modifiers with a chance (rotten flesh's food poisoning raises `hunger_drain`). Crafting
  quality makes food up to 30% more filling. Stats `exhaustion` and `hunger_drain` let gear and
  effects change hunger; the `player_eat` event can change or cancel a meal; players have
  `set_hunger`, `add_exhaustion` and `feed`; commands `/feed` and `/hunger <0-20>`. Bundled food:
  apple 4, bread 5, raw/cooked porkchop 3/8, rotten flesh 4 (vanilla), trail ration 6 plus a speed
  boost (Guild, JavaScript).
- **Eating animation:** food is served on a plate (`style: "plate"`, the default) or eaten from the
  hand (`"hand"`): your arm brings it to your mouth chomp by chomp, it loses a bite at each third of
  `eat_time` (bites are cut out of the item's own icon, so mod foods work too), pixel crumbs in the
  food's `color` fall, and the plate empties. Drinks and potions (`"drink"`) are swigged straight from
  the bottle with gulp sounds and give back their `remainder`. Other players see the same: the left
  hand holds the plate, the right lifts the food, the head tips back for drinks. The hunger bar pops
  as a meal lands. Bundled drinks: apple juice (base, bottles from glass) and mana potions (Arcana,
  restore mana through `player_eat`).

```gdscript
api.register_item("bread", {"icon": "textures/bread.png", "food": {"hunger": 5, "saturation": 6.0}})
```

- **Biomes and world generation:** the engine biome generator (`api.use_biome_generator`) picks biomes
  from smooth climate noise (temperature, humidity, weirdness, peaks) and continentalness (land or
  ocean), blends biome heights so borders are smooth, and takes surface blocks, plants and features from
  the closest biome. `register_biome(name, {climate, ocean, height: {base, variation, peaks}, surface:
  {top, filler, depth, underwater, beach, stone}, features: [{feature, per_chunk}], plants: [{block,
  chance, on}]})`; `register_feature(name, {type: tree | column | boulder | spike | mushroom | patch,
  ...})` or a GDScript Callable. Features may cross chunk borders (positions depend only on their own
  chunk, and each chunk keeps the blocks that fall inside it). Spawn rules take `biomes`; `get_biome`,
  `/biome`. Vanilla: plains, forest, birch flower forest, taiga, snowy tundra, desert, swamp, savanna,
  mountains and ocean with oak, birch, spruce, acacia and swamp trees, cacti, boulders, ferns and dead
  bushes (new base blocks; all logs make planks).
  Biomes with a `weirdness` value only appear where the weirdness noise passes it, which makes them
  rare: vanilla's glowing mushroom fields (mycelium, huge red and glowing mushrooms, boomshrooms) and
  shadowwood (gloomgrass, towering dark trees, nightblooms, night stalkers even at dusk), and Arcana's
  crystal highlands (crystal stone and glowing mana spires) that Arcana adds to any biome world.
  Caves: `add_cave_carver({tunnels, caverns, ravines, lava, lava_level, water_level, entrance_chance})`
  carves winding tunnels and big caverns from interpolated 3D noise, deep ravines, lava below
  `lava_level` and water lakes in low caverns, without breaching seas (cells that cannot hold a cave
  are skipped). Biomes can set their own `surface.water` (vanilla's glowing pools in mushroom fields
  and murky gloom water in shadowwood; Arcana's glowing mana springs) and trees can hang `fruit`
  (shadowwood's glowing pods). Blocks with `contact_damage: {amount, interval, cause}` hurt players
  and mobs inside them (lava). Vanilla ores are placed by depth: coal high, iron in the middle and the
  new cobalt ore (smelts into cobalt ingots) deep near the lava.
- **Structures:** build something in creative, then `/struct pos1` and `/struct pos2` (on the blocks
  you look at; a box outline shows the selection) and `/struct save <name> [keep_air]` to write a JSON
  template to the world's `structures/` folder (`/struct place <name> [rotation]` and `/struct list`).
  Copy the file into a mod and `register_structure_template(name, "structures/x.json")`. Templates keep
  block states and block data, so a chest can carry `{loot: "<table>"}` and a spawner `{spawner:
  {entity, count, range}}`. `register_structure(name, {templates or generator, spacing, separation,
  biomes, place: surface | underground, y, sink, foundation, swaps: {biome: {block: block}}, reach,
  chance})` places at most one per region of `spacing` chunks, rotated, with per-biome material swaps,
  deterministically so pieces line up across chunk borders; GDScript generators return pieces for
  code-built layouts. `register_loot_table(name, {rolls, entries})` fills structure chests the first
  time they are opened. Blocks with `spawner: true` (base's monster spawner) spawn mobs in the dark
  near players.
  Vanilla structures (templates in `mods/vanilla/structures/`, written by `tools/generate_structures.py`):
  underground dungeons with a zombie, skeleton or spider spawner, cobwebs and two loot chests; ruins
  and watchtowers built from local materials (sandstone in deserts, spruce in taiga, acacia on the
  savanna); branching mineshafts generated in code from corridor, crossing and room pieces with chests
  and webs; and rare ancient arenas in plains, savanna and desert whose altar wakes the Colossus when
  a survival player walks in, guarding cobalt, iron and shadow essence.

- **Natural spawning:** spawn rules pick spots on the surface and in caves near each player and check
  the light there (block light or daylight-scaled sky light, 0-15). Monsters default to light 0-7, so
  night, caves and unlit rooms spawn them and torches keep an area safe; animals default to 9-15 on
  sunny ground. Rules add `category`, `light`, `place` (surface/underground), `group` (pack size), and
  categories cap mobs around each player (`set_spawn_caps`). Monsters despawn far from everyone (at
  once beyond 96 blocks, now and then beyond 32); animals, persistent mobs and mobs with data
  `no_despawn` stay. `/mobs` shows counts and caps.

- **Farm animals and breeding:** mobs with `breeding: {food, love_seconds, cooldown, grow_seconds,
  baby_scale, tempt}` follow players holding their food, fall in love when fed (hearts), pair up with
  another in love nearby and have a baby that is drawn smaller, drops nothing and grows up (feeding
  speeds it up). Entities have a replicated look (`entity.set_look({scale, hide, tint, pose})`): model parts
  can be hidden or tinted by name prefix. Events `entity_fed`, `entity_bred`, `entity_grew`;
  `entity_interact` can be cancelled. Vanilla adds cows (beef, leather, milk with a bucket, which
  cures food poisoning), sheep (shears take wool in the sheep's color and it regrows; nine wool colors
  from dyes made of bone, coal, poppies, dandelions, saplings and mixes; lambs inherit or mix colors;
  wool makes matching beds) and chickens (chicken, feathers, eggs laid every few minutes); cows and
  sheep eat wheat, chickens seeds, pigs apples.

- **Taming:** mobs with `taming: {items, chance, follow_distance, teleport_distance}` are tamed by
  right-clicking them with one of `items` (each try uses one). A tamed mob belongs to that player: it
  follows them and teleports to catch up, never targets them, attacks whatever hurts its owner or
  whatever its owner hits, never despawns, and sits or stands when its owner right-clicks it (a
  sitting pose on the client). Events `entity_tamed`, `entity_sit`; data `owner`, `owner_name`,
  `sitting`. Vanilla wolves are neutral pack animals tamed with bones, wear a red collar once tamed
  and breed on meat.

- **Monster traits:** mob AI configs add `climb` (walks up walls when blocked; pair with a high
  `step_up`), `hop: {interval, height}` (moves only in hops), `day_temperament` (e.g. "neutral" while
  standing in bright daylight) and `fear_light` (flees to darkness when its spot, or a torch held
  nearby, reaches that light level); entity definitions add `split: {entity, count}` (breaks into
  smaller mobs on death). Vanilla spiders climb, pounce and ignore players by day unless hit (string);
  slimes hop around caves and split large -> medium -> small (slimeballs); rare night stalkers hunt
  the darkest nights and caves, fast and clever, but flee light and torches (shadow essence).

- **Explosions:** `api.explode(position, power, options)` casts rays that lose strength with distance
  and each block's `blast_resistance` (default from hardness; unbreakable blocks and liquids stop the
  blast), destroys what they get through (drops with a 1 / power chance), and hurts and knocks back
  players and mobs by distance and cover (armor helps). Mob explosions only break blocks while the
  `mob_griefing` rule is on; any explosion can pass `break_blocks: false`. The `explosion` event lists
  the blocks and can change or cancel them. Mob attacks gain `type: "explode"` (a fuse wind-up; it
  fizzles if the target gets `fuse_escape` blocks away). Vanilla's boomshroom is a walking mushroom
  that sneaks up, hisses and explodes (boom spores when killed).

- **Beds and respawning:** a bed is a two-block piece (the foot where you click, the head behind it;
  breaking either half removes both). Right-clicking one sets your respawn point; at night, with no
  hostile mobs within 8 blocks and the bed free, you lie down (the screen dims, "Leave bed" or any
  movement gets you up; damage wakes you). When `sleep_percentage` of online players (default 100) have
  slept for 5 seconds, the night skips to morning. Respawning uses your bed if it still stands with room
  beside it, otherwise the world spawn with a message. Others see you lying on the bed. Engine keys:
  `bed: true` and `pair` on blocks; events `player_sleep`, `player_wake`, `night_skipped`; rules
  `sleeping`, `sleep_percentage`. Bundled: a straw bed (3 planks + hay bale).

- **Gameplay rules** (`set_gameplay`, or `/gameplay rule value`): `item_drops` ("entity" or
  "inventory"; Skyblock uses inventory so drops don't fall into the void), `keep_inventory`, `pvp`,
  `fall_damage`, `natural_regeneration`, `hunger`, `starvation_min_health`, `sleeping`, `sleep_percentage`, `mob_spawning`, `mob_griefing`.
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
  guild mod an elite bounty zombie tuned from JavaScript and a coin snatcher whose loot-grabbing
  behaviour is written in JavaScript (`/guild goblin`).
- **Cost:** 300 mobs with about 130 hunting 10 players, plus 200 item stacks: 3.5 ms per tick with
  the native extension, 9.3 ms with the GDScript fallback (`tests/bench.tscn`).

### Guidebook

An illustrated book players open with **G**, from the pause menu or by using a **Survival Guide** item
(base: 1 planks + 1 stick). Mods write it; the engine draws it, tracks progress and syncs it.

- **Chapters and pages** (`register_guide_chapter(name, {title, icon, order, description})`,
  `register_guide_page(name, {chapter, title, icon, order, unlock, hint, keywords, blocks})`; JS
  `registerGuideChapter` / `registerGuidePage`). Pages are lists of blocks: `text` (BBCode), `heading`,
  `tip`, `items` (icons you click to open the recipe book), `recipe` (live cards from the real
  recipes, hidden while undiscovered), `entity` (a turning 3D portrait), `image` (a texture in the
  mod), `link` (another page) and `keys` (the player's current key for an action).
- **Unlocks** keep spoilers hidden: `{item}` once held, `{recipe}` once known, `{entity}` once seen within
  12 blocks, `{flag}` set by a mod (`api.set_guide_flag(player, flag)`, JS `player.setGuideFlag`), or
  `{biome}` once visited, `{page}` after reading another page. Locked pages show "???" and a hint. `api.unlock_guide_page`
  and `api.open_guide(player, page)` (JS `player.unlockGuidePage` / `openGuide`) do it directly.
- Bundled chapters: First Steps, Survival, Crafting and Smithing (base), Animals, Monsters and The World
  (vanilla), Arcana, Industry, and the Adventurers' Guild (written in JavaScript). Recipe blocks also
  show smelting. `tests/gameplay_test.gd` checks that every item, mob, page and recipe they name exists.
- Unlocks, reads, flags and the last open page are saved per player. New pages pop up a note and a
  "Guide · N new" badge; the book has search, back/forward and previous/next page, and reopens where
  you left off. Event `guide_page_unlocked {player, page}`.

### Tutorials and tips

Guided goals in the player's own world, completed by doing the real thing. A tracker on the left shows
the current step, its progress and the guide page it links to ([G] opens that page); a bobbing marker
and a screen-edge arrow point at the nearest matching block or mob. The vanilla **Survival Basics**
tutorial (logs → planks → table → pickaxe → stone → food → bed → sleep) starts for new survival players
and for sandbox players who switch to survival.

- `register_tutorial(name, {title, description, order, auto_start, reward: [[item, count]], steps: [{title,
  text, icon, goal, hint, page, reward}]})` (JS `registerTutorial`). Goals: `break`, `place`, `craft`,
  `pickup`, `eat`, `use_item`, `use_block`, `equip`, `kill`, `breed`, `tame`, `learn`, `read`,
  `unlock_page`, `sleep`, `respawn`, `death`, `damage`, `upgrade`, `assemble` with a `target` (names,
  `*` wildcards, e.g. `base:*log`) and `count`; `event` for any engine or mod event; polled `have`,
  `depth`, `reach`, `biome`, `hunger_below`, `health_below`, `night`, `flag`; and `manual`
  (`api.advance_tutorial(player)`). Hints: `{block}`, `{entity}` or `{position}` (break, use_block,
  kill, breed, tame and reach goals get one automatically).
- `register_tip(name, {text, icon, page, trigger: goal})` (JS `registerTip`): shown once per player, at
  most one every 12 seconds, with [G] to read more.
- Players skip steps, stop or replay tutorials and turn tips off from the pause menu's **Tutorials**
  panel or `/tutorial list | start <id> | skip | stop | tips on|off`. Progress is saved per player.
  Rule `tutorials` (auto-start). Events `tutorial_started`, `tutorial_step`, `tutorial_completed`,
  `tip_shown`. Also `api.start_tutorial`, `stop_tutorial`, `get_tutorial_state`, `show_tip`.

### Example: a worked mod

The two worked examples that stood here described the Industry and Arcana mods, both deleted on
21 September 2026. Rather than describe mods you cannot run, the example to read is
**`tests/mods/proving`** - the Proving Ground, which the test suite plays.

It is a better example than either of them was, for a reason that is not about freshness: its rule is
that *if the engine can do it, this mod does it*, so it is the one place where every capability on this
page appears in working code. It is also deliberately plain - no textures, no models, no dependencies -
so what you are reading is the API and not somebody's art direction.

    godot --headless --path . -- --server --mods=proving --world=test --port=24600

`tests/mods/proving/` is laid out by capability family: `things.gd` (blocks, items, recipes), `life.gd`
(creatures and their abilities), `society.gd` (characters, shops, objectives, companions), `machines.gd`
(energy, fluids, signals, multiblocks) and `presentation.gd` (effects, music, weather, tutorials).
`tests/mods/proving_js/` is the same idea in JavaScript.

## Logs and errors (for mod authors)

- **Logging:** `api.debug / info / warn / error(message)` in GDScript, `console.debug / log / warn / error`
  (or `api.debug` ...) in JavaScript. Lines go to the console, `<world>/logs/latest.log` (the last five
  runs are kept) and the dev tools. Debug lines are hidden until you raise a mod's level:
  `/log level my_mod debug`, or start the server with `--log-level=warn,my_mod:debug`. `/log [mod] [count]`
  shows recent lines in chat.
- **Script errors are caught:** GDScript runtime errors (through Godot's Logger with script backtraces)
  and JavaScript exceptions (with their JS stack) are attributed to the mod whose code was running, with
  file, line and stack, and grouped with a count. `api.error` reports the same way. Admins get a red card
  in game for each new error ("Error in my_mod main.gd:42"); `/errors` lists them, `/errors clear [mod]`,
  `/errors mute | unmute`.

### Dev tools (F8)

Admins (or everyone on a server started with `--dev`) press **F8** for a side panel; the game keeps
running beside it (click the world to play, F8 to get the mouse back, F8 again to close).

- **Logs:** live server log with source, level and text filters. **Errors:** script errors by mod with
  counts, file:line and the stack.
- **Inspect:** what the crosshair points at (up to 64 blocks): a block's name, state, block data, light,
  biome, definition and station status; a mob's health, data and AI (behaviour, target, threat, path,
  goal); a player's health, hunger, stats, modifiers, data and tutorial. Refreshes every second.
- **Events:** a live trace of events (filter by name, `block_*`), each with its payload (players,
  entities, blocks and items by name), the handlers that ran in order with their mod and time, who
  cancelled it and what they changed.
- **Perf:** server time over the last 10 seconds per mod: event handlers, scheduled tasks, commands,
  block ticks and mob behaviours (ms per second, calls, average and worst), next to the engine's own
  tick costs.
- **Draw:** shows mods' debug drawings and the engine's AI view (behaviour labels, target lines, paths
  and homes of mobs within 32 blocks). Drawings stay on with the panel closed.
- Debug drawing API: `api.debug_box(from, to, color, seconds, label)`, `debug_line`, `debug_text`,
  `debug_path`, `debug_sphere` (JS: `api.draw.box / line / text / path / sphere`). Nothing is sent or
  queued while nobody watches.

### Dev dashboard (web)

The same tools in a browser, handy on a second screen or for a headless server. Start the server with
`--dev-web=24580` (or `--dev`, which serves it on the game port + 15); it prints
`Dev dashboard: http://127.0.0.1:24580/?token=...` and admins can get the address with `/devweb`.
It listens on 127.0.0.1 unless `--dev-web-host` says otherwise, and every request needs the token.
Tabs: Logs (filters, follow), Errors (stacks), Events (live trace with a filter), Perf (sortable),
Inspect (a player, what they look at, a block by coordinates or an entity id, live), Creations (review
player creations) and Server (mods, players). `#perf`-style links open a tab. JSON API: `/api/state`,
`/api/inspect`, `/api/clear_errors`, `/api/reload`, `/api/ugc*` (see `engine/server/dev_web.gd`).

With the native extension the dashboard is served by a Rust HTTP server (`native/src/http.rs`, tiny_http
on its own threads: keep-alive, many browsers at once) and the page gets live updates pushed twice a
second over Server-Sent Events (`/api/stream`); the status line says "live (push)". Game data is still
read on the game thread. Without the extension a small GDScript server answers and the page polls.

### Reloading mods

- **Quick reload** (`/reload <mod>` or `all`, or the dashboard's Server tab): the mod's scripts are
  recompiled and its `setup` runs again. Event handlers, commands, timers, block tick handlers, mob
  behaviours, spawn rules, recipes, guide pages, tutorials and tips are replaced; blocks, items and
  entities it registers again update in place with the same ids; recipes keep their places (ones it no
  longer registers are hidden); players see the new definitions, recipe book, guide and tutorials at
  once. A script that does not compile leaves the old version running. Anything that cannot change live
  (a new block, item, entity, sound, effect or file, and world generation) is skipped with a note to do
  a full reload. Keep state that must survive in `api.storage`, player or entity data.
- **File watcher:** on with `--dev` (or `/reload watch on`): saving a `.gd`, `.js` or `.json` file in a
  mod folder reloads that mod half a second later and tells admins the result; changed textures,
  models, sounds or `mod.json` ask for a full reload.
- **Full reload** (`/reload full`): the server saves, restarts in place with the same settings and reads
  every mod again (new blocks, textures, models); players get a "Reloading mods…" notice and the game
  reconnects them automatically. Needs the dedicated server scene or the Host menu (both are). Event
  `mod_reloaded {mod, ok, notes, error}`.

### Mod packages, versions and validation

- **mod.json** gains `engine` (the mod API range it works with, e.g. `"^1.0"`; this engine is
  `Protocol.MOD_API_VERSION` 1.0.0), dependency ranges (`"depends": ["base@^1.0", {"id": "arcana",
  "version": ">=1.2 <2"}]` or `{"base": "^1.0"}`), `optional_depends` (loaded first when installed),
  `conflicts`, `authors`, `license` and `homepage`. Ranges: `^`, `~`, `>=`/`<`..., `1.x`, spaces for
  "and", `||` for "or" (`engine/shared/semver.gd`). Load errors say exactly what is wrong ("arcana needs
  base ^2.0, but base 1.4.0 is installed").
- **Packages:** `godot --headless --path . res://tools/mod_tool.tscn -- pack mods/my_mod` validates the mod
  and writes `build/mods/my_mod-1.2.0.zip`. Drop the zip into any mods folder (`--mods-dir`); the server
  unpacks it once into `user://mod_cache/` and loads it like a folder (a folder with the same id wins).
- **Validator:** `mod_tool.tscn -- validate mods/my_mod [--json]` (exit code 1 on errors), or `/validate
  my_mod` in game. It checks the manifest (typos like "dependencies", versions, ranges, engine range,
  main script), files (unreadable images, oversized files, textures over 256 px that players download,
  files nothing uses), that every GDScript compiles, a real load in a throwaway server (errors and
  warnings with file:line, missing assets), and references in what the mod registered: block drops,
  sounds, containers and pairs; item teaches and food remainders; entity drops and sounds; guide page
  icons, unlocks, items, recipes, entities, links and keys; tutorial and tip goal targets and pages.
  `tools/run_tests.sh` validates every bundled mod.
