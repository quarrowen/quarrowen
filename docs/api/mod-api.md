# Mod API reference

Every function a mod can call, generated from `engine/server/mod_api.gd` by
`mod_tool.tscn -- docs`. For the engine's own readers - the registries and helpers behind
these - see [engine.md](engine.md).

Mod API 1.0.0 · game 0.41.1


## Logging and debugging

### `api.info(message) -> void`

JavaScript: `info`

Logs a line from this mod (console, <world>/logs/latest.log and the dev tools).

### `api.debug_box(from: Vector3, to: Vector3, color := "#ffcc00", seconds := 2.0, label := "") -> void`

Debug drawing for developers (shown to admins with the dev overlay's Draw toggle on; cheap when
nobody watches). Shapes expire after `seconds`. Colors are "#rrggbb" or "#rrggbbaa".

**See also:** `debug_text`, `draw`

### `api.debug_line(from: Vector3, to: Vector3, color := "#ffcc00", seconds := 2.0) -> void`

A debug line between two points (see debug_box).

**See also:** `draw`

### `api.debug_text(position: Vector3, text: String, color := "#ffffff", seconds := 2.0) -> void`

A debug label floating at a position, always facing the camera (see debug_box).

**See also:** `draw`

### `api.debug_path(points: Array, color := "#60ff90", seconds := 2.0) -> void`

A debug path through a list of points (Vector3 or [x, y, z]), with a dot at each (see debug_box).

**See also:** `draw`

### `api.debug_sphere(center: Vector3, radius := 0.5, color := "#6090ff", seconds := 2.0) -> void`

A debug wire sphere (see debug_box).

**See also:** `draw`

### `api.debug(message) -> void`

JavaScript: `debug`

Log levels for authors: debug lines only appear with `/log level <mod> debug` (or --log-level).
Messages go to the server console, <world>/logs/latest.log and the dev tools.

### `api.warn(message) -> void`

JavaScript: `warn`

Logs a warning from this mod (shown in yellow in the dev tools).

### `api.error(message) -> void`

JavaScript: `error`

Logs an error from the mod (grouped like script errors and shown to admins).

### `api.set_server_info(values: Dictionary) -> void`

Sets the server name/description shown to connecting clients.

```gdscript
api.set_server_info({"name": "Proving Ground", "motd": "Nothing here is meant to be fun."})
```

### `api.company_info(company_id: int) -> Dictionary`

**See also:** `claim_plot`, `plot_problem`

### `api.assembly_info(assembly_id: int) -> Dictionary`

{id, realm, origin, offset, cells, name}, or {}.

### `api.claim_info(claim_id: int) -> Dictionary`

One claim: {realm, chunks, owner, player_id, name, centre, cost, paused}, or {}.

### `api.link_info(id: int) -> Dictionary`

One link: {kind, a, b, length}, or {} if there is no such link.


## Events, commands and timers

### `api.cancel_assembly(assembly_id: int) -> bool`

Puts it back exactly where it was lifted from.

**See also:** `cancel`

### `api.on(event: String, handler: Callable, priority := 0) -> void`

Higher priority runs first.

```gdscript
api.on("entity_spawned", func(ev):
	if ev.entity.type == ids.grazer and not ev.entity.data.has("look"):
		ev.entity.set_look({"hide": ["collar"]}))
```

**See also:** `add_handler`

### `api.register_command(command: String, description: String, handler: Callable, permission := "") -> void`

`handler(player, args: PackedStringArray)` runs for "/name args...". permission "admin" restricts
it to server admins (QW_ADMINS, /op, or the local host).

```gdscript
api.register_command("trial", "Go into a private copy of a room", func(player, _args):
	var here: String = api.instance_of(player)
	if not here.is_empty():
		api.leave_instance(player)
		player.send_message("Back out.")
		return
	var run: String = api.open_instance("trial", {"data": {"opened_for": player.name}})
	if run.is_empty():
		player.send_message("No room to open one.")
		return
	api.enter_instance(player, run, Vector3(0.5, 66, 0.5))
	player.send_message("You are in %s." % run))
```

**See also:** `add_command`

### `api.after(seconds: float, callback: Callable) -> int`

Runs `callback` once after `seconds`. Returns a task id for `cancel`.

**See also:** `schedule`

### `api.every(seconds: float, callback: Callable) -> int`

Runs `callback` every `seconds`. Returns a task id for `cancel`.

**See also:** `schedule`

### `api.cancel(task_id: int) -> void`

Stops a timer started with after or every.

**See also:** `broadcast_player_event`, `cancel_task`, `settle`


## Guidebook and tutorials

### `api.register_guide_chapter(chapter_name: String, def := {}) -> bool`

A guidebook chapter: {title, icon (item name), order, description}. Names without ":" are this mod's.

```gdscript
api.register_guide_chapter("proving", {"title": "The Proving Ground", "order": 1})
```

**See also:** `add_chapter`, `item`, `qualified`

### `api.register_guide_page(page_name: String, def: Dictionary) -> bool`

A guidebook page (see engine/shared/guide_registry.gd): {chapter, title, icon, order, unlock: {item (a
name or a list of names, any of which opens it) |
recipe | entity | flag | page}, hint, keywords, blocks: [{type: text | heading | items | recipe |
entity | image | tip | link | keys, ...}]}. Item, entity, page and flag names without ":" are this
mod's; image blocks take a texture path in this mod.

```gdscript
api.register_guide_page("what", {"chapter": "proving", "title": "What this is",
	"content": [{"type": "text", "text": "A mod that exists to be tested."}]})
```

**See also:** `add_page`, `qualified`, `register_asset`

### `api.open_guide(player, page := "") -> void`

Opens the guidebook for a player at a page ("" = where they left off).

**See also:** `open`, `qualified`

### `api.set_guide_flag(player, flag: String, on := true) -> void`

