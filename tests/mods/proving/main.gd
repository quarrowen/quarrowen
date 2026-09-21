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
	# Flat and predictable. A test that has to go looking for the ground is a test that measures
	# terrain generation when it meant to measure something else.
	api.set_world_generator(FlatGround.new(api.block("proving:rock"), api.block("proving:soil"), api.block("proving:turf")))
	api.set_gameplay({"keep_inventory": true, "natural_regeneration": true, "tutorials": false})
	things.setup(api, ids)
	life.setup(api, ids)
	society.setup(api, ids)
	machines.setup(api, ids)
	presentation.setup(api, ids)
	api.set_spawn_handler(func(_player): return Vector3(0.5, GROUND_Y + 1, 0.5))
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
	func generate(chunk) -> void:
		for x in Chunk.SIZE_X:
			for z in Chunk.SIZE_Z:
				for y in range(0, TOP + 1):
					chunk.blocks[Chunk.index(x, y, z)] = stone if y < TOP - 3 else (dirt if y < TOP else grass)
