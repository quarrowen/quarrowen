extends Node
## Authoritative game server engine. Loads mods, which define the content and rules; owns the world;
## simulates every player from their inputs; validates edits; streams content, chunks and snapshots.

const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const Chunk = preload("res://engine/shared/chunk.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")
const ModApi = preload("res://engine/server/mod_api.gd")
const ModLoader = preload("res://engine/server/mod_loader.gd")
const JsMod = preload("res://engine/server/js_mod.gd")
const Identity = preload("res://engine/shared/identity.gd")
const Native = preload("res://engine/shared/native.gd")
const WorldTime = preload("res://engine/shared/world_time.gd")
const ItemRegistry = preload("res://engine/shared/item_registry.gd")

const DEFAULT_MAX_PLAYERS := 64
## Other players are replicated only within this distance (blocks) of the recipient...
const INTEREST_RADIUS := 96.0
## ...and beyond this distance only on every other snapshot.
const NEAR_RADIUS := 32.0
const VIEW_RADIUS := 8
const UNLOAD_MARGIN := 2
const SPAWN_RADIUS := 2
const CHUNK_SENDS_PER_PLAYER_PER_TICK := 3
## Pending chunks examined per player per tick while looking for ready ones to send.
const STREAM_SCAN := 48
const TIME_SYNC_INTERVAL := 30.0
const SNAPSHOT_INTERVAL_TICKS := 3
const MAX_QUEUED_INPUTS := 30
const MAX_INPUTS_PER_PACKET := 5
const REACH := 6.0
const EDITS_PER_SECOND := 15.0
const CHAT_MAX_LENGTH := 160
const SAVE_INTERVAL := 10.0
const WORLD_UNLOAD_INTERVAL := 10.0

var registry := BlockRegistry.new()
var items := ItemRegistry.new(registry)
var rules := PlayerPhysics.Rules.new()
var world := VoxelWorld.new()
var world_seed := 0
var server_info := {"name": "VoxelCraft Server", "game": "", "description": "", "motd": "", "mods": []}
var generator: Object = null
## Objects with decorate(chunk, world_seed) run after the generator on worker threads (e.g. ores).
var generation_passes: Array = []
var spawn_handler := Callable()
var players := {}  # peer_id -> ServerPlayer
var tick := 0

var _joining := {}  # peer_id -> {name, queue: Array, offset, requested}
var _assets := {}  # asset name -> {path, hash, size}
var _asset_bytes := {}  # hash -> PackedByteArray
var _handlers := {}  # event -> Array of [priority, Callable]
var _commands := {}  # name -> {description, handler, mod}
var _tasks := {}  # id -> {due, interval, callback}
var _task_seq := 0
var _time := 0.0
var _save_dir := ""
var _meta := {}
var _max_chunk_jobs := maxi(2, OS.get_processor_count() - 2)
var _chunk_jobs := {}  # Vector2i -> job Dictionary (load/generate on a worker thread)
var _save_task := -1
## Delta persistence: only edits relative to freshly generated terrain are saved.
var _deltas := {}  # Vector2i chunk -> {local index: block id}
var _generated := {}  # Vector2i chunk -> PackedByteArray as generated (kept while the chunk has edits)
var _block_data := {}  # Vector2i chunk -> {Vector3i: Dictionary}
var _save_dirty := {}  # Vector2i chunk -> true
var _js_mods: Array = []  # keeps JavaScript runtimes alive
var _recipes: Array = []  # {inputs: {item id: count}, output: item id, count}
var _snapshot_round := 0
var _time_of_day := 0.5
var _day_length := 0.0
var _time_sync_timer := 0.0
var _admin_token := ""
## Lower-case names or player ids granted admin by configuration (VOXEL_ADMINS).
var _config_admins := {}
var _save_timer := 0.0
var _unload_timer := 0.0
var _view_offsets: Array[Vector2i] = []
var _started := false
var _metrics_interval := 0.0
var _metrics := {}


## config keys:
##   port, max_players, world, seed, admin_token, mods (PackedStringArray), mod_dirs (PackedStringArray, searched
##   before res://mods), data_dir (default user://worlds), metrics (seconds between reports, 0 = off),
##   offline (true = load mods and world without opening a socket, for benchmarks)
func start(config: Dictionary) -> Error:
	_admin_token = config.get("admin_token", "")
	for entry in String(config.get("admins", "")).split(",", false):
		_config_admins[entry.strip_edges().to_lower()] = true
	_metrics_interval = float(config.get("metrics", 0.0))
	Engine.max_fps = 60
	var data_dir := String(config.get("data_dir", "user://worlds"))
	_save_dir = data_dir.path_join(String(config.get("world", "world")).validate_filename())
	DirAccess.make_dir_recursive_absolute(_save_dir + "/chunks")
	_load_meta(int(config.get("seed", -1)))
	world_seed = int(_meta.seed)
	_register_builtin_commands()

	var err := _load_mods(config.get("mods", PackedStringArray()), config.get("mod_dirs", PackedStringArray()))
	if err != OK:
		return err
	_hash_assets()
	_apply_rules_to_world()
	_build_view_offsets()

	for x in range(-SPAWN_RADIUS, SPAWN_RADIUS + 1):
		for z in range(-SPAWN_RADIUS, SPAWN_RADIUS + 1):
			_ensure_chunk(Vector2i(x, z))

	if config.get("offline", false):
		return OK
	err = Net.create_server(int(config.get("port", 24565)), int(config.get("max_players", DEFAULT_MAX_PLAYERS)))
	if err != OK:
		printerr("[server] Failed to listen on port %d: %s" % [config.get("port"), error_string(err)])
		return err
	Net.server = self
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_started = true
	print("[server] '%s' running game '%s' with mods %s, %d blocks, %d assets, seed %d, port %d" % [
		server_info.name, server_info.game, server_info.mods, registry.defs.size(), _assets.size(), world_seed, config.get("port")])
	return OK


func _exit_tree() -> void:
	for job: Dictionary in _chunk_jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_chunk_jobs.clear()
	if not _save_dir.is_empty():
		_save_all(true)
	if Net.server == self:
		Net.server = null


# --- Mods ---------------------------------------------------------------------------------------