Guide flags unlock pages with `unlock: {flag}` (names without ":" are this mod's). Saved per player.

**See also:** `qualified`, `set_flag`

### `api.has_guide_flag(player, flag: String) -> bool`

Whether a player has a guide flag (see set_guide_flag).

**See also:** `has_flag`, `qualified`

### `api.unlock_guide_page(player, page: String, notify := true) -> bool`

Unlocks a guide page for a player whatever its condition. Returns true if it was locked.

**See also:** `qualified`, `unlock`

### `api.is_guide_page_unlocked(player, page: String) -> bool`

Whether a guide page is open to a player.

**See also:** `is_unlocked`, `qualified`

### `api.register_tutorial(tutorial_name: String, def: Dictionary) -> bool`

A tutorial: guided goals completed by real actions (see engine/server/tutorials.gd for goal types):
{title, description, order, auto_start, reward: [[item, count]], steps: [{title, text, icon, goal: {type,
target, count, ...}, hint: {block | entity | position} or false, page, reward}]}. Names without ":" are
this mod's.

```gdscript
api.register_tutorial("basics", {"display_name": "Basics", "auto_start": true, "order": 1,
	"modes": ["survival"], "steps": [
	{"title": "Find a rock", "goal": {"type": "break", "target": ["proving:rock"]}},
	{"title": "Hold four", "goal": {"type": "have", "target": ["proving:rock"], "count": 4}},
	{"title": "Say when", "goal": {"type": "manual"}}]})
```

**See also:** `add_handler`, `announce`, `qualified`

### `api.register_tip(tip_name: String, def: Dictionary) -> bool`

A one-time contextual tip: {text, icon, page (guide page to read more), trigger: a goal}.

```gdscript
api.register_tip("basics", {"text": "Rock is the thing to dig", "trigger": {"type": "night"}})
```

**See also:** `add_handler`, `qualified`

### `api.start_tutorial(player, tutorial_name: String) -> bool`

Starts (or restarts) a tutorial for a player. Returns false if it does not exist.

**See also:** `qualified`, `start`

### `api.stop_tutorial(player) -> void`

Stops the player's running tutorial; it will not start by itself again.

**See also:** `step`, `stop`

### `api.advance_tutorial(player) -> void`

Completes the player's current tutorial step (for "manual" goals).

**See also:** `advance`

### `api.get_tutorial_state(player) -> Dictionary`

{active, step, progress, done: [ids]} for a player.

**See also:** `now`, `state_of`

### `api.show_tip(player, tip_name: String) -> bool`

Shows a registered tip now (even if seen before).

**See also:** `icon_of`, `key_name`, `library`, `node_key`, `qualified`, `state_of`


## Crafting

### `api.register_recipe(inputs: Dictionary, output: String, count := 1, options := {}) -> bool`

Shapeless recipe: `inputs` maps item names to counts. Appears in the engine crafting menu (C key).
options: pattern (["C", "S"]) with key ({"C": "base:coal", "S": "base:stick"}) makes the recipe shaped for
the experimentation grid (its inputs are counted from the pattern; pass {} as inputs), unlock ("known" | "pickup" (default) | "blueprint" | "experiment" | "secret") and hint (text
shown while undiscovered) for recipe discovery, time (seconds in the station's queue; more players there craft faster), project (built
together: players contribute ingredients over time, see project_completed), tier (minimum station
tier), needs ([station features]), station (name of the crafting station block needed, e.g. "crafting_table"; blocks declare
`station: "<name>"`; without one it is crafted anywhere), category (recipe book tab: tools, weapons,
armor, blocks, food, materials, misc or one from register_recipe_category), id (defaults to
"<mod>:<output name>").
An input named "#base:logs" means *any* member of that tag. Held back until every mod has loaded and
then written out as one recipe per member, because the whole point of a tag is that a mod loading
later can add to it - resolving one here would silently miss whatever comes after.

```gdscript
api.register_recipe({"proving:rock": 2}, "proving:plain", 1, {"unlock": "known"})
```

**See also:** `add_recipe`, `defer_tag_recipe`, `is_excluded`, `item`, `item_name`, `qualified`

### `api.register_material(material_name: String, def: Dictionary) -> void`

A material parts can be made of: {display_name, item (raw material item name), color, tier, speed,
durability, damage, handle (durability multiplier as a handle), trait: {name, description, modifiers,
durability_mult, speed_mult, damage_add, glow}}. Every part type gets a recipe for it.

```gdscript
api.register_material("dull", {"display_name": "Dull", "item": "proving:token", "color": "#888888",
	"tier": 2, "speed": 4.0, "durability": 100, "damage": 1.0, "handle": 1.6,
	"trait": {"name": "Plain", "description": "nothing special", "speed_mult": 0.0}})
```

**See also:** `add_material`, `item`, `qualified`

### `api.register_part_type(part_name: String, def: Dictionary) -> int`

A kind of part (registers the part item): {display_name, sprite (grayscale 16x16 image tinted by the
material), cost (material per part), station (where parts are made)}.

```gdscript
api.register_part_type("head", {"display_name": "Head", "cost": 3, "station": "proving:bench"})
```

**See also:** `add_part_type`, `register_asset`, `register_item`

### `api.register_assembly(assembly_name: String, def: Dictionary) -> int`

A tool or weapon built from parts (registers its item): {display_name, icon (shown for plain
stacks), slots: [{name, part, label}], tool_type, damage, cooldown, reach, sweep, station}. The
first slot is the head. Part names without ":" are this mod's.

```gdscript
api.register_assembly("prover", {"display_name": "Prover", "tool_type": "pickaxe", "damage": 3.0,
	"station": "proving:bench", "skill": "proving:steady",
	"slots": [{"name": "head", "part": "head", "label": "Head"},
		{"name": "grip", "part": "handle", "label": "Handle"}]})
```

**See also:** `add_assembly`, `qualified`, `register_item`

### `api.register_minigame(minigame_name: String, def: Dictionary) -> void`

A crafting minigame recipes and assemblies can name as their `skill` (crafting by hand for better
quality; see engine/shared/minigame.gd): {title, type: "timing" | "hold" | "sequence", verb, rounds,
speed, zone, cool, team (bellows + hammer), duration, window}.

```gdscript
api.register_minigame("steady", {"title": "Hold Steady", "type": "timing", "verb": "Strike",
	"rounds": 3, "speed": 1.0, "zone": 0.25})
```

**See also:** `register`

### `api.register_station(station_name: String, def: Dictionary) -> void`

Makes a station upgradable (see engine/server/stations.gd): tiers [{block, title, kit, grants}],
workshop {radius, upgrades: [{block, title, max, grants}]}, multiblock {core, pattern, legend,
title}. grants: {features, tier, speed, quality, pull_radius, hints}. Blocks involved still declare
`station: "<name>"`. Recipes then ask for `tier` and `needs` (features).

```gdscript
api.register_station("bench", {"workshop": {"radius": 2,
	"upgrades": [{"block": "proving:lamp", "title": "Bright", "grants": {"features": ["bright"]}}]}})
```

**See also:** `register`

### `api.get_station(position: Vector3i) -> Dictionary`

The station at a position: {name, title, tier, tier_title, features, speed, quality, pull_radius,
hints, detected, available, next, structure}, or {}.

**See also:** `evaluate`

### `api.register_recipe_category(category_name: String, def := {}) -> bool`

Adds a recipe book tab. def: display_name, icon (item name shown on the tab).

```gdscript
api.register_recipe_category("proven", {"display_name": "Proven", "icon": "proving:token"})
```

**See also:** `item`, `register_category`

### `api.register_container(container_name: String, def: Dictionary) -> bool`

Registers a container type (see engine/server/containers.gd): {title, groups: [{name, count,
columns, label, take_only, accepts}], progress: [{name, label, color}]}. Blocks use it with
`container: "<name>"` and open it on right-click. Names without ":" are this mod's.

```gdscript
api.register_container("crate", {"title": "Crate",
	"groups": [{"name": "items", "count": 6}, {"name": "fuel", "count": 1, "accepts": "fuel"}],
	"progress": [{"name": "work", "label": "Work", "color": "#80ff80"}]})
```

**See also:** `on`, `open_bag`, `qualified`, `register`, `register_item`

### `api.get_container(position: Vector3i)`

The container at a position (engine/server/container.gd), or null.

**See also:** `block_key`, `get_block_data`, `get_block_loaded`, `realm_of`, `set_block_data`, `type_of_block`

### `api.open_container(player, position: Vector3i) -> bool`

Opens a container's screen for a player (as if they right-clicked it).

**See also:** `open`

### `api.set_fuel(item_name: String, seconds: float) -> void`

Makes an item burn in fuel slots for `seconds`.

```gdscript
api.set_fuel("proving:token", 20.0)
```

**See also:** `item`

### `api.get_fuel(item_id: int) -> float`

How many seconds an item burns in a furnace (0 = not fuel).

**See also:** `register_process`

### `api.register_process(kind: String, input: String, output: String, count := 1, seconds := 10.0) -> bool`

A processing recipe machines look up by kind: register_process("smelting", "base:iron_ore",
"base:iron_ingot", 1, 10.0).

```gdscript
api.register_process("grinding", "proving:plain", "proving:rock", 1, 2.0)
```

**See also:** `add_process`, `is_excluded`, `item`, `qualified`

### `api.get_process(kind: String, item_id: int) -> Dictionary`

{output, count, seconds} for an input, or {} when that kind of machine cannot process it.

### `api.lift_assembly(positions: Array, options := {}) -> int`

Takes a set of blocks out of the world and holds them as one moving thing: a platform on a track, a
drawbridge, a contraption somebody built and started. Returns an assembly id, or 0 - and then
`assembly_problem()` says why in words a player can be shown.

The blocks leave the world at once, keeping their state and their data, so nothing is ever in two
places. What moves it, how fast and when it stops are yours; the engine moves blocks and has never
heard of a piston.

**See also:** `lift`, `qualified`

### `api.move_assembly(assembly_id: int, by: Vector3) -> bool`

Moves it, and carries whoever is standing on it. `by` may be fractional - being off the grid is the
entire point.

**See also:** `assembly_problem`, `move`

### `api.settle_assembly(assembly_id: int) -> bool`

Puts it back into the world where it has got to. **Refused if something is in the way**, rather than
landing on top of it - an engine that deletes what somebody built because a machine arrived is not
one to build with. Returns false, and `assembly_problem()` says so.

**See also:** `settle`

### `api.assembly_problem() -> String`

Why the last lift or settle was refused.

**See also:** `register_multiblock`

### `api.fill_container(container, table_name: String, context := {}) -> int`

Fills a container from a loot table, now. The obvious call for a chest that appears when a boss
dies, or a reward handed out at the end of a run.

var chest = api.get_container(where)
api.fill_container(chest, "boss_hoard", {"player": winner})

Rolls into the **empty** slots, leaving anything already in there alone, so filling a chest twice
does not throw away what somebody put in it. Returns how many stacks went in.

The other two ways a container gets loot are still there and still right: a structure's chest
carries `{"loot": "table"}` in its block data and rolls itself the first time it is opened, which
is what a dungeon laid out from a template wants, and `roll_loot` hands back the stacks for a mod
that wants to put them somewhere other than a container. (2026-09-21)

**See also:** `get_item`, `roll_loot`, `set_item`

### `api.show_crafting(player) -> void`

Opens the crafting screen for a player, crafting by hand.

**See also:** `open_crafting`


## Items

### `api.register_item(item_name: String, def: Dictionary) -> int`

Registers a non-block item. `icon` is a texture path; `usable` makes right-click fire item_use.
Returns the item id (>= 256), or -1.

```gdscript
ids.pail = api.register_item("pail", {"display_name": "Pail", "max_stack": 1, "usable": true})
```

**See also:** `is_excluded`, `qualified`, `register`, `register_asset`, `reload`

### `api.drop_item(item_id: int, count: int, position: Vector3, realm_id := "")`

Drops an item stack entity (players walk over it to pick it up).

**See also:** `max_stack`, `qualified`, `register_instance`, `spawn`

### `api.item(item_name: String) -> int`

JavaScript: `item`

Looks up any block or item id by name ("base:coal", or a local name). -1 if unknown.

### `api.item_name(id: int) -> String`

The full name ("mod:name") of a block or item id, or "".

### `api.item_max_stack(id: int) -> int`

How many of this item fit in one slot.

**See also:** `max_stack`

### `api.item_display_name(id: int) -> String`

The name players see for a block or item id.

**See also:** `category`, `key`, `unlock`

### `api.require_item(item_name: String) -> int`

As require_block, for an item or a block (they share an id space).

```gdscript
ev.player.give(api.require_item("proving:prod"), 1)
```

**See also:** `item`

### `api.send_item(from: Dictionary, item_name: String, count := 1, data := {}) -> bool`

Sends a thing along the links to whichever connected face will take it. Returns false if nothing
would, which is how a machine knows to hold on to it rather than dropping it on the floor.

**Things are not a quantity.** A pickaxe with twelve durability and a name somebody gave it cannot
be halved and is not interchangeable with the next one, so this is its own mechanism rather than
power with a different unit - though it travels the same links. Destinations take turns, so a line
of chests fills evenly rather than the first one found swallowing everything.

**See also:** `qualified`, `send`, `tag`

### `api.on_item_arrived(handler: Callable) -> void`

Told when something arrives: {realm, position, face, item, count, data, from}.

**See also:** `on_arrived`


## Mobs and entities

### `api.register_entity(entity_name: String, def: Dictionary) -> int`

Registers an entity type (mob, projectile, object). See EntityRegistry.register for keys. Model and
sprite paths are relative to the mod folder; sound names without a ":" are this mod's.
Returns the type id, or -1.

```gdscript
ids.grazer = api.register_entity("grazer", {"kind": "mob", "display_name": "Grazer",
	"width": 0.8, "height": 1.0, "health": 10, "speed": 2.2, "category": "animal", "persistent": true,
	"taming": {"items": ["proving:grain"], "chance": 1.0, "follow_distance": 3.0, "teleport_distance": 16.0},
	"breeding": {"items": ["proving:grain"], "cooldown": 5.0},
	"nameplate": {"show_health": true},
	# Drops, so it has a loot table another mod can extend - which is what extend_loot is for.
	"drops": [["proving:token", 1], ["proving:grain", 2]],
	"ai": {"preset": "passive", "wander_radius": 6}})
```

**See also:** `folder`, `is_excluded`, `qualified`, `register`, `register_asset`, `reload`

### `api.explode(position: Vector3, power: float, options := {}) -> Dictionary`

Sets off an explosion (see engine/server/explosions.gd): power ~3 is a mob blast. options: source,
break_blocks, drop_chance, damage (multiplier), effect, sound. Returns the explosion event.

**See also:** `blast_resistance`, `break_block`, `cast`, `damage`, `damage_player`, `get_block_v`

### `api.entity_type(entity_name: String) -> int`

Entity type id by name ("vanilla:zombie", or a local name). -1 if unknown.

**See also:** `qualified`

### `api.spawn_entity(entity_name: String, position: Vector3, options := {})`

Spawns an entity. options: yaw, velocity (Vector3), data (Dictionary), owner (player or entity,
for projectiles), **realm** (which world to put it in; the overworld by default). Returns the
entity or null.

`realm` matters for instances: without it every spawn landed in the overworld, so a dungeon could
be entered but never populated. (2026-09-21)

**See also:** `entity_type`, `qualified`, `register_instance`, `spawn`

### `api.spawn_projectile(entity_name: String, from: Vector3, velocity: Vector3, owner = null, realm_id := "")`

Fires a projectile entity from `from` with `velocity`, credited to `owner` (player or entity).

**See also:** `entity_type`, `qualified`, `register_instance`, `spawn`

### `api.get_entities(center: Vector3, radius: float, entity_name := "") -> Array`

Living entities within `radius` of `center`, optionally only of one type.

**See also:** `entity_type`, `in_radius`

### `api.get_entity(entity_id: int)`

The entity with this id, or null if it is gone.

### `api.register_mob_behavior(behavior_name: String, def: Dictionary) -> void`

Registers a mob behaviour that mobs listing it in ai.behaviors can choose. `def`:
score:  Callable(brain) -> float   utility each think; the highest scoring behaviour runs.
Engine scores: idle 0.05, wander 0.1, investigate 0.4, search <= 0.65, engage 0.7-0.9,
return_home 0.95+, flee 1.05, scripted 1.2
update: Callable(brain, delta)     called each think while it runs; use brain.move_to / stop /
look_at, brain.target, brain.entity, brain.can_see_target(), brain.health_fraction()
stop:   Callable(brain)            optional, when another behaviour takes over

```gdscript
api.register_mob_behavior("forage", {
	"score": func(brain): return 0.2 if api.order_of(brain.entity) == "proving:forage" else 0.0,
	"update": func(brain, _delta): brain.stop(),
})
```

**See also:** `qualified`

### `api.make_noise(position: Vector3, radius: float, source = null) -> void`

Lets mobs hear something at `position` (they come to investigate). `source` may be a player.

**See also:** `category`, `place`

### `api.add_spawn_rule(def: Dictionary) -> void`

Natural spawning. def: entity (name), category ("monster" | "animal" | "ambient" | "misc"; default
from the mob's AI), light [min, max] (0-15; monsters default to [0, 7] so torches keep them away,
animals to [9, 15]), place ("any" | "surface" | "underground"), time ("night" | "day" | "any"), on
(block names the mob may stand on; default any), group [min, max] (pack size), max_nearby (per
player), max_total, chance (per player per second), min_distance, max_distance. See
engine/server/spawning.gd for caps and despawning.

```gdscript
api.add_spawn_rule({"entity": "biter", "max_light": 4, "weight": 1, "group": [1, 2]})
```

**See also:** `add_rule`, `block`, `entity_type`, `is_excluded`, `qualified`

### `api.set_spawn_caps(caps: Dictionary) -> void`

How many mobs of each category may be around each player: {monster, animal, ambient, misc}.

```gdscript
var apply_caps := func(): api.set_spawn_caps({"monster": int(caps.get(String(api.setting("monsters")), 24))})
```

**See also:** `set_caps`

### `api.require_entity(entity_name: String) -> int`

As require_block, for an entity type.

**See also:** `entity_type`

### `api.extend_entity(entity_name: String, additions: Dictionary) -> bool`

Adds to a creature another mod owns, without forking it: a new attack on their boss, another drop,
an extra behaviour.

api.extend_entity("proving:grazer", {"ai": {"attacks": [{"name": "kick", "type": "melee"}]}})

**Additive only, and that is the whole design.** Appending to a list is commutative: three mods can
each add an attack and the result does not depend on which loaded last. "Set the health to 40" is
not, and supporting it would mean inventing a conflict system nobody asked for. What can be added:
`ai.attacks`, `ai.behaviors`, `ai.phases` and `drops`. Anything else is refused and says so.

Takes effect for creatures spawned afterwards. One already walking about keeps the brain it was
given, which is why this belongs in `setup()` rather than halfway through a game.

**See also:** `entity_type`, `is_excluded`, `qualified`

### `api.set_spawn_handler(handler: Callable) -> void`

Where a player who has never played here before starts: `handler(player) -> Vector3`.

This runs before the world around it is loaded, so it is also the right place to *build* the thing
the player should open their eyes on. Placing a structure from `player_join` instead is too late -
the player has already been put at the old position and sees themselves moved. (playtest, 2026-09-18)

```gdscript
api.set_spawn_handler(func(_player): return Vector3(0.5, GROUND_Y + 1, 0.5))
```


## World generation

### `api.place_structure_in(template_name: String, at: Vector3i, realm_id := "", rotation := 0) -> bool`

Pastes a saved structure into a world. `realm_id` is which world - without it a dungeon's rooms
were built in the overworld while the players stood in an empty instance. (2026-09-21)

**See also:** `follow`, `place`, `qualified`, `register_instance`

### `api.set_world_generator(generator: Object, realm_id := "") -> void`

`generator` must implement `generate(chunk)`; write into a local copy of `chunk.blocks`
(index with Chunk.index(x, y, z)) and assign it back for speed.

```gdscript
api.set_world_generator(FlatGround.new(api.require_block("proving:rock"), api.require_block("proving:soil"), api.require_block("proving:turf")))
```

**See also:** `qualified`, `register_instance`, `reload`

### `api.use_biome_generator(options := {}, realm_id := "") -> Object`

Turns on the engine biome generator (engine/server/worldgen/biome_generator.gd) for this world.
options: sea_level, snow_level. Register biomes and features before or after; returns the generator.

**See also:** `biome_generator`, `qualified`, `register_instance`

### `api.biome_generator(realm_id := "") -> Object`

The shared biome generator (created on first use, even if the game uses its own generator).

**See also:** `block`, `qualified`, `register_instance`

### `api.register_biome(biome_name: String, def: Dictionary, realm_id := "") -> void`

A biome for the biome generator: {climate, ocean, height, surface, features, plants}. See BiomeGenerator.

```gdscript
api.register_biome("plain", {"climate": [0.4, 0.6], "height": [0.0, 0.2],
	"surface": "proving:turf", "features": [], "plants": []})
```

**See also:** `add_biome`, `biome_generator`, `qualified`

### `api.add_cave_carver(options := {}) -> void`

Carves caves, caverns and ravines into the biome generator's terrain (see worldgen/cave_carver.gd).
options: tunnels, caverns, ravines (bools), lava (block name), lava_level, water_level, min_y,
entrance_chance.

**See also:** `biome_generator`, `block`

### `api.register_structure_template(template_name: String, source) -> bool`

A structure template: a JSON file in this mod (e.g. "structures/tower.json", saved with /struct save)
or a template dictionary. Names without ":" are this mod's.

```gdscript
api.register_structure_template("hut", {"size": [2, 1, 2], "palette": ["proving:rock"],
	"blocks": [[0, 0, 0, 0], [1, 0, 0, 0], [0, 0, 1, 0], [1, 0, 1, 0]]})
```

**See also:** `add_template`, `biome_generator`

### `api.place_structure(template_name: String, at: Vector3i, rotation := 0) -> bool`

Generated structures (see worldgen/structures.gd): {templates: [{template, weight}] or generator
(GDScript Callable), spacing, separation, biomes, place, y, sink, foundation, swaps, reach, chance}.
Stamps a template into the world now, rotated a quarter turn at a time (0-3). What `/struct place`
does, for a mod that wants to build something itself rather than leave it to world generation: a
story's outpost, a rescue site, a prize somebody hid.

**See also:** `place`, `qualified`

### `api.register_structure(structure_name: String, def: Dictionary) -> void`

```gdscript
api.register_structure("hut_site", {"template": "proving:hut", "rarity": 0.0})
```

**See also:** `add_set`, `biome_generator`, `qualified`, `register_loot`

### `api.register_loot(table_name: String, def: Dictionary) -> void`

Declares what something gives: a mob that dies, a block that breaks, a chest, a reward (docs/loot.md).

api.register_loot("zombie", {"pools": [
{"rolls": [0, 2], "entries": [{"item": "base:rotten_flesh", "count": [1, 2], "weight": 3},
{"empty": true, "weight": 1}]},
{"rolls": 1, "when": {"killed_by": "player"}, "entries": [{"item": "base:iron_ingot", "weight": 1},
{"empty": true, "weight": 20}]},
]})

Pools roll on their own, so each is one idea ("some flesh" / "rarely, iron"). An entry names an `item`,
another `table` to roll instead, or `empty: true` for the miss; `weight` is relative within its pool,
`count` is a number or [min, max], `data` is the item data the stack carries. `when` on a pool or an
entry takes killed_by, tool, biome, depth, time, chance and first_time. An entity or block can name its
table with `loot: "<name>"`; without one, its `drops` list is read as a table.
Tables can also be JSON files: every loot/*.json in the mod folder registers as "<mod>:<file name>".

```gdscript
api.register_loot("crate_loot", {"pools": [
	{"rolls": 1, "guaranteed": true, "entries": [{"item": "proving:token", "count": [1, 3]}]}]})
```

**See also:** `qualified`, `register`

### `api.register_loot_table(table_name: String, def: Dictionary) -> void`

Same as register_loot (the name it had before tables were used for everything).

```gdscript
api.register_loot_table("bench_loot", {"pools": [
	{"rolls": 1, "entries": [{"item": "proving:rod", "count": [1, 1]}]}]})
```

**See also:** `extend_entity`, `register_loot`

### `api.extend_loot(table_name: String, def: Dictionary) -> void`

Adds pools to a table another mod owns, without forking it: an extra drop on their mob, a bonus in
their dungeon chests.

**See also:** `extend`, `fill_container`, `get_container`, `qualified`

### `api.roll_loot(table_name: String, context := {}) -> Array`

Rolls a table and returns [[item id, count, data], …], for anything the engine does not roll itself
(fishing, a quest reward, a prize crate). `context` may carry player, cause, tool, position and seed.

**See also:** `qualified`, `roll`

### `api.loot_sources(item_name: String) -> Array`

What a mob, block or table gives, without rolling: everything it could drop, as
[{item, chance, count, table}]. This is what the guide's "what drops this?" is built from.

**See also:** `qualified`, `sources_of`

### `api.set_loot_rate(multiplier: float) -> void`

How much everything drops, as a multiplier (1.0 is normal). A host's "how much loot" setting.

### `api.get_loot_rate() -> float`

**See also:** `set_loot_boost`

### `api.set_loot_boost(target: String, factor: float, seconds := 0.0) -> void`

Turns one thing up (or down) for a while, for an event: `target` is a table or an item name, `factor`
how much more often it comes up, `seconds` how long (0: until it is changed back).

api.set_loot_boost("base:coal", 3.0, 3600.0)     # coal everywhere, for an hour
api.set_loot_boost("vanilla:dungeon", 2.0)       # richer dungeon chests until further notice

**See also:** `qualified`, `set_boost`

### `api.register_feature(feature_name: String, def, realm_id := "") -> void`

A world feature (tree, cactus, boulder, spike, huge mushroom, patch) as data {type, ...} or, from
GDScript, a Callable(writer, origin: Vector3i, rng) run on worker threads. See worldgen/features.gd.

```gdscript
api.register_feature("boulder", {"type": "boulder", "block": "proving:rock", "radius": [1, 2]})
```

**See also:** `add_feature`, `biome_generator`, `get_eye_position`, `look_direction`, `raycast`

### `api.get_biome(position: Vector3) -> String`

Name of the biome at a column ("" without the biome generator).

**See also:** `biome_at`

### `api.add_generation_pass(pass_object: Object, realm_id := "") -> void`

Adds a pass run after the world generator for every new chunk, on worker threads:
`pass_object.decorate(chunk, world_seed)`. Lets add-on mods put ores or structures in any game.

**See also:** `qualified`, `register_instance`

### `api.add_ore_pass(def: Dictionary, realm_id := "") -> void`

Scatters veins of `ore` inside `replace` in every new chunk. def: ore, replace (block names),
veins (per chunk), size (blocks per vein), min_y, max_y, chance (per vein, 0-1).
`realm_id` puts the ore in another world instead of the one the server starts with - the Emberdeep
wants its own ores, and they are not the overworld's at a different depth.

**See also:** `add_generation_pass`, `block`


## Blocks and the world

### `api.register_block(block_name: String, def: Dictionary) -> int`

Registers a block. `name` is namespaced to this mod. Texture and model paths are relative to the
mod folder. See BlockRegistry.register for keys (render, light, interactive, model, ...). Extra keys
(e.g. `drops`: "base:cobblestone" or "") are kept server-side.
Returns the runtime block id, or -1 on error.
Beds: `bed: true` (right-click sets the respawn point and sleeps at night). Two-block pieces:
`pair: {block, direction: "back" | "front" | "up" | "down"}` places `block` next to it (relative to
the facing of an `orientation: "horizontal"` block) and removes both together; give the second half
the opposite direction and `placeable: false`.
`contact_damage: {amount, interval, cause}` hurts players and mobs whose body is inside the block
(lava).

```gdscript
ids.wire = api.register_block("wire", {"display_name": "Wire",
	"hardness": 0.5, "signal_carry": true, "connect_group": "proving_signal"})
```

**See also:** `expand_textures`, `is_excluded`, `qualified`, `register`, `register_asset`, `reload`

### `api.register_block_tick(block_name: String, handler: Callable, options := {}) -> bool`

Makes blocks of a type change over time. `handler(ctx)` gets {position, block, state, ticks, reason,
payload, elapsed, realm}: "random" ticks come about every options.interval seconds (default 30) per
block, and "scheduled" ticks come from schedule_block_tick. **Use ctx.realm** when reading or
writing blocks: a position does not say which world it is in.

Blocks only tick while somebody is near enough for the server to be running that part of the world.
A block that was asleep - because its chunk was unloaded, or because everybody walked away - is
handed the ticks it missed at once when it wakes (`ticks` > 1) unless options.catch_up is false.
`ticks` is capped, so returning to a world after a week does not run a week of growth in one frame;
`elapsed` is the true number of seconds it stood still, for a handler that would rather work the
answer out itself.

```gdscript
api.register_block_tick("lamp", func(ctx):
	api.set_block_data(ctx.position, {"ticked": int(api.get_block_data(ctx.position).get("ticked", 0)) + 1}),
	{"interval": 5, "random": false})
```

**See also:** `block`, `is_excluded`, `qualified`, `register`

### `api.schedule_block_tick(position: Vector3i, seconds: float, payload := {}) -> void`

Calls the tick handler of the block at `position` after `seconds`, with `payload` (saved with the world).

**See also:** `schedule`

### `api.get_light(position: Vector3i) -> int`

Light level 0-15 at a position right now: block light or sky light scaled by daylight, whichever is
brighter. An estimate (no occlusion) meant for growth and spawning rules.

**See also:** `get_daylight`, `light_at`

### `api.get_light_levels(position: Vector3i) -> Dictionary`

{sky, block} light levels 0-15 (sky not scaled by the time of day).

**See also:** `light_levels`

### `api.get_world_clock() -> float`

Seconds of world time that have passed (keeps counting across restarts, not while stopped).

### `api.break_block(position: Vector3i, drop := true, realm_id := "") -> void`

Breaks a block as if mined without a player: drops its items (when `drop`) and plays its sound.
Fires block_destroyed {position, block, drops} (drops may be changed).

**See also:** `block_changed`, `block_removed`, `block_state`, `break_block`, `chunk_coord_at`, `clear_block_data`

### `api.block_textures(block_name: String) -> Array`

Looks up a block id by name ("base:stone", or "stone" for this mod's own). -1 if unknown.
The texture names a block uses, so a slab or stairs can be made of the same material.

**See also:** `block`, `item`

### `api.require_block(block_name: String) -> int`

The id of something this mod cannot work without. `block`, `item` and `entity_type` answer a
*question* - "is this installed?" - and return -1 for no, which mods rely on to make optional
content optional (`if api.item("other:thing") > 0`). These state a *requirement* instead: a name
that is not there is an error, said out loud at load with the mod that asked.

**Use these for anything you keep.** A -1 stored in a generator, a cached field or a table becomes
65535 when it is written as the u16 a block id is - and 65535 is UNLOADED, so the world reads as
absent rather than wrong. Three bugs in one day came from that, all of them a question's answer
being used as a contract. (2026-09-21)

```gdscript
ev.player.set_hotbar([api.require_block("proving:plain"), api.require_block("proving:lamp"),
	api.require_block("proving:crate"), api.require_block("proving:rock"),
	api.require_block("proving:step")], 64)
```

**See also:** `block`

### `api.block(block_name: String) -> int`

JavaScript: `block`

### `api.block_name(id: int) -> String`

The full name ("mod:name") of a block id, or "".

### `api.block_display_name(id: int) -> String`

The name players see for a block id.

### `api.register_multiblock(pattern_name: String, def: Dictionary) -> bool`

A machine somebody assembles out of blocks. Described as layers of characters, bottom first, the
way anybody would draw it on paper:

api.register_multiblock("forge", {
"layers": [["BBB", "BBB", "BBB"],
["B B", " C ", "B B"]],
"key": {"B": "base:brick", "C": "base:furnace"},
"controller": "C"})

A space means "do not care". A key may name a **tag** with `#`, so "any log" works and a mod adding
a tree joins in. The controller is where the machine's data lives - where a player right-clicks and
where the inventory hangs.

You are told when one is finished or spoiled (`multiblock_formed`, `multiblock_broken`), and can ask
at any time with `multiblock_at`. The engine does not *remember* which are built: that would mean
saving a fact that can be worked out from the blocks, and a saved fact can disagree with them.

```gdscript
api.register_multiblock("engine", {
	"layers": [["PPP", "PCP", "PPP"]],
	"key": {"P": "#proving:stone_like", "C": "proving:core"},
	"controller": "C"})
```

**See also:** `qualified`, `register`

### `api.multiblock_at(controller: Vector3i, pattern_name := "", realm_id := "") -> Dictionary`

The machine whose controller is at this position, or {}: {name, controller, origin, cells}.

**See also:** `at`, `qualified`, `register_instance`, `register_liquid`

### `api.extend_block(block_name: String, additions: Dictionary) -> bool`

Adds to a block another mod owns. `drops` is the one list a block has; everything else about a block
is baked into lookup tables at registration and cannot change afterwards.

**See also:** `block`, `is_excluded`, `qualified`

### `api.get_block(pos: Vector3i, realm_id := "") -> int`

Loads the chunk if needed. Use get_loaded_block when scanning large areas.

```gdscript
if api.get_block(at, realm_id) != int(ids.slime):
```

**See also:** `get_block_loaded`, `qualified`, `register_instance`

### `api.get_loaded_block(pos: Vector3i, realm_id := "") -> int`

Block id without loading anything; BlockRegistry.UNLOADED (255) if the chunk is not in memory.

**See also:** `collides`, `get_block_v`, `qualified`, `register_instance`

### `api.is_solid(block: int) -> bool`

Whether a block id collides (unloaded space counts as solid).

### `api.is_breakable(block: int) -> bool`

Whether players can break a block id.

### `api.get_drops(block: int) -> Array`

What breaking this block yields by default: [[item id, count], ...].

**See also:** `get_block`, `set_block`

### `api.set_block(pos: Vector3i, id: int, realm_id := "", keep_data := false, state := 0) -> void`

Sets a block authoritatively (loading its chunk if needed) and replicates it to players. Block
data at the position is cleared when the block type changes unless `keep_data` is true.

**`realm_id` comes third, like everywhere else.** It used to sit fifth, behind `keep_data` and
`state`, which made this the only one of the eight block functions that did not take the realm
straight after its required arguments - `get_block`, `get_block_state`, `get_block_data`,
`set_block_data`, `clear_block_data`, `sees_sky` and `fill` all do. Anyone who had learned
`get_block(pos, realm)` wrote `set_block(pos, id, realm)` and put a realm where a bool goes.

That mistake is loud (GDScript refuses the conversion, names the file and line, and aborts the
call), so nothing was ever silently wrong. It was simply a trap the signature laid, and there is no
reason for the odd one out to stay odd. (2026-09-21)

```gdscript
api.set_block(at, 0, realm_id)
```

**See also:** `qualified`, `register_instance`, `set_block_authoritative`

### `api.get_block_state(pos: Vector3i, realm_id := "") -> int`

Per-block state byte (e.g. facing 0-3 for "orientation": "horizontal" blocks).

```gdscript
if api.get_block_state(at, realm_id) != 0:
```

**See also:** `block_state`, `chunk_coord_at`, `index`, `qualified`, `register_instance`

### `api.facing_from_yaw(yaw: float) -> int`

Facing (0-3) an oriented block gets when placed by someone looking along `yaw`.

**See also:** `block`

### `api.facing_direction(state: int) -> Vector3i`

Front direction of an oriented block (+Z/+X/-Z/-X for facing 0-3).

### `api.get_block_data(pos: Vector3i, realm_id := "") -> Dictionary`

Block data ("block entities"): a Dictionary of JSON-compatible values stored with the world and
removed automatically when the block is broken or replaced.

**See also:** `chunk_coord_at`, `qualified`, `register_instance`

### `api.set_block_data(pos: Vector3i, data: Dictionary, realm_id := "") -> void`

Replaces the data dictionary stored with the block at a position (saved with the world).

```gdscript
api.set_block_data(ctx.position, {"level": int(ctx.level)}))
```

**See also:** `add_chunk`, `block`, `chunk_coord_at`, `chunk_path`, `decorate`, `generate`

### `api.clear_block_data(pos: Vector3i, realm_id := "") -> void`

Removes the data stored with the block at a position.

**See also:** `chunk_coord_at`, `qualified`, `register_instance`

### `api.find_block_data(block := -1, realm_id := "") -> Array[Vector3i]`

Loaded positions that carry block data, optionally filtered to one block id.

**See also:** `get_block_v`, `qualified`, `register_instance`

### `api.set_world_time(time_of_day: float, day_length := -1.0) -> void`

time_of_day: 0 = midnight, 0.25 = sunrise, 0.5 = noon. day_length in seconds (0 freezes time).

**See also:** `daylight`, `get_day_length`, `phase`

### `api.get_time_of_day() -> float`

The time of day from 0 to 1 (0 midnight, 0.25 sunrise, 0.5 noon, 0.75 sunset).

### `api.get_daylight() -> float`

Sky brightness in [0.12, 1] for the current time of day.

**See also:** `block`, `daylight`, `get_time_of_day`

### `api.sees_sky(pos: Vector3i, realm_id := "") -> bool`

True if nothing opaque or solid is above the block (it can see the sky).

**See also:** `area_cells`, `get_block`

### `api.fill(from: Vector3i, to: Vector3i, id: int, realm_id := "") -> void`

JavaScript: `fill`

Sets every block in the box between two corners (inclusive) to a block id.

**Admin, not a player action**: no permission check, no events, no budget, no drops. For a tool a
player holds, use `area_edit`, which asks all of those.

### `api.surface_y(x: int, z: int, realm_id := "") -> int`

Y of the highest non-air block in the column, or -1.

**See also:** `qualified`, `register_instance`, `surface_height`


## Players and gameplay

### `api.players() -> Array`

JavaScript: `players`

Everyone playing on this server right now, as an Array of players.

**See also:** `register_weather`

### `api.set_player_rig(def: Dictionary) -> void`

Replaces the player character rig for this server (see engine/shared/player_rig.gd).

**See also:** `reload`, `sanitize`

### `api.register_cosmetic(cosmetic_name: String, def: Dictionary) -> String`

Registers a server cosmetic players can wear on this server (see engine/shared/cosmetics.gd for
the def: category, paint, pixels, boxes, texture, model, color, covers, unlocked...). `texture` and
`model` are paths in this mod. `unlocked: false` makes it wearable only after player.grant_cosmetic.
Returns the cosmetic's full name ("mod:name"), or "" when invalid.

```gdscript
api.register_cosmetic("cap", {"category": "hat", "display_name": "Cap", "unlocked": true,
	"boxes": [{"from": [-4, 8, -4], "size": [8, 2, 8], "color": "#4488cc"}]})
```

**See also:** `attach`, `register`, `register_asset`, `reload`

### `api.register_cosmetic_category(category_name: String, def := {}) -> bool`

Adds a cosmetic category. def: display_name, attach (rig attachment point for boxes and models),
covers (armor slots its cosmetics replace by default).

```gdscript
api.register_cosmetic_category("hat", {"display_name": "Hats"})
```

**See also:** `register_category`

### `api.set_cosmetics_policy(values: Dictionary) -> void`

Sets how cosmetics work on this server. values (any subset):
allow_builtin: players may wear built-in cosmetics (their own look from other servers)
allow_colors:  players may recolor cosmetics and choose skin colors
armor: "player" (each player chooses per slot), "armor" (armor always shows), "cosmetics"
blocked: [cosmetic names or categories]
uniform: avatar data laid over every player, e.g. {wear: {shirt: {id: "builtin:tshirt", color: "#d94c4c"}}}
For per-player looks (teams, disguises) use player.set_avatar_override or the avatar_change event.

**See also:** `refresh_avatar`, `set_policy`

### `api.register_equipment_slot(slot_name: String, def := {}) -> bool`

Adds an equipment slot (after head, chest, legs, feet, offhand). Items with a matching
`equip_slot` go in it; its modifiers apply while worn. def: display_name.

```gdscript
api.register_equipment_slot("charm", {"display_name": "Charm"})
```

**See also:** `get_stat`, `register_slot`

### `api.register_stat(stat_name: String, base: float) -> bool`

Adds a player stat with a base value. Items and effects change it with modifiers; read it with
player.get_stat(name). Engine stats: see ItemRegistry.BASE_STATS.

```gdscript
api.register_stat("proving:resolve", 1.0)
```

**See also:** `can_see_target`, `health_fraction`

### `api.set_gameplay(values: Dictionary) -> void`

Game-wide rules: item_drops ("entity" | "inventory"), keep_inventory, pvp, fall_damage,
natural_regeneration, mob_spawning.

```gdscript
api.set_gameplay({"keep_inventory": true, "natural_regeneration": true, "tutorials": true})
```

### `api.get_gameplay(rule: String)`

A gameplay rule's current value (see set_gameplay), or null.

### `api.player_roles(player_id: String) -> Array`

A player's roles by player id (the default role included).

**See also:** `roles_of`

### `api.set_player_role(player_id: String, role: String, on := true) -> bool`

Gives (or takes) a role. Returns whether anything changed.

**See also:** `give`, `take`

### `api.set_physics(values: Dictionary) -> void`

Movement tunables (walk_speed, sprint_speed, gravity, jump_velocity, ...) and `void_below`.

**See also:** `set_rules`

### `api.get_players() -> Array`

Everyone online (player objects).

### `api.find_player(player_name: String)`

The online player with this name (any case), or null.

### `api.broadcast(text: String) -> void`

JavaScript: `broadcast`

Sends a chat message to everyone.

**See also:** `add_death_messages`, `broadcast_chat`


## Sounds, effects and assets

### `api.register_sound(sound_name: String, files, options := {}) -> int`

Registers a sound from one or more audio files in the mod folder (.ogg or .wav; a random one plays
each time). options: volume (0-2), pitch, pitch_variance, range (blocks). Returns the sound id.

```gdscript
api.register_sound("chime", "music/daylight.ogg", {"volume": 0.4, "range": 24.0})
```

**See also:** `register`, `register_ambience`, `register_asset`, `reload`

### `api.register_effect(effect_name: String, def: Dictionary) -> int`

Registers a visual effect: particle emitters, light flash, camera shake and sound (see
engine/shared/effect_registry.gd). Emitter textures are paths in this mod or "soft", "spark",
"star", "square". Returns the effect id, or -1.

```gdscript
api.register_effect("puff", {"particles": 12, "color": "#cccccc", "scale": 1.0, "duration": 0.6})
```

**See also:** `damage`, `qualified`, `register`, `register_asset`, `reload`

### `api.play_effect(effect_name: String, position: Vector3, options := {}) -> void`

Plays an effect for everyone in range. options: color ("#rrggbb", tints it), scale, direction
(Vector3), duration (seconds for continuous emitters), follow (an entity or player it moves with).
Built in: engine:hit, engine:crit, engine:smoke, engine:sparkle, engine:magic, engine:heal,
engine:dust, engine:explosion.

```gdscript
api.play_effect("puff", at + Vector3(0, 1, 0), {"scale": 1.0})
```

**See also:** `clean_options`, `follow`, `qualified`

### `api.play_sound(sound_name: String, position: Vector3, volume := 1.0, pitch := 1.0) -> void`

Plays a sound at a world position for everyone in range.

**See also:** `play_sound_at`, `qualified`

### `api.register_asset(relative_path: String, options := {}) -> String`

Makes a file from this mod's folder downloadable by clients. Returns its asset name.
options: {lazy} - a lazy asset is listed for the client but not part of the download it waits through
to join; it is fetched the first time something needs it. Use it for anything big and optional (music
is the reason it exists). Anything the world cannot be drawn without must stay eager.

```gdscript
api.register_asset("music/night.ogg", {"lazy": true})
```

**See also:** `add_asset`, `reload`

### `api.start_effect(effect_name: String, position: Vector3, options := {}, realm_id := "") -> int`

An effect that keeps going until you stop it, at a place. Returns a handle, or 0.

`play_effect` is a burst that forgets itself, which cannot say "this machine is working now".
Whoever walks up to a running machine sees it working, not only whoever was there when it started.

**See also:** `clean_options`, `qualified`, `realm_of`

### `api.stop_effect(handle: int) -> bool`

Stops one started with start_effect.


## Server

### `api.storage: Dictionary  (property)`

Persistent Dictionary owned by this mod, saved with the world.


## Everything else

### `api.reloading := false  (property)`

True while the mod's setup re-runs for a quick reload (see engine/server/mod_reload.gd): blocks,
items and entities that exist update in place; things that cannot change live are skipped and noted.

### `api.register_ambience(options: Dictionary) -> String`

Registers an occasional atmospheric sound near a player: wind out in the open, a drip in the dark,
water lapping by a lake. Returns "" or why it was refused.

api.register_ambience({"sound": "wind", "sky": true, "every": [20.0, 45.0]})
api.register_ambience({"sound": "drip", "sky": false, "depth": [0, 45], "every": [8.0, 25.0]})
api.register_ambience({"sound": "lapping", "near": ["base:water"], "radius": 6})

Conditions: `sky` (true outdoors, false under something), `depth` [low, high], `biome` (one or a
list), `near` (block names - the sound then comes *from* one of them, so water laps from the water),
`radius`, `chance`. `every` is [minimum, maximum] seconds, kept per player, so two people in
different places hear their own surroundings rather than each other's.

In the engine rather than in a mod because otherwise every mod that wanted weather or caves would
write the same four decisions - how often is too often, how far can it be, who else hears it, what
about somebody asleep - and none of them would agree.

```gdscript
api.register_ambience({"sound": "proving:chime", "sky": true, "every": [20.0, 45.0]})
```

**See also:** `register`, `set_default_role`

### `api.set_default_role(role_name: String) -> String`

The role every player has unless somebody gives them another. This is how a mod makes a story: the
stock "visitor" role is chat and interact with no build, so the valley stays as its author left it
while doors, chests and levers still work.

api.set_default_role("visitor")   # a world to walk through, not one to change

Story mode needed no new capability in the end: "build" has been a permission since roles existed,
the engine already refuses a break or a place without it, tells the player why (once every three
seconds, not once a click) and puts the block back on the client that predicted it. All that was
missing was a mod being able to say which role people start in. Returns "" or why not.

**See also:** `exists`

### `api.register_weather(weather_name: String, def: Dictionary) -> int`

Registers a kind of weather. The engine draws it and keeps everyone in the same sky; the mod decides
what it looks like and when it happens.

api.register_weather("rain", {
"emitter": {"amount": 220, "lifetime": 1.1, "speed": [16, 20], "direction": [0, -1, 0],
"spread": 3, "size": [0.05, 0.05], "colors": ["#9fc4e8aa"], "shape": "box",
"extents": [18, 1, 18]},
"sound": "rain", "sky_tint": "#6a7686", "light_scale": 0.72})

`emitter` is the same shape as an effect's (see register_effect), drawn continuously above whoever is
out in it. `sound` loops while it falls, `sky_tint` colours the sky, `light_scale` darkens the world,
`fog` closes the distance in.

**When it rains is not here.** That is a mod's decision and games want wildly different answers - a
survival world on a timer, a story where the storm arrives because the story says so.

```gdscript
api.register_weather("haze", {"display_name": "Haze", "darkness": 0.2, "particles": "puff"})
```

**See also:** `qualified`, `register`, `reload`

### `api.set_weather(weather_name: String, options := {}) -> void`

Starts weather for everyone, or stops it with "". `seconds` of 0 leaves it until something changes it.

### `api.get_weather() -> Dictionary`

What the sky is doing: {name, intensity}. `name` is "" when it is clear.

**See also:** `register_music`, `weather_state`

### `api.register_music(track_name: String, file: String, options := {}) -> int`

Registers a music track. `attribution` is required: say who made it and under what licence.

api.register_music("valley", "music/valley.ogg", {
"attribution": "Kevin MacLeod - Meadow (CC0)", "volume": 0.8})

The audio is registered as a *lazy* asset, so it does not join the download a player waits through to
get in; it arrives quietly afterwards and the track starts when it is ready. Nothing is ever held up
waiting for music, which is the whole reason the lazy lane exists.

Attribution is required rather than encouraged because whoever runs a server is redistributing this
to their children and anyone else who joins, and a track whose source nobody wrote down is one whose
licence nobody can check later. `/music` shows the credits in game.

```gdscript
api.register_music("daylight", "music/daylight.ogg", {"volume": 0.9, "attribution": credit})
```

**See also:** `register`, `register_asset`, `reload`

### `api.play_music(player, track_name: String, options := {}) -> void`

Starts a track for one player, or for everybody when `player` is null. Playing the track that is
already playing does nothing, so this is safe to call every time the biome or the time of day
changes - which is how a mod will actually want to use it.

options: {fade (seconds to cross over, default 2.0), restart (start again even if it is already
playing, default false)}.

```gdscript
api.play_music(ev.player, "night" if api.get_daylight() < 0.3 else "daylight", {"fade": 6.0}))
```

**See also:** `send_music`

### `api.stop_music(player, options := {}) -> void`

Fades the music out for one player, or for everybody when `player` is null.

**See also:** `send_music`

### `api.set_map_marker(player, marker_id: String, marker: Dictionary) -> void`

Puts a marker on a player's map and compass (it stays until removed).
`marker` = {label, position, color, dimension}. Markers are per player, so a home or a grave only shows
to whoever it belongs to. `dimension` ("" = the ordinary world) hides it while they are somewhere else.

**See also:** `dimension_of`

### `api.clear_map_marker(player, marker_id: String) -> void`

Takes a marker off a player's map.

### `api.set_world_marker(marker_id: String, marker: Dictionary) -> void`

Puts a marker on everyone's map and compass (a village, a shared base, an event). Saved with the world.
`marker` = {label, position, color, dimension} ("" = the ordinary world).

### `api.clear_world_marker(marker_id: String) -> void`

Takes a marker off everyone's map.

### `api.open_bag(player, slot: int) -> bool`

Opens the bag a player is carrying in one of their own inventory slots.

A bag is an item whose definition names a `container` type, the way a chest block does. Its
contents live in the item's own data, so it holds what it holds wherever it goes - into a chest,
onto the floor, into somebody else's hands - with no bookkeeping to keep the two in step.

api.register_item("satchel", {"display_name": "Satchel", "container": "proving:satchel"})
api.on("item_use", func(ev): api.open_bag(ev.player, ev.player.selected_slot))

A bag cannot be put inside a bag; the engine refuses it, because a container that can contain
itself is a duplication bug waiting for somebody to find it.

```gdscript
if not api.open_bag(player, player.selected_slot):
```

**See also:** `open_item`, `shared_store`

### `api.shared_store(store_name: String, container_type: String) -> bool`

Declares a store that is the same contents wherever it is opened. Returns false if the container
type is unknown.

**Whose it is, is the name's business.** One vault for the server is `shared_store("vault", ...)`;
one each is `shared_store("vault_" + p.player_id, ...)`. The engine keeps a table of names, which
is why it does not need to know which you meant.

```gdscript
api.shared_store("vault", "vault")
```

**See also:** `declare_store`

### `api.open_shared(player, store_name: String) -> bool`

Opens a shared store for a player. Declare it with `shared_store` first.

```gdscript
api.open_shared(player, "vault"))
```

**See also:** `open_store`

### `api.get_shared(store_name: String)`

The contents of a shared store without opening a screen, for a mod that wants to read or fill one.
Returns null if it was never declared.

**See also:** `store_key`

### `api.play_decal(position: Vector3, normal := Vector3i.UP, look := {}, realm_id := "") -> void`

Leaves a mark on the world: scorch where a blast went off, a stain under something leaking.
look: {color, size, seconds} - no seconds leaves it until older marks push it out.

It projects onto whatever is underneath, so it follows the shape of the ground and does not have to
know what it landed on. `normal` turns it to lie on a wall rather than the floor.

```gdscript
api.play_decal(at - Vector3(0, 0.5, 0), Vector3i.UP, {"color": "#222222", "size": 2.0})
```

**See also:** `qualified`, `realm_of`

### `api.screen_tint(player, look := {}) -> void`

Washes a colour over one player's view: underwater, poisoned, standing too near the fire.
look: {color, strength 0-1, seconds} - no seconds holds it until it is changed or cleared, which is
what "underwater" wants; seconds fades it out, which is what a flash wants. strength 0 clears it.

A tint on the *view*, which nothing could do before - weather colours the sky and the fog, and that
is not the same thing. It obeys the player's accessibility setting for flashes, because a
full-screen colour is exactly what somebody may need turned down and a mod should not overrule it.

```gdscript
api.screen_tint(player, {"color": "#3366aa", "strength": 0.3})
```

### `api.play_beam(from: Vector3, to: Vector3, look := {}, realm_id := "") -> void`

Draws a line between two places for a moment: a spell going off, an arc of lightning, a beam
holding something up. look: color, width, seconds, sag (0 is straight, higher hangs).

Its own call rather than an effect with a shape, because an emitter says "from here, outwards" and
can never say "from here to there".

```gdscript
api.play_beam(at + Vector3(0, 1, 0), at + Vector3(0, 1, 6), {"color": "#88ddff", "seconds": 0.5})
```

**See also:** `qualified`, `realm_of`

### `api.found_company(company_name: String, founder_id: String) -> int`

A group of players that things can belong to: a guild, a town, a crew. Returns its id, or 0.

**Separate from plots on purpose**, though a plot is the obvious thing for one to own: plenty of
servers want groups without land, and plenty want land without groups. What a rank means is yours -
the engine only keeps who is in what and what they are called, and holds one opinion of its own:
the last owner cannot leave or be demoted, because a company nobody owns cannot be wound up and
everything it holds becomes unreachable.

**See also:** `create`

### `api.disband_company(company_id: int) -> bool`

**See also:** `disband`

### `api.set_company_rank(company_id: int, player_id: String, rank: String) -> bool`

Ranks are "member", "officer", "owner", least to most.

**See also:** `set_rank`

### `api.remove_from_company(company_id: int, player_id: String) -> bool`

### `api.company_rank(company_id: int, player_id: String) -> String`

**See also:** `rank_of`

### `api.company_at_least(company_id: int, player_id: String, rank: String) -> bool`

Whether somebody is at least this rank.

**See also:** `at_least`

### `api.companies_of(who) -> Array`

Every company somebody is in: [{id, name, rank}].

**See also:** `of_player`

### `api.claim_plot(from: Vector3i, to: Vector3i, options := {}) -> int`

Marks out a piece of ground with an owner. The engine asks before letting anybody change a block
inside it, on every edit path at once. Returns the plot id, or 0 - and `plot_problem()` says why.

api.claim_plot(from, to, {"owner": player.player_id, "name": "Rowan's garden"})
api.claim_plot(from, to, {"company": guild_id})

**What may be claimed, how much and what it costs are yours.** The engine stores a box and an owner
and enforces it. Plots may not overlap - two owners of one block is a question with no good answer -
and admins are never stopped, because somebody has to be able to put right a plot marked over a
village.

**See also:** `claim`, `qualified`

### `api.release_plot(plot_id: int) -> bool`

**See also:** `release`

### `api.plot_problem() -> String`

### `api.plot_at(position: Vector3i, realm_id := "") -> Dictionary`

The plot a block is in, or {}.

**See also:** `at`, `qualified`

### `api.may_build(player, position: Vector3i, realm_id := "") -> bool`

Whether this player may change a block here. The engine already asks this itself before any edit;
this is for a mod that wants to check before offering something.

**See also:** `at`, `may_build_in`, `qualified`

### `api.add_plot_member(plot_id: int, player_id: String) -> bool`

**See also:** `add_member`

### `api.remove_plot_member(plot_id: int, player_id: String) -> bool`

**See also:** `remove_member`

### `api.plots_of(who) -> Array`

Every plot somebody has a say in.

**See also:** `of_player`, `register_objective`

### `api.register_objective(objective_name: String, def: Dictionary) -> bool`

Something a player has been asked to do: a story, a daily errand, a contract, a delivery.

api.register_objective("deliver_the_post", {"display_name": "The Post",
"steps": [{"text": "Take the letter to Bramble"}, {"text": "Bring her answer back"}]})

**Not a tutorial and not a milestone**, both of which exist already. A tutorial teaches, starts
itself and is the same for everybody; a milestone notices something that already happened. An
objective is given, can be refused, runs alongside others, has steps in an order, and can be
abandoned.

**The engine never decides whether a step is done.** It counts, remembers and tells you; you watch
whatever event means "they did it" and call advance_objective. Otherwise the engine would have to
learn what delivering a letter is.

```gdscript
api.register_objective("errand", {"display_name": "An Errand",
	"steps": [{"text": "Go and see"}, {"text": "Come back", "count": 2}]})
```

**See also:** `register`

### `api.give_objective(player, objective_name: String) -> bool`

Gives one to a player. False if they have it, have finished one that does not repeat, or are
carrying as many as they may.

**See also:** `give`, `qualified`

### `api.advance_objective(player, objective_name: String, amount := 1) -> bool`

Counts towards the step they are on; finishing the last step fires `objective_done`, which is where
a reward belongs - the engine has no idea what a reward would be.

**See also:** `advance`, `qualified`

### `api.abandon_objective(player, objective_name: String) -> bool`

**See also:** `abandon`, `qualified`

### `api.objectives_of(player) -> Array`

What they are doing now: [{name, display_name, step, of, text, progress, needed}].

**See also:** `active_for`

### `api.has_objective(player, objective_name: String) -> bool`

**See also:** `qualified`

### `api.objective_finished(player, objective_name: String) -> int`

How many times they have finished it.

**See also:** `finished`, `qualified`, `register_character`

### `api.register_character(character_name: String, def: Dictionary) -> bool`

Somebody to talk to: a villager, a guide, a shopkeeper, a character in a story.

api.register_character("bramble", {"display_name": "Bramble", "color": "#ffd166", "lines": {
"start": {"text": "Oh - somebody. I saw your fire from the ridge.", "options": [
{"text": "What have you got?", "sells": "bramble_wares"},
{"text": "Need anything doing?", "gives": "deliver_the_post"},
{"text": "Who are you?", "goes_to": "who"}]},
"who": {"text": "Bramble. I mend things, mostly.",
"options": [{"text": "I see", "goes_to": "start"}]}}})

The engine draws the conversation, so every character in every mod looks and works the same way - a
child who has learned to talk to one has learned to talk to all of them. It knows a conversation is
lines with options and nothing else about what any of it means.

`goes_to` moves to another line, `gives` hands over an objective, `sells` opens a shop, and `does`
fires `character_choice` for anything else at all.

```gdscript
api.register_character("keeper", {"display_name": "The Keeper", "color": "#ffd166", "lines": {
	"start": {"text": "You again.", "options": [
		{"text": "What have you got?", "sells": "stall"},
		{"text": "Anything to do?", "gives": "errand"},
		{"text": "Who are you?", "goes_to": "who"},
		{"text": "Nothing", "does": "wave"}]},
	"who": {"text": "The keeper of this place.", "options": [{"text": "I see", "goes_to": "start"}]},
	"settled": {"text": "Settled in, then."}}})
```

**See also:** `register`

### `api.talk_to(player, character_name: String, options := {}) -> bool`

Starts a conversation, usually from an `entity_interact` handler. `line` is where to open - which
is yours, because whether somebody has settled in or is still a stranger is a fact about your story
and not about conversations.

**See also:** `qualified`, `talk`

### `api.has_met(player, character_name: String) -> bool`

Whether this player has ever spoken to them, which is most of what "we have met before" needs.

**See also:** `qualified`, `register_shop`

### `api.register_shop(shop_name: String, def: Dictionary) -> bool`

Somewhere to buy and sell: a village stall, a pedlar, a vending machine.

api.register_shop("bramble_wares", {"display_name": "Bramble's Wares", "offers": [
{"item": "rope", "count": 2, "price": 4, "ledger": "coins", "stock": 10, "restock": 600.0},
{"item": "apple", "price": 1, "ledger": "coins", "sells": true},
{"item": "lantern", "cost": [{"item": "iron_bar", "count": 2}, {"item": "coal"}]}]})

**Coins are not assumed.** A price is a number out of a ledger, or a list of items, or both, so a
game with no money barters perfectly well. `sells: true` turns an offer round - the player hands
the item over and is paid for it.

**Stock is the part that matters.** A shop with unlimited everything is a creative menu with an
extra step; `stock` and `restock` are what make the blacksmith who has three swords this week
somewhere worth going back to. Leave `stock` out for an offer that never runs dry.

```gdscript
api.register_shop("stall", {"display_name": "The Stall", "offers": [
	{"item": "proving:token", "count": 2, "price": 5, "ledger": "coins", "stock": 3, "restock": 30.0},
	{"item": "proving:rock", "count": 4, "cost": [{"item": "proving:token", "count": 1}]},
	{"item": "proving:plain", "price": 1, "ledger": "coins", "sells": true}]})
```

**See also:** `register`

### `api.show_shop(player, shop_name: String) -> bool`

Opens the stall. Drawn by the engine, like a conversation, so every shop works the same way.

**See also:** `qualified`, `show`

### `api.shop_trade(player, shop_name: String, index: int) -> bool`

Does one trade directly, for a shop with no panel - a vending block, a delivery chute. False when
it cannot happen, and `shop_problem` says why in words a child can read.

**See also:** `qualified`, `trade`

### `api.shop_problem() -> String`

### `api.shop_offers(player, shop_name: String) -> Array`

What is on the shelves: [{index, item, name, count, price, ledger, cost, sells, left, can}].

**See also:** `offers_for`, `qualified`, `register_entity`, `set_nameplate`

### `api.set_nameplate(target, spec := {}) -> bool`

The label over a thing's head: what it is called, how hurt it is, and anything you want to add.

api.set_nameplate(mob, {"lines": ["Wants: wheat"], "show_health": true})
api.register_entity("cow", {..., "nameplate": {"show_health": true}})

Creatures are quiet by default - a field of forty sheep each wearing a label is worse than no
labels - so a type only gets one if its definition says so, or a mod sets one on a particular
creature. Players always have their name.

`spec` merges with what is already there, so you can add a line without knowing whether health is
being shown. Keys: name, lines (up to 4), show_health, color, range, hidden.

**See also:** `set_plate`

### `api.nameplate_of(target) -> Dictionary`

What is over its head now, defaults included.

**See also:** `plate_of`

### `api.clear_nameplate(target) -> bool`

**See also:** `float_text`, `follow`

### `api.float_text(text: String, position: Vector3, options := {}, realm_id := "") -> void`

A word that floats in the world for a moment and then goes: the damage off a hit, "+3" over a
chest, a name over a thing.

api.float_text("12", position, {"color": "#ff6666", "follow": mob})

Transient on purpose - nothing is stored and nobody has to clean it up. It is drawn through walls,
because a number that vanishes behind a post is a number nobody can read.

options: color, seconds, rise (how far it drifts up), size, follow (a player or entity it sticks to).

```gdscript
api.float_text("%d" % roundi(was - float(ev.health)),
	e.body.position + Vector3(0, e.def.height * 0.9, 0),
	{"color": "#ffd166", "follow": e, "seconds": 0.8}))
```

**See also:** `qualified`, `register_entity`

### `api.mount(player, entity) -> bool`

Puts a player on a vehicle - an entity whose type has a `vehicle` block. Returns false when it is
full, too far away, or they are already riding something.

api.register_entity("boat", {"kind": "mob", "model": "models/boat.glb", "ai": {"preset": "none"},
"vehicle": {"seats": 2, "speed": 6.0, "turn_speed": 3.0, "floats": true}})

A rider stops simulating themselves: their position comes from the vehicle and their input becomes
steering - throttle forward and back, and the vehicle turns towards wherever they are looking.
Sneak gets off. The player's own physics is untouched, which is why riding cannot break walking.

**See also:** `config_of`, `is_alive`, `riders_of`, `tell_riding`

### `api.dismount(player, to = null) -> bool`

Takes a player off. `to` is where to put them down; by default beside the vehicle.

**See also:** `riders_of`, `tell_riding`

### `api.riding(player)`

The entity a player is riding, or null.

### `api.riders_of(entity) -> Array`

Who is aboard, as player ids.

**See also:** `order`, `register_order`

### `api.register_order(order_name: String, def := {}) -> bool`

Something a tamed creature can be told to do.

api.register_order("fetch", {"display_name": "Fetch that", "behavior": "my_mod:fetch"})
api.order(dog, "fetch")

Taming already gave a companion three of its four parts - it follows, it is owned, and it does not
despawn. Taking instruction was one boolean, `sitting`, toggled by right-clicking, which runs out
the moment there are three things to say.

Three orders are the engine's own, because all three are about *where*: `engine:follow`,
`engine:stay` and `engine:guard`. Anything else maps to a behaviour registered with
`register_mob_behavior` - the engine sets the order, your behaviour decides what it looks like.

Right-clicking a companion opens the order panel, drawn by the engine. Restrict what a particular
creature may be told by handling `companion_orders` and editing `orders`.

```gdscript
api.register_order("forage", {"display_name": "Forage here", "behavior": "proving:forage"})
```

**See also:** `at`, `qualified`, `register`

### `api.order(entity, order_name: String, options := {}) -> bool`

Tells a creature something. options: at (where, for orders that need a place; defaults to where it
is standing).

**See also:** `give`, `now`, `qualified`

### `api.order_of(entity) -> String`

What it is being told to do now ("engine:follow" when nobody has said otherwise).

```gdscript
"score": func(brain): return 0.2 if api.order_of(brain.entity) == "proving:forage" else 0.0,
```

### `api.show_orders(player, entity) -> bool`

Opens the order panel for a player, as right-clicking their own companion does.

**See also:** `place_field`, `register_field`, `show`

### `api.register_field(field_name: String, def: Dictionary) -> bool`

Ground that does something to whoever stands in it, for a while: a pool of fire left where a boss
landed, gas from a cracked pipe, the warmth of a campfire, a healing circle in a village.

api.register_field("fire_pool", {"radius": 3.0, "seconds": 10.0, "effect": "engine:flame",
"tick": {"seconds": 1.0, "damage": 2.0, "cause": "fire"},
"condition": {"condition": "burning", "seconds": 4.0}})

api.place_field("fire_pool", position, {"seconds": 20.0, "owner": mob})

**Called a field because plots and claims are taken** - plots are ground with an owner, claims are
ground kept awake. **It is always visible**: an invisible thing on the floor that hurts a child is
not a hazard but a trick, so placing one starts a running effect. You choose which; you cannot
choose none.

`affects` is "everyone", "players" or "creatures" - not "enemies", which would mean the engine
learning about sides. `except_owner` (on by default) keeps whoever left it out of their own fire.

```gdscript
api.register_field("scorch", {"display_name": "Scorch", "radius": 3.0, "seconds": 8.0,
	"effect": "engine:smoke", "tick": {"seconds": 1.0, "damage": 1.0, "cause": "scorch"},
	"condition": {"condition": "venom", "seconds": 3.0}})
```

**See also:** `qualified`, `register`

### `api.place_field(field_name: String, position: Vector3, options := {}) -> int`

Puts one down. options: seconds, radius, level (multiplies damage, heal and the condition's level),
owner (a player or creature it will not touch), realm. Returns its id, or 0.

**See also:** `place`, `qualified`

### `api.clear_field(id: int) -> bool`

### `api.fields_at(position: Vector3, realm_id := "") -> Array`

Every field a point is inside: [{id, kind, realm, position, radius, level, seconds}].

**See also:** `at`, `qualified`, `register_condition`

### `api.register_condition(condition_name: String, def: Dictionary) -> bool`

Something a player or a creature is temporarily under: swiftness, poison, a well-fed glow.

api.register_condition("swiftness", {"display_name": "Swiftness", "color": "#7fd6ff",
"modifiers": [{"stat": "move_speed", "amount": 0.2, "op": "multiply"}], "max_level": 3})

api.register_condition("poison", {"display_name": "Poison", "good": false,
"tick": {"seconds": 1.5, "damage": 1.0, "cause": "poison"}})

**Called a condition because `register_effect` already means particles.** A condition is a stat
change, or something that repeats on a timer, or both - and the timer is the part a plain timed
modifier could never express, which is what poison, regeneration and burning all need.

Levels multiply rather than re-describe: Swiftness II is the same modifiers doubled. `stacks` says
what a second helping does - "strongest" (the default), "refresh" or "extend".

What stays yours: what conditions exist, what brews or cures them, and what a level means.

```gdscript
api.register_condition("venom", {"display_name": "Venom", "good": false, "color": "#89c24a",
	"tick": {"seconds": 1.0, "damage": 1.0, "cause": "venom"}, "max_level": 3})
```

**See also:** `register`

### `api.give_condition(target, condition_name: String, options := {}) -> bool`

Gives one to a player or a creature. options: seconds (0 = until taken away), level.

**See also:** `give`, `qualified`

### `api.clear_condition(target, condition_name: String) -> bool`

**See also:** `qualified`

### `api.clear_conditions(target, only_bad := false) -> int`

Takes everything away, or with `only_bad` everything unpleasant - which is the whole of what a cure
is, and saves listing every affliction in the game. Returns how many went.

**See also:** `clear_all`

### `api.has_condition(target, condition_name: String) -> bool`

**See also:** `qualified`

### `api.condition_level(target, condition_name: String) -> int`

0 when they do not have it.

**See also:** `level_of`, `qualified`

### `api.conditions_of(target) -> Array`

What they are under: [{name, display_name, color, level, good, seconds}], `seconds` -1 for one that
does not run out.

**See also:** `of_target`, `register_ledger`

### `api.register_ledger(ledger_name: String, def := {}) -> bool`

A named number a player owns: coins, reputation, contribution, experience, a guild's standing.

api.register_ledger("coins", {"display_name": "Coins", "min": 0})
api.register_ledger("delving", {"display_name": "Delving", "levels": [0, 50, 150, 400]})

**Balances and experience are one thing here, not two.** They are the same storage asked a
different question - a balance is a number you care about the value of, experience is one you care
about the level of - so a ledger given thresholds answers about levels as well.

The engine stores a number against a player and a name and never learns that one of them is money.
What a level unlocks, whether anything unlocks at all, whether coins may go negative: all yours.

```gdscript
api.register_ledger("coins", {"display_name": "Coins", "min": 0})
```

**See also:** `register`

### `api.balance_of(player, ledger_name: String) -> float`

```gdscript
{"type": "progress", "value": int(api.balance_of(player, "coins")), "max": 10, "color": "#6fcf97"},
```

**See also:** `qualified`, `value_of`

### `api.add_balance(player, ledger_name: String, amount: float) -> float`

Adds (or, with a negative amount, takes away). Returns what it ended up as, which is not always what
was asked for when the ledger has a floor or a ceiling.

```gdscript
api.add_balance(ev.player, "coins", 1.0))
```

**See also:** `qualified`

### `api.set_balance(player, ledger_name: String, value: float) -> float`

**See also:** `qualified`, `set_value`

### `api.spend_balance(player, ledger_name: String, amount: float) -> bool`

Takes `amount` only if there is that much. Written as one call on purpose: a shop that checks and
then subtracts has a gap between the two, and this does not.

**See also:** `at`, `qualified`, `spend`

### `api.level_of(player, ledger_name: String) -> int`

What level they are at (0 when the ledger has no thresholds).

**See also:** `level_for`, `qualified`, `value_of`

### `api.level_progress(player, ledger_name: String) -> Dictionary`

{level, value, into (0-1 through this level), needed, next} - for a bar on the screen.

**See also:** `progress_of`, `qualified`

### `api.balances_of(player) -> Array`

Everything a player has any of: [{name, display_name, value, level}].

**See also:** `all_of`, `register_modifier`

### `api.register_modifier(modifier_name: String, def: Dictionary) -> bool`

A named mark that can be put on a particular item and changes what it does - an enchantment, in
your own words.

api.register_modifier("keen", {"display_name": "Keen", "max_level": 3,
"per_level": [{"stat": "damage", "amount": 1.0}], "applies_to": ["#base:axes"]})

`applies_to` names items or tags; empty means anything. The stat changes are worked out per level,
and a line of lore is written into the item so its tooltip says "Keen II" without anything new on
the wire.

**There is no hook system here on purpose.** A mark that should set things alight is a mod listening
to the hit event it already has and asking whether the weapon is kindled. A second way of doing what
events already do would be worse than one.

```gdscript
api.register_modifier("keen", {"display_name": "Keen", "max_level": 3,
	"per_level": [{"stat": "attack_damage", "amount": 1.0}], "applies_to": ["#proving:prods"]})
```

**See also:** `qualified`, `register`

### `api.apply_modifier(item_data: Dictionary, item_name: String, modifier_name: String, level := 1) -> Dictionary`

Puts a mark on an item, returning the new item data (level 0 takes it off). The item is returned
unchanged if the mark does not belong on it, so a mistake gives back an item rather than a mess.

**See also:** `apply`, `qualified`

### `api.modifier_level(item_data: Dictionary, modifier_name: String) -> int`

What level of a mark an item carries, or 0.

**See also:** `level_of`, `qualified`

### `api.modifiers_on(item_data: Dictionary) -> Array`

Every mark on an item: [{name, level, display_name}].

**See also:** `assembly_problem`, `marks_on`

### `api.register_liquid(block_name: String, def := {}) -> bool`

Makes a block a liquid that goes somewhere: spreads, falls, and dries up when nothing feeds it.

api.register_liquid("water", {"range": 7, "falls": true, "speed": 0.25})

def: `range` (how many blocks from a source before it runs out), `falls`, `speed` (seconds between
steps - lava is slow, which is most of what makes it frightening), `shallow` (a block to use once it
has spread `shallow_from` blocks - give it a slab shape and a thin sheet looks and wades like one).

The level lives in the block's state: 0 is a source and never runs out, and each block outwards is
one weaker. Nothing new is written to disk or sent to clients, because states already were.

```gdscript
api.register_liquid("slime", {"range": 4, "falls": true, "speed": 0.4,
	"shallow": "proving:slime_thin", "shallow_from": 2})
```

**See also:** `block`, `is_excluded`, `qualified`, `register`, `register_block_tick`

### `api.register_liquid_meeting(a_name: String, b_name: String, result_name: String) -> bool`

What forms where two different liquids meet - the black glass where lava meets water. The engine
has never heard of obsidian; it only knows that two of them touching makes a third thing.

```gdscript
api.register_liquid_meeting("slime", "proving:slime", "proving:plain")
```

**See also:** `block`, `is_excluded`, `qualified`, `register_meeting`

### `api.keep_awake(position: Vector3i, options := {}) -> int`

Keeps the world around a position awake when nobody is standing there, so a machine goes on running
after its owner walks away. Returns a claim id.

options: `radius` (chunks either side, 0-8), `player_id` (who to tell if it has to be paused),
`name` (what to call the place when telling them), `realm`.

**This costs somebody something, and the engine says so.** Claims are charged what their chunks
actually spend in block ticks, and when they exceed the share of a tick the host allows, the
dearest is paused first and its owner is told in plain words. Nothing is ever deleted - pausing
stops the ticking and leaves the blocks and their contents alone.

Only things that *cannot* be caught up need this. Crops and furnaces work out what they missed when
somebody comes back; a pump feeding a network cannot, because what it did depended on the rest of
the world while it was doing it.

**See also:** `qualified`

### `api.let_sleep(claim_id: int) -> bool`

Stops keeping it awake.

### `api.wake_claim(claim_id: int) -> bool`

Lets a paused claim run again.

**See also:** `resume`, `set_accepts`

### `api.set_accepts(node: Dictionary, filter := {}) -> void`

What a face will take, as items and tags. An empty filter takes anything, which is what an ordinary
pipe end is; `deny: true` turns it inside out, which is how "everything except cobblestone" is said.

api.set_accepts(node, {"tags": ["base:logs"]})

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `api.stop_accepting(node: Dictionary) -> void`

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `api.would_accept(from: Dictionary, item_name: String) -> bool`

Whether anything connected would take this, without sending it.

**See also:** `key_name`, `node_key`, `qualified`, `reachable`, `tag`

### `api.register_drive(unit_name: String) -> bool`

A kind of value *driven* through the links rather than stored in them: rotation, and anything else
that means "this end turns, so that end turns".

**Not the same as a quantity.** Power buffers, fills and runs out, and two generators on one grid
add up. Rotation is a speed and a direction, it arrives the instant the shaft turns, nothing
accumulates anywhere, and two sources driving one line do not add - they fight, and the engine says
so rather than inventing an average nobody asked for.

Gearing is not here. A gearbox is a block that reads one line and drives another at a different
speed, which is a few lines in a mod - and then the engine has no opinion about what ratios exist.

```gdscript
api.register_drive("shaft")
```

**See also:** `register_unit`

### `api.set_drive(unit_name: String, node: Dictionary, value: float) -> void`

This face drives at `value` - a speed, with a sign for which way round. 0 stops driving.

**See also:** `qualified`, `set_source`, `tag`

### `api.driven_at(unit_name: String, node: Dictionary) -> float`

What a face is being driven at. Zero when nothing drives it, and zero when the line is jammed,
because a jammed line does not turn.

**See also:** `qualified`, `tag`, `value_at`

### `api.drive_jammed(unit_name: String, node: Dictionary) -> bool`

Whether two sources are fighting over the line this face is on.

**See also:** `jammed_at`, `qualified`, `tag`

### `api.on_driven(unit_name: String, handler: Callable) -> void`

Told when what a face is driven at changes: {realm, position, face, unit, value, jammed}.

**See also:** `on_changed`, `qualified`

### `api.register_unit(unit_name: String) -> bool`

A kind of quantity that moves along links: power, steam, water, mana. The engine keeps them apart
by name and learns nothing else about any of them.

```gdscript
api.register_unit("power")
```

### `api.set_supply(unit_name: String, node: Dictionary, amount: float) -> void`

This face offers this much per second (0 to stop). A generator running; a tank draining.

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `api.set_demand(unit_name: String, node: Dictionary, amount: float) -> void`

This face wants this much per second (0 to stop asking).

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `api.received(unit_name: String, node: Dictionary) -> float`

What a face is actually receiving, which is not always what it asked for.

**See also:** `key_name`, `node_key`, `qualified`, `tag`

### `api.on_received(unit_name: String, handler: Callable) -> void`

Told when what a face receives changes: {realm, position, face, unit, wanted, got}.

**What a shortfall means is yours to decide.** The engine says "you asked for twenty and you have
seven" and has no opinion about whether that is a furnace running slowly, a lamp going dim or a
pump stopping dead. When there is not enough to go round everybody gets the same fraction of what
they asked for, so a grid under load dims all over rather than failing in an order nobody can see.

**See also:** `qualified`, `register_link_kind`

### `api.register_link_kind(kind_name: String, def := {}) -> bool`

A kind of connection a player can lay: a cable, a pipe, an aerial.

api.register_link_kind("cable", {"span": 12, "item": "base:copper_wire", "draw": "cable"})
api.register_link_kind("aerial", {"wireless": true, "span": 48, "crosses_realms": true})

def: `span` (how far it reaches), `item` (what a block of it costs to lay), `draw` - "cable" sags,
"pipe" is rigid and wants a shorter span, "" draws nothing - `wireless` (nothing drawn, no clear
line needed), `crosses_realms` (wireless only; a cable is a physical thing and cannot run through
the gap between worlds), `needs_air`, `per_node` (how many may meet at one face).

A node is a **face** of a block, so a machine can take power in one side and push items out of
another. Raise the reach of a particular connector by handling the `link_reach` event - that is
where an upgrade or a better aerial belongs, rather than in the kind itself.

```gdscript
api.register_link_kind("cable", {"span": 10.0, "needs_air": true, "draw": "cable", "color": "#c2703c"})
```

**See also:** `link_problem`, `register_kind`

### `api.link(kind_name: String, a: Dictionary, b: Dictionary) -> int`

Joins two faces. Each end is {realm, position, face} - realm "" is the world a server starts with,
face is 0..5 (up, down, north, south, west, east). Returns the link id, or 0; when it is 0,
`link_problem()` says why in a sentence a player can be shown.

**See also:** `qualified`, `tag`

### `api.link_problem() -> String`

Why the last link() was refused.

### `api.link_refused(kind_name: String, a: Dictionary, b: Dictionary) -> String`

Whether two faces could be joined, without joining them: "" means yes, anything else is the reason.

**See also:** `qualified`, `tag`, `why_not`

### `api.unlink(id: int, why := "removed") -> bool`

Removes a link by id.

**See also:** `cut`

### `api.links_at(position: Vector3i, realm_id := "") -> Array`

Every link touching a block, as ids.

**See also:** `at_block`, `qualified`

### `api.tag(tag_name: String, names: Array) -> void`

Puts blocks or items into a named group: "any log", "any ore", "anything a pipe may carry".

api.tag("logs", ["base:oak_log", "base:birch_log"])   # in base: defines base:logs
api.tag("base:logs", ["cherry:cherry_log"])            # elsewhere: adds to base:logs

A bare name is your own mod's, as everywhere else here; writing it out in full always means exactly
what it says. **Adding to another mod's tag is the point** - a mod that adds a tree can put its wood
in `base:logs` and every recipe the base game wrote for logs accepts it, without the base game
knowing that mod exists.

A tag in a namespace no installed mod owns is kept and warned about rather than refused, so a mod
that integrates with another when it happens to be there does not have to guard every call.

```gdscript
api.tag("currency", ["proving:token"])
```

**See also:** `qualified`

### `api.tagged(tag_name: String) -> Array`

The names in a tag (empty if nothing has defined it).

**See also:** `names_in`, `qualified`

### `api.has_tag(name: String, tag_name: String) -> bool`

Whether a block or item name is in a tag. Reads as "does this thing have this tag", which is why the
thing comes first here and the tag comes first in `tag` and `tagged`.

Both arguments are strings, so getting them the wrong way round used to return a quiet `false` and a
mod that simply never matched anything. Now it says so. (2026-09-20)

**See also:** `exists`, `qualified`

### `api.tags_of(name: String) -> Array`

Every tag a block or item is in.

**See also:** `qualified`

### `api.register_signal(block_name: String, handler: Callable) -> bool`

Tells `handler(ctx)` when the level arriving at a block of this type changes: a door that should
open, a lamp that should light, a machine that should start. ctx = {position, block, level,
previous, realm}.

Signals are three block keys and this one call. A block emits (`signal: 15` in its definition, or
set_signal for a lever that is only sometimes on), a block carries (`signal_carry: true`, one level
weaker each block, so fifteen blocks and it is gone), and a block listens - this.

**Gates, delays, inverters, latches and repeaters are blocks you write**, each one listening here
and emitting with set_signal. The engine has no opinion about what logic looks like, because a
puzzle game and a factory want different answers and it is not the engine's business to pick.

```gdscript
api.register_signal("core", func(ctx):
	api.set_block_data(ctx.position, {"level": int(ctx.level)}))
```

**See also:** `block`, `is_excluded`, `qualified`, `register`

### `api.set_signal(position: Vector3i, level: int, realm_id := "") -> void`

Makes the block at `position` emit `level` (0 to 15; 0 stops it). For a lever being flipped, a plate
being stood on, or a gate of your own working out what it should be saying.

```gdscript
api.set_signal(ev.position, 15 if api.signal_at(ev.position) == 0 else 0))
```

**See also:** `qualified`, `register_instance`, `set_source`

### `api.signal_at(position: Vector3i, realm_id := "") -> int`

The strongest level arriving at a position from anything touching it.

**See also:** `qualified`, `reaching`, `register_instance`

### `api.register_instance(kind_name: String, def := {}) -> bool`

Declares a kind of private, throwaway space: a dungeon, a puzzle room, an arena.

An instance **is a realm with a lifetime** - the same separate world dimensions already give you,
but made on demand and thrown away when it empties. Nothing in one is written to disk.

api.register_instance("dungeon", {"generator": Rooms.new(), "empty_seconds": 30,
"max_players": 4})

def: {generator, passes, empty_seconds, max_players, display_name}. Without a generator the space
is empty air, which is what a mod that builds its own room wants.

```gdscript
api.register_instance("trial", {"display_name": "The Trial", "empty_seconds": 5.0, "max_players": 2})
```

**See also:** `register`

### `api.open_instance(kind_name: String, options := {}) -> String`

Opens one and returns its id, or "" if it could not be opened.

options: {seed, data (anything you want to keep with it; read it back with `instance_data`)}.

```gdscript
var run: String = api.open_instance("trial", {"data": {"opened_for": player.name}})
```

**See also:** `open`

### `api.enter_instance(player, instance_id: String, position: Vector3) -> bool`

Sends a player in, remembering where they were so `leave_instance` can put them back.

```gdscript
api.enter_instance(player, run, Vector3(0.5, 66, 0.5))
```

**See also:** `enter`

### `api.leave_instance(player) -> bool`

Puts a player back where they were before they entered.

```gdscript
api.leave_instance(player)
```

**See also:** `leave`

### `api.close_instance(instance_id: String) -> bool`

Closes one now: everybody inside goes back and the space is thrown away. An instance also closes
itself once it has been empty for its kind's `empty_seconds`.

**See also:** `close`

### `api.instance_of(player) -> String`

The instance a player is in, or "".

```gdscript
var here: String = api.instance_of(player)
```

### `api.instance_data(instance_id: String) -> Dictionary`

What you kept with an instance when you opened it.

**See also:** `add_ore_pass`, `add_realm`, `data_of`, `decorate`

### `api.add_realm(realm_id: String, options := {}) -> Object`

Adds another world to this server, reached through a portal. Call it while the mod is setting up.

var deep := api.add_realm("emberdeep", {"name": "The Emberdeep", "generator": MyCaves.new()})

options: name (shown when travelling), generator (as set_world_generator, but for this world),
passes (objects with decorate(chunk, seed), as ore passes are), seed (by default derived from the
world's seed and this realm's name, so it is stable but not the same terrain as the overworld).

Ores, biomes and features go in with the realm's id: `api.add_ore_pass({...}, "emberdeep")`.

Returns the realm, or null if the name is taken. The id is qualified with the mod's own name, so two
mods may both have an "underworld" without meeting. A realm costs nothing until somebody is standing
in it: an empty one is not ticked at all (see docs/roadmap.md, "How much of the world is running").

To send somebody there: a portal block whose block data is {portal: {realm: "<mod>:emberdeep"}},
or send_to_realm. What the world is made of is the generator's business, and what it means is yours.

```gdscript
api.add_realm("deep", {"display_name": "The Deep", "generator": "void"})
```

**See also:** `attach`, `reload`, `set_storage`, `start`

### `api.realm_of(player) -> String`

Which world a player is standing in, as the id add_realm was given ("" is the one a server starts
with). Positions mean nothing without it: every world has a block at the same coordinates.

```gdscript
var realm_id: String = api.realm_of(player)
```

### `api.send_to_realm(player, realm_id: String, position: Vector3) -> bool`

Moves a player to another world, standing at `position`. Returns false if there is no such world, or
they are already in it. Cancellable by a mod through the `player_realm_change` event, which may also
change where they come out.

**See also:** `ensure_area_loaded`, `generate`, `index`, `links_for`, `qualified`, `realm_of`

### `api.set_wind(degrees: float, strength := 0.5, seconds := 0.0) -> void`

Sets the wind: `degrees` clockwise from north, `strength` 0 (still) to 1 (a gale), `seconds` 0 for
until something says otherwise - the same shape as `set_weather`.

Wind is visual: it leans the grass, drags the clouds and slants the rain. Nothing in the simulation
depends on it, so a mod may move it as freely as it likes. While a mod holds it the engine stops
drifting it on its own.

```gdscript
api.set_wind(240.0, 0.85)
```

### `api.get_wind() -> Dictionary`

The wind right now: `{angle, strength}`. The gusts a player actually sees are worked out on each
client, so this is the average rather than the instant.

**See also:** `wind_state`

### `api.sources_of(item_id: int) -> Array`

Everywhere an item comes from that is not a recipe: blocks that drop it, creatures that drop it,
loot tables that hold it, ore in the ground.

Returns [{kind, from, detail, chance}] with the reliable sources first. `kind` is one of "block",
"creature", "container", "ground" or "other".

**Mostly derived, not declared.** The engine already knows every loot table, every block's drops,
every creature's drops and every ore pass, so a mod that registered a creature with `drops` has
already said where that item comes from - being asked to say it again in a second registry is how
the two fall out of step.

**See also:** `chance_of`, `describe`, `kind_of`, `of_item`

### `api.register_source(item_name: String, source: Dictionary) -> bool`

Declares a source nothing can infer: traded by somebody, washed up after a storm, given as a
reward. `detail` is shown to a player, so write it as a sentence.

source: {kind ("block"|"creature"|"container"|"ground"|"other"), from, detail, chance}.

```gdscript
api.register_source("proving:token", {"kind": "other", "from": "the keeper",
	"detail": "handed over for a favour", "chance": 0.5})
```

**See also:** `declare`, `item`

### `api.register_milestone(milestone_name: String, def: Dictionary) -> bool`

A milestone: something a player has done, remembered for the life of the world and paid out once
(see engine/server/milestones.gd). Goals are written exactly as tutorial goals are - {type, target,
count}, type being an event goal (break, place, craft, kill, ...) or "event" - but the count is a
lifetime total. No target means anything of that kind counts.
{title, description, goal, icon, order, secret (hidden until reached), announce (tell everyone),
reward: {items: [[item, count]], cosmetic}}. The usual reward is a cosmetic, because a cosmetic is
something other players can see. Names without ":" are this mod's.

```gdscript
api.register_milestone("first_stone", {"display_name": "First Stone",
	"goal": {"type": "break", "target": ["proving:rock"]}})
```

**See also:** `qualified`, `register`

### `api.milestone_reached(player, milestone_name: String) -> bool`

Whether a player has reached a milestone, for gating something behind it.

**See also:** `qualified`, `reached`

### `api.set_ugc_policy(values: Dictionary) -> void`

How this server treats player creations (engine/server/ugc.gd): {enabled, accept: "auto" | "trusted" |
"approval" | "off", kinds: ["skin", "accessory", "model"], library (others may wear approved ones),
max_per_player, max_bytes_per_player}. Saved with the world.

**See also:** `set_policy`

### `api.ugc_list(filter := "approved") -> Array`

Player creations for review or rewards: filter pending | reported | approved | rejected | removed | all.
Each: {id, manifest {kind, category, name, author, author_name}, status, reason, reports, uploaded_by, size}.

**See also:** `review_list`

### `api.ugc_get(id: String) -> Dictionary`

One creation's record, or {}.

### `api.ugc_set_status(id: String, status: String, reason := "") -> bool`

Approves, rejects (hidden; the author may upload a fixed version) or removes (blocked for good) a creation.

**See also:** `set_status`

### `api.ugc_report(player, id: String, reason := "other", details := "") -> String`

Files a report as a player (e.g. from a mod's own report button).

**See also:** `report`

### `api.ugc_trust(player_id: String, on := true) -> void`

Trusted creators' uploads skip the approval queue when the policy accepts "trusted".

**See also:** `set_trusted`

### `api.ugc_ban(player_id: String, on := true, reason := "") -> void`

Stops (or allows again) a player uploading creations; banning also hides their creations.

**See also:** `set_banned`

### `api.register_permission(permission: String, description: String, roles := []) -> void`

Describes a permission a mod checks with player.has_permission, and which built-in roles get it by
default (e.g. ["moderator"]; admins and owners have every permission anyway).

```gdscript
api.register_permission("proving.prove", "May prove things", ["moderator"])
```

**See also:** `merge`, `role`

### `api.network_servers() -> Array`

The servers players can travel to from here (network.json): [{key, name, address, port, hop, inventory}].

### `api.set_arrival_point(id: String, position: Vector3) -> void`

Names a spot where players arriving from other servers can appear (tickets name it as their arrival).

**See also:** `set_arrival`

### `api.raycast(origin: Vector3, direction: Vector3, max_distance := 5.0, options := {}) -> Dictionary`

JavaScript: `raycast`

What a ray from `origin` in `direction` hits: `{hit, position, normal, block}` (position and normal are
Vector3i; `hit` is false when it reaches `max_distance` or unloaded world).

By default it sees what a player's crosshair sees, which deliberately looks straight through water -
you aim at the riverbed, not the river. Pass `{"liquids": true}` when the liquid is the point: a
fishing rod has to find the water's surface, and there is no other way to ask where that is.

var look := api.look_direction(player)
var hit := api.raycast(player.get_eye_position(), look, 6.0, {"liquids": true})
options.realm names the world to cast in; without it, the one a server starts with.

```gdscript
var hit: Dictionary = api.raycast(player.get_eye_position(), api.look_direction(player), 6.0)
```

**See also:** `cast`, `qualified`, `raycast_lut_with_liquids`, `register_instance`

### `api.look_direction(player) -> Vector3`

Where a player is looking, as a unit vector. The same direction the engine uses for their reach.

**See also:** `column`

### `api.set_rejoin_handler(handler: Callable) -> void`

Where a player who has played here before comes back to: `handler(player, saved_position) -> Vector3`.
Return `Vector3.INF` to leave them where they logged out, which is what happens with no handler.

A separate question from `set_spawn_handler`, and usually a different answer. A story might want a
first-time arrival at the structure it placed, and everyone after that back in their own bed. A lobby
server wants the opposite: everybody, every time, in the lobby. Answering both with one handler meant
a mod could only have one of them.

**See also:** `decorate`

### `api.is_liquid(block: int) -> bool`

Whether a block id is a liquid (water, lava, and anything a mod declares `liquid: true`).

### `api.area_cells(rule_name: String, ctx := {}) -> Array`

The cells a shape covers: "box" ({from, to}), "sphere" ({position, radius}), "vein"
({position, block, max}) or a shape a mod registered. `max` caps how many come back.

var cells := api.area_cells("vein", {"position": at, "player": p, "max": 64})

Choosing the cells and changing them are separate on purpose: between the two is where a tool
shows a preview, counts what it would cost, or asks whether the player really meant it.

```gdscript
var cells: Array = api.area_cells("vein", {"position": at, "player": player, "max": 64})
```

**See also:** `cells`

### `api.register_area_rule(rule_name: String, chooser: Callable) -> void`

Registers a way of choosing cells, for a tool the three built-in shapes do not describe - a line,
a wall, everything touching one face. The callable is handed the context `area_cells` was called
with and returns an Array of Vector3i.

```gdscript
api.register_area_rule("column", func(ctx):
	var at: Vector3i = ctx.get("position", Vector3i.ZERO)
	var height: int = clampi(int(ctx.get("height", 4)), 1, 32)
	var out: Array = []
	for dy in height:
		out.append(at + Vector3i(0, dy, 0))
	return out)
```

**See also:** `register_rule`

### `api.area_edit(player, cells: Array, options := {}) -> Dictionary`

Changes every cell a player is allowed to change. `block` 0 (or absent) breaks instead of places.

options: {block, drops (default true), realm}.

Returns {changed, skipped, refused, reason}. **This is not `fill`.** Every cell goes through the
plot check, the block events, the loot roll, tool wear and the player's edit budget, so a mod
listening for `block_broken` hears this exactly as it hears a pickaxe, and a selection reaching
into somebody's garden does the part outside it and reports the rest as `skipped`. `fill` is the
admin door and asks none of that.

```gdscript
var done: Dictionary = api.area_edit(player, cells, {"block": 0})
```

**See also:** `apply`

### `api.show_area(player, cells: Array, options := {}) -> void`

Outlines a selection for one player, before they commit to it. `seconds` 0 holds it until it is
cleared, which is what a tool with a live selection wants; an empty list takes it away.

options: {color, seconds}.

```gdscript
api.show_area(player, cells, {"seconds": 3.0})
```

**See also:** `preview`

### `api.add_death_messages(key: String, lines: Array) -> void`

More ways of saying that somebody died, so a mod’s own mobs get their own send-off rather than the
engine’s general one. `key` is a cause ("lava", "fall", "magic") or the name of an entity; the first
"%s" is the player and a second one is whatever did it. One is picked at random, never the same twice
running, alongside the lines already there.

api.add_death_messages("mymod:dragon", ["%s was toasted by %s", "%s argued with %s and lost"])

Keep them kind: say what happened, never what anyone is like. Children read these about themselves.

**See also:** `qualified`, `register_settings`

### `api.register_settings(schema: Dictionary) -> void`

Declares the settings a host may change without editing this mod, as {key: definition}. Each
definition takes a `type` ("bool", "int", "float", "choice" or "text"), a `label` players see, an
optional `help` line, a `default`, `min`/`max`/`step` for numbers and `choices` ([[value, label]])
for a choice. Call it while the mod loads; declaring the same key again updates its definition.

api.register_settings({
"monster_rate": {"label": "How many monsters", "type": "float", "default": 1.0, "min": 0.0, "max": 3.0,
"help": "Multiplies how often monsters appear."},
"difficulty":   {"label": "Difficulty", "type": "choice", "default": "normal",
"choices": [["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]]},
})

The server owns the values, so all three ways in agree: mod_settings.json in the server's data
folder, the /modsettings command, and the admin settings screen. They live in the world, so a world
carries its own settings and a backup restores them.

```gdscript
api.register_settings({
	"monsters": {"label": "How many monsters", "type": "choice", "default": "normal",
		"choices": [["none", "None"], ["few", "A few"], ["normal", "Normal"], ["many", "Lots"]]},
	"day_minutes": {"label": "Minutes in a day", "type": "int", "default": 20, "min": 2, "max": 120},
	"zombies_burn": {"label": "Monsters burn by day", "type": "bool", "default": true},
})
```

**See also:** `register`

### `api.setting(key: String)`

This mod's setting, as the host left it (its default until someone changes it). null if not declared.

**See also:** `get_value`, `is_game`, `on`, `show_title`

### `api.is_game() -> bool`

Is this mod the game being played, or is it being used as a foundation by another one?

A game mod is often somebody else's dependency: a story game builds on a sandbox one, so the
sandbox's blocks, creatures and recipes are all wanted, but its title card and its welcome are not -
the player is in the story. Guard anything that speaks for the whole game with this:

api.on("player_join", func(ev):
if api.is_game():
ev.player.show_title("Open Sandbox", "Build anything", 4.0))

The game is the first mod the server was asked to load that declares `"kind": "game"`; a game loaded
only because something else depends on it is not it. Add-ons (kind "addon") are never the game.

### `api.game_id() -> String`

The id of the game being played, whichever mod this is. Useful for an add-on that wants to behave
differently depending on the game it has been added to.

### `api.settings() -> Dictionary`

Every setting of this mod as {key: value}, for passing to something that wants a config dictionary.

**See also:** `get_block_data`, `list`, `merge`

### `api.set_setting(key: String, value) -> String`

Changes one of this mod's settings from code (the same path the admin screen uses, so handlers of
`settings_changed` run). Returns "" or why it was refused.

**See also:** `set_value`

### `api.static qualified(ref: String, owner: String) -> String`

The same rule, for the capabilities that hold names a mod wrote inside a definition - a shop's
ledger, a character's shop - and so must qualify them against that mod rather than against
whoever happens to be asking later. Public because three things need it and a private function two
systems copy is a fact about the code that ought to be visible in the code.
