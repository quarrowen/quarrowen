# Crafting

Part of the [Mod API reference](../mod-api.md). Mod API 1.0.0 · game 0.42.0


### `api.register_recipe`

GDScript: `api.register_recipe(inputs: Dictionary, output: String, count := 1, options := {}) -> bool`

JavaScript: `api.registerRecipe(inputs: Record<string, number>, output: string, count?: number, options?: { station?: string; tier?: number; needs?: string[]; category?: string; id?: string; time?: number; project?: boolean; unlock?: "known" | "pickup" | "blueprint" | "experiment" | "secret"; hint?: string; skill?: string }): void`

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
api.register_recipe({"#proving:rubble": 2}, "proving:soil", 1, {"id": "soil_from_any_rubble"})
```

**See also:** `add_recipe`, `defer_tag_recipe`, `is_excluded`, `item`, `item_name`, `qualified`

### `api.register_material`

GDScript: `api.register_material(material_name: String, def: Dictionary) -> void`

JavaScript: `api.registerMaterial(name: string, def: { display_name?: string; item: string; color?: string; tier?: number; speed?: number; durability?: number; damage?: number; handle?: number; trait?: { name: string; description?: string; modifiers?: StatModifier[]; durability_mult?: number; speed_mult?: number; damage_add?: number; glow?: ItemDef["glow"] } }): void`

A material parts can be made of: {display_name, item (raw material item name), color, tier, speed,
durability, damage, handle (durability multiplier as a handle), trait: {name, description, modifiers,
durability_mult, speed_mult, damage_add, glow}}. Every part type gets a recipe for it.

```gdscript
api.register_material("dull", {"display_name": "Dull", "item": "proving:token", "color": "#888888",
	"tier": 2, "speed": 4.0, "durability": 100, "damage": 1.0, "handle": 1.6,
	"trait": {"name": "Plain", "description": "nothing special", "speed_mult": 0.0}})
```

**See also:** `add_material`, `item`, `qualified`

### `api.register_part_type`

GDScript: `api.register_part_type(part_name: String, def: Dictionary) -> int`

JavaScript: `api.registerPartType(name: string, def: { display_name?: string; sprite: string; cost?: number; station?: string }): number`

A kind of part (registers the part item): {display_name, sprite (grayscale 16x16 image tinted by the
material), cost (material per part), station (where parts are made)}.

```gdscript
api.register_part_type("head", {"display_name": "Head", "cost": 3, "station": "proving:bench"})
```

**See also:** `add_part_type`, `register_asset`, `register_item`

### `api.register_assembly`

GDScript: `api.register_assembly(assembly_name: String, def: Dictionary) -> int`

JavaScript: `api.registerAssembly(name: string, def: { display_name?: string; icon?: string; slots: { name: string; part: string; label?: string }[]; tool_type?: string; damage?: number; cooldown?: number; reach?: number; sweep?: number; station?: string; skill?: string }): number`

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

### `api.register_minigame`

GDScript: `api.register_minigame(minigame_name: String, def: Dictionary) -> void`

JavaScript: `api.registerMinigame(name: string, def: { title?: string; type?: "timing" | "hold" | "sequence"; verb?: string; rounds?: number; speed?: number; zone?: number; cool?: number; team?: boolean; duration?: number; window?: number }): void`

A crafting minigame recipes and assemblies can name as their `skill` (crafting by hand for better
quality; see engine/shared/minigame.gd): {title, type: "timing" | "hold" | "sequence", verb, rounds,
speed, zone, cool, team (bellows + hammer), duration, window}.

```gdscript
api.register_minigame("steady", {"title": "Hold Steady", "type": "timing", "verb": "Strike",
	"rounds": 3, "speed": 1.0, "zone": 0.25})
```

**See also:** `register`

### `api.register_station`

GDScript: `api.register_station(station_name: String, def: Dictionary) -> void`

JavaScript: `api.registerStation(name: string, def: StationDef): void`

Makes a station upgradable (see engine/server/stations.gd): tiers [{block, title, kit, grants}],
workshop {radius, upgrades: [{block, title, max, grants}]}, multiblock {core, pattern, legend,
title}. grants: {features, tier, speed, quality, pull_radius, hints}. Blocks involved still declare
`station: "<name>"`. Recipes then ask for `tier` and `needs` (features).

```gdscript
api.register_station("bench", {"workshop": {"radius": 2,
	"upgrades": [{"block": "proving:lamp", "title": "Bright", "grants": {"features": ["bright"]}}]}})
