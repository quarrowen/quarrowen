extends "res://engine/server/mod.gd"
## Firstlight: the survival game. A night you have to get through, and a morning that means you did.
##
## **The name is the design.** What a survival game is actually about, for a child, is the first dawn:
## the dark is frightening, you shelter, and then it is morning and you managed it. Everything here is
## tuned to make that moment land and then repeat at a larger scale - the first night, the first cave,
## the first time something rare is announced and you go after it.
##
## **This registers no blocks and no items.** `base` owns the nouns, `simple_machines` and
## `simple_gear` own the things you build and hold, and a game owns the *rules*: how hungry, how dark,
## how punishing, what lives where, and what any of it is for. If this file ever needs to register a
## block, the line has moved. (The same test as `creative`, from the other side: creative proves the
## content works with no rules at all; this proves the rules are all a game has to bring.)
##
## Settled with the user, 2026-09-23: a **classic survival arc** - real hunger, monsters that hurt,
## caves worth being careful in, and a ladder of gear. The rare creatures are **a real shortcut**
## rather than a requirement. Finishable **alone**, better with two.

const Chunk = preload("res://engine/shared/chunk.gd")

## Where the stone stops being ordinary. Below this the world is deepstone - harder, darker, and the
## reason a cobalt pickaxe is worth making.
const DEEP_FROM := 30

## Where the sea sits. The same number `base`'s biome heights are written against.
const SEA_LEVEL := 62


func setup(api) -> void:
	_rules(api)
	_world(api)
	_who_lives_here(api)


## What kind of game this is, in one dictionary.
##
## The three that are not the obvious choice, and why:
##
## - **`keep_inventory: false`, which sounds harsher than it is.** `base` gives a death a **grave** - a
##   container block holding everything, that only the player who died can open. So dying costs you the
##   walk back and the nerve to make it, not an afternoon's work. That is the whole bargain: a
##   consequence a child can recover from is a consequence they will take seriously; one they cannot is
##   a child who stops playing.
## - **`pvp: false`.** Two siblings on one server. This is not a thing they should be able to do to each
##   other by accident, or on purpose.
## - **`mob_griefing: false`.** A Boomshroom walking into the house you spent an evening on and taking a
##   wall out is the single most demoralising thing this genre does to a new player. The creature still
##   goes off and still hurts; it just cannot unbuild anything.
##
## `starvation_min_health: 1.0` is the engine's default and worth leaving alone: hunger hurts, and it
## stops one hit short of killing you. Being unable to starve to death is what lets hunger be a real
## pressure in a game for children rather than a cruelty.
func _rules(api) -> void:
	api.set_gameplay({
		"hunger": true,
		"starvation_min_health": 1.0,
		"fall_damage": true,
		"durability": true,
		"mob_spawning": true,
		"natural_regeneration": true,
		"keep_inventory": false,
		"mob_griefing": false,
		# **On, by the user's call** (2026-09-24), against the recommendation here, which was that two
		# siblings should not be able to hit each other. Their children and their judgement - and it is
		# not a one-way door: `/gameplay pvp false` turns it off on a running server without a restart,
		# which is the thing to reach for if an evening goes wrong rather than editing this file.
		"pvp": true,
		"item_drops": "entity",
		"recipe_discovery": true,
		"tutorials": true,
		"sleeping": true,
		# **Half, not all**, confirmed by the user 2026-09-24: with two playing, one going to bed ends
		# the night. At 100 either child can hold the other in the dark by refusing to sleep, which is
		# a sibling argument the game does not need to host.
		"sleep_percentage": 50,
	})


## Turning `base`'s biomes into a world worth surviving in.
##
## Deliberately close to `creative`'s numbers rather than different for its own sake: the ore depths
## and cave shape were tuned once and there is no reason a survival world should be a different planet.
## What differs is that here they *matter* - the same sunstone at y<16 is a curiosity in a creative
## world and a reason to dig in this one.
func _world(api) -> void:
	api.use_biome_generator({"sea_level": SEA_LEVEL, "snow_level": 104})
	# Before the ores: the deep ones replace deepstone, so deepstone has to exist first.
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
	api.add_cave_carver({"tunnels": true, "caverns": true, "ravines": true,
		"lava": "base:lava", "lava_level": 10, "water_level": SEA_LEVEL, "min_y": 4,
		"entrance_chance": 0.18})


## Turns the bottom of the world to deepstone. A pass rather than a biome field, because
## `surface.stone` is one block for a whole column. Runs on a worker thread and touches only the chunk
## it is given.
##
## The same twenty lines as `creative`'s, and copied rather than shared on purpose: a generation pass
## attaches to the *realm*, so it is a rule, and rules belong to the game that wants them. Putting it
## somewhere both games import would put a rule in a library, which is the mistake that cost an
## afternoon on 2026-09-23 when `base` briefly owned one. (If a third game wants it, that is the point
## to reconsider - three is a pattern, two is a coincidence.)
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


## Who lives where, and how often.
##
## **The night is the pressure, so the night is where the numbers are.** Monsters on the surface only
## after dark and underground at any hour, because a cave does not care what time it is - which is
## what makes going down a decision rather than a chore.
func _who_lives_here(api) -> void:
	# Daylight, on grass. The reason a meadow is somewhere to settle.
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
	for deep in ["dustling", "clatterjack", "spider"]:
		api.add_spawn_rule({"entity": "base:" + deep, "category": "monster", "place": "underground",
			"group": [1, 2], "max_nearby": 3, "chance": 0.018})
	api.add_spawn_rule({"entity": "base:night_stalker", "category": "monster", "time": "night",
		"place": "surface", "group": [1, 1], "max_nearby": 1, "chance": 0.004})
	api.add_spawn_rule({"entity": "base:boomshroom", "category": "monster", "time": "night",
		"group": [1, 2], "max_nearby": 2, "chance": 0.01})
	_the_rare_ones(api)


## The four the whole server is told about.
##
## Numbers taken from `creative`'s, which were measured with `tools/spawn_probe.tscn` rather than
## guessed - including the Barrow Warden's, which is ten times its siblings' because its block list
## means only about 4% of attempts find anywhere to stand. Run the probe again if these move.
##
## Here they actually fire: `creative` sets `mob_spawning: false`, so every rule in it is inert and
## these four have never once appeared in a running game.
func _the_rare_ones(api) -> void:
	api.add_spawn_rule({"entity": "base:wisp", "category": "monster", "time": "night",
		"place": "surface", "max_nearby": 1, "max_total": 1, "chance": 0.0004,
		"min_distance": 40.0, "max_distance": 72.0})
	api.add_spawn_rule({"entity": "base:hollow_piper", "category": "monster", "time": "night",
		"place": "surface", "max_nearby": 1, "max_total": 1, "chance": 0.0003,
		"min_distance": 40.0, "max_distance": 72.0})
	api.add_spawn_rule({"entity": "base:barrow_warden", "category": "monster", "time": "night",
		"place": "surface", "on": ["base:stone", "base:gravel", "base:cobblestone"],
		"max_nearby": 1, "max_total": 1, "chance": 0.006})
	api.add_spawn_rule({"entity": "base:palemoth", "category": "animal", "time": "night",
		"place": "surface", "light": [0, 15], "max_nearby": 1, "max_total": 2, "chance": 0.0009})
