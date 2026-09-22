extends "res://engine/server/mod.gd"
## The Proving Ground: a game that exists to be tested rather than played.
##
## **The rule is that if the engine can do it, this mod does it.** Adding a capability to the engine
## means adding it here in the same commit, and `tests/proving_test.gd` then asserts it worked.
##
## Until this existed the engine was tested through the seven games shipped with it, which meant every
## engine change dragged seven mods behind it, and coverage was whatever the content happened to use.
## That is how 139 unbound JavaScript functions and 39 undocumented events went unnoticed for weeks.
##
## Laid out by capability family rather than by the story it tells, because it tells no story. Each
## submodule is kept as a member: a RefCounted nobody holds is freed the moment `setup` returns, taking
## its handlers with it, silently (see CLAUDE.md).

const Things = preload("things.gd")
const Life = preload("life.gd")
const Society = preload("society.gd")
const Machines = preload("machines.gd")
const Presentation = preload("presentation.gd")

var api
## Ids of everything registered, so the tests can ask for them by name rather than guessing.
var ids := {}
var things := Things.new()
var life := Life.new()
var society := Society.new()
var machines := Machines.new()
var presentation := Presentation.new()


func setup(mod_api) -> void:
	api = mod_api
	api.set_server_info({"name": "Proving Ground", "motd": "Nothing here is meant to be fun."})
	api.set_gameplay({"keep_inventory": true, "natural_regeneration": true, "tutorials": true})
	# Settings a host can change, which nothing else exercises now that the games are gone.
	api.register_settings({
		"monsters": {"label": "How many monsters", "type": "choice", "default": "normal",
			"choices": [["none", "None"], ["few", "A few"], ["normal", "Normal"], ["many", "Lots"]]},
		"day_minutes": {"label": "Minutes in a day", "type": "int", "default": 20, "min": 2, "max": 120},
		"zombies_burn": {"label": "Monsters burn by day", "type": "bool", "default": true},
	})
	# A setting that actually does something, so "the mod acted on it" is a real assertion rather than
	# a registry lookup. The numbers match what a host would expect the words to mean.
	var caps := {"none": 0, "few": 8, "normal": 24, "many": 48}
	var apply_caps := func(): api.set_spawn_caps({"monster": int(caps.get(String(api.setting("monsters")), 24))})
	api.on("settings_changed", func(ev):
		if ev.key == "monsters":
			apply_caps.call())
	things.setup(api, ids)
	# **After things.setup, not before.** The generator is built with block ids, and asking for one that
	# is not registered yet returns -1, which encodes as 65535 and generates a world made of nothing.
	# "Reordering mod registration" is in CLAUDE.md's list of things that look safe and are not.
	api.set_world_generator(FlatGround.new(api.require_block("proving:rock"), api.require_block("proving:soil"), api.require_block("proving:turf")))
	# Worldgen data this mod's own flat generator never consults, registered anyway because these are
	# capabilities and the point of this mod is that every one of them has a user. A biome, a feature
	# and a structure template are all just data until a generator asks for them. (2026-09-22)
	api.register_biome("plain", {"climate": [0.4, 0.6], "height": [0.0, 0.2],
		"surface": "proving:turf", "features": [], "plants": []})
	api.register_feature("boulder", {"type": "boulder", "block": "proving:rock", "radius": [1, 2]})
	# Each block is [x, y, z, palette index], not a flat array of indices - which the error message at
	# load says plainly, and is why it says it.
	api.register_structure_template("hut", {"size": [2, 1, 2], "palette": ["proving:rock"],
		"blocks": [[0, 0, 0, 0], [1, 0, 0, 0], [0, 0, 1, 0], [1, 0, 1, 0]]})
	api.register_structure("hut_site", {"template": "proving:hut", "rarity": 0.0})
	life.setup(api, ids)
	society.setup(api, ids)
	machines.setup(api, ids)
	presentation.setup(api, ids)
	api.set_spawn_handler(func(_player): return Vector3(0.5, GROUND_Y + 1, 0.5))
	# Something to build and fight with. A game that hands a player nothing leaves every test that
	# wants to place a block having to arrange its own inventory first.
	api.on("player_join", func(ev):
		if bool(ev.get("first_time", false)):
			ev.player.set_hotbar([api.require_block("proving:plain"), api.require_block("proving:lamp"),
				api.require_block("proving:crate"), api.require_block("proving:rock"),
				api.require_block("proving:step")], 64)
			ev.player.give(api.require_item("proving:prod"), 1)
			ev.player.give(api.require_item("proving:grain"), 8))
	apply_caps.call()
	api.register_command("proving", "What this mod registered", func(player, _args):
		player.send_message("proving: %d things registered" % ids.size()))


const GROUND_Y := 64


## Ground at a fixed height with nothing on it. Written here rather than in a submodule because the
## world a test stands on is the first thing anybody reading this file wants to know.
##
## Flat and predictable on purpose: a test that has to go looking for the ground ends up measuring
## terrain generation when it meant to measure something else.
class FlatGround:
	extends RefCounted

	const Chunk = preload("res://engine/shared/chunk.gd")
	## An inner class cannot see the outer script's constants, so the height lives here too.
	const TOP := 64

	var stone := 0
	var dirt := 0
	var grass := 0

	func _init(stone_id: int, dirt_id: int, grass_id: int) -> void:
		stone = stone_id
		dirt = dirt_id
		grass = grass_id

	# Runs on a worker thread and touches only the chunk and ids read at construction.
	#
	# A block is a little-endian u16, so the cell index shifts left by one to become a byte offset -
	# `chunk.blocks[index] = id` writes one byte into the middle of a pair and generates nothing at all.
	# chunk.gd says so on line 3, which I should have read first. (2026-09-21)
	func generate(chunk) -> void:
		for x in Chunk.SIZE_X:
			for z in Chunk.SIZE_Z:
				for y in range(0, TOP + 1):
					var id := stone if y < TOP - 3 else (dirt if y < TOP else grass)
					chunk.blocks.encode_u16(Chunk.index(x, y, z) << 1, id)
