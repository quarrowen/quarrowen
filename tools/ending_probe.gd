extends Node
## Builds the altar in a generated ruin and checks the ending really happens.
##
##   godot --headless --path . res://tools/ending_probe.tscn
##
## The ending is a chain of four things that each work alone: a structure generates, a multiblock
## notices it is complete, a handler spawns a creature, and a timer moves it. Nothing short of doing
## all four in order proves any of it, and none of them is visible to `mod_tool validate`.

const GameServer = preload("res://engine/server/game_server.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")


func _ready() -> void:
	var server := GameServer.new()
	add_child(server)
	var scratch: String = OS.get_environment("TMPDIR").path_join("qw-ending-%d" % Time.get_ticks_msec())
	if server.start({"mods": PackedStringArray(["firstlight"]), "world": "ending",
			"data_dir": scratch, "seed": 11, "offline": true}) != OK:
		print("start failed")
		return get_tree().quit(1)

	var api = server._api_for("firstlight")
	var at: Vector3 = api.find_structure("altar_site", Vector3.ZERO)
	if at == Vector3.INF:
		print("FAIL no ruin found")
		return get_tree().quit(1)
	print("ruin at %s" % str(at))
	for c in range(-2, 3):
		for d in range(-2, 3):
			server.ensure_area_loaded(Vector3(at.x + c * 16, at.y, at.z + d * 16))

	var origin := Vector3i(at)
	var sun: int = server.registry.ids.get("base:sunstone_block", -1)
	var torch: int = server.registry.ids.get("base:torch", -1)
	var floor_ok := true
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if server.realm.world.get_block_v(origin + Vector3i(dx, 0, dz)) != server.registry.ids.get("base:deepstone", -1):
				floor_ok = false
	print("floor is deepstone: %s" % floor_ok)
	# All four corners, so this does not depend on which way the template was rotated.
	for corner in [Vector3i(-1, 1, -1), Vector3i(1, 1, 1), Vector3i(-1, 1, 1), Vector3i(1, 1, -1)]:
		api.set_block(origin + corner, sun)
	await get_tree().process_frame
	print("altar formed:     %s" % (not api.multiblock_at(origin).is_empty()))

	var before: int = server.entities.entities.size()
	api.set_block(origin + Vector3i(0, 1, 0), torch)
	await get_tree().process_frame
	# The rise runs on a timer; step it forward and watch what the world holds.
	var giant = null
	for i in 80:
		server._time += 0.25
		await get_tree().process_frame
		for e in server.entities.entities.values():
			if str(e.def.get("name", "")) == "base:colossus":
				giant = e
	print("entities before %d, after %d" % [before, server.entities.entities.size()])
	print("colossus spawned: %s" % (giant != null))
	if giant != null:
		print("colossus at %s (altar y %d)" % [str(giant.position), origin.y])
	get_tree().quit(0 if giant != null else 1)
