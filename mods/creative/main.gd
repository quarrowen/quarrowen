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
