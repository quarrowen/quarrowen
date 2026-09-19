extends RefCounted
## /quickdemo: lays a small quickdust circuit in front of whoever ran it, so a screenshot can show
## what the signals capability looks like in the game. A test fixture, not shipped content.

var api


func setup(mod_api) -> void:
	api = mod_api
	api.register_command("quickdemo", "build a quickdust circuit in front of you", _build, "admin")


func _build(player, _args) -> void:
	var here := Vector3i(player.position.floor()) + Vector3i(0, -1, 0)
	var stone: int = api.block("base:stone")
	var dust: int = api.block("base:quickdust")
	var lever: int = api.block("base:lever")
	var lamp: int = api.block("base:quicklamp")
	var ore: int = api.block("base:quickstone")

	# A dark stone plinth to lay it on, so the glow has something to read against.
	for dx in range(-1, 10):
		for dz in range(-4, 5):
			for dy in range(0, 4):
				api.set_block(here + Vector3i(dx, dy, dz), 0 if dy > 0 else stone)
	# A back wall with a seam of quickstone in it.
	for dx in range(-1, 10):
		for dy in range(1, 5):
			api.set_block(here + Vector3i(dx, dy, -4), stone)
	for spot in [Vector3i(1, 2, -4), Vector3i(2, 3, -4), Vector3i(2, 2, -4), Vector3i(5, 3, -4),
			Vector3i(6, 2, -4), Vector3i(6, 3, -4), Vector3i(8, 2, -4)]:
		api.set_block(here + spot, ore)

	# The circuit: a lever, a run of dust, a lamp at each end of a branch.
	api.set_block(here + Vector3i(0, 1, 0), lever)
	for n in range(1, 8):
		api.set_block(here + Vector3i(n, 1, 0), dust)
	for dz in [-2, -1, 1, 2]:
		api.set_block(here + Vector3i(4, 1, dz), dust)
	api.set_block(here + Vector3i(4, 1, 3), lamp)
	api.set_block(here + Vector3i(4, 1, -3), lamp)
	api.set_block(here + Vector3i(8, 1, 0), lamp)
	api.set_signal(here + Vector3i(0, 1, 0), 15)
	player.send_message("Quickdust demo built.")
