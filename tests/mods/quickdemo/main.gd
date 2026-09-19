extends RefCounted
## /quickdemo: lays a small quickdust circuit in front of whoever ran it, so a screenshot can show
## what the signals capability looks like in the game. A test fixture, not shipped content.

var api


func setup(mod_api) -> void:
	api = mod_api
	api.register_command("quickdemo", "build a quickdust circuit in front of you", _build, "admin")
	api.register_command("wiredemo", "a generator lighting lamps over strung cable", _wires, "admin")
	api.register_link_kind("cable", {"span": 14, "draw": "cable", "color": "#c8822e"})
	api.register_link_kind("pipe", {"span": 6, "draw": "pipe", "color": "#8a9aa6"})


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

	# Poles with a cable strung between them, and a short rigid pipe beside it, so the two read as
	# different things rather than as one thing drawn twice.
	var poles := []
	for dx in [0, 7, 14]:
		for dy in range(1, 5):
			api.set_block(here + Vector3i(dx, dy, 4), stone)
		poles.append(here + Vector3i(dx, 4, 4))
	for i in poles.size() - 1:
		api.link("cable", {"position": poles[i], "face": 0}, {"position": poles[i + 1], "face": 0})
	for dy in range(1, 3):
		api.set_block(here + Vector3i(2, dy, -2), stone)
		api.set_block(here + Vector3i(7, dy, -2), stone)
	api.link("pipe", {"position": here + Vector3i(2, 2, -2), "face": 0},
		{"position": here + Vector3i(7, 2, -2), "face": 0})
	player.send_message("Quickdust demo built.")


## A generator on one side, lamps on the other, and cable strung between poles across the gap. What
## the networks work is actually for.
func _wires(player, _args) -> void:
	var here := Vector3i(player.position.floor()) + Vector3i(0, -1, 0)
	var stone: int = api.block("base:stone")
	var pole: int = api.block("industry:pole")
	var gen: int = api.block("industry:coal_generator")
	var lamp: int = api.block("industry:lamp")
	if pole <= 0:
		player.send_message("The industry mod is not loaded.")
		return
	# Two little platforms with a gap between them, so the cable has something to span.
	for side in [0, 12]:
		for dx in range(side, side + 5):
			for dz in range(-2, 3):
				api.set_block(here + Vector3i(dx, 0, dz), stone)
				for dy in range(1, 6):
					api.set_block(here + Vector3i(dx, dy, dz), 0)
	for dy in range(1, 4):
		api.set_block(here + Vector3i(2, dy, 0), pole)
		api.set_block(here + Vector3i(14, dy, 0), pole)
	api.set_block(here + Vector3i(1, 1, 0), gen)
	api.set_block(here + Vector3i(15, 1, 0), lamp)
	api.set_block(here + Vector3i(15, 1, 2), lamp)
	api.set_block_data(here + Vector3i(1, 1, 0), {"burn": 600.0})
	api.link("industry:cable", {"position": here + Vector3i(2, 3, 0), "face": 0},
		{"position": here + Vector3i(14, 3, 0), "face": 0})
	# The span is 12 and a cable reaches 14: any further and the engine refuses it, which is exactly
	# what it should do and exactly what it did the first time this demo was written. (2026-09-19)
	player.send_message("Wire demo built: %d links." % api.links_at(here + Vector3i(2, 3, 0)).size())
