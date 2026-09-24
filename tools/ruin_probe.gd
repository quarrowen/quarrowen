extends Node
## Does the altar ruin actually generate? Scans a band of the deep for sunstone blocks.
const GameServer = preload("res://engine/server/game_server.gd")

func _ready() -> void:
	var server := GameServer.new()
	add_child(server)
	var scratch: String = OS.get_environment("TMPDIR").path_join("qw-ruin-%d" % Time.get_ticks_msec())
	if server.start({"mods": PackedStringArray(["firstlight"]), "world": "ruin",
			"data_dir": scratch, "seed": 11, "offline": true}) != OK:
		print("start failed")
		return get_tree().quit(1)
	server.set_physics_process(false)
	var sunstone: int = server.registry.ids.get("base:sunstone_block", -1)
	print("sunstone_block id: %d" % sunstone)
	var found := 0
	var sites := []
	# Walk a wide area of the deep band the structure set asks for.
	for cx in range(-12, 13):
		for cz in range(-12, 13):
			server.ensure_area_loaded(Vector3(cx * 16 + 8, 14, cz * 16 + 8))
	for x in range(-200, 201, 1):
		for z in range(-200, 201, 1):
			for y in range(4, 26):
				if server.realm.world.get_block_v(Vector3i(x, y, z)) == sunstone:
					found += 1
					if sites.size() < 4 and not sites.any(func(s): return Vector3(s).distance_to(Vector3(x, y, z)) < 20.0):
						sites.append(Vector3i(x, y, z))
	print("sunstone blocks found: %d at %s" % [found, str(sites)])
	# And the locator: does asking where one is agree with where one actually got built?
	var api = server._api_for("firstlight")
	for from in [Vector3.ZERO, Vector3(300, 70, -250)]:
		var at: Vector3 = api.find_structure("altar_site", from)
		print("locator from %s -> %s (%.0f blocks away)" % [str(from), str(at),
			Vector2(at.x - from.x, at.z - from.z).length() if at != Vector3.INF else -1.0])
		if at == Vector3.INF:
			continue
		# Is the hall actually carved? Count air in the box the template claims to occupy.
		for c in range(-2, 3):
			for d in range(-2, 3):
				server.ensure_area_loaded(Vector3(at.x + c * 16, at.y, at.z + d * 16))
		var air := 0
		var headroom := 0
		for dx in range(-10, 11):
			for dz in range(-10, 11):
				for dy in range(1, 18):
					if server.realm.world.get_block_v(Vector3i(at.x + dx, at.y + dy, at.z + dz)) == 0:
						air += 1
		for dy in range(1, 20):
			if server.realm.world.get_block_v(Vector3i(at.x, at.y + dy, at.z)) == 0:
				headroom = dy
			else:
				break
		print("  hall: %d air blocks in the 21x17x21 box, %d clear above the altar" % [air, headroom])
	get_tree().quit(0)
