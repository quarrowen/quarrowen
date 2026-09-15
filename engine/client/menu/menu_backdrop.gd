extends Node3D
## The main menu's live background: a small world generated in this process by an offline game server
## (no socket, nothing saved), meshed like the game draws it, with a slow orbiting camera, a gentle
## day cycle and the player's avatar standing in front.
##
## Generation runs on worker threads a few chunks at a time, so the menu stays responsive; the world
## fades in when the first ring is ready. `ready_to_show` tells the menu it can hide its plain backdrop.

signal ready_to_show

const GameServer = preload("res://engine/server/game_server.gd")
const ChunkMesher = preload("res://engine/client/chunk_mesher.gd")
const TextureAtlas = preload("res://engine/client/texture_atlas.gd")
const VoxelMaterial = preload("res://engine/client/voxel_material.gd")
const WorldTime = preload("res://engine/shared/world_time.gd")
const Chunk = preload("res://engine/shared/chunk.gd")
const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const Avatar = preload("res://engine/client/avatar/avatar.gd")
const PlayerRig = preload("res://engine/shared/player_rig.gd")
const LookBuilder = preload("res://engine/client/avatar/look_builder.gd")
const Cosmetics = preload("res://engine/shared/cosmetics.gd")
const CreationLibrary = preload("res://engine/client/creation_library.gd")

const DATA_DIR := "user://cache/menu_backdrop"
const RADIUS := 6  # chunks around the centre that are drawn
const ORBIT_SECONDS := 240.0
const ORBIT_RADIUS := 8.0
const DAY_SECONDS := 300.0
const SEEDS := [1337, 4242, 90210, 777, 2026, 31415]

var game := "vanilla"
var avatar_look := {}
var player_name := ""
## Orbiting camera and passing time (off: a still view, for players who prefer less motion).
var motion := true

var _server: Node
var _atlas := {}
var _context := {}
var _solid: ShaderMaterial
var _translucent: ShaderMaterial
var _queue: Array[Vector2i] = []  # chunks still to mesh, nearest first
var _jobs := {}  # coord -> {task_id, chunks, context, result}
var _camera: Camera3D
var _sun: DirectionalLight3D
var _sky: ProceduralSkyMaterial
var _environment: Environment
var _avatar: Avatar
var _looks: LookBuilder
var _centre := Vector3.ZERO
var _heights := {}  # Vector2i column -> surface y, while choosing the spot
var _orbit := 0.0
var _time := 0.3
var _shown := false
var _fade := 0.0


func _ready() -> void:
	_build_scene()
	_start_world.call_deferred()


func _exit_tree() -> void:
	for job: Dictionary in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_jobs.clear()
	_server = null  # a child: freed with this node (it saves nothing, see _start_world)


func _build_scene() -> void:
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color.WHITE
	_environment.ambient_light_energy = 0.55
	_environment.fog_enabled = true
	_environment.fog_mode = Environment.FOG_MODE_DEPTH
	_environment.fog_depth_begin = RADIUS * Chunk.SIZE_X * 0.5
	_environment.fog_depth_end = RADIUS * Chunk.SIZE_X * 1.1
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = _environment
	add_child(world_env)
	_sun = DirectionalLight3D.new()
	_sun.light_energy = 0.8
	add_child(_sun)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.far = RADIUS * Chunk.SIZE_X * 3.0
	add_child(_camera)
	_camera.make_current()
	_apply_time()


func _start_world() -> void:
	# One frame so the menu draws before the (short) synchronous spawn-area generation.
	await get_tree().process_frame
	await get_tree().process_frame
	_server = GameServer.new()
	_server.name = "MenuBackdropServer"
	add_child(_server)
	var err: Error = _server.start({"mods": PackedStringArray(game.split(",", false)), "world": "backdrop_%s" % game.replace(",", "_"),
		"data_dir": DATA_DIR, "seed": SEEDS[randi() % SEEDS.size()], "offline": true, "log_level": "all:error"})
	if err != OK:
		push_warning("[menu] Backdrop world could not start (%s)" % error_string(err))
		_server.free()
		_server = null
		return
	_server._save_dir = ""  # a backdrop, not a world to keep: never saved
	_server.set_physics_process(false)
	_server.set_process(false)
	_build_materials()
	for r in RADIUS + 1:
		for x in range(-r, r + 1):
			for z in range(-r, r + 1):
				if maxi(absi(x), absi(z)) == r:
					_queue.append(Vector2i(x, z))