func _load_mods(requested: PackedStringArray, extra_dirs: PackedStringArray) -> Error:
	# External folders come first so a deployment can override bundled mods.
	var dirs := ModLoader.search_dirs(extra_dirs)
	var available := ModLoader.discover(dirs)
	if requested.is_empty():
		printerr("[server] No mods requested. Available: %s" % ", ".join(available.keys()))
		return ERR_INVALID_PARAMETER
	var order := ModLoader.resolve(requested, available)
	if order.is_empty():
		return ERR_CANT_RESOLVE
	for manifest in order:
		if String(manifest.main).get_extension() == "js":
			var js_mod := JsMod.new(self, manifest)
			var js_error := js_mod.load()
			if js_error != OK:
				return js_error
			_js_mods.append(js_mod)
			server_info.mods.append("%s@%s" % [manifest.id, manifest.version])
			print("[server] Loaded JavaScript mod %s %s" % [manifest.id, manifest.version])
			continue
		var script = load(manifest.dir.path_join(manifest.main))
		if script == null or not script.can_instantiate():
			printerr("[server] Mod '%s' failed to load %s" % [manifest.id, manifest.main])
			return ERR_PARSE_ERROR
		var instance = script.new()
		if not instance.has_method("setup"):
			printerr("[server] Mod '%s' has no setup(api) method" % manifest.id)
			return ERR_INVALID_DATA
		instance.setup(ModApi.new(self, manifest))
		server_info.mods.append("%s@%s" % [manifest.id, manifest.version])
		print("[server] Loaded mod %s %s" % [manifest.id, manifest.version])
	# The game is the first requested mod marked as one; add-ons like industry follow it.
	var game: Dictionary = available[requested[requested.size() - 1]]
	for id in requested:
		if available[id].game:
			game = available[id]
			break
	server_info.game = game.name
	if server_info.description.is_empty():
		server_info.description = game.description
	return OK


func mod_storage(mod_id: String) -> Dictionary:
	if not _meta.mod_storage.has(mod_id):
		_meta.mod_storage[mod_id] = {}
	return _meta.mod_storage[mod_id]


func add_asset(asset_name: String, path: String) -> void:
	if _assets.has(asset_name):
		return
	if not FileAccess.file_exists(path):
		push_error("[server] Asset not found: %s (%s)" % [asset_name, path])
		return
	_assets[asset_name] = {"path": path}


func _hash_assets() -> void:
	for asset_name: String in _assets:
		var bytes := FileAccess.get_file_as_bytes(_assets[asset_name].path)
		if bytes.size() > Protocol.MAX_ASSET_SIZE:
			push_error("[server] Asset %s exceeds %d bytes" % [asset_name, Protocol.MAX_ASSET_SIZE])
			continue
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(bytes)
		var hash := ctx.finish().hex_encode()
		_assets[asset_name].hash = hash
		_assets[asset_name].size = bytes.size()
		_asset_bytes[hash] = bytes


func set_rules(values: Dictionary) -> void:
	rules.apply_dict(values)
	_apply_rules_to_world()
	if _started:
		for p: ServerPlayer in players.values():
			Net.s_rules.rpc_id(p.peer_id, rules.to_dict())


func _apply_rules_to_world() -> void:
	rules.solid_lut = registry.solid_lut
	rules.liquid_lut = registry.liquid_lut
	world.set_lookup_tables(registry.solid_lut, registry.liquid_lut)
	world.void_below = rules.void_below


# --- Events, commands, scheduler ----------------------------------------------------------------

func add_handler(event: String, handler: Callable, priority: int) -> void:
	var list: Array = _handlers.get(event, [])
	list.append([priority, handler])
	list.sort_custom(func(a, b): return a[0] > b[0])
	_handlers[event] = list


func emit(event: String, payload: Dictionary) -> Dictionary:
	for entry in _handlers.get(event, []):
		var handler: Callable = entry[1]
		if handler.is_valid():
			handler.call(payload)
	return payload


## permission: "" (everyone) or "admin".
func add_command(command: String, description: String, handler: Callable, mod_id: String, permission := "") -> void:
	_commands[command.to_lower()] = {"description": description, "handler": handler, "mod": mod_id, "permission": permission}


func is_admin(p) -> bool:
	return p != null and (_meta.admins.has(p.player_id) or _config_admins.has(p.player_id) or _config_admins.has(p.name.to_lower()))


func _permitted(p, command: Dictionary) -> bool:
	return command.get("permission", "") != "admin" or is_admin(p)


func schedule(seconds: float, callback: Callable, interval: float) -> int:
	_task_seq += 1
	_tasks[_task_seq] = {"due": _time + maxf(seconds, 0.0), "interval": interval, "callback": callback}
	return _task_seq


func cancel_task(task_id: int) -> void:
	_tasks.erase(task_id)


func _run_tasks() -> void:
	for id: int in _tasks.keys():
		var task = _tasks.get(id)
		if task == null or task.due > _time:
			continue
		if task.interval > 0.0:
			task.due += task.interval
		else:
			_tasks.erase(id)
		if task.callback.is_valid():
			task.callback.call()


func _register_builtin_commands() -> void:
	add_command("help", "List commands", _cmd_help, "engine")
	add_command("players", "List online players", _cmd_players, "engine")
	add_command("op", "<player> - grant admin", _cmd_op.bind(true), "engine", "admin")
	add_command("deop", "<player> - revoke admin", _cmd_op.bind(false), "engine", "admin")
	add_command("kick", "<player> [reason] - disconnect a player", _cmd_kick, "engine", "admin")
	add_command("whoami", "Show your player id and permissions", _cmd_whoami, "engine")


func _cmd_help(player, _args: PackedStringArray) -> void:
	var names := _commands.keys()
	names.sort()
	for n in names:
		if _permitted(player, _commands[n]):
			player.send_message("/%s - %s" % [n, _commands[n].description])


func _cmd_op(player, args: PackedStringArray, grant: bool) -> void:
	var target = _find_online(args[0] if args.size() > 0 else "")
	if target == null:
		player.send_message("No online player named '%s'" % (args[0] if args.size() > 0 else ""))
		return
	if grant and not _meta.admins.has(target.player_id):
		_meta.admins.append(target.player_id)
	elif not grant:
		_meta.admins.erase(target.player_id)
	broadcast_chat("%s %s admin rights for %s" % [player.name, "granted" if grant else "revoked", target.name])


func _cmd_kick(player, args: PackedStringArray) -> void:
	var target = _find_online(args[0] if args.size() > 0 else "")
	if target == null:
		player.send_message("No online player named '%s'" % (args[0] if args.size() > 0 else ""))
		return
	kick(target.peer_id, " ".join(args.slice(1)) if args.size() > 1 else "Kicked by %s" % player.name)