```

**See also:** `register`

### `api.get_station`

GDScript: `api.get_station(position: Vector3i) -> Dictionary`

JavaScript: `api.getStation(position: Vec3): Record<string, unknown>`

The station at a position: {name, title, tier, tier_title, features, speed, quality, pull_radius,
hints, detected, available, next, structure}, or {}.

**See also:** `evaluate`

### `api.register_recipe_category`

GDScript: `api.register_recipe_category(category_name: String, def := {}) -> bool`

JavaScript: `api.registerRecipeCategory(categoryName, def)`

```gdscript
api.register_recipe_category("proven", {"display_name": "Proven", "icon": "proving:token"})
```

**See also:** `has_category`, `item`, `register_category`

### `api.register_container`

GDScript: `api.register_container(container_name: String, def: Dictionary) -> bool`

JavaScript: `api.registerContainer(name: string, def: { title?: string; groups: { name: string; count: number; columns?: number; label?: string; take_only?: boolean; accepts?: string[] | "fuel" }[]; progress?: { name: string; label?: string; color?: string }[] }): boolean`

Registers a container type (see engine/server/containers.gd): {title, groups: [{name, count,
columns, label, take_only, accepts}], progress: [{name, label, color}]}. Blocks use it with
`container: "<name>"` and open it on right-click. Names without ":" are this mod's.

```gdscript
api.register_container("crate", {"title": "Crate",
	"groups": [{"name": "items", "count": 6}, {"name": "fuel", "count": 1, "accepts": "fuel"}],
	"progress": [{"name": "work", "label": "Work", "color": "#80ff80"}]})
```

**See also:** `on`, `open_bag`, `qualified`, `register`, `register_item`

### `api.get_container`

GDScript: `api.get_container(position: Vector3i)`

JavaScript: `api.getContainer(position)`

The container at a position (engine/server/container.gd), or null.

**See also:** `block_key`, `get_block_data`, `get_block_loaded`, `realm_of`, `set_block_data`, `type_of_block`

### `api.open_container`

GDScript: `api.open_container(player, position: Vector3i) -> bool`

JavaScript: `api.openContainer(player: Player, position: Vec3): boolean`

Opens a container's screen for a player (as if they right-clicked it).

**See also:** `open`

### `api.set_fuel`

GDScript: `api.set_fuel(item_name: String, seconds: float) -> void`

JavaScript: `api.setFuel(item: string, seconds: number): void`

Makes an item burn in fuel slots for `seconds`.

```gdscript
api.set_fuel("proving:token", 20.0)
```

**See also:** `item`

### `api.get_fuel`

GDScript: `api.get_fuel(item_id: int) -> float`

JavaScript: `api.getFuel(item: ItemId): number`

How many seconds an item burns in a furnace (0 = not fuel).

**See also:** `register_process`

### `api.register_process`

GDScript: `api.register_process(kind: String, input: String, output: String, count := 1, seconds := 10.0) -> bool`

JavaScript: `api.registerProcess(kind: string, input: string, output: string, count?: number, seconds?: number): void`

A processing recipe machines look up by kind: register_process("smelting", "base:iron_ore",
"base:iron_ingot", 1, 10.0).

```gdscript
api.register_process("grinding", "proving:plain", "proving:rock", 1, 2.0)
```

**See also:** `add_process`, `is_excluded`, `item`, `qualified`

### `api.get_process`

GDScript: `api.get_process(kind: String, item_id: int) -> Dictionary`

JavaScript: `api.getProcess(kind: string, item: ItemId): { output: ItemId; count: number; seconds: number } | Record<string, never>`

{output, count, seconds} for an input, or {} when that kind of machine cannot process it.

### `api.lift_assembly`

GDScript: `api.lift_assembly(positions: Array, options := {}) -> int`

JavaScript: `api.liftAssembly(positions, options)`

Takes a set of blocks out of the world and holds them as one moving thing: a platform on a track, a
drawbridge, a contraption somebody built and started. Returns an assembly id, or 0 - and then
`assembly_problem()` says why in words a player can be shown.

The blocks leave the world at once, keeping their state and their data, so nothing is ever in two
places. What moves it, how fast and when it stops are yours; the engine moves blocks and has never
heard of a piston.

**See also:** `lift`, `qualified`

### `api.move_assembly`

GDScript: `api.move_assembly(assembly_id: int, by: Vector3) -> bool`

JavaScript: `api.moveAssembly(assemblyId, by)`

Moves it, and carries whoever is standing on it. `by` may be fractional - being off the grid is the
entire point.

**See also:** `assembly_problem`, `move`

### `api.settle_assembly`

GDScript: `api.settle_assembly(assembly_id: int) -> bool`

JavaScript: `api.settleAssembly(assemblyId)`

Puts it back into the world where it has got to. **Refused if something is in the way**, rather than
landing on top of it - an engine that deletes what somebody built because a machine arrived is not
one to build with. Returns false, and `assembly_problem()` says so.

**See also:** `settle`

### `api.assembly_problem`

GDScript: `api.assembly_problem() -> String`

JavaScript: `api.assemblyProblem()`

Why the last lift or settle was refused.

**See also:** `register_multiblock`

### `api.fill_container`

GDScript: `api.fill_container(container, table_name: String, context := {}) -> int`

JavaScript: `api.fillContainer(container, tableName, context)`

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

### `api.show_crafting`

GDScript: `api.show_crafting(player) -> void`

JavaScript: `api.showCrafting(player: Player): void`

Opens the crafting screen for a player, crafting by hand.

**See also:** `open_crafting`