func _build_materials() -> void:
	var images := {}
	for d in _server.registry.defs:
		for tex: String in d.textures:
			if images.has(tex) or not _server._assets.has(tex):
				continue
			var img := Image.new()
			if img.load_png_from_buffer(FileAccess.get_file_as_bytes(_server._assets[tex].path)) == OK:
				images[tex] = img
	_atlas = TextureAtlas.build(images)
	_solid = VoxelMaterial.create(_atlas.texture, false)
	_translucent = VoxelMaterial.create(_atlas.texture, true)
	_context = ChunkMesher.make_context(_server.registry, _atlas.uv)
	_apply_time()


## A grassy open spot near spawn for the avatar: on grass (not a tree or bare rock), not on a peak,
## with the camera's circle around it free of anything taller than the avatar.
func _find_centre() -> Vector3:
	var best := Vector3(8.5, _surface(8, 8) + 1, 8.5)
	var best_score := -INF
	for x in range(-16, 33, 2):
		for z in range(-16, 33, 2):
			var y := _surface(x, z)
			if y < 0 or y > 900 or not str(_server.registry.defs[_server.world.get_block(x, y, z)].name).contains("grass"):
				continue
			# Nothing taller than the avatar between it and the camera, all the way round.
			var clear := true
			var around := 0.0
			var samples := 0
			for ring in [2.0, 4.0, 6.0, ORBIT_RADIUS, ORBIT_RADIUS + 1.5]:
				for k in 32:
					var b := TAU * k / 32.0
					var h := _surface(x + roundi(cos(b) * ring), z + roundi(sin(b) * ring))
					if h > y + 1 or h < 0:
						clear = false
						break
					around += h
					samples += 1
				if not clear:
					break
			if not clear:
				continue
			# Flat ground near the average height of the area reads as a meadow, not a summit.
			var score := -absf(around / samples - y) * 2.0 - Vector2(x - 8, z - 8).length() * 0.05
			if score > best_score:
				best_score = score
				best = Vector3(x + 0.5, y + 1, z + 0.5)
	return best


## The y of the highest solid block in a column (-1 when none or not loaded).
func _surface(x: int, z: int) -> int:
	var key := Vector2i(x, z)
	if _heights.has(key):
		return _heights[key]
	var height := -1
	if not _server.world.chunks.has(Vector2i(floori(x / float(Chunk.SIZE_X)), floori(z / float(Chunk.SIZE_Z)))):
		height = 999  # unknown: treat as blocked
	else:
		for y in range(Chunk.SIZE_Y - 2, 0, -1):
			var block: int = _server.world.get_block(x, y, z)
			if block != BlockRegistry.AIR and _server.registry.solid_lut[block] == 1:
				height = y
				break
	_heights[key] = height
	return height


func _is_tree(block: int) -> bool:
	var block_name := str(_server.registry.defs[block].name)
	return block_name.contains("leaves") or block_name.contains("log") or block_name.contains("wood")


func _place_avatar() -> void:
	var registry := Cosmetics.new()
	var images := {}
	CreationLibrary.register_all(registry, images)
	_looks = LookBuilder.new(registry, images, CreationLibrary.read_model)
	_avatar = Avatar.new()
	add_child(_avatar)
	_avatar.build(PlayerRig.default_rig())
	_avatar.position = _centre
	refresh_avatar(avatar_look, player_name)


## Shows a (new) look on the menu avatar, e.g. after the avatar editor closes.
func refresh_avatar(look: Dictionary, name_text: String) -> void:
	avatar_look = look
	player_name = name_text
	if _avatar != null and _looks != null:
		_looks.clear_cache()
		_looks.apply(_avatar, look, "")


func _process(delta: float) -> void:
	if motion:
		_time = fposmod(_time + delta / DAY_SECONDS, 1.0)
		_orbit = fposmod(_orbit + delta / ORBIT_SECONDS, 1.0)
	var angle := _orbit * TAU
	var eye := _centre + Vector3(cos(angle) * ORBIT_RADIUS, 3.2, sin(angle) * ORBIT_RADIUS)
	_camera.position = eye
	_camera.look_at(_centre + Vector3(0, 1.8, 0))
	_camera.h_offset = -2.2  # the menu panels sit on the left; keep the avatar right of centre
	if _avatar != null:
		# Face the camera, a little turned, breathing.
		_avatar.rotation.y = atan2(eye.x - _centre.x, eye.z - _centre.z) + PI + 0.35
		_avatar.animate(delta, Vector3.ZERO, true, -0.1)
	_apply_time()
	if _server == null:
		return
	_poll_jobs()
	if _fade < 1.0 and _shown:
		_fade = minf(1.0, _fade + delta * 1.5)


