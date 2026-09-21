extends RefCounted
## In-game structure authoring (admins): select a box, save it as a template, place templates.
##   /struct pos1 | pos2     corners from the block you look at (or where you stand)
##   /struct save <name> [keep_air]   saves to the world's structures/ folder as template "world:<name>"
##   /struct place <name> [rotation]  places a template at the block you look at
##   /struct list
## Saved files are plain JSON: copy one into a mod and register it with register_structure_template.

const Structures = preload("res://engine/server/worldgen/structures.gd")
const VoxelRaycast = preload("res://engine/shared/voxel_raycast.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")
const MAX_VOLUME := 64 * 64 * 64

var _server
var _selections := {}  # peer id -> {a, b}


func _init(game_server) -> void:
	_server = game_server


func folder() -> String:
	return _server._save_dir + "/structures"


## Loads templates saved in this world's structures/ folder as "world:<name>".
func load_saved() -> void:
	if _server.biome_generator == null:
		return
	var dir := DirAccess.open(folder())
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".json"):
			var doc = JSON.parse_string(FileAccess.get_file_as_string(folder().path_join(file)))
			if doc is Dictionary:
				_server.biome_generator.structures.add_template("world:" + file.get_basename(), doc)


func command(player, args: PackedStringArray) -> void:
	if args.is_empty():
		player.send_message("Usage: /struct pos1 | pos2 | save <name> [keep_air] | place <name> [rotation] | list")
		return
	match args[0]:
		"pos1", "pos2":
			var sel: Dictionary = _selections.get(player.peer_id, {})
			sel["a" if args[0] == "pos1" else "b"] = _aimed(player)
			_selections[player.peer_id] = sel
			player.send_message("%s set to %s" % [args[0], sel["a" if args[0] == "pos1" else "b"]])
			if sel.has("a") and sel.has("b") and player._online():
				Net.s_selection.rpc_id(player.peer_id, sel.a, sel.b, true)
		"save":
			var sel: Dictionary = _selections.get(player.peer_id, {})
			if args.size() < 2 or not (sel.has("a") and sel.has("b")):
				player.send_message("Set pos1 and pos2 first, then /struct save <name>")
				return
			var name := args[1].validate_filename().to_lower()
			var extent: Vector3i = (sel.a - sel.b).abs() + Vector3i.ONE
			if extent.x * extent.y * extent.z > MAX_VOLUME:
				player.send_message("That selection is too big (max 64x64x64)")
				return
			var doc := Structures.capture(_server, sel.a, sel.b, args.size() > 2 and args[2] == "keep_air")
			DirAccess.make_dir_recursive_absolute(folder())
			var file := FileAccess.open(folder().path_join(name + ".json"), FileAccess.WRITE)
			file.store_string(JSON.stringify(doc))
			file.close()
			if _server.biome_generator != null:
				_server.biome_generator.structures.add_template("world:" + name, doc)
			player.send_message("Saved template world:%s (%d blocks) to %s" % [name, doc.blocks.size(), folder().path_join(name + ".json")])
			if player._online():
				Net.s_selection.rpc_id(player.peer_id, sel.a, sel.b, false)
		"place":
			if args.size() < 2 or _server.biome_generator == null:
				player.send_message("Usage: /struct place <template> [rotation 0-3]")
				return
			var template_name := args[1] if args[1].contains(":") else "world:" + args[1]
			var ok := place(template_name, _aimed(player) + Vector3i.UP, int(args[2]) if args.size() > 2 else 0)
			player.send_message("Placed %s" % template_name if ok else "No template named %s" % template_name)
		"list":
			var names: Array = _server.biome_generator.structures.templates.keys() if _server.biome_generator != null else []
			player.send_message("Templates: %s" % ", ".join(PackedStringArray(names)))
		_:
			player.send_message("Unknown /struct option")


## Places a template now (world edits and block data), corner at `at`.
func place(template_name: String, at: Vector3i, rotation := 0, into = null) -> bool:
	var structures = _server.biome_generator.structures
	var t: Dictionary = structures.templates.get(template_name, {})
	if t.is_empty():
		return false
	for b in t.blocks:
		var p: Vector3i = at + Structures.rotate(Vector3i(b[0], b[1], b[2]), t.size, rotation)
		_server.set_block_authoritative(p, b[3], false, structures._rotate_state(b[3], b[4], rotation), into)
	for local: Vector3i in t.data:
		var p: Vector3i = at + Structures.rotate(local, t.size, rotation)
		var entry: Dictionary = t.data[local].duplicate(true)
		entry.structure_seed = hash([p.x, p.y, p.z, randi()])
		_server.set_block_data(p, entry, into)
	return true


func _aimed(player) -> Vector3i:
	var eye: Vector3 = player.get_eye_position()
	var ray: Dictionary = VoxelRaycast.cast(_server.realm_of(player).world, _server.registry.solid_lut, eye, PlayerPhysics.look_direction(player.yaw, player.pitch), 8.0)
	if ray.hit:
		return ray.position
	return Vector3i(floori(player.state.position.x), floori(player.state.position.y) - 1, floori(player.state.position.z))
