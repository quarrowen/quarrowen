extends Node
## A Firstlight server that builds and lights the altar for you, so the ending can be photographed.
##
##   QW_PORT=24620 godot --headless --path . res://tools/ending_server.tscn
##
## Test scaffolding, not a feature: there is no `/setblock`, so a screenshot of the ending would
## otherwise mean a client aiming at nine particular blocks deep underground. This starts an ordinary
## networked server, finds the ruin world generation placed, repairs the altar and lights it a few
## seconds after somebody joins - which is exactly what a player does, done by the server instead.
##
## Prints where the altar is, so the shot can be told where to stand.

const ServerMain = preload("res://engine/server_main.gd")


func _ready() -> void:
	var main := ServerMain.new()
	main.name = "ServerMain"
	add_child(main)
	await get_tree().create_timer(3.0).timeout
	var server = main.get_node_or_null("GameServer")
	if server == null:
		print("[ending] no server")
		return
	var api = server._api_for("firstlight")
	var at: Vector3 = api.find_structure("altar_site", Vector3.ZERO)
	if at == Vector3.INF:
		print("[ending] no ruin near spawn")
		return
	print("[ending] altar at %d %d %d" % [int(at.x), int(at.y) + 1, int(at.z)])
	# Watch the event from outside the mod, so "the ending did not happen" can be told apart from
	# "the ending happened and did nothing visible".
	api.on("multiblock_formed", func(ev):
		print("[ending] EVENT multiblock_formed %s at %s" % [str(ev.get("name")), str(ev.get("controller"))]))
	for c in range(-2, 3):
		for d in range(-2, 3):
			server.ensure_area_loaded(Vector3(at.x + c * 16, at.y, at.z + d * 16))
	# Wait for somebody to arrive before lighting it: the whole point is to photograph what they see.
	while server.players.is_empty():
		await get_tree().create_timer(0.5).timeout
	# **Put them in the hall first.** `base:colossus` is not persistent, so one spawned with every
	# player 180 blocks away on the surface is removed the same tick for having nobody near it - which
	# looks exactly like a spawn that failed. In a real game you are standing at the altar when you
	# light it; here the server has to arrange that. (2026-09-24)
	for p in server.players.values():
		p.teleport(Vector3(at.x + 4.0, at.y + 3.0, at.z + 9.0))
	await get_tree().create_timer(float(OS.get_environment("QW_ENDING_DELAY") if not OS.get_environment("QW_ENDING_DELAY").is_empty() else "6")).timeout
	var origin := Vector3i(at)
	var sun: int = server.registry.ids.get("base:sunstone_block", -1)
	# All four corners, so this does not depend on which way the template was rotated.
	for corner in [Vector3i(-1, 1, -1), Vector3i(1, 1, 1), Vector3i(-1, 1, 1), Vector3i(1, 1, -1)]:
		api.set_block(origin + corner, sun)
	await get_tree().create_timer(1.0).timeout
	print("[ending] altar multiblock before torch: %s" % str(api.multiblock_at(origin)))
	var corners := []
	for dx in [-1, 1]:
		for dz in [-1, 1]:
			corners.append(server.realm.world.get_block_v(origin + Vector3i(dx, 1, dz)))
	print("[ending] floor=%d (deepstone is %d), corners=%s (sunstone is %d)" % [
		server.realm.world.get_block_v(origin), server.registry.ids.get("base:deepstone", -1),
		str(corners), sun])
	print("[ending] lighting it")
	api.set_block(origin + Vector3i(0, 1, 0), server.registry.ids.get("base:torch", -1))
	# Report what the ending actually does to the world, second by second: a screenshot of a dark room
	# cannot tell "it did not rise" from "it had already gone back down".
	for i in 18:
		await get_tree().create_timer(1.0).timeout
		var seen := []
		for e in server.entities.entities.values():
			if str(e.def.get("name", "")) == "base:colossus":
				seen.append("y=%.2f (altar y %d, %.1f above)" % [e.position.y, origin.y + 1, e.position.y - float(origin.y + 1)])
		if i == 0:
			print("[ending] torch at %s is %d; altar_lit: %s" % [str(origin + Vector3i(0, 1, 0)),
				server.realm.world.get_block_v(origin + Vector3i(0, 1, 0)),
				str(api.multiblock_at(origin + Vector3i(0, 1, 0), "firstlight:altar_lit"))])
		if i < 3:
			var all := []
			for e in server.entities.entities.values():
				all.append("%s@y%.1f" % [str(e.def.get("name", "")), e.position.y])
			print("[ending] t+%ds entities: %s" % [i + 1, ", ".join(all) if not all.is_empty() else "(none at all)"])
		print("[ending] t+%ds colossus: %s" % [i + 1, ", ".join(seen) if not seen.is_empty() else "none"])
