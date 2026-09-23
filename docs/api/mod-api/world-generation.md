# World generation

Part of the [Mod API reference](../mod-api.md). Mod API 1.0.0 · game 0.42.0


### `api.place_structure_in`

GDScript: `api.place_structure_in(template_name: String, at: Vector3i, realm_id := "", rotation := 0) -> bool`

JavaScript: `api.placeStructureIn(templateName, at, realmId, rotation)`

Pastes a saved structure into a world. `realm_id` is which world - without it a dungeon's rooms
were built in the overworld while the players stood in an empty instance. (2026-09-21)

**See also:** `follow`, `place`, `qualified`, `register_instance`

### `api.set_world_generator`

GDScript: `api.set_world_generator(generator: Object, realm_id := "") -> void`

JavaScript: *not available - takes a Object, which needs a GDScript object on the other side.*

`generator` must implement `generate(chunk)`; write into a local copy of `chunk.blocks`
(index with Chunk.index(x, y, z)) and assign it back for speed.

```gdscript
api.set_world_generator(FlatGround.new(api.require_block("proving:rock"), api.require_block("proving:soil"), api.require_block("proving:turf")))
```

**See also:** `qualified`, `register_instance`, `reload`

### `api.use_biome_generator`

GDScript: `api.use_biome_generator(options := {}, realm_id := "") -> Object`

JavaScript: `api.useBiomeGenerator(options?: { sea_level?: number; snow_level?: number }): void`

Turns on the engine biome generator (engine/server/worldgen/biome_generator.gd) for this world.
options: sea_level, snow_level. Register biomes and features before or after; returns the generator.

**See also:** `biome_generator`, `qualified`, `register_instance`

### `api.biome_generator`

GDScript: `api.biome_generator(realm_id := "") -> Object`

JavaScript: `api.biomeGenerator(realmId)`

The shared biome generator (created on first use, even if the game uses its own generator).

**See also:** `block`, `qualified`, `register_instance`

### `api.register_biome`

GDScript: `api.register_biome(biome_name: String, def: Dictionary, realm_id := "") -> void`

JavaScript: `api.registerBiome(name: string, def: Record<string, unknown>): void`

A biome for the biome generator: {climate, ocean, height, surface, features, plants}. See BiomeGenerator.

```gdscript
api.register_biome("plain", {"climate": [0.4, 0.6], "height": [0.0, 0.2],
	"surface": "proving:turf", "features": [], "plants": []})
```

**See also:** `add_biome`, `biome_generator`, `qualified`

### `api.add_cave_carver`

GDScript: `api.add_cave_carver(options := {}) -> void`

JavaScript: `api.addCaveCarver(options)`

Carves caves, caverns and ravines into the biome generator's terrain (see worldgen/cave_carver.gd).
options: tunnels, caverns, ravines (bools), lava (block name), lava_level, water_level, min_y,
entrance_chance.

**See also:** `biome_generator`, `block`

### `api.register_structure_template`

GDScript: `api.register_structure_template(template_name: String, source) -> bool`

JavaScript: `api.registerStructureTemplate(name: string, source: string | Record<string, unknown>): boolean`

A structure template: a JSON file in this mod (e.g. "structures/tower.json", saved with /struct save)
or a template dictionary. Names without ":" are this mod's.

```gdscript
api.register_structure_template("hut", {"size": [2, 1, 2], "palette": ["proving:rock"],
	"blocks": [[0, 0, 0, 0], [1, 0, 0, 0], [0, 0, 1, 0], [1, 0, 1, 0]]})
```

**See also:** `add_template`, `biome_generator`

### `api.place_structure`

GDScript: `api.place_structure(template_name: String, at: Vector3i, rotation := 0) -> bool`

JavaScript: `api.placeStructure(templateName, at, rotation)`

Generated structures (see worldgen/structures.gd): {templates: [{template, weight}] or generator
(GDScript Callable), spacing, separation, biomes, place, y, sink, foundation, swaps, reach, chance}.
Stamps a template into the world now, rotated a quarter turn at a time (0-3). What `/struct place`
does, for a mod that wants to build something itself rather than leave it to world generation: a
story's outpost, a rescue site, a prize somebody hid.

**See also:** `place`, `qualified`

### `api.register_structure`

GDScript: `api.register_structure(structure_name: String, def: Dictionary) -> void`

JavaScript: `api.registerStructure(name: string, def: Record<string, unknown>): void`

```gdscript
api.register_structure("hut_site", {"template": "proving:hut", "rarity": 0.0})
```

**See also:** `add_set`, `biome_generator`, `qualified`, `register_loot`

### `api.register_loot`

