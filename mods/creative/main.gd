extends "res://engine/server/mod.gd"
## The creative sandbox: `base`'s world, everything placeable, and nothing that can hurt you.
##
## **This mod is the proof that the base/game line holds.** The rule settled on 21 September 2026 was
## that `base` owns nouns and a game owns rules; the test of it was always *"a creative game ships
## zero recipes and everything still exists and works"*. So this registers **no blocks, no items and
## no recipes at all** - it is thirty lines of rules over four packs of content, which is exactly what
## a game is supposed to be. If this file ever needs to register a block, the line has moved.
##
## It takes `simple_machines` and `simple_gear` for their *blocks and items* rather than their
## recipes: a builder wants a furnace to put in a kitchen and a sword to hang on a wall. Their recipes
## come along and are harmless here, because nobody needs to craft anything.

const Chunk = preload("res://engine/shared/chunk.gd")

## Where the stone stops being ordinary. Below this the world is deepstone - harder, darker, and the
## reason a cobalt pickaxe is worth making.
const DEEP_FROM := 30

## Where the sea sits. The same number `base`'s biome heights are written against.
const SEA_LEVEL := 62


func setup(api) -> void:
	_world(api)
	_who_lives_here(api)
	# Nothing that interrupts building. Mobs still exist as content, they simply are not spawned -
	# a child placing blocks on a cliff does not want a skeleton arriving.
	api.set_gameplay({
		"fall_damage": false,
		"hunger": false,
		"mob_spawning": false,
		"mob_griefing": false,
		"durability": false,
		"pvp": false,
		"keep_inventory": true,
		"natural_regeneration": true,
	})
	# Everyone arrives able to fly and to take from the palette (B). Done per player on join rather
	# than as a server default, because "creative" is a property of a player in this engine - the
	# same server can hold a builder and a visitor.
	api.on("player_join", func(ev):
		if ev.player != null:
			ev.player.set_creative(true))


## Turning `base`'s biomes into an actual world.
##
## **This is a game's decision, not a pack's.** `base` says what a meadow is made of; how much iron is
## in the ground, whether there are caves, and where the stone turns to deepstone are rules - a
## survival game will want different numbers from this one, and a flat building world would want none
## of it. `base` did briefly install all of this itself and the effect was immediate and wrong: ore
## passes and generation passes attach to the *realm* rather than to the generator, so they ran over
## mods that had set a world generator of their own, and a deepstone layer quietly rewrote the AI
## arena's flat test floor. (2026-09-23)
func _world(api) -> void:
	api.use_biome_generator({"sea_level": SEA_LEVEL, "snow_level": 104})
	# Before the ores: the deep ones replace deepstone, so deepstone has to exist first. The engine
	# fills a column with one stone per biome and has no notion that depth means anything, so the
	# layer is a pass of our own.
	api.add_generation_pass(DeepStone.new(api.require_block("base:stone"), api.require_block("base:deepstone")))
	for ore in [
		{"ore": "base:coal_ore", "veins": 8.0, "size": 12, "min_y": 6, "max_y": 120},
		{"ore": "base:copper_ore", "veins": 5.0, "size": 8, "min_y": 6, "max_y": 90},
		{"ore": "base:iron_ore", "veins": 4.0, "size": 7, "min_y": 4, "max_y": 70},
		{"ore": "base:gold_ore", "veins": 1.6, "size": 5, "min_y": 4, "max_y": 34},
		{"ore": "base:cobalt_ore", "veins": 1.0, "size": 4, "min_y": 3, "max_y": 22},
		{"ore": "base:sunstone_ore", "veins": 0.35, "size": 3, "min_y": 3, "max_y": 16},
	]:
		var vein: Dictionary = ore.duplicate()
		vein["replace"] = "base:stone"
		api.add_ore_pass(vein)
	for deep in [
		{"ore": "base:deep_coal_ore", "veins": 4.0, "size": 10},
		{"ore": "base:deep_copper_ore", "veins": 3.0, "size": 7},
		{"ore": "base:deep_iron_ore", "veins": 3.0, "size": 6},
		{"ore": "base:deep_gold_ore", "veins": 1.4, "size": 4},
	]:
		var vein: Dictionary = deep.duplicate()
		vein["replace"] = "base:deepstone"
		vein["min_y"] = 2
		vein["max_y"] = DEEP_FROM
		api.add_ore_pass(vein)
	# Caves, with lava at the bottom. `water_level` stops a tunnel draining the sea into itself;
	# `entrance_chance` is what makes a cave something you can find rather than only fall into.
	api.add_cave_carver({"tunnels": true, "caverns": true, "ravines": true,
		"lava": "base:lava", "lava_level": 10, "water_level": SEA_LEVEL, "min_y": 4,
		"entrance_chance": 0.18})


## Turns the bottom of the world to deepstone. A pass rather than a biome field, because
## `surface.stone` is one block for a whole column: a biome cannot say "stone up here, deepstone down
## there". Runs on a worker thread and touches only the chunk it is given.
class DeepStone:
	extends RefCounted

	var stone := 0
	var deep := 0

	func _init(stone_id: int, deep_id: int) -> void:
		stone = stone_id
		deep = deep_id

	func decorate(chunk, _seed_value: int) -> void:
		if stone <= 0 or deep <= 0:
			return
		for y in DEEP_FROM:
			for z in Chunk.SIZE_Z:
				for x in Chunk.SIZE_X:
					var at := Chunk.index(x, y, z) << 1
					if chunk.blocks.decode_u16(at) == stone:
						chunk.blocks.encode_u16(at, deep)