func _cmd_whoami(player, _args: PackedStringArray) -> void:
	player.send_message("%s: player id %s%s" % [player.name, player.player_id, " (admin)" if is_admin(player) else ""])


func _find_online(player_name: String):
	for p: ServerPlayer in players.values():
		if p.name.to_lower() == player_name.to_lower():
			return p
	return null


func _cmd_players(player, _args: PackedStringArray) -> void:
	var names := PackedStringArray()
	for p: ServerPlayer in players.values():
		names.append(p.name)
	player.send_message("Online (%d): %s" % [names.size(), ", ".join(names)])


# --- Tick ---------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	tick += 1
	_time += delta
	_stream_assets()
	_poll_chunk_jobs()
	_advance_time(delta)
	var sim_usec := 0
	var stream_usec := 0
	for p: ServerPlayer in players.values():
		var a := Time.get_ticks_usec()
		_simulate_player(p)
		var b := Time.get_ticks_usec()
		p.edit_tokens = minf(p.edit_tokens + EDITS_PER_SECOND * delta, EDITS_PER_SECOND)
		_stream_chunks(p)
		sim_usec += b - a
		stream_usec += Time.get_ticks_usec() - b
	var t1 := Time.get_ticks_usec()
	_run_tasks()
	emit("tick", {"delta": delta, "tick": tick})
	var t2 := Time.get_ticks_usec()

	if tick % SNAPSHOT_INTERVAL_TICKS == 0 and not players.is_empty():
		_send_snapshots()
	var t3 := Time.get_ticks_usec()

	_save_timer += delta
	if _save_timer >= SAVE_INTERVAL:
		_save_timer = 0.0
		_save_all()
	_unload_timer += delta
	if _unload_timer >= WORLD_UNLOAD_INTERVAL:
		_unload_timer = 0.0
		_unload_unused_chunks()
	if _metrics_interval > 0.0:
		_record_metrics(delta, Time.get_ticks_usec() - t0, sim_usec, stream_usec, t2 - t1, t3 - t2)