func _poll_jobs() -> void:
	for coord: Vector2i in _jobs.keys():
		var job: Dictionary = _jobs[coord]
		if not WorkerThreadPool.is_task_completed(job.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_jobs.erase(coord)
		_apply_mesh(coord, job.result)
	# Generate what the next mesh needs (the chunk and its neighbours), then mesh it.
	_server._poll_chunk_jobs()
	while _jobs.size() < 2 and not _queue.is_empty():
		var coord: Vector2i = _queue[0]
		var missing := false
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var c := coord + Vector2i(dx, dz)
				if not _server.world.chunks.has(c):
					missing = true
					_server._request_chunk(c)
		if missing:
			return
		_queue.pop_front()
		var chunks := []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				chunks.append(_server.world.chunks[coord + Vector2i(dx, dz)].blocks)
		var job := {"chunks": chunks, "context": _context, "result": []}
		job.task_id = WorkerThreadPool.add_task(func(): job.result = ChunkMesher.build(job.chunks, job.context), false, "menu mesh")
		_jobs[coord] = job
	if not _shown and _queue.size() < (2 * RADIUS + 1) * (2 * RADIUS + 1) - 25 and _jobs.is_empty():
		# Trees and other features spill in from neighbouring chunks as they generate, so the avatar's spot is
		# chosen once the middle of the view is complete.
		_shown = true
		_heights.clear()
		_centre = _find_centre()
		_place_avatar()
		ready_to_show.emit()


func _apply_mesh(coord: Vector2i, result: Array) -> void:
	var node := MeshInstance3D.new()
	node.position = Vector3(coord.x * Chunk.SIZE_X, 0, coord.y * Chunk.SIZE_Z)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := ArrayMesh.new()
	for i in 2:
		if not result[i].is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result[i], [], {}, ChunkMesher.SURFACE_FLAGS)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _solid if i == 0 else _translucent)
	node.mesh = mesh
	add_child(node)


func _apply_time() -> void:
	# Mostly day: sunrise to a little after sunset, then back (a menu should not sit in the dark).
	var time_of_day := lerpf(0.23, 0.77, 0.5 - 0.5 * cos(_time * TAU))
	var daylight := WorldTime.daylight(time_of_day)
	var t := inverse_lerp(WorldTime.NIGHT_LIGHT, 1.0, daylight)
	var sun_height := sin((time_of_day - 0.25) * TAU)
	var sun_tint := Color(0.55, 0.62, 0.9).lerp(Color(1.0, 0.72, 0.5), clampf(t * 3.0, 0.0, 1.0)).lerp(Color(1.0, 0.97, 0.92), clampf((sun_height - 0.15) * 2.5, 0.0, 1.0))
	var sun_direction := Vector3(cos((time_of_day - 0.25) * TAU), sun_height, 0.35).normalized()
	var horizon := Color(0.05, 0.06, 0.12).lerp(Color(0.72, 0.84, 0.96), t).lerp(Color(0.95, 0.62, 0.45), clampf(0.35 - absf(sun_height), 0.0, 0.35))
	_sky.sky_top_color = Color(0.01, 0.02, 0.06).lerp(Color(0.32, 0.54, 0.92), t)
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = horizon
	_sky.ground_bottom_color = Color(0.02, 0.02, 0.04).lerp(Color(0.3, 0.4, 0.55), t)
	_environment.fog_light_color = horizon
	_sun.look_at_from_position(Vector3.ZERO, -sun_direction if sun_direction.y > 0.05 else Vector3(0.3, -1, 0.2))
	_sun.light_color = sun_tint
	_environment.ambient_light_energy = lerpf(0.25, 0.55, t)
	for material in [_solid, _translucent]:
		if material == null:
			continue
		material.set_shader_parameter("daylight", daylight)
		material.set_shader_parameter("sun_tint", Vector3(sun_tint.r, sun_tint.g, sun_tint.b))
		material.set_shader_parameter("sun_direction", sun_direction)
		material.set_shader_parameter("sky_color", Vector3(_sky.sky_top_color.r, _sky.sky_top_color.g, _sky.sky_top_color.b))
		material.set_shader_parameter("horizon_color", Vector3(horizon.r, horizon.g, horizon.b))