## Where `base`'s creatures live.
##
## **A game's decision, like the generator.** Spawn rules attach to the realm rather than to a biome,
## so rules written in `base` fire in every world built on it - which is how the Proving Ground's flat
## test world ended up with mobs wandering through it, dirtying chunks fast enough that a save queue
## never drained. (2026-09-23)
##
## They are all here and all inert, because this game sets `mob_spawning: false` - a builder does not
## want a skeleton archer arriving. They are written down anyway so a survival game can start from
## something that works rather than from an empty file, and so that turning spawning back on in a
## creative world is one setting rather than an afternoon.
func _who_lives_here(api) -> void:
	for animal in [["pig", 3], ["sheep", 4], ["cow", 3], ["chicken", 4]]:
		api.add_spawn_rule({"entity": "base:" + String(animal[0]), "category": "animal", "time": "day",
			"place": "surface", "on": ["base:grass"], "group": [2, int(animal[1])],
			"max_nearby": 4, "chance": 0.02})
	api.add_spawn_rule({"entity": "base:wolf", "category": "animal", "place": "surface",
		"on": ["base:grass", "base:snow"], "group": [1, 3], "max_nearby": 2, "chance": 0.008})
	# The marsh is the Mirelet's, which is what makes a marsh worth naming.
	api.add_spawn_rule({"entity": "base:mirelet", "category": "monster", "place": "surface",
		"on": ["base:grass", "base:dirt"], "group": [2, 4], "max_nearby": 4, "chance": 0.012})
	for monster in ["dustling", "clatterjack", "spider", "goblin"]:
		api.add_spawn_rule({"entity": "base:" + monster, "category": "monster", "time": "night",
			"group": [1, 3], "max_nearby": 3, "chance": 0.02})
	# Underground, at any hour, because a cave does not care what time it is.
	for deep in ["dustling", "clatterjack", "spider"]:
		api.add_spawn_rule({"entity": "base:" + deep, "category": "monster", "place": "underground",
			"group": [1, 2], "max_nearby": 3, "chance": 0.018})
	api.add_spawn_rule({"entity": "base:night_stalker", "category": "monster", "time": "night",
		"place": "surface", "group": [1, 1], "max_nearby": 1, "chance": 0.004})
	api.add_spawn_rule({"entity": "base:boomshroom", "category": "monster", "time": "night",
		"group": [1, 2], "max_nearby": 2, "chance": 0.01})
	_the_rare_ones(api)


## The four the server is told about when they turn up.
##
## **Rare is a number, and the number lives here.** What a Wisp *is* belongs to `base`; that you meet
## one about once a fortnight of nights is this game's decision, and a survival game that wants them
## every night only changes `chance`. The engine does the rest: announcing one, marking it on
## everybody's compass with the time left on it, and taking it away again if nobody comes.
##
## `chance` is rolled per player per second, so these are small on purpose. At 0.0004 a player out at
## night meets one roughly every forty minutes of darkness; `max_nearby: 1` and `max_total: 1` are what
## make it *the* Wisp rather than a wisp. Without `max_total` a server of six children would have six
## of them out at once and the announcement would stop meaning anything.
func _the_rare_ones(api) -> void:
	# Out in the open, where a light in the distance is something you can see and set off towards.
	api.add_spawn_rule({"entity": "base:wisp", "category": "monster", "time": "night",
		"place": "surface", "max_nearby": 1, "max_total": 1, "chance": 0.0004,
		"min_distance": 40.0, "max_distance": 72.0})
	api.add_spawn_rule({"entity": "base:hollow_piper", "category": "monster", "time": "night",
		"place": "surface", "max_nearby": 1, "max_total": 1, "chance": 0.0003,
		"min_distance": 40.0, "max_distance": 72.0})
	# Stone things come up out of stony ground, which is the one of the four you can go looking for
	# rather than wait for - so it gets two rules, and **underground is the one that will actually
	# fire.** Written with only the surface rule first, and it was very nearly unspawnable: every
	# biome's `surface.top` is grass, sand, snow or gravel, so exposed stone and cobblestone come
	# almost entirely from boulder features, and `find_spot` abandons the whole attempt when the first
	# standing spot it finds is not in `on` rather than carrying on up the column. Six attempts against
	# perhaps two percent of columns, times 0.0006 a second, is a creature that exists on paper.
	# (2026-09-23, found by reading spawning.gd rather than by playing - which is the only way this
	# kind of mistake gets found, because nothing about it fails.)
	# No `time` on this one, following the deep rules above: a cave does not care what hour it is, and
	# underground *is* night, which is the whole reason the four are night creatures.
	api.add_spawn_rule({"entity": "base:barrow_warden", "category": "monster",
		"place": "underground", "on": ["base:stone", "base:deepstone", "base:gravel"],
		"max_nearby": 1, "max_total": 1, "chance": 0.0006})
	# The surface one stays as the rarer half, because meeting one standing by a boulder under the sky
	# is a better story than meeting one in a tunnel - it is just not a thing to rely on.
	api.add_spawn_rule({"entity": "base:barrow_warden", "category": "monster", "time": "night",
		"place": "surface", "on": ["base:stone", "base:gravel", "base:cobblestone"],
		"max_nearby": 1, "max_total": 1, "chance": 0.0006})
	# The harmless one is the least rare of the four and needs no darkness to stand in: `light` is
	# widened past the monster default because it is an animal and animals want light to spawn in,
	# while this one wants the night without minding the moon.
	api.add_spawn_rule({"entity": "base:palemoth", "category": "animal", "time": "night",
		"place": "surface", "light": [0, 15], "max_nearby": 1, "max_total": 2, "chance": 0.0009})