func _record_metrics(delta: float, total: int, sim: int, stream: int, mods: int, snapshot: int) -> void:
	var m := _metrics
	if m.is_empty():
		m.merge({"elapsed": 0.0, "ticks": 0, "total": 0, "max": 0, "sim": 0, "stream": 0, "mods": 0, "snapshot": 0, "gen": 0, "gen_usec": 0})
	m.elapsed += delta
	m.ticks += 1
	m.total += total
	m.max = maxi(m.max, total)
	m.sim += sim
	m.stream += stream
	m.mods += mods
	m.snapshot += snapshot
	if m.elapsed < _metrics_interval:
		return
	var sent := 0
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer and peer.host:
		sent = int(peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
	var n := float(m.ticks)
	print("[metrics] players %d  chunks %d  tick avg %.2f ms (max %.2f)  sim %.3f  stream+gen %.2f (%d gens, %.2f ms each)  mods %.3f  snapshot %.3f  out %.1f KB/s" % [
		players.size(), world.chunks.size(), m.total / n / 1000.0, m.max / 1000.0, m.sim / n / 1000.0,
		m.stream / n / 1000.0, m.gen, (m.gen_usec / maxf(m.gen, 1.0)) / 1000.0, m.mods / n / 1000.0,
		m.snapshot / n / 1000.0, sent / m.elapsed / 1024.0])
	_metrics = {}


func _simulate_player(p: ServerPlayer) -> void:
	# Normally one input per tick; consume two when the client is ahead to drain jitter backlog.
	var budget := 2 if p.input_queue.size() > 3 else 1
	while budget > 0 and not p.input_queue.is_empty():
		var input = p.input_queue.pop_front()
		PlayerPhysics.step(p.state, input, world, rules)
		p.last_processed_seq = input.seq
		budget -= 1


func _send_snapshots() -> void:
	_snapshot_round += 1
	var full_rate := _snapshot_round % 2 == 0
	var list: Array = players.values()
	if Native.enabled():
		var ids := PackedInt32Array()
		var seqs := PackedInt32Array()
		var positions := PackedVector3Array()
		var velocities := PackedVector3Array()
		var yaws := PackedFloat32Array()
		var pitches := PackedFloat32Array()
		var grounded := PackedByteArray()
		for p: ServerPlayer in list:
			ids.append(p.peer_id)
			seqs.append(p.last_processed_seq)
			positions.append(p.state.position)
			velocities.append(p.state.velocity)
			yaws.append(p.yaw)
			pitches.append(p.pitch)
			grounded.append(1 if p.state.on_ground else 0)
		var payloads: Array = ClassDB.class_call_static(&"NativeSnapshots", &"build", ids, seqs, positions,
			velocities, yaws, pitches, grounded, INTEREST_RADIUS, NEAR_RADIUS, full_rate)
		for i in mini(list.size(), payloads.size()):
			Net.s_snapshot.rpc_id(list[i].peer_id, tick, payloads[i])
		return
	for p: ServerPlayer in list:
		Net.s_snapshot.rpc_id(p.peer_id, tick, _build_snapshot(p, full_rate))


## Per-player snapshot: the recipient's own authoritative state, then compact entries for other
## players within INTEREST_RADIUS (beyond NEAR_RADIUS only at full rate). GDScript twin of
## NativeSnapshots.build; both produce the same layout.
func _build_snapshot(p: ServerPlayer, full_rate: bool) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	var s = p.state
	buf.put_32(p.last_processed_seq)
	buf.put_float(s.position.x)
	buf.put_float(s.position.y)
	buf.put_float(s.position.z)
	buf.put_float(s.velocity.x)
	buf.put_float(s.velocity.y)
	buf.put_float(s.velocity.z)
	buf.put_u8(1 if s.on_ground else 0)
	var count_at := buf.get_position()
	buf.put_u16(0)
	var count := 0
	var radius_sq := INTEREST_RADIUS * INTEREST_RADIUS
	var near_sq := NEAR_RADIUS * NEAR_RADIUS
	for other: ServerPlayer in players.values():
		if other == p:
			continue
		var dist_sq: float = other.state.position.distance_squared_to(s.position)
		if dist_sq > radius_sq or (dist_sq > near_sq and not full_rate):
			continue
		buf.put_32(other.peer_id)
		buf.put_float(other.state.position.x)
		buf.put_float(other.state.position.y)
		buf.put_float(other.state.position.z)
		buf.put_u16(int(wrapf(other.yaw, 0.0, TAU) / TAU * 65535.0))
		buf.put_16(int(clampf(other.pitch, -PI * 0.5, PI * 0.5) / (PI * 0.5) * 32767.0))
		count += 1
	var end := buf.get_position()
	buf.seek(count_at)
	buf.put_u16(count)
	buf.seek(end)
	return buf.data_array


# --- World time ---------------------------------------------------------------------------------

func _advance_time(delta: float) -> void:
	if _day_length > 0.0:
		_time_of_day = fposmod(_time_of_day + delta / _day_length, 1.0)
	_time_sync_timer += delta
	if _time_sync_timer >= TIME_SYNC_INTERVAL:
		_time_sync_timer = 0.0
		_broadcast_time()


## `time_of_day`: 0 = midnight, 0.25 = sunrise, 0.5 = noon. `day_length` in seconds, 0 = frozen.
func set_world_time(time_of_day: float, day_length: float) -> void:
	_time_of_day = fposmod(time_of_day, 1.0)
	_day_length = maxf(day_length, 0.0)
	_broadcast_time()


func get_time_of_day() -> float:
	return _time_of_day


func get_day_length() -> float:
	return _day_length


func _broadcast_time() -> void:
	for p: ServerPlayer in players.values():
		Net.s_time.rpc_id(p.peer_id, _time_of_day, _day_length)


# --- Joining & content delivery -----------------------------------------------------------------

func on_hello(peer_id: int, protocol: int, player_name: String, public_key: String) -> void:
	if players.has(peer_id) or _joining.has(peer_id):
		return
	if protocol != Protocol.VERSION:
		kick(peer_id, "Protocol mismatch: server %d, client %d" % [Protocol.VERSION, protocol])
		return
	var key := Identity.parse_public_key(public_key)
	if key == null:
		kick(peer_id, "Invalid identity key")
		return
	var player_id := Identity.player_id(key)
	var clean_name := player_name.strip_edges().left(16)
	if clean_name.is_empty():
		clean_name = "Player%d" % (peer_id % 1000)
	for p: ServerPlayer in players.values():
		if p.player_id == player_id:
			kick(peer_id, "You are already connected")
			return
		if p.name.to_lower() == clean_name.to_lower():
			kick(peer_id, "The name '%s' is already in use" % clean_name)
			return
	var owner := String(_meta.names.get(clean_name.to_lower(), ""))
	if not owner.is_empty() and owner != player_id:
		kick(peer_id, "The name '%s' belongs to another player on this server" % clean_name)
		return
	var nonce := Identity.new_nonce()
	_joining[peer_id] = {"name": clean_name, "player_id": player_id, "key": key, "nonce": nonce,
		"authenticated": false, "queue": [], "offset": 0, "requested": false}
	Net.s_challenge.rpc_id(peer_id, nonce)


## The client proves it holds the private key for the identity it presented.
func on_auth(peer_id: int, signature: PackedByteArray) -> void:
	var j: Dictionary = _joining.get(peer_id, {})
	if j.is_empty() or j.authenticated:
		return
	if not Identity.verify(j.key, j.nonce, signature):
		_joining.erase(peer_id)
		kick(peer_id, "Authentication failed")
		return
	j.authenticated = true
	_meta.names[String(j.name).to_lower()] = j.player_id
	var manifest := []
	for asset_name: String in _assets:
		var a: Dictionary = _assets[asset_name]
		if a.has("hash"):
			manifest.append([asset_name, a.hash, a.size])
	var content := {"blocks": registry.to_network(), "items": items.to_network(), "rules": rules.to_dict()}
	Net.s_server_info.rpc_id(peer_id, server_info, content, manifest)


## The local host proves it launched this server and becomes a permanent admin.
func on_claim_admin(peer_id: int, token: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or _admin_token.is_empty() or token != _admin_token:
		return
	if not _meta.admins.has(p.player_id):
		_meta.admins.append(p.player_id)
	p.send_message("You are an admin on this server.")


func on_request_assets(peer_id: int, hashes: PackedStringArray) -> void:
	var j: Dictionary = _joining.get(peer_id, {})
	if j.is_empty() or j.requested or not j.authenticated:
		return
	j.requested = true
	for hash in hashes.slice(0, Protocol.MAX_ASSETS):
		if _asset_bytes.has(hash) and not j.queue.has(hash):
			j.queue.append(hash)


func _stream_assets() -> void:
	for peer_id: int in _joining:
		var j: Dictionary = _joining[peer_id]
		var budget := Protocol.ASSET_BYTES_PER_TICK
		while budget > 0 and not j.queue.is_empty():
			var hash: String = j.queue[0]
			var bytes: PackedByteArray = _asset_bytes[hash]
			var piece := bytes.slice(j.offset, j.offset + Protocol.ASSET_PIECE_SIZE)
			Net.s_asset_piece.rpc_id(peer_id, hash, j.offset, bytes.size(), piece)
			j.offset += piece.size()
			budget -= maxi(piece.size(), 1)
			if j.offset >= bytes.size():
				j.queue.pop_front()
				j.offset = 0


func on_client_ready(peer_id: int) -> void:
	var j: Dictionary = _joining.get(peer_id, {})
	if j.is_empty() or not j.requested or not j.queue.is_empty():
		return
	_joining.erase(peer_id)
	_spawn_player(peer_id, j.name, j.player_id)


func _spawn_player(peer_id: int, player_name: String, player_id: String) -> void:
	var p := ServerPlayer.new(self, peer_id, player_name)
	p.player_id = player_id
	p.edit_tokens = EDITS_PER_SECOND
	var saved = _meta.players.get(player_id)
	var first_time := not (saved is Dictionary)
	if not first_time:
		var pos = saved.get("position")
		if pos is Array and pos.size() == 3:
			p.state.position = Vector3(pos[0], pos[1], pos[2])
		p.inventory.load_packed(PackedInt32Array(saved.get("inventory", [])))
		p.inventory.creative = bool(saved.get("creative", false))
		p.data = saved.get("data", {}) if saved.get("data") is Dictionary else {}
	players[peer_id] = p
	if first_time:
		p.state.position = spawn_handler.call(p) if spawn_handler.is_valid() else _default_spawn()
	ensure_area_loaded(p.state.position)

	Net.s_welcome.rpc_id(peer_id, peer_id, p.state.position, 0.0)
	Net.s_time.rpc_id(peer_id, _time_of_day, _day_length)
	p.sync_inventory()
	for other: ServerPlayer in players.values():
		if other != p:
			Net.s_player_joined.rpc_id(peer_id, other.peer_id, other.name)
			Net.s_player_joined.rpc_id(other.peer_id, peer_id, player_name)
	if not server_info.motd.is_empty():
		p.send_message(server_info.motd)
	broadcast_chat("%s joined the game" % player_name)
	print("[server] %s joined (peer %d, player id %s%s)" % [player_name, peer_id, player_id, ", admin" if is_admin(p) else ""])
	emit("player_join", {"player": p, "first_time": first_time})


func _default_spawn() -> Vector3:
	_ensure_chunk(Vector2i.ZERO)
	for y in range(Chunk.SIZE_Y - 1, 0, -1):
		if world.get_block(8, y, 8) != BlockRegistry.AIR:
			return Vector3(8.5, y + 1, 8.5)
	return Vector3(8.5, 64, 8.5)


func _on_peer_disconnected(peer_id: int) -> void:
	_joining.erase(peer_id)
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	emit("player_leave", {"player": p})
	_store_player(p)
	players.erase(peer_id)
	for other: ServerPlayer in players.values():
		Net.s_player_left.rpc_id(other.peer_id, peer_id)
	broadcast_chat("%s left the game" % p.name)
	print("[server] %s left (peer %d)" % [p.name, peer_id])


func kick(peer_id: int, reason: String) -> void:
	print("[server] Kicking peer %d: %s" % [peer_id, reason])
	Net.s_kick.rpc_id(peer_id, reason)
	# Delay the disconnect so the kick message is flushed first.
	get_tree().create_timer(0.2).timeout.connect(_disconnect_peer.bind(peer_id))


func _disconnect_peer(peer_id: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer and peer.get_peer(peer_id):
		peer.disconnect_peer(peer_id)


# --- Chunk streaming ----------------------------------------------------------------------------

func _build_view_offsets() -> void:
	for x in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
		for z in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
			if x * x + z * z <= VIEW_RADIUS * VIEW_RADIUS + VIEW_RADIUS:
				_view_offsets.append(Vector2i(x, z))
	_view_offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() < b.length_squared())


func _stream_chunks(p: ServerPlayer) -> void:
	var center := VoxelWorld.chunk_coord_of(p.state.position)
	if center != p.stream_center:
		p.stream_center = center
		p.pending_chunks.clear()
		for offset in _view_offsets:
			var coord := center + offset
			if not p.sent_chunks.has(coord):
				p.pending_chunks.append(coord)
		for coord: Vector2i in p.sent_chunks.keys():
			var d := coord - center
			if maxi(absi(d.x), absi(d.y)) > VIEW_RADIUS + UNLOAD_MARGIN:
				p.sent_chunks.erase(coord)
				Net.s_unload_chunk.rpc_id(p.peer_id, coord)

	# Send the nearest chunks that are ready; ask workers to prepare the ones that are not.
	var sends := 0
	var i := 0
	while i < p.pending_chunks.size() and i < STREAM_SCAN and sends < CHUNK_SENDS_PER_PLAYER_PER_TICK:
		var coord: Vector2i = p.pending_chunks[i]
		var chunk = world.chunks.get(coord)
		if chunk == null:
			_request_chunk(coord)
			i += 1
			continue
		p.pending_chunks.remove_at(i)
		p.sent_chunks[coord] = true
		Net.s_chunk.rpc_id(p.peer_id, coord, chunk.encode(), chunk.encode_states())
		sends += 1


## Starts loading/generating a chunk on a worker thread if capacity allows.
func _request_chunk(coord: Vector2i) -> void:
	if world.chunks.has(coord) or _chunk_jobs.has(coord) or _chunk_jobs.size() >= _max_chunk_jobs:
		return
	var job := _make_chunk_job(coord)
	job.task_id = WorkerThreadPool.add_task(_run_chunk_job.bind(job), false, "chunk %s" % coord)
	_chunk_jobs[coord] = job


func _make_chunk_job(coord: Vector2i) -> Dictionary:
	return {"coord": coord, "path": _chunk_path(coord), "generator": generator, "passes": generation_passes,
		"seed": world_seed, "result": {}, "task_id": -1}


## Worker thread: generate the chunk, then apply saved edits and block data on top. Touches only the
## job, the (thread-safe) generator and the read-only block registry.
func _run_chunk_job(job: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	var chunk = Chunk.new(job.coord)
	if job.generator != null:
		job.generator.generate(chunk)
	for pass_object in job.passes:
		pass_object.decorate(chunk, job.seed)
	var generated: PackedByteArray = chunk.blocks
	var deltas := {}
	var data := {}
	if FileAccess.file_exists(job.path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(job.path))
		if saved is Dictionary:
			var blocks: PackedByteArray = chunk.blocks
			var palette: Array = saved.get("palette", [])
			var edits: Array = saved.get("blocks", [])
			for k in range(0, edits.size() - 1, 2):
				var index := int(edits[k])
				var name_index := int(edits[k + 1])
				if index < 0 or index >= Chunk.VOLUME or name_index < 0 or name_index >= palette.size():
					continue
				var id := registry.id_of(String(palette[name_index]))
				if id < 0:
					continue  # block from a removed mod: keep generated terrain
				blocks.encode_u16(index << 1, id)
				if id != generated.decode_u16(index << 1):
					deltas[index] = id
			chunk.blocks = blocks
			var saved_states = saved.get("states", [])
			if saved_states is Array:
				chunk.load_states(PackedInt32Array(saved_states))
			var entries = saved.get("data", {})
			if entries is Dictionary:
				for key: String in entries:
					var parts := key.split(",")
					if parts.size() == 3 and entries[key] is Dictionary:
						data[Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))] = entries[key]
	job.result = {"chunk": chunk, "generated": generated, "deltas": deltas, "data": data, "usec": Time.get_ticks_usec() - started}


func _poll_chunk_jobs() -> void:
	for coord: Vector2i in _chunk_jobs.keys():
		var job: Dictionary = _chunk_jobs[coord]
		if WorkerThreadPool.is_task_completed(job.task_id):
			WorkerThreadPool.wait_for_task_completion(job.task_id)
			_chunk_jobs.erase(coord)
			_integrate_chunk(job)


func _integrate_chunk(job: Dictionary) -> void:
	var r: Dictionary = job.result
	if world.chunks.has(job.coord) or r.is_empty():
		return
	world.add_chunk(r.chunk)
	if not r.deltas.is_empty():
		_deltas[job.coord] = r.deltas
		_generated[job.coord] = r.generated
	if not r.data.is_empty():
		_block_data[job.coord] = r.data
	if not _metrics.is_empty():
		_metrics.gen += 1
		_metrics.gen_usec += r.usec


## Returns the chunk, loading or generating it synchronously if needed.
func _ensure_chunk(coord: Vector2i):
	var chunk = world.chunks.get(coord)
	if chunk != null:
		return chunk
	var job: Dictionary = _chunk_jobs.get(coord, {})
	if job.is_empty():
		job = _make_chunk_job(coord)
		_run_chunk_job(job)
	else:
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_chunk_jobs.erase(coord)
	_integrate_chunk(job)
	return world.chunks.get(coord)


## Loads the chunks around a position so players placed there have ground to stand on.
func ensure_area_loaded(pos: Vector3) -> void:
	var center := VoxelWorld.chunk_coord_of(pos)
	for x in range(-1, 2):
		for z in range(-1, 2):
			_ensure_chunk(center + Vector2i(x, z))


func _unload_unused_chunks() -> void:
	var needed := {}
	var r := VIEW_RADIUS + UNLOAD_MARGIN
	for p: ServerPlayer in players.values():
		var center := VoxelWorld.chunk_coord_of(p.state.position)
		for x in range(-r, r + 1):
			for z in range(-r, r + 1):
				needed[center + Vector2i(x, z)] = true
	for x in range(-SPAWN_RADIUS, SPAWN_RADIUS + 1):
		for z in range(-SPAWN_RADIUS, SPAWN_RADIUS + 1):
			needed[Vector2i(x, z)] = true
	var writes := []
	for coord: Vector2i in world.chunks.keys():
		if needed.has(coord):
			continue
		if _save_dirty.has(coord) or _block_data.has(coord):
			writes.append(_serialize_chunk(coord))
		_save_dirty.erase(coord)
		_deltas.erase(coord)
		_generated.erase(coord)
		_block_data.erase(coord)
		world.remove_chunk(coord)
	if not writes.is_empty():
		_write_async(writes, false)


# --- World access for mods ----------------------------------------------------------------------

func get_block_loaded(pos: Vector3i) -> int:
	if pos.y >= 0 and pos.y < Chunk.SIZE_Y:
		_ensure_chunk(VoxelWorld.chunk_coord_at(pos.x, pos.z))
	return world.get_block_v(pos)


func set_block_authoritative(pos: Vector3i, id: int, keep_data := false, state := 0) -> void:
	if not registry.is_valid(id) or pos.y < 0 or pos.y >= Chunk.SIZE_Y:
		return
	_ensure_chunk(VoxelWorld.chunk_coord_at(pos.x, pos.z))
	if world.get_block_v(pos) != id or get_block_state(pos) != state:
		_apply_block(pos, id, keep_data, state)


func get_block_state(pos: Vector3i) -> int:
	var chunk = world.chunks.get(VoxelWorld.chunk_coord_at(pos.x, pos.z))
	if chunk == null or pos.y < 0 or pos.y >= Chunk.SIZE_Y:
		return 0
	return chunk.states.get(Chunk.index(pos.x & 15, pos.y, pos.z & 15), 0)


# --- Block data (block entities) ----------------------------------------------------------------

## Live dictionary for the block at `pos`, or an empty one if it has none. Mutations to a returned
## dictionary are saved; call set_block_data to attach data to a block that has none yet.
func get_block_data(pos: Vector3i) -> Dictionary:
	return _block_data.get(VoxelWorld.chunk_coord_at(pos.x, pos.z), {}).get(pos, {})


func set_block_data(pos: Vector3i, data: Dictionary) -> void:
	var coord := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	_ensure_chunk(coord)
	if not _block_data.has(coord):
		_block_data[coord] = {}
	_block_data[coord][pos] = data
	_save_dirty[coord] = true


func clear_block_data(pos: Vector3i) -> void:
	var coord := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	var entries: Dictionary = _block_data.get(coord, {})
	if entries.erase(pos):
		_save_dirty[coord] = true
		if entries.is_empty():
			_block_data.erase(coord)


## Positions of loaded blocks that have data, optionally only of one block type.
func find_block_data(block := -1) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for entries: Dictionary in _block_data.values():
		for pos: Vector3i in entries:
			if block < 0 or world.get_block_v(pos) == block:
				out.append(pos)
	return out


func broadcast_chat(text: String) -> void:
	for p: ServerPlayer in players.values():
		Net.s_chat.rpc_id(p.peer_id, text)


# --- Client gameplay messages -------------------------------------------------------------------

func on_inputs(peer_id: int, packet: PackedByteArray) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or packet.is_empty():
		return
	var count := packet[0]
	if count > MAX_INPUTS_PER_PACKET or packet.size() != 1 + count * PlayerPhysics.INPUT_SIZE:
		return
	var buf := StreamPeerBuffer.new()
	buf.data_array = packet
	buf.seek(1)
	for i in count:
		var input = PlayerPhysics.PlayerInput.read(buf)
		if input.seq <= p.last_received_seq or not (is_finite(input.yaw) and is_finite(input.pitch)):
			continue
		input.pitch = clampf(input.pitch, -PI * 0.5, PI * 0.5)
		p.last_received_seq = input.seq
		p.input_queue.append(input)
		p.yaw = input.yaw
		p.pitch = input.pitch
	while p.input_queue.size() > MAX_QUEUED_INPUTS:
		p.input_queue.pop_front()


func on_break_block(peer_id: int, pos: Vector3i) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var current := world.get_block_v(pos)
	if not _can_edit(p, pos) or current == BlockRegistry.UNLOADED or registry.breakable_lut[current] == 0:
		_reject_edit(p, pos)
		return
	var ev := emit("block_break", {"player": p, "position": pos, "block": current, "drops": _default_drops(current), "cancelled": false})
	if ev.cancelled:
		_reject_edit(p, pos)
		return
	_apply_block(pos, BlockRegistry.AIR)
	if not p.inventory.creative and ev.drops is Array:
		for drop in ev.drops:
			if drop is Array and drop.size() == 2 and items.is_valid(int(drop[0])):
				p.inventory.add(int(drop[0]), int(drop[1]), items.max_stack(int(drop[0])))
		p.sync_inventory()
	emit("block_broken", {"player": p, "position": pos, "block": current})


func on_place_block(peer_id: int, pos: Vector3i, yaw: float) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var block := p.inventory.selected_block()
	var current := world.get_block_v(pos)
	var valid := _can_edit(p, pos) and block > 0 and registry.placeable_lut[block] == 1 \
		and (current == BlockRegistry.AIR or registry.liquid_lut[current] == 1) and _has_solid_neighbor(pos)
	if valid:
		for other: ServerPlayer in players.values():
			if registry.solid_lut[block] == 1 and PlayerPhysics.overlaps_block(other.state.position, pos):
				valid = false
				break
	if valid:
		valid = not emit("block_place", {"player": p, "position": pos, "block": block, "cancelled": false}).cancelled
	if not valid:
		_reject_edit(p, pos)
		return
	p.inventory.consume_selected()
	if not p.inventory.creative:
		p.sync_inventory()
	var state := BlockRegistry.facing_from_yaw(yaw) if registry.defs[block].orientation == 1 and is_finite(yaw) else 0
	_apply_block(pos, block, false, state)
	emit("block_placed", {"player": p, "position": pos, "block": block})


func on_interact(peer_id: int, pos: Vector3i) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var block := world.get_block_v(pos)
	if block == BlockRegistry.UNLOADED or registry.interactive_lut[block] == 0 or not _can_edit(p, pos):
		return
	emit("block_interact", {"player": p, "position": pos, "block": block})


func on_select_slot(peer_id: int, slot: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p:
		p.inventory.selected = clampi(slot, 0, p.inventory.ids.size() - 1)


func on_chat(peer_id: int, text: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var clean := text.strip_edges().left(CHAT_MAX_LENGTH)
	if clean.is_empty() or p.edit_tokens < 1.0:
		return
	p.edit_tokens -= 1.0
	if clean.begins_with("/"):
		var parts := clean.substr(1).split(" ", false)
		if parts.is_empty():
			return
		var command: Dictionary = _commands.get(parts[0].to_lower(), {})
		if command.is_empty():
			p.send_message("Unknown command /%s. Try /help" % parts[0])
		elif not _permitted(p, command):
			p.send_message("You don't have permission to use /%s" % parts[0])
		else:
			command.handler.call(p, parts.slice(1))
		return
	if not emit("chat", {"player": p, "text": clean, "cancelled": false}).cancelled:
		broadcast_chat("<%s> %s" % [p.name, clean])


func on_use_item(peer_id: int, has_target: bool, target: Vector3i, normal: Vector3i) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var item := p.inventory.selected_item()
	if item < ItemRegistry.FIRST_ITEM or not items.is_usable(item) or p.edit_tokens < 1.0:
		return
	p.edit_tokens -= 1.0
	if has_target and (not world.has_chunk(VoxelWorld.chunk_coord_at(target.x, target.z)) \
			or p.get_eye_position().distance_to(Vector3(target) + Vector3.ONE * 0.5) > REACH + 0.87):
		has_target = false
	emit("item_use", {"player": p, "item": item, "has_target": has_target, "position": target,
		"normal": normal.clamp(-Vector3i.ONE, Vector3i.ONE), "direction": PlayerPhysics.look_direction(p.yaw, p.pitch)})


func on_open_menu(peer_id: int, menu: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p and menu == "crafting":
		show_crafting(p)


# --- Crafting -----------------------------------------------------------------------------------

func add_recipe(inputs: Dictionary, output: int, count: int) -> void:
	_recipes.append({"inputs": inputs, "output": output, "count": count})


func _can_craft(p: ServerPlayer, recipe: Dictionary) -> bool:
	if p.inventory.creative:
		return true
	for id: int in recipe.inputs:
		if p.inventory.count_of(id) < recipe.inputs[id]:
			return false
	return true


func show_crafting(p: ServerPlayer) -> void:
	var children := [{"type": "label", "text": "Crafting", "size": 22, "color": "#ffd166"}]
	if _recipes.is_empty():
		children.append({"type": "label", "text": "This server has no recipes."})
	for i in mini(_recipes.size(), 20):
		var recipe: Dictionary = _recipes[i]
		var parts := PackedStringArray()
		for id: int in recipe.inputs:
			parts.append("%d %s" % [recipe.inputs[id], items.display_name(id)])
		var can := _can_craft(p, recipe)
		children.append({"type": "hbox", "children": [
			{"type": "image", "asset": items.icon_of(recipe.output), "size": 24},
			{"type": "label", "text": "%d x %s  <-  %s" % [recipe.count, items.display_name(recipe.output), ", ".join(parts)],
				"color": "#ffffff" if can else "#8a8a8a"},
			{"type": "button", "text": "Craft", "action": "craft:%d" % i, "disabled": not can},
		]})
	children.append({"type": "button", "text": "Close", "action": "close"})
	p.show_ui("engine:crafting", {"anchor": "center", "modal": true, "children": children})


func _on_crafting_action(p: ServerPlayer, action: String) -> void:
	if action == "close":
		p.hide_ui("engine:crafting")
		return
	var index := int(action.trim_prefix("craft:"))
	if not action.begins_with("craft:") or index < 0 or index >= _recipes.size():
		return
	var recipe: Dictionary = _recipes[index]
	if not _can_craft(p, recipe):
		return
	if not p.inventory.creative:
		for id: int in recipe.inputs:
			p.inventory.remove(id, recipe.inputs[id])
	var left := p.inventory.add(recipe.output, recipe.count, items.max_stack(recipe.output))
	p.sync_inventory()
	if left > 0:
		p.send_message("Inventory full: %d %s lost" % [left, items.display_name(recipe.output)])
	emit("item_crafted", {"player": p, "item": recipe.output, "count": recipe.count})
	show_crafting(p)


func on_ui_action(peer_id: int, ui_id: String, action: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p and ui_id == "engine:crafting" and p.ui_ids.has(ui_id):
		_on_crafting_action(p, action.left(64))
		return
	if p and p.ui_ids.has(ui_id):
		emit("ui_action", {"player": p, "ui_id": ui_id.left(64), "action": action.left(64)})


func on_shutdown_request(peer_id: int, token: String) -> void:
	if _admin_token.is_empty() or token != _admin_token:
		push_warning("[server] Rejected shutdown request from peer %d" % peer_id)
		return
	print("[server] Shutdown requested by host")
	get_tree().quit()  # _exit_tree saves and waits for the writes


func _default_drops(block: int) -> Array:
	var drops = registry.defs[block].get("drops", null)
	if drops == null:
		return [[block, 1]]
	if drops is String:
		var id := items.id_of(drops)
		return [[id, 1]] if id > 0 else []
	return drops if drops is Array else []


func _can_edit(p: ServerPlayer, pos: Vector3i) -> bool:
	if p.edit_tokens < 1.0:
		return false
	p.edit_tokens -= 1.0
	if pos.y < 0 or pos.y >= Chunk.SIZE_Y or not world.has_chunk(VoxelWorld.chunk_coord_at(pos.x, pos.z)):
		return false
	return p.get_eye_position().distance_to(Vector3(pos) + Vector3(0.5, 0.5, 0.5)) <= REACH + 0.87


func _has_solid_neighbor(pos: Vector3i) -> bool:
	for dir in [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		if registry.solid_lut[world.get_block_v(pos + dir)] == 1 and world.get_block_v(pos + dir) != BlockRegistry.UNLOADED:
			return true
	return false


func _apply_block(pos: Vector3i, block: int, keep_data := false, state := 0) -> void:
	var coord := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	var chunk = world.chunks.get(coord)
	if chunk == null:
		return
	if not _generated.has(coord):
		_generated[coord] = chunk.blocks.duplicate()
	var old := world.get_block_v(pos)
	world.set_block(pos.x, pos.y, pos.z, block)
	var index := Chunk.index(pos.x & 15, pos.y, pos.z & 15)
	if not _deltas.has(coord):
		_deltas[coord] = {}
	if _generated[coord].decode_u16(index << 1) == block:
		_deltas[coord].erase(index)
	else:
		_deltas[coord][index] = block
	if state > 0:
		chunk.states[index] = state & 255
	else:
		chunk.states.erase(index)
	_save_dirty[coord] = true
	if old != block and not keep_data:
		clear_block_data(pos)
	for p: ServerPlayer in players.values():
		if p.sent_chunks.has(coord):
			Net.s_block_changed.rpc_id(p.peer_id, pos, block, state & 255)


## Tells the client the authoritative block and inventory so it can roll back its prediction.
func _reject_edit(p: ServerPlayer, pos: Vector3i) -> void:
	var block := world.get_block_v(pos)
	if block != BlockRegistry.UNLOADED:
		Net.s_block_changed.rpc_id(p.peer_id, pos, block, get_block_state(pos))
	p.sync_inventory()


# --- Persistence --------------------------------------------------------------------------------
# Worlds are saved as deltas: chunks/x_z.json holds only blocks that differ from freshly generated
# terrain (stored by block name) plus block data. Untouched chunks are never written, so changing
# world generation or mods applies to them automatically.

func _chunk_path(coord: Vector2i) -> String:
	return "%s/chunks/%d_%d.json" % [_save_dir, coord.x, coord.y]


func _load_meta(seed_override: int) -> void:
	var path := _save_dir + "/world.json"
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_meta = parsed
	if not _meta.has("seed"):
		_meta.seed = seed_override if seed_override >= 0 else randi()
	for key in ["players", "mod_storage", "names"]:
		if not (_meta.get(key) is Dictionary):
			_meta[key] = {}
	if not (_meta.get("admins") is Array):
		_meta.admins = []
	if _meta.get("time") is Array and _meta.time.size() == 2:
		_time_of_day = float(_meta.time[0])
		_day_length = float(_meta.time[1])


## Returns [path, json text] for a chunk's delta, or [path, null] when there is nothing to keep.
func _serialize_chunk(coord: Vector2i) -> Array:
	var deltas: Dictionary = _deltas.get(coord, {})
	var entries: Dictionary = _block_data.get(coord, {})
	var chunk = world.chunks.get(coord)
	var states: PackedInt32Array = chunk.encode_states() if chunk != null else PackedInt32Array()
	if deltas.is_empty() and entries.is_empty() and states.is_empty():
		return [_chunk_path(coord), null]
	var palette := []
	var palette_index := {}
	var edits := []
	for index: int in deltas:
		var block_name: String = registry.defs[deltas[index]].name
		if not palette_index.has(block_name):
			palette_index[block_name] = palette.size()
			palette.append(block_name)
		edits.append(index)
		edits.append(palette_index[block_name])
	var data := {}
	for pos: Vector3i in entries:
		data["%d,%d,%d" % [pos.x, pos.y, pos.z]] = entries[pos]
	return [_chunk_path(coord), JSON.stringify({"version": 1, "palette": palette, "blocks": edits, "states": Array(states), "data": data})]

func _store_player(p: ServerPlayer) -> void:
	_meta.players[p.player_id] = {
		"name": p.name,
		"position": [p.state.position.x, p.state.position.y, p.state.position.z],
		"inventory": Array(p.inventory.to_packed()),
		"creative": p.inventory.creative,
		"data": p.data,
	}


## Serializes changed chunks and metadata on this thread, then writes files on a worker.
func _save_all(wait := false) -> void:
	if _save_dir.is_empty():
		return
	var writes := []
	var coords := _save_dirty.duplicate()
	for coord: Vector2i in _block_data:
		coords[coord] = true  # block data dictionaries may have been mutated in place
	for coord: Vector2i in coords:
		if world.chunks.has(coord):
			writes.append(_serialize_chunk(coord))
	_save_dirty.clear()
	for p: ServerPlayer in players.values():
		_store_player(p)
	_meta.time = [_time_of_day, _day_length]
	writes.append([_save_dir + "/world.json", JSON.stringify(_meta, "\t")])
	_write_async(writes, wait)


func _write_async(writes: Array, wait: bool) -> void:
	if _save_task != -1:
		WorkerThreadPool.wait_for_task_completion(_save_task)
	_save_task = WorkerThreadPool.add_task(_write_files.bind(writes), false, "world save")
	if wait:
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1


## Worker thread: [path, text] writes; null text deletes the file.
static func _write_files(writes: Array) -> void:
	for w in writes:
		if w[1] == null:
			if FileAccess.file_exists(w[0]):
				DirAccess.remove_absolute(w[0])
			continue
		var tmp: String = w[0] + ".tmp"
		var file := FileAccess.open(tmp, FileAccess.WRITE)
		if file == null:
			push_error("[server] Could not write %s" % w[0])
			continue
		file.store_string(w[1])
		file.close()
		DirAccess.rename_absolute(tmp, w[0])
