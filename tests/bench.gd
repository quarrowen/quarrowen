extends Node
## Micro-benchmarks for the engine hot paths, run headless without networking:
##   godot --headless --path . res://tests/bench.tscn -- [--chunks=200] [--steps=20000]
## Prints per-operation timings so GDScript and native implementations can be compared.

const GameServer = preload("res://engine/server/game_server.gd")
const ChunkMesher = preload("res://engine/client/chunk_mesher.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")


func _ready() -> void:
	var chunk_count := 200
	var steps := 20000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--chunks="):
			chunk_count = int(arg.substr(9))
		elif arg.begins_with("--steps="):
			steps = int(arg.substr(8))

	var server := GameServer.new()
	add_child(server)
	DirAccess.make_dir_recursive_absolute("user://bench")
	server.start({"mods": PackedStringArray(["base", "simple_machines", "proving"]), "mod_dirs": PackedStringArray(["res://tests/mods"]), "world": "bench_%d" % Time.get_ticks_msec(),
		"data_dir": "user://bench", "seed": 42, "offline": true})
	var world = server.world
	var side := ceili(sqrt(chunk_count))
	var coords: Array[Vector2i] = []
	for i in chunk_count:
		coords.append(Vector2i(i % side - side / 2, i / side - side / 2))

	var t := Time.get_ticks_usec()
	for c in coords:
		server._ensure_chunk(c)
	_report("worldgen (flat proving terrain)", Time.get_ticks_usec() - t, coords.size(), "chunk")

	var ctx := ChunkMesher.make_context(server.registry, {"": Rect2()})
	var faces := 0
	t = Time.get_ticks_usec()
	for c in coords:
		var neighbourhood := []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				neighbourhood.append(_bytes(world, c + Vector2i(dx, dz)))
		var r := ChunkMesher.build(neighbourhood, ctx)
		for i in 2:
			if not r[i].is_empty():
				faces += r[i][Mesh.ARRAY_INDEX].size() / 6
	_report("mesh build%s (%d quads total)" % [" + lighting + greedy" if ctx.native else "", faces], Time.get_ticks_usec() - t, coords.size(), "chunk")

	var snapshot_players := 100
	var positions := PackedVector3Array()
	for i in snapshot_players:
		positions.append(Vector3(randf_range(-60, 60), 60, randf_range(-60, 60)))
	if ctx.native:
		var ids := PackedInt32Array(range(snapshot_players))
		var zeros_f := PackedFloat32Array()
		zeros_f.resize(snapshot_players)
		var zeros_b := PackedByteArray()
		zeros_b.resize(snapshot_players)
		t = Time.get_ticks_usec()
		for round in 100:
			ClassDB.class_call_static(&"NativeSnapshots", &"build", ids, ids, positions, positions, zeros_f, zeros_f, zeros_b, 96.0, 32.0, round % 2 == 0)
		_report("snapshots for %d clustered players" % snapshot_players, Time.get_ticks_usec() - t, 100, "round")

	t = Time.get_ticks_usec()
	for c in coords:
		world.chunks[c].encode()
	_report("chunk encode (zstd)", Time.get_ticks_usec() - t, coords.size(), "chunk")

	var state := PlayerPhysics.State.new()
	state.position = server._default_spawn()
	var input := PlayerPhysics.PlayerInput.new()
	input.move = Vector2(0.3, 1.0)
	input.sprint = true
	t = Time.get_ticks_usec()
	for i in steps:
		input.yaw = i * 0.002
		input.jump = i % 40 == 0
		PlayerPhysics.step(state, input, world, server.rules)
	_report("player physics step", Time.get_ticks_usec() - t, steps, "step")
	print("[bench] physics ended at %s (sanity check)" % state.position)

	# Entity simulation: mobs hunting 10 players (perception, pathfinding, tactics) plus pigs and
	# resting item stacks in the loaded area.
	server.set_physics_process(false)
	var spawn := server._default_spawn()
	var ServerPlayer = load("res://engine/server/server_player.gd")
	for i in 10:
		var p = ServerPlayer.new(server, 1000 + i, "Bench%d" % i)
		var px := randf_range(-50, 50)
		var pz := randf_range(-50, 50)
		p.state.position = Vector3(px, server.surface_height(floori(px), floori(pz)) + 1, pz)
		p.set_max_health(1000000.0)
		p.health = 1000000.0
		server.players[p.peer_id] = p
	for kind in [["proving:biter", 150], ["proving:grazer", 150]]:
		for i in kind[1]:
			var x := randf_range(-60, 60)
			var z := randf_range(-60, 60)
			var y: int = server.surface_height(floori(x), floori(z))
			server.entities.spawn(server.entities.registry.id_of(kind[0]), Vector3(x, y + 1, z))
	var coal: int = server.items.id_of("base:coal")
	for i in 200:
		server.entities.drop_item(coal, 1, spawn + Vector3(randf_range(-30, 30), 20, randf_range(-30, 30)))
	for i in 180:
		server._time += 1.0 / 60.0
		server.entities.tick(1.0 / 60.0)  # let items settle, mobs acquire targets
	var engaged := 0
	t = Time.get_ticks_usec()
	for i in 600:
		server._time += 1.0 / 60.0
		server.tick += 1
		server.entities.tick(1.0 / 60.0)
		for p in server.players.values():
			p.hurt_timer = 0.0
	for brain in server.entities.ai.brains.values():
		if brain.behavior in ["engage", "search", "investigate"]:
			engaged += 1
	_report("entity tick (%d mobs, %d hunting, 200 items)" % [server.entities.ai.brains.size(), engaged], Time.get_ticks_usec() - t, 600, "tick")
	server.players.clear()

	server.queue_free()
	await get_tree().process_frame
	_remove_tree(ProjectSettings.globalize_path("user://bench"))
	get_tree().quit()


func _bytes(world, coord: Vector2i) -> PackedByteArray:
	var chunk = world.chunks.get(coord)
	return chunk.blocks if chunk != null else PackedByteArray()


func _report(what: String, usec: int, count: int, unit: String) -> void:
	print("[bench] %-40s %8.3f ms/%s  (%d in %.2f s)" % [what, usec / 1000.0 / count, unit, count, usec / 1e6])


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