GDScript: `api.register_loot(table_name: String, def: Dictionary) -> void`

JavaScript: `api.registerLoot(tableName, def)`

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

### `api.register_loot_table`

GDScript: `api.register_loot_table(table_name: String, def: Dictionary) -> void`

JavaScript: `api.registerLootTable(name: string, def: { rolls?: [number, number]; entries: { item: string; count?: [number, number]; weight?: number }[] }): void`

Deprecated: use `register_loot`. The name it had before tables were used for everything.

```gdscript
api.register_loot_table("bench_loot", {"pools": [
	{"rolls": 1, "entries": [{"item": "proving:rod", "count": [1, 1]}]}]})
```

**See also:** `extend_entity`, `register_loot`

### `api.extend_loot`

GDScript: `api.extend_loot(table_name: String, def: Dictionary) -> void`

JavaScript: `api.extendLoot(tableName, def)`

Adds pools to a table another mod owns, without forking it: an extra drop on their mob, a bonus in
their dungeon chests.

**See also:** `extend`, `fill_container`, `get_container`, `qualified`

### `api.roll_loot`

GDScript: `api.roll_loot(table_name: String, context := {}) -> Array`

JavaScript: `api.rollLoot(tableName, context)`

Rolls a table and returns [[item id, count, data], …], for anything the engine does not roll itself
(fishing, a quest reward, a prize crate). `context` may carry player, cause, tool, position and seed.

**See also:** `qualified`, `roll`

### `api.loot_sources`

GDScript: `api.loot_sources(item_name: String) -> Array`

JavaScript: `api.lootSources(itemName)`

What a mob, block or table gives, without rolling: everything it could drop, as
[{item, chance, count, table}]. This is what the guide's "what drops this?" is built from.

**See also:** `qualified`, `sources_of`

### `api.set_loot_rate`

GDScript: `api.set_loot_rate(multiplier: float) -> void`

JavaScript: `api.setLootRate(multiplier)`

How much everything drops, as a multiplier (1.0 is normal). A host's "how much loot" setting.

### `api.get_loot_rate`

GDScript: `api.get_loot_rate() -> float`

JavaScript: `api.getLootRate()`

**See also:** `set_loot_boost`

### `api.set_loot_boost`

GDScript: `api.set_loot_boost(target: String, factor: float, seconds := 0.0) -> void`

JavaScript: `api.setLootBoost(target, factor, seconds)`

Turns one thing up (or down) for a while, for an event: `target` is a table or an item name, `factor`
how much more often it comes up, `seconds` how long (0: until it is changed back).

api.set_loot_boost("base:coal", 3.0, 3600.0)     # coal everywhere, for an hour
api.set_loot_boost("vanilla:dungeon", 2.0)       # richer dungeon chests until further notice

**See also:** `qualified`, `set_boost`

### `api.register_feature`

GDScript: `api.register_feature(feature_name: String, def, realm_id := "") -> void`

JavaScript: `api.registerFeature(name: string, def: Record<string, unknown>): void`

A world feature (tree, cactus, boulder, spike, huge mushroom, patch) as data {type, ...} or, from
GDScript, a Callable(writer, origin: Vector3i, rng) run on worker threads. See worldgen/features.gd.

```gdscript
api.register_feature("boulder", {"type": "boulder", "block": "proving:rock", "radius": [1, 2]})
```

**See also:** `add_feature`, `biome_generator`, `get_eye_position`, `look_direction`, `raycast`

### `api.get_biome`

GDScript: `api.get_biome(position: Vector3) -> String`

JavaScript: `api.getBiome(position)`

Name of the biome at a column ("" without the biome generator).

**See also:** `biome_at`

### `api.add_generation_pass`

GDScript: `api.add_generation_pass(pass_object: Object, realm_id := "") -> void`

JavaScript: *not available - takes a Object, which needs a GDScript object on the other side.*

Adds a pass run after the world generator for every new chunk, on worker threads:
`pass_object.decorate(chunk, world_seed)`. Lets add-on mods put ores or structures in any game.

**See also:** `qualified`, `register_instance`

### `api.add_ore_pass`

GDScript: `api.add_ore_pass(def: Dictionary, realm_id := "") -> void`

JavaScript: `api.addOrePass(def: OrePassDef): void`

Scatters veins of `ore` inside `replace` in every new chunk. def: ore, replace (block names),
veins (per chunk), size (blocks per vein), min_y, max_y, chance (per vein, 0-1).
`realm_id` puts the ore in another world instead of the one the server starts with - the Emberdeep
wants its own ores, and they are not the overworld's at a different depth.

**See also:** `add_generation_pass`, `block`
