extends Node
## Authoritative game server engine. Loads mods, which define the content and rules; owns the world;
## simulates every player from their inputs; validates edits; streams content, chunks and snapshots.

const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const Chunk = preload("res://engine/shared/chunk.gd")
const WorldBackups = preload("res://engine/server/world_backups.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")
const Inventory = preload("res://engine/shared/inventory.gd")
const ModApi = preload("res://engine/server/mod_api.gd")
const ModLoader = preload("res://engine/server/mod_loader.gd")
const JsMod = preload("res://engine/server/js_mod.gd")
const Identity = preload("res://engine/shared/identity.gd")
const Native = preload("res://engine/shared/native.gd")
const WorldTime = preload("res://engine/shared/world_time.gd")
const ItemRegistry = preload("res://engine/shared/item_registry.gd")
const Entities = preload("res://engine/server/entities.gd")
const Entity = preload("res://engine/server/entity.gd")
const SoundRegistry = preload("res://engine/shared/sound_registry.gd")
const VoxelRaycast = preload("res://engine/shared/voxel_raycast.gd")
const EntityRegistry = preload("res://engine/shared/entity_registry.gd")
const Mining = preload("res://engine/shared/mining.gd")
const PlayerStats = preload("res://engine/server/player_stats.gd")
const PlayerRig = preload("res://engine/shared/player_rig.gd")
const Cosmetics = preload("res://engine/shared/cosmetics.gd")
const EffectRegistry = preload("res://engine/shared/effect_registry.gd")
const BlockTicks = preload("res://engine/server/block_ticks.gd")
const Containers = preload("res://engine/server/containers.gd")
const RecipeRegistry = preload("res://engine/shared/recipe_registry.gd")
const Stations = preload("res://engine/server/stations.gd")
const StationSessions = preload("res://engine/server/station_sessions.gd")

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
const ATTACK_REACH := 4.5
const ATTACK_INTERVAL := 0.25
const PLAYER_HURT_INVULNERABLE := 0.5
const REGEN_DELAY := 5.0
const REGEN_INTERVAL := 2.5
const VOID_DAMAGE_Y := -32.0
## Landing as fast as a fall from higher than this (blocks) hurts: 1 damage per extra block.
const SAFE_FALL_HEIGHT := 3.2
## Blocks around a crafting station whose chests it can draw ingredients from.
const STATION_PULL_RADIUS := 4
## Minimum seconds between avatar changes from a client.
const AVATAR_CHANGE_INTERVAL := 0.2

var registry := BlockRegistry.new()
var items := ItemRegistry.new(registry)
var rules := PlayerPhysics.Rules.new()
var world := VoxelWorld.new()
var world_seed := 0
var entities := Entities.new(self)
var sounds := SoundRegistry.new()
## The character body every client draws players with (see PlayerRig; mods may replace it).
var player_rig := PlayerRig.default_rig()
## Built-in and server cosmetics, categories and this server's cosmetics policy.
var cosmetics := Cosmetics.new()
## Named visual effects clients render on request (see EffectRegistry).
var effects := EffectRegistry.new()
## Random and scheduled block ticks, the world clock and server-side light (see BlockTicks).
var block_ticks := BlockTicks.new(self)
## Container types and open container screens (chests, furnaces, machines).
var containers := Containers.new(self)
## Game-wide rules mods can change with set_gameplay.
var gameplay := {
	"item_drops": "entity",  # "entity": broken blocks drop items to pick up; "inventory": straight into the inventory
	"keep_inventory": true,
	"pvp": false,
	"fall_damage": true,
	"natural_regeneration": true,
	"mob_spawning": true,
	"durability": true,  # tools, weapons and armor wear out
	"tray_access": "contributors",  # station trays: "contributors" (plus owner and team) | "anyone"
	"recipe_discovery": true,  # players learn recipes (see RecipeRegistry unlock rules); false = all known
}
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
## Crafting recipes and categories (sent to clients for the recipe book).
var recipes := RecipeRegistry.new()
## Station tiers, workshop upgrades and multiblock structures.
var stations := Stations.new(self)
## Co-op crafting at stations: presence, shared trays, timed jobs and projects.
var sessions := StationSessions.new(self)
var _snapshot_round := 0
var _support_rules := {}  # block id -> null (none) | true (solid below) | {block id: true}
var _fuels := {}  # item id -> seconds it burns
var _processes := {}  # kind -> {input item id: {output, count, seconds}}
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
var _backup_dir := ""
var _backup_interval := 0.0  # seconds, 0 = no automatic backups
var _backup_keep := 24
var _backup_timer := 0.0
var _backup_task := -1
var _backup_job := {}  # shared with the worker: {path, error, pruned, requester}
## Automatic backups are skipped while nothing happens in the world.
var _activity_since_backup := false
## Chunks whose saved file lists persistent entities; resaved so entities that walked away are dropped.
var _entity_chunks := {}


## config keys:
##   port, max_players, world, seed, admin_token, mods (PackedStringArray), mod_dirs (PackedStringArray, searched
##   before res://mods), data_dir (default user://worlds), metrics (seconds between reports, 0 = off),
##   offline (true = load mods and world without opening a socket, for benchmarks),
##   backup_interval (minutes between automatic backups, 0 = off), backup_keep (archives kept),
##   restore ("latest", a backup file name or an archive path to restore before loading)
func start(config: Dictionary) -> Error:
	_admin_token = config.get("admin_token", "")
	for entry in String(config.get("admins", "")).split(",", false):
		_config_admins[entry.strip_edges().to_lower()] = true
	_metrics_interval = float(config.get("metrics", 0.0))
	Engine.max_fps = 60
	var data_dir := String(config.get("data_dir", "user://worlds"))
	var world_name := String(config.get("world", "world")).validate_filename()
	_save_dir = data_dir.path_join(world_name)
	_backup_dir = data_dir.path_join("backups").path_join(world_name)
	_backup_interval = float(config.get("backup_interval", 0.0)) * 60.0
	_backup_keep = maxi(1, int(config.get("backup_keep", 24)))
	var restore := String(config.get("restore", ""))
	if not restore.is_empty():
		var archive := WorldBackups.resolve(_backup_dir, restore)
		if archive.is_empty():
			printerr("[server] No backup '%s' in %s" % [restore, ProjectSettings.globalize_path(_backup_dir)])
			return ERR_FILE_NOT_FOUND
		var restore_error := WorldBackups.restore(archive, _save_dir)
		if not restore_error.is_empty():
			printerr("[server] Restore failed: %s" % restore_error)
			return FAILED
		print("[server] Restored world '%s' from %s" % [world_name, archive.get_file()])
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
	var tls: Array = Net.load_or_create_server_identity(data_dir.path_join("identity"))
	err = Net.create_server(int(config.get("port", 24565)), int(config.get("max_players", DEFAULT_MAX_PLAYERS)), tls[0], tls[1], tls[2])
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
	if _backup_task != -1:
		WorkerThreadPool.wait_for_task_completion(_backup_task)
		_backup_task = -1
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
	for p: ServerPlayer in players.values():
		_update_player_rules(p)
		if _started:
			Net.s_rules.rpc_id(p.peer_id, rules.to_dict())


func _apply_rules_to_world() -> void:
	rules.solid_lut = registry.solid_lut
	rules.liquid_lut = registry.liquid_lut
	world.set_lookup_tables(registry.solid_lut, registry.liquid_lut)
	world.void_below = rules.void_below
	entities.ai.update_tables()


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
	add_command("backup", "Back up the world now", _cmd_backup, "engine", "admin")
	add_command("backups", "List world backups", _cmd_backups, "engine", "admin")
	add_command("give", "<item> [count] [player] - give items", _cmd_give, "engine", "admin")
	add_command("tp", "<x> <y> <z> | <player> - teleport", _cmd_tp, "engine", "admin")
	add_command("summon", "<entity> [count] - spawn entities in front of you", _cmd_summon, "engine", "admin")
	add_command("heal", "[player] - restore health", _cmd_heal, "engine", "admin")
	add_command("gamemode", "survival | creative [player]", _cmd_gamemode, "engine", "admin")
	add_command("kill", "Die and respawn", func(p, _args): kill_player(p, "command", null), "engine")
	add_command("gameplay", "[rule value] - show or change gameplay rules", _cmd_gameplay, "engine", "admin")


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


func _cmd_backup(player, _args: PackedStringArray) -> void:
	if backup_now(player.peer_id):
		player.send_message("Backup started")
	else:
		player.send_message("A backup is already running")


func _cmd_backups(player, _args: PackedStringArray) -> void:
	var backups := WorldBackups.list(_backup_dir)
	player.send_message("%d backups in %s (keeping %d)" % [backups.size(), ProjectSettings.globalize_path(_backup_dir), _backup_keep])
	for i in mini(backups.size(), 10):
		player.send_message("  %s  %s" % [backups[i].name, String.humanize_size(backups[i].size)])


## Flushes pending saves, then archives the world on a worker thread. `requester` (peer id) is told
## when it finishes. Returns false if a backup is already running.
func backup_now(requester := 0) -> bool:
	if _backup_task != -1 or _save_dir.is_empty():
		return false
	_save_all(true)
	_activity_since_backup = false
	_backup_timer = 0.0
	var world_name := _save_dir.get_file()
	_backup_job = {"path": _backup_dir.path_join("%s-%s%s" % [world_name, WorldBackups.timestamp(), WorldBackups.EXTENSION]),
		"error": "", "pruned": 0, "requester": requester, "started": Time.get_ticks_msec()}
	_backup_task = WorkerThreadPool.add_task(_run_backup.bind(_save_dir, _backup_dir, _backup_keep, _backup_job), false, "world backup")
	return true


static func _run_backup(world_dir: String, backup_dir: String, keep: int, job: Dictionary) -> void:
	job.error = WorldBackups.create(world_dir, job.path)
	if job.error.is_empty():
		job.pruned = WorldBackups.prune(backup_dir, keep)


func _poll_backup(delta: float) -> void:
	if _backup_task == -1:
		_backup_timer += delta
		if _backup_interval > 0.0 and _backup_timer >= _backup_interval:
			_backup_timer = 0.0
			if _activity_since_backup or not players.is_empty():
				backup_now()
		return
	if not WorkerThreadPool.is_task_completed(_backup_task):
		return
	WorkerThreadPool.wait_for_task_completion(_backup_task)
	_backup_task = -1
	var job := _backup_job
	var message: String
	if job.error.is_empty():
		message = "Backup saved: %s (%s, %dms)" % [String(job.path).get_file(),
			String.humanize_size(FileAccess.open(job.path, FileAccess.READ).get_length()), Time.get_ticks_msec() - int(job.started)]
	else:
		message = "Backup failed: %s" % job.error
	print("[server] " + message)
	var requester: ServerPlayer = players.get(int(job.requester))
	if requester:
		requester.send_message(message)
	emit("backup", {"path": job.path, "error": job.error})


func _target_player(player, args: PackedStringArray, index: int):
	if args.size() <= index:
		return player
	var target = _find_online(args[index])
	if target == null:
		player.send_message("No online player named '%s'" % args[index])
	return target


func _cmd_give(player, args: PackedStringArray) -> void:
	if args.is_empty():
		player.send_message("Usage: /give <item> [count] [player]")
		return
	var id := items.id_of(args[0] if args[0].contains(":") else "base:" + args[0])
	if id <= 0:
		player.send_message("Unknown item '%s'" % args[0])
		return
	var target = _target_player(player, args, 2)
	if target == null:
		return
	var count := clampi(int(args[1]) if args.size() > 1 else 1, 1, 64 * 36)
	var left: int = target.give(id, count)
	player.send_message("Gave %d %s to %s" % [count - left, items.display_name(id), target.name])


func _cmd_tp(player, args: PackedStringArray) -> void:
	if args.size() == 3 and args[0].is_valid_float() and args[1].is_valid_float() and args[2].is_valid_float():
		player.teleport(Vector3(float(args[0]), float(args[1]), float(args[2])))
	elif args.size() == 1:
		var target = _target_player(player, args, 0)
		if target != null:
			player.teleport(target.state.position)
	else:
		player.send_message("Usage: /tp <x> <y> <z> | /tp <player>")


func _cmd_summon(player, args: PackedStringArray) -> void:
	var type_id := entities.registry.id_of(args[0]) if not args.is_empty() else -1
	if type_id < 0 or type_id == EntityRegistry.ITEM:
		var names := entities.registry.ids.keys().filter(func(n): return n != "engine:item")
		player.send_message("Usage: /summon <entity> [count]. Entities: %s" % ", ".join(names))
		return
	var forward := PlayerPhysics.look_direction(player.yaw, 0.0)
	for i in clampi(int(args[1]) if args.size() > 1 else 1, 1, 20):
		entities.spawn(type_id, player.state.position + forward * 3.0 + Vector3(randf_range(-0.5, 0.5), 0.2, randf_range(-0.5, 0.5)))


func _cmd_heal(player, args: PackedStringArray) -> void:
	var target = _target_player(player, args, 0)
	if target != null:
		heal_player(target, target.max_health)


func _cmd_gamemode(player, args: PackedStringArray) -> void:
	if args.is_empty() or not args[0] in ["survival", "creative"]:
		player.send_message("Usage: /gamemode survival | creative [player]")
		return
	var target = _target_player(player, args, 1)
	if target == null:
		return
	target.set_creative(args[0] == "creative")
	target.send_message("Game mode: %s" % args[0])


func _cmd_gameplay(player, args: PackedStringArray) -> void:
	if args.size() < 2:
		for key in gameplay:
			player.send_message("%s = %s" % [key, gameplay[key]])
		return
	if not gameplay.has(args[0]):
		player.send_message("Unknown rule '%s'" % args[0])
		return
	var value = args[1] if gameplay[args[0]] is String else args[1] in ["true", "on", "1", "yes"]
	set_gameplay({args[0]: value})
	broadcast_chat("%s set %s to %s" % [player.name, args[0], value])


func set_player_rig(def: Dictionary) -> void:
	player_rig = PlayerRig.sanitize(def)


func set_gameplay(values: Dictionary) -> void:
	for key in values:
		if not gameplay.has(key):
			push_warning("[server] Unknown gameplay rule '%s'" % key)
		elif gameplay[key] is bool:
			gameplay[key] = bool(values[key])
		else:
			gameplay[key] = String(values[key])


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
	block_ticks.update(delta)
	containers.update(delta)
	sessions.update(delta)
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
	entities.tick(delta)
	for p: ServerPlayer in players.values():
		_update_health(p, delta)
	var t1 := Time.get_ticks_usec()
	_run_tasks()
	emit("tick", {"delta": delta, "tick": tick})
	var t2 := Time.get_ticks_usec()

	if tick % SNAPSHOT_INTERVAL_TICKS == 0 and not players.is_empty():
		_send_snapshots()
		entities.replicate(players.values())
	var t3 := Time.get_ticks_usec()

	_poll_backup(delta)
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
	if p.dead:
		# Dead players do not move; acknowledge inputs so the client's prediction queue drains.
		if not p.input_queue.is_empty():
			p.last_processed_seq = p.input_queue.back().seq
			p.input_queue.clear()
		return
	# Normally one input per tick; consume two when the client is ahead to drain jitter backlog.
	var budget := 2 if p.input_queue.size() > 3 else 1
	while budget > 0 and not p.input_queue.is_empty():
		var input = p.input_queue.pop_front()
		var falling_speed := -p.state.velocity.y
		PlayerPhysics.step(p.state, input, world, p.physics_rules if p.physics_rules != null else rules)
		p.last_processed_seq = input.seq
		budget -= 1
		_track_fall(p, falling_speed)
	if tick % 15 == 0 and p.state.on_ground and Vector2(p.state.velocity.x, p.state.velocity.z).length() > rules.walk_speed + 0.5:
		entities.ai.make_noise(p.state.position, 7.0, p)  # sprinting footsteps


func _track_fall(p: ServerPlayer, speed_before: float) -> void:
	var feet := world.get_block(floori(p.state.position.x), floori(p.state.position.y + 0.2), floori(p.state.position.z))
	if registry.liquid_lut[feet] == 1:
		p.fall_velocity = 0.0
		return
	if not p.state.on_ground:
		p.fall_velocity = maxf(p.fall_velocity, speed_before)
		return
	var impact := maxf(p.fall_velocity, speed_before)
	p.fall_velocity = 0.0
	# Height an object must fall under normal gravity to land this fast: v^2 / (2g).
	var height := impact * impact / (2.0 * 32.0)
	if height > SAFE_FALL_HEIGHT and gameplay.fall_damage:
		damage_player(p, floorf(height - SAFE_FALL_HEIGHT + 0.5), "fall", null)


# --- Health, damage & death ---------------------------------------------------------------------

func _update_health(p: ServerPlayer, delta: float) -> void:
	if tick % 30 == 0 and not p.modifiers.is_empty():
		for m in p.modifiers.values():
			if m.expires > 0.0 and _time >= m.expires:
				p.refresh_stats()
				break
	if p.dead:
		return
	p.hurt_timer = maxf(p.hurt_timer - delta, 0.0)
	if p.state.position.y < VOID_DAMAGE_Y:
		p.void_timer += delta
		if p.void_timer >= 0.5:
			p.void_timer = 0.0
			damage_player(p, 4.0, "void", null, Vector3.ZERO, true)
	if gameplay.natural_regeneration and p.health < p.max_health and _time - p.last_damage_time > REGEN_DELAY:
		p.regen_timer += delta
		if p.regen_timer >= REGEN_INTERVAL:
			p.regen_timer = 0.0
			heal_player(p, 1.0)


## Returns true if damage applied. `direction` sets the knockback direction (defaults to away from
## the attacker). `bypass_cooldown` lets continuous damage (void) ignore the invulnerability window.
func damage_player(p: ServerPlayer, amount: float, cause: String, attacker = null, direction := Vector3.ZERO, bypass_cooldown := false, knockback := 6.0) -> bool:
	if p == null or p.dead or amount <= 0.0 or (p.inventory.creative and cause != "void"):
		return false
	if p.hurt_timer > 0.0 and not bypass_cooldown:
		return false
	var stats := p.get_stats()
	var protected := cause in PlayerStats.ARMOR_CAUSES
	var reduced := PlayerStats.apply_armor(amount, stats.armor, stats.toughness) if protected else amount
	var ev := emit("player_damage", {"player": p, "amount": reduced, "raw_amount": amount, "cause": cause, "attacker": attacker, "cancelled": false})
	if ev.cancelled or float(ev.amount) <= 0.0:
		return false
	p.health = maxf(p.health - float(ev.amount), 0.0)
	if protected:
		for i in p.inventory.equipment_slots.size():
			var index := Inventory.SIZE + i
			if p.inventory.ids[index] > 0 and not items.get_def(p.inventory.ids[index]).get("armor", {}).is_empty():
				damage_item(p, index, 1, "armor")
	knockback *= 1.0 - float(stats.knockback_resistance)
	p.hurt_timer = PLAYER_HURT_INVULNERABLE
	p.last_damage_time = _time
	p.regen_timer = 0.0
	var source := Entities._attacker_position(attacker)
	if direction == Vector3.ZERO and source != Vector3.INF:
		direction = p.state.position - source
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		p.state.velocity += direction.normalized() * knockback + Vector3(0, minf(4.5, knockback * 0.75), 0)
	entities.ai.make_noise(p.state.position, 12.0, p, true)
	sync_health(p, true)
	play_sound_at("engine:hurt", p.get_eye_position(), 1.0, randf_range(0.9, 1.1))
	_broadcast_player_event(p, Entities.Event.HURT)
	if p.health <= 0.0:
		kill_player(p, cause, attacker)
	return true


func heal_player(p: ServerPlayer, amount: float) -> void:
	if p.dead or p.health >= p.max_health:
		return
	p.health = minf(p.health + amount, p.max_health)
	sync_health(p)


func sync_health(p: ServerPlayer, hurt := false) -> void:
	if _started:
		Net.s_health.rpc_id(p.peer_id, p.health, p.max_health, p.dead, hurt)


func kill_player(p: ServerPlayer, cause: String, attacker) -> void:
	if p.dead:
		return
	var attacker_name := ""
	if attacker != null and attacker.get("peer_id") != null:
		attacker_name = String(attacker.name)
	elif attacker != null and attacker.get("def") != null:
		attacker_name = String(attacker.def.display_name)
	var messages := {"fall": "%s fell from a high place", "void": "%s fell out of the world",
		"attack": "%s was slain by %s", "mob": "%s was slain by %s", "projectile": "%s was shot by %s"}
	var message := "%s died" % p.name
	if messages.has(cause) and (not attacker_name.is_empty() or String(messages[cause]).count("%s") == 1):
		message = messages[cause] % ([p.name, attacker_name] if String(messages[cause]).count("%s") == 2 else [p.name])
	var ev := emit("player_death", {"player": p, "cause": cause, "attacker": attacker,
		"keep_inventory": gameplay.keep_inventory, "message": message})
	p.health = 0.0
	p.dead = true
	p.fall_velocity = 0.0
	if not ev.keep_inventory and not p.inventory.creative:
		var center := p.state.position + Vector3(0, 1.0, 0)
		for i in p.inventory.total():
			if p.inventory.ids[i] > 0 and p.inventory.counts[i] > 0:
				entities.drop_item(p.inventory.ids[i], p.inventory.counts[i], center, Vector3.INF, 0.6, p.inventory.data[i])
		if p.inventory.cursor_count > 0:
			entities.drop_item(p.inventory.cursor_id, p.inventory.cursor_count, center, Vector3.INF, 0.6, p.inventory.cursor_data)
		p.inventory.clear()
		p.sync_inventory()
	sync_health(p)
	_broadcast_player_event(p, Entities.Event.DEATH)
	play_sound_at("engine:death", p.get_eye_position())
	if not String(ev.message).is_empty():
		broadcast_chat(String(ev.message))


func on_respawn(peer_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or not p.dead:
		return
	var spawn := p.spawn_point
	if spawn == Vector3.INF:
		spawn = spawn_handler.call(p) if spawn_handler.is_valid() else _default_spawn()
	var ev := emit("player_respawn", {"player": p, "position": spawn})
	p.dead = false
	p.health = p.max_health
	p.hurt_timer = 1.0
	p.last_damage_time = _time
	p.teleport(ev.position if ev.position is Vector3 else spawn)
	sync_health(p)
	_broadcast_player_event(p, Entities.Event.RESPAWN)


func _broadcast_player_event(p: ServerPlayer, kind: int) -> void:
	if not _started:
		return
	for other: ServerPlayer in players.values():
		if other != p:
			Net.s_player_event.rpc_id(other.peer_id, p.peer_id, kind)


# --- Sounds -------------------------------------------------------------------------------------

## Plays a registered sound at a world position for players in range. `exclude` is a peer id that
## already played it locally (e.g. the player who broke the block).
func play_sound_at(sound_name: String, pos: Vector3, volume := 1.0, pitch := 1.0, exclude := 0) -> void:
	var id := sounds.id_of(sound_name)
	if id < 0 or not _started:
		return
	var reach: float = sounds.defs[id].range
	for p: ServerPlayer in players.values():
		if p.peer_id != exclude and p.state.position.distance_to(pos) <= reach:
			Net.s_sound.rpc_id(p.peer_id, id, pos, volume, pitch, true)


## Plays a registered effect at a position for players in range. options: see EffectRegistry
## (color, scale, direction, duration, follow: an entity or player).
func play_effect(effect_name: String, pos: Vector3, options := {}, exclude := 0) -> void:
	var id := effects.id_of(effect_name)
	if id < 0 or not _started:
		return
	var follow = options.get("follow")
	var clean := EffectRegistry.clean_options(options)
	if follow is ServerPlayer:
		clean.follow_player = follow.peer_id
	elif follow != null and follow is Object and follow.get("id") is int:
		clean.follow_entity = follow.id
	var reach: float = effects.defs[id].range
	for p: ServerPlayer in players.values():
		if p.peer_id != exclude and p.state.position.distance_to(pos) <= reach:
			Net.s_effect.rpc_id(p.peer_id, id, pos, clean)


func play_sound_to(p: ServerPlayer, sound_name: String, volume := 1.0, pitch := 1.0) -> void:
	var id := sounds.id_of(sound_name)
	if id >= 0 and _started:
		Net.s_sound.rpc_id(p.peer_id, id, Vector3.ZERO, volume, pitch, false)


func broadcast_entity_event(e, kind: int, arg: int) -> void:
	if not _started:
		return
	for p: ServerPlayer in players.values():
		if p.known_entities.has(e.id):
			Net.s_entity_event.rpc_id(p.peer_id, e.id, kind, arg)


## Sound name for a block action ("break", "place", "step"); empty when the block has none.
func block_sound(block: int, action: String) -> String:
	return String(registry.defs[block].sounds.get(action, "")) if registry.is_valid(block) else ""


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
	var content := {"blocks": registry.to_network(), "items": items.to_network(), "rules": rules.to_dict(),
		"entities": entities.registry.to_network(), "sounds": sounds.to_network(),
		"equipment_slots": items.slots.duplicate(true), "stats": items.stats.duplicate(),
		"player_rig": player_rig, "cosmetics": cosmetics.to_network(), "effects": effects.to_network(), "recipes": recipes.to_network(), "processes": _processes,
		"stations": stations.to_network()}
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
	_spawn_player(peer_id, j.name, j.player_id, j.get("avatar", {}))


func _spawn_player(peer_id: int, player_name: String, player_id: String, avatar = {}) -> void:
	var p := ServerPlayer.new(self, peer_id, player_name)
	p.player_id = player_id
	p.edit_tokens = EDITS_PER_SECOND
	var saved = _meta.players.get(player_id)
	var first_time := not (saved is Dictionary)
	if not first_time:
		var pos = saved.get("position")
		if pos is Array and pos.size() == 3:
			p.state.position = Vector3(pos[0], pos[1], pos[2])
		p.load_inventory(saved)
		p.inventory.creative = bool(saved.get("creative", false))
		p.data = saved.get("data", {}) if saved.get("data") is Dictionary else {}
		for id in (saved.get("cosmetics") if saved.get("cosmetics") is Array else []):
			p.owned_cosmetics[String(id)] = true
		p.server_wear = saved.get("server_wear") if saved.get("server_wear") is Dictionary else {}
		for recipe_id in (saved.get("recipes") if saved.get("recipes") is Array else []):
			p.known_recipes[str(recipe_id)] = true
		for item_name in (saved.get("seen_items") if saved.get("seen_items") is Array else []):
			p.seen_items[str(item_name)] = true
		p.health = clampf(float(saved.get("health", p.max_health)), 1.0, p.max_health)
		var spawn_point = saved.get("spawn_point")
		if spawn_point is Array and spawn_point.size() == 3:
			p.spawn_point = Vector3(spawn_point[0], spawn_point[1], spawn_point[2])
	players[peer_id] = p
	if first_time:
		p.state.position = spawn_handler.call(p) if spawn_handler.is_valid() else _default_spawn()
	ensure_area_loaded(p.state.position)

	Net.s_welcome.rpc_id(peer_id, peer_id, p.state.position, 0.0)
	_set_client_avatar(p, avatar, true)
	Net.s_cosmetics.rpc_id(peer_id, PackedStringArray(p.owned_cosmetics.keys()), cosmetics.policy)
	Net.s_known_recipes.rpc_id(peer_id, PackedStringArray(p.known_recipes.keys()), gameplay.recipe_discovery)
	Net.s_time.rpc_id(peer_id, _time_of_day, _day_length)
	p.sync_inventory()
	refresh_stats(p)
	sync_health(p)
	for other: ServerPlayer in players.values():
		if other != p:
			Net.s_player_joined.rpc_id(peer_id, other.peer_id, other.name)
			Net.s_player_joined.rpc_id(other.peer_id, peer_id, player_name)
			Net.s_player_appearance.rpc_id(peer_id, other.peer_id, other.appearance)
			Net.s_player_appearance.rpc_id(other.peer_id, peer_id, p.appearance)
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
	containers.close(p, false)
	sessions.leave(p)
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
	if peer and multiplayer.get_peers().has(peer_id):
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
		"seed": world_seed, "result": {}, "task_id": -1, "scan_ids": block_ticks.scan_ids()}


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
			if saved.get("entities") is Array:
				job.entities = saved.entities
			job.ticks = saved.get("ticks")
			var entries = saved.get("data", {})
			if entries is Dictionary:
				for key: String in entries:
					var parts := key.split(",")
					if parts.size() == 3 and entries[key] is Dictionary:
						data[Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))] = entries[key]
	job.result = {"chunk": chunk, "generated": generated, "deltas": deltas, "data": data, "entities": job.get("entities", []),
		"tickable": BlockTicks.scan(chunk.blocks, job.scan_ids[0]), "lights": BlockTicks.scan(chunk.blocks, job.scan_ids[1]),
		"ticks": job.get("ticks"), "usec": Time.get_ticks_usec() - started}


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
	block_ticks.load_chunk(job.coord, r.tickable, r.lights, r.ticks)
	if not r.deltas.is_empty():
		_deltas[job.coord] = r.deltas
		_generated[job.coord] = r.generated
	if not r.data.is_empty():
		_block_data[job.coord] = r.data
	if not r.entities.is_empty():
		_entity_chunks[job.coord] = true
		entities.load_chunk(r.entities)
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
		var records := entities.unload_chunk(coord)
		if _save_dirty.has(coord) or _block_data.has(coord) or not records.is_empty() or _entity_chunks.has(coord) \
				or block_ticks.save_chunk(coord) != null:
			writes.append(_serialize_chunk(coord, records))
		block_ticks.unload_chunk(coord)
		_entity_chunks.erase(coord)
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


## Y of the highest solid or liquid block in the column (loading it if needed), or -1. Plants and
## other non-solid decorations are skipped, so things placed on the surface stand on the ground.
func surface_height(x: int, z: int) -> int:
	_ensure_chunk(VoxelWorld.chunk_coord_at(x, z))
	for y in range(Chunk.SIZE_Y - 1, -1, -1):
		var block := world.get_block(x, y, z)
		if block != BlockRegistry.AIR and (registry.solid_lut[block] == 1 or registry.liquid_lut[block] == 1):
			return y
	return -1


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
	if not _started:
		return
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
	if not _can_edit(p, pos) or current == BlockRegistry.UNLOADED or registry.breakable_lut[current] == 0 or p.dead:
		_reject_edit(p, pos)
		return
	var held := p.inventory.selected_item()
	var tool := items.tool_of(held)
	var harvest := true
	if not p.inventory.creative:
		var required := Mining.break_time(registry.defs[current], tool, p.get_stat("mining_speed"))
		# Accept a little early for latency; the client times the crack animation itself.
		var mined_long_enough: bool = p.mining.get("position") == pos and _time - float(p.mining.get("started", INF)) >= required * 0.8 - 0.15
		if required > 0.05 and not mined_long_enough:
			_reject_edit(p, pos)
			return
		harvest = Mining.can_harvest(registry.defs[current], tool)
	_stop_mining(p)
	var ev := emit("block_break", {"player": p, "position": pos, "block": current, "item": held, "slot": p.inventory.selected,
		"drops": _default_drops(current) if harvest else [], "cancelled": false})
	if ev.cancelled:
		_reject_edit(p, pos)
		return
	_apply_block(pos, BlockRegistry.AIR)
	entities.ai.make_noise(Vector3(pos) + Vector3.ONE * 0.5, 10.0, p)
	play_sound_at(block_sound(current, "break"), Vector3(pos) + Vector3.ONE * 0.5, 1.0, randf_range(0.85, 1.1), peer_id)
	if not p.inventory.creative and ev.drops is Array:
		for drop in ev.drops:
			if not (drop is Array and drop.size() == 2 and items.is_valid(int(drop[0]))):
				continue
			if gameplay.item_drops == "entity":
				entities.drop_item(int(drop[0]), int(drop[1]), Vector3(pos) + Vector3(0.5, 0.3, 0.5),
					Vector3(randf_range(-1.0, 1.0), randf_range(2.0, 3.5), randf_range(-1.0, 1.0)), 0.3)
			else:
				p.inventory.add(int(drop[0]), int(drop[1]), items.max_stack(int(drop[0])))
		if registry.defs[current].hardness > 0.0 and items.max_durability(held) > 0:
			damage_item(p, p.inventory.selected, 1, "mine")
		p.sync_inventory()
	emit("block_broken", {"player": p, "position": pos, "block": current, "item": held, "slot": p.inventory.selected, "harvested": harvest})


func on_place_block(peer_id: int, pos: Vector3i, yaw: float) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var block := p.inventory.selected_block()
	var current := world.get_block_v(pos)
	var valid: bool = _can_edit(p, pos) and block > 0 and registry.placeable_lut[block] == 1 \
		and (current == BlockRegistry.AIR or registry.liquid_lut[current] == 1 or registry.defs[current].replaceable) \
		and _has_solid_neighbor(pos) and is_supported(pos, block)
	if valid:
		for other: ServerPlayer in players.values():
			if registry.solid_lut[block] == 1 and PlayerPhysics.overlaps_block(other.state.position, pos) and not other.dead:
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
	if not str(registry.defs[block].get("station", "")).is_empty():
		sessions.claim(pos, p)
	entities.ai.make_noise(Vector3(pos) + Vector3.ONE * 0.5, 8.0, p)
	play_sound_at(block_sound(block, "place"), Vector3(pos) + Vector3.ONE * 0.5, 1.0, randf_range(0.85, 1.1), peer_id)
	_broadcast_player_event(p, Entities.Event.SWING)
	emit("block_placed", {"player": p, "position": pos, "block": block})


func on_interact(peer_id: int, pos: Vector3i) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var block := world.get_block_v(pos)
	if block == BlockRegistry.UNLOADED or registry.interactive_lut[block] == 0 or not _can_edit(p, pos):
		return
	var ev := emit("block_interact", {"player": p, "position": pos, "block": block, "cancelled": false})
	if ev.cancelled:
		return
	if not containers.type_of_block(block).is_empty():
		containers.open(p, pos)
	elif not String(registry.defs[block].get("station", "")).is_empty():
		open_crafting(p, {"position": pos})


func on_select_slot(peer_id: int, slot: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p:
		p.inventory.selected = clampi(slot, 0, Inventory.HOTBAR - 1)
		_stop_mining(p)
		refresh_stats(p)


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
	if item >= ItemRegistry.FIRST_ITEM and not items.is_usable(item) and not String(items.get_def(item).equip_slot).is_empty():
		_equip_from_hand(p)
		return
	if item < ItemRegistry.FIRST_ITEM or not items.is_usable(item) or p.edit_tokens < 1.0:
		return
	p.edit_tokens -= 1.0
	var teaches: Array = p.inventory.data[p.inventory.selected].get("teaches", items.get_def(item).get("teaches", []))
	if teaches is Array and not teaches.is_empty():
		_read_blueprint(p, teaches)
		return
	if has_target and (not world.has_chunk(VoxelWorld.chunk_coord_at(target.x, target.z)) \
			or p.get_eye_position().distance_to(Vector3(target) + Vector3.ONE * 0.5) > REACH + 0.87):
		has_target = false
	_broadcast_player_event(p, Entities.Event.SWING)
	var use_effect := String(items.visuals(item, p.inventory.data[p.inventory.selected]).effects.get("use", ""))
	if not use_effect.is_empty():
		var look_dir := PlayerPhysics.look_direction(p.yaw, p.pitch)
		play_effect(use_effect, p.get_eye_position() + look_dir * 0.8, {"direction": look_dir})
	emit("item_use", {"player": p, "item": item, "has_target": has_target, "position": target,
		"normal": normal.clamp(-Vector3i.ONE, Vector3i.ONE), "direction": PlayerPhysics.look_direction(p.yaw, p.pitch)})


func on_open_menu(peer_id: int, menu: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p and menu == "crafting":
		open_crafting(p, {})


func on_attack(peer_id: int, kind: int, target_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.dead:
		return
	var stats := p.get_stats()
	if _time - p.last_attack_time < float(stats.attack_cooldown) * 0.9:
		return
	var target = entities.entities.get(target_id) if kind == 0 else players.get(target_id)
	if target == null or target == p or (kind == 0 and not target.is_alive()) or (kind == 1 and target.dead):
		return
	var box: AABB = target.aabb() if kind == 0 else AABB(target.state.position - Vector3(PlayerPhysics.HALF_WIDTH, 0, PlayerPhysics.HALF_WIDTH),
		Vector3(PlayerPhysics.HALF_WIDTH * 2.0, PlayerPhysics.HEIGHT, PlayerPhysics.HALF_WIDTH * 2.0))
	var eye := p.get_eye_position()
	var distance := eye.distance_to(eye.clamp(box.position, box.end))
	if distance > float(stats.reach):
		return
	var center := box.get_center()
	var ray := VoxelRaycast.cast(world, registry.solid_lut, eye, center - eye, eye.distance_to(center))
	if ray.hit and eye.distance_to(Vector3(ray.position) + Vector3.ONE * 0.5) < distance - 0.5:
		return  # a wall is in the way
	p.last_attack_time = _time
	var item := p.inventory.selected_item()
	# Critical hits: attacking while falling (a jump attack) or by the crit_chance stat.
	var critical: bool = (not p.state.on_ground and p.state.velocity.y < -1.0) or randf() < float(stats.crit_chance)
	var damage: float = float(stats.attack_damage) * (float(stats.crit_multiplier) if critical else 1.0)
	var ev := emit("player_attack", {"player": p, "target": target, "target_kind": "entity" if kind == 0 else "player",
		"item": item, "slot": p.inventory.selected, "damage": damage, "critical": critical, "cancelled": false})
	if ev.cancelled:
		return
	play_sound_at("engine:swing", eye, 0.7, randf_range(0.9, 1.1), peer_id)
	_broadcast_player_event(p, Entities.Event.SWING)
	var look := items.visuals(item, p.inventory.data[p.inventory.selected]) if item >= ItemRegistry.FIRST_ITEM else {"effects": {}}
	var direction3 := PlayerPhysics.look_direction(p.yaw, p.pitch)
	if look.effects.has("swing"):
		play_effect(look.effects.swing, eye + direction3 * 0.9, {"direction": direction3})
	entities.ai.make_noise(eye, 14.0, p, true)
	var direction := PlayerPhysics.look_direction(p.yaw, 0.0)
	var landed := false
	if kind == 0:
		landed = entities.damage(target, float(ev.damage), "attack", p, direction)
		var sweep := float(items.weapon_of(item).get("sweep", 0.0))
		if landed and sweep > 0.0:
			for other in entities.in_radius(target.body.position, 1.8):
				if other != target and other.def.kind == "mob":
					other.hurt_timer = 0.0
					entities.damage(other, float(ev.damage) * sweep, "attack", p, other.body.position - p.state.position)
	elif gameplay.pvp:
		landed = damage_player(target, float(ev.damage), "attack", p, direction, false, 6.0 * float(stats.knockback))
	if landed:
		var impact := eye.clamp(box.position, box.end).lerp(center, 0.5)
		play_effect(String(look.effects.get("hit", "engine:hit")), impact, {"direction": -direction3})
		if critical:
			play_effect("engine:crit", impact + Vector3(0, 0.3, 0))
	if landed and items.max_durability(item) > 0:
		damage_item(p, p.inventory.selected, 1 if not items.weapon_of(item).is_empty() else 2, "attack")


func on_interact_entity(peer_id: int, target_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	var e = entities.entities.get(target_id)
	if p == null or p.dead or e == null or not e.is_alive() or p.edit_tokens < 1.0:
		return
	p.edit_tokens -= 1.0
	if p.get_eye_position().distance_to(e.aabb().get_center()) > ATTACK_REACH + e.def.width:
		return
	emit("entity_interact", {"player": p, "entity": e, "item": p.inventory.selected_item()})


func on_inventory_click(peer_id: int, slot: int, button: int, shift: bool) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.dead:
		return
	if slot == -1:
		# Clicked outside the inventory: drop what the cursor holds.
		if p.inventory.cursor_count > 0:
			var n := p.inventory.cursor_count if button == 1 else 1
			p.drop(p.inventory.cursor_id, n, p.inventory.cursor_data)
			p.inventory.cursor_count -= n
			if p.inventory.cursor_count <= 0:
				p.inventory.cursor_id = 0
				p.inventory.cursor_data = {}
	elif button == 3 and p.inventory.creative and slot >= 0 and slot < p.inventory.total() and p.inventory.cursor_count <= 0:
		# Middle click in creative: pick up a full stack copy.
		if p.inventory.ids[slot] > 0:
			p.inventory.cursor_id = p.inventory.ids[slot]
			p.inventory.cursor_count = items.max_stack(p.inventory.ids[slot])
			p.inventory.cursor_data = p.inventory.data[slot].duplicate(true)
	elif slot >= Containers.SLOT_BASE:
		containers.click(p, slot - Containers.SLOT_BASE, button, shift)
		return
	elif shift and p.open_container != null and slot < Inventory.SIZE:
		containers.quick_move_in(p, slot)
		return
	else:
		p.inventory.click(slot, button, shift, items.max_stack, _slot_accepts.bind(p))
	p.sync_inventory()


func on_inventory_closed(peer_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		containers.close(p, false)
	if p == null or p.inventory.cursor_count <= 0:
		return
	var left := p.inventory.add(p.inventory.cursor_id, p.inventory.cursor_count, items.max_stack(p.inventory.cursor_id), p.inventory.cursor_data)
	if left > 0:
		p.drop(p.inventory.cursor_id, left, p.inventory.cursor_data)
	p.inventory.cursor_id = 0
	p.inventory.cursor_count = 0
	p.inventory.cursor_data = {}
	p.sync_inventory()


func on_drop_item(peer_id: int, whole_stack: bool) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.dead or p.edit_tokens < 1.0:
		return
	p.edit_tokens -= 1.0
	var slot := p.inventory.selected
	var id := p.inventory.ids[slot]
	var count := p.inventory.counts[slot] if not p.inventory.creative else items.max_stack(id)
	if id <= 0 or count <= 0:
		return
	var n := count if whole_stack else 1
	if emit("item_drop", {"player": p, "item": id, "count": n, "cancelled": false}).cancelled:
		p.sync_inventory()
		return
	var item_data: Dictionary = p.inventory.data[slot].duplicate(true)
	if not p.inventory.creative:
		p.inventory.set_slot(slot, id, count - n, item_data)
		p.sync_inventory()
	p.drop(id, n, item_data)
	play_sound_at("engine:drop", p.get_eye_position(), 0.6)


func _slot_accepts(slot_index: int, id: int, p: ServerPlayer) -> bool:
	var i := slot_index - Inventory.SIZE
	return i >= 0 and i < p.inventory.equipment_slots.size() and items.fits_slot(id, p.inventory.equipment_slots[i])


## Right-click with a wearable item: swap it with whatever is in its equipment slot.
func _equip_from_hand(p: ServerPlayer) -> void:
	var hand := p.inventory.selected
	var id := p.inventory.ids[hand]
	var index := p.inventory.equipment_index(String(items.get_def(id).equip_slot))
	if index < 0 or p.inventory.counts[hand] != 1:
		return
	var worn := [p.inventory.ids[index], p.inventory.counts[index], p.inventory.data[index]]
	p.inventory.set_slot(index, id, 1, p.inventory.data[hand])
	p.inventory.set_slot(hand, worn[0], worn[1], worn[2])
	play_sound_at("engine:equip", p.get_eye_position(), 0.8)
	p.sync_inventory()


func on_mine_start(peer_id: int, pos: Vector3i) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.dead or p.get_eye_position().distance_to(Vector3(pos) + Vector3.ONE * 0.5) > REACH + 1.5:
		return
	var block := world.get_block_v(pos)
	if block == BlockRegistry.UNLOADED or registry.breakable_lut[block] == 0:
		return
	p.mining = {"position": pos, "started": _time}
	_broadcast_player_event(p, Entities.Event.SWING)
	var seconds := Mining.break_time(registry.defs[block], items.tool_of(p.inventory.selected_item()), p.get_stat("mining_speed"))
	_broadcast_mining(p, pos, seconds)


func on_mine_stop(peer_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		_stop_mining(p)


func _stop_mining(p: ServerPlayer) -> void:
	if p.mining.is_empty():
		return
	var pos: Vector3i = p.mining.position
	p.mining = {}
	_broadcast_mining(p, pos, -1.0)


## Lets nearby players see the crack animation on a block someone else is breaking.
func _broadcast_mining(p: ServerPlayer, pos: Vector3i, seconds: float) -> void:
	if not _started:
		return
	for other: ServerPlayer in players.values():
		if other != p and other.state.position.distance_to(Vector3(pos)) < 32.0:
			Net.s_mining.rpc_id(other.peer_id, p.peer_id, pos, seconds)


## Wears an item: adds `amount` to its item data `damage`; at the item's durability it breaks.
func damage_item(p: ServerPlayer, slot: int, amount: int, reason := "use") -> void:
	if slot < 0 or slot >= p.inventory.total() or amount <= 0:
		return
	var id := p.inventory.ids[slot]
	var max_durability := items.max_durability(id)
	if id <= 0 or max_durability <= 0 or not gameplay.durability or p.inventory.creative:
		return
	var ev := emit("item_durability", {"player": p, "slot": slot, "item": id, "data": p.inventory.data[slot],
		"amount": amount, "reason": reason, "cancelled": false})
	if ev.cancelled or int(ev.amount) <= 0:
		return
	var item_data: Dictionary = p.inventory.data[slot].duplicate(true)
	item_data.damage = int(item_data.get("damage", 0)) + int(ev.amount)
	if item_data.damage >= max_durability:
		p.inventory.clear_slot(slot)
		emit("item_break", {"player": p, "slot": slot, "item": id, "data": item_data})
		play_sound_at("engine:item_break", p.get_eye_position())
		play_effect(String(items.visuals(id, item_data).effects.get("break", "engine:smoke")), p.get_eye_position() + PlayerPhysics.look_direction(p.yaw, p.pitch) * 0.6, {"scale": 0.4})
		p.send_message("Your %s broke" % items.display_name(id))
	else:
		p.inventory.data[slot] = item_data
	p.sync_inventory()


## Recomputes a player's stats, applies max health and movement speed, reports equipment changes and
## sends the result to the client when it changed.
func refresh_stats(p: ServerPlayer) -> void:
	var stats := PlayerStats.compute(p, items)
	var ev := emit("player_stats", {"player": p, "stats": stats})
	if ev.stats is Dictionary:
		stats = ev.stats
	p._stats = stats
	p._stats_dirty = false
	var new_max := float(stats.max_health)
	if not is_equal_approx(new_max, p.max_health):
		p.max_health = new_max
		p.health = minf(p.health, new_max)
		sync_health(p)
	_update_player_rules(p)
	var worn := p.inventory.ids.slice(Inventory.SIZE)
	if p._equipment_ids.size() == worn.size():
		for i in worn.size():
			if worn[i] != p._equipment_ids[i]:
				emit("equipment_changed", {"player": p, "slot": p.inventory.equipment_slots[i], "old_item": p._equipment_ids[i], "item": worn[i]})
	p._equipment_ids = worn
	if p._online() and stats != p._sent_stats:
		p._sent_stats = stats.duplicate()
		Net.s_player_stats.rpc_id(p.peer_id, stats)
	refresh_appearance(p)


## What other players see: held item, visible armor and avatar. Sent to everyone when it changes.
func refresh_appearance(p: ServerPlayer) -> void:
	var armor := {}
	for i in p.inventory.equipment_slots.size():
		var index := Inventory.SIZE + i
		var slot_name: String = p.inventory.equipment_slots[i]
		if slot_name != "offhand" and p.inventory.ids[index] > 0:
			armor[slot_name] = p.inventory.ids[index]
	var visible := cosmetics.visible_armor(armor, p.avatar)
	var appearance := {"held": p.inventory.selected_item(), "armor": visible, "avatar": p.avatar}
	var held := p.inventory.selected_item()
	if held >= ItemRegistry.FIRST_ITEM:
		var look := items.visuals(held, p.inventory.data[p.inventory.selected])
		if not look.glow.is_empty() or not look.trail.is_empty() or look.effects.has("held"):
			appearance.held_look = {"glow": look.glow, "trail": look.trail, "held": look.effects.get("held", "")}
	# The brightest glow among visible armor lights the whole armor texture.
	for slot_name in visible:
		var slot_index := p.inventory.equipment_index(slot_name)
		var glow: Dictionary = items.visuals(visible[slot_name], p.inventory.data[slot_index] if slot_index >= 0 else {}).glow
		if not glow.is_empty() and float(glow.energy) > float(appearance.get("armor_glow", {}).get("energy", 0.0)):
			appearance.armor_glow = glow
	var ev := emit("player_appearance", {"player": p, "appearance": appearance})
	appearance = ev.appearance
	if appearance == p.appearance or not _started:
		p.appearance = appearance
		return
	p.appearance = appearance
	for other: ServerPlayer in players.values():
		Net.s_player_appearance.rpc_id(other.peer_id, p.peer_id, appearance)


# --- Cosmetics ----------------------------------------------------------------------------------

## A client sent its avatar: while joining it is kept for spawn; in game it replaces the player's look.
func on_set_avatar(peer_id: int, avatar: Dictionary) -> void:
	var j: Dictionary = _joining.get(peer_id, {})
	if not j.is_empty():
		if j.authenticated:
			j.avatar = avatar
		return
	var p: ServerPlayer = players.get(peer_id)
	if p == null or _time - p.avatar_changed_at < AVATAR_CHANGE_INTERVAL:
		return
	p.avatar_changed_at = _time
	_set_client_avatar(p, avatar, false)


## Built-in picks form the player's portable look. Server cosmetic picks are remembered by this server;
## on join (`joining`) the client only knows its portable look, so remembered picks are kept.
func _set_client_avatar(p: ServerPlayer, avatar, joining: bool) -> void:
	var clean := cosmetics.sanitize_avatar(avatar, can_wear.bind(p))
	if not cosmetics.policy.allow_colors:
		clean.erase("skin")
		clean.erase("body")
		for cat_name in clean.get("wear", {}):
			clean.wear[cat_name].erase("color")
	var portable := clean.duplicate(true)
	var server_picks := {}
	for cat_name in clean.get("wear", {}):
		if not Cosmetics.is_builtin(clean.wear[cat_name].id):
			server_picks[cat_name] = clean.wear[cat_name]
			portable.wear.erase(cat_name)
	p.portable_avatar = portable
	if not joining:
		p.server_wear = server_picks
	refresh_avatar(p)


## Whether a player may pick a cosmetic themselves (mods can still dress anyone in anything).
func can_wear(cosmetic_name: String, p: ServerPlayer) -> bool:
	var d := cosmetics.get_def(cosmetic_name)
	if d.is_empty() or cosmetics.is_blocked(cosmetic_name):
		return false
	if Cosmetics.is_builtin(cosmetic_name):
		return cosmetics.policy.allow_builtin
	return d.unlocked or p.owned_cosmetics.has(cosmetic_name)


## Recomputes the look others see: portable look (or the name's default), then this server's picks,
## the policy uniform, the player's override and avatar_change handlers.
func refresh_avatar(p: ServerPlayer) -> void:
	var base: Dictionary = p.portable_avatar if not p.portable_avatar.is_empty() else Cosmetics.default_avatar(p.name)
	var avatar := cosmetics.sanitize_avatar(base, can_wear.bind(p))
	avatar = Cosmetics.merge(avatar, cosmetics.sanitize_avatar({"wear": p.server_wear}, can_wear.bind(p)))
	avatar = Cosmetics.merge(avatar, cosmetics.policy.uniform)
	avatar = Cosmetics.merge(avatar, p.avatar_override)
	var ev := emit("avatar_change", {"player": p, "avatar": avatar})
	p.avatar = cosmetics.sanitize_avatar(ev.avatar)
	refresh_appearance(p)


func grant_cosmetic(p: ServerPlayer, cosmetic_name: String, owned: bool) -> void:
	if owned == p.owned_cosmetics.has(cosmetic_name) or cosmetics.get_def(cosmetic_name).is_empty():
		return
	if owned:
		p.owned_cosmetics[cosmetic_name] = true
	else:
		p.owned_cosmetics.erase(cosmetic_name)
	if p._online():
		Net.s_cosmetics.rpc_id(p.peer_id, PackedStringArray(p.owned_cosmetics.keys()), cosmetics.policy)
	refresh_avatar(p)


func set_cosmetics_policy(values: Dictionary) -> void:
	cosmetics.set_policy(values)
	for p: ServerPlayer in players.values():
		if p._online():
			Net.s_cosmetics.rpc_id(p.peer_id, PackedStringArray(p.owned_cosmetics.keys()), cosmetics.policy)
		refresh_avatar(p)


func _update_player_rules(p: ServerPlayer) -> void:
	var speed := float(p._stats.get("move_speed", 1.0)) if not p._stats.is_empty() else 1.0
	if is_equal_approx(speed, 1.0):
		p.physics_rules = null
		return
	p.physics_rules = PlayerPhysics.Rules.new()
	var values := rules.to_dict()
	values.walk_speed = rules.walk_speed * speed
	values.sprint_speed = rules.sprint_speed * speed
	p.physics_rules.apply_dict(values)
	p.physics_rules.solid_lut = rules.solid_lut
	p.physics_rules.liquid_lut = rules.liquid_lut


# --- Crafting -----------------------------------------------------------------------------------

## `station`: "" (crafted anywhere) or a station name blocks declare with `station` (e.g. a crafting table).
## options: category, id. Returns the recipe index.
func add_recipe(inputs: Dictionary, output: int, count: int, station := "", options := {}) -> int:
	return recipes.add({"inputs": inputs, "output": output, "count": count, "station": station,
		"category": options.get("category", ""), "id": options.get("id", ""), "tier": options.get("tier", 0),
		"needs": options.get("needs", []), "time": options.get("time", 0.0), "project": options.get("project", false),
		"unlock": options.get("unlock", "pickup"), "hint": options.get("hint", "")}, items)


## How long an item burns as fuel (seconds; 0 = not fuel).
func get_fuel(item: int) -> float:
	return float(_fuels.get(item, 0.0))


func set_fuel(item: int, seconds: float) -> void:
	if seconds > 0.0:
		_fuels[item] = seconds
	else:
		_fuels.erase(item)


## Processing recipes machines look up: kind ("smelting", "grinding", ...) -> input -> result.
func add_process(kind: String, input: int, output: int, count: int, seconds: float) -> void:
	if not _processes.has(kind):
		_processes[kind] = {}
	_processes[kind][input] = {"output": output, "count": count, "seconds": seconds}


func get_process(kind: String, input: int) -> Dictionary:
	return _processes.get(kind, {}).get(input, {})


## Whether the player is at the station a recipe needs (creative players craft anything anywhere).
func _at_station(p: ServerPlayer, recipe: Dictionary) -> bool:
	if recipe.station.is_empty() or p.inventory.creative:
		return true
	var s: Dictionary = p.crafting_station
	return _station_valid(p) and s.name == recipe.station and Stations.usable(s) and int(s.get("tier", 1)) >= int(recipe.get("tier", 0)) \
		and recipe.get("needs", []).all(func(f): return s.get("features", []).has(f))


## The player's crafting station still exists and is within reach.
func _station_valid(p: ServerPlayer) -> bool:
	var s: Dictionary = p.crafting_station
	if s.is_empty() or not s.has("position") or str(registry.defs[world.get_block_v(s.position)].get("station", "")) != s.name:
		return false
	return p.get_eye_position().distance_to(Vector3(s.position) + Vector3.ONE * 0.5) <= Containers.MAX_DISTANCE


## Items a station can draw from containers around it: {item id: count}. Empty when crafting by hand.
func crafting_stock(p: ServerPlayer) -> Dictionary:
	var stock := sessions.usable_tray(p, p.crafting_station.position) if _station_valid(p) else {}
	for c in _stock_containers(p):
		for i in c.size():
			var s: Dictionary = c.get_item(i)
			if s.item > 0 and s.data.is_empty():
				stock[s.item] = int(stock.get(s.item, 0)) + s.count
	return stock


func _stock_containers(p: ServerPlayer) -> Array:
	var out := []
	if not _station_valid(p):
		return out
	var center: Vector3i = p.crafting_station.position
	var r := STATION_PULL_RADIUS + int(p.crafting_station.get("pull_radius", 0))
	for pos: Vector3i in find_block_data():
		if absi(pos.x - center.x) <= r and absi(pos.y - center.y) <= r and absi(pos.z - center.z) <= r:
			var c = containers.get_container(pos)
			if c != null:
				out.append(c)
	return out


## How many times the player can craft a recipe right now (inventory plus the station's nearby chests).
func craftable_times(p: ServerPlayer, recipe: Dictionary, limit := 999) -> int:
	if not _at_station(p, recipe) or not knows_recipe(p, recipe.id):
		return 0
	if p.inventory.creative:
		return limit
	var stock := crafting_stock(p)
	var times := limit
	for id: int in recipe.inputs:
		times = mini(times, (p.inventory.count_of(id) + int(stock.get(id, 0))) / int(recipe.inputs[id]))
	return times


func _can_craft(p: ServerPlayer, recipe: Dictionary) -> bool:
	return craftable_times(p, recipe, 1) > 0


# --- Discovery ------------------------------------------------------------------------------------

func knows_recipe(p: ServerPlayer, recipe_id: String) -> bool:
	if not gameplay.recipe_discovery or p.inventory.creative or p.known_recipes.has(recipe_id):
		return true
	var index := recipes.index_of(recipe_id)
	return index >= 0 and recipes.recipes[index].unlock == "known"


## Teaches a recipe. Returns true if the player did not know it (creative players still learn it).
func learn_recipe(p: ServerPlayer, recipe_id: String, source := "mod") -> bool:
	var index := recipes.index_of(recipe_id)
	if index < 0 or p.known_recipes.has(recipe_id):
		return false
	p.known_recipes[recipe_id] = true
	if p._online():
		Net.s_recipe_learned.rpc_id(p.peer_id, index, source)
	emit("recipe_learned", {"player": p, "recipe": recipe_id, "source": source})
	return true


## "pickup" recipes unlock the first time a player holds one of their ingredients.
func check_discoveries(p: ServerPlayer) -> void:
	var fresh := []
	for i in p.inventory.total():
		var id := p.inventory.ids[i]
		if id > 0 and p.inventory.counts[i] > 0:
			var item_name := items.name_of(id)
			if not p.seen_items.has(item_name):
				p.seen_items[item_name] = true
				fresh.append(id)
	if fresh.is_empty() or not gameplay.recipe_discovery:
		return
	for id in fresh:
		for index in recipes.using(id):
			var r: Dictionary = recipes.recipes[index]
			if r.unlock == "pickup":
				learn_recipe(p, r.id, "pickup")


func _read_blueprint(p: ServerPlayer, teaches: Array) -> void:
	var learned := 0
	for recipe_id in teaches:
		if learn_recipe(p, str(recipe_id), "blueprint"):
			learned += 1
	if learned == 0:
		p.show_title("", "You already know everything on this blueprint", 1.5)
		return
	if not p.inventory.creative:
		p.inventory.consume_selected()
		p.sync_inventory()
	play_sound_to(p, "engine:discover")
	play_effect("engine:sparkle", p.get_eye_position() + PlayerPhysics.look_direction(p.yaw, p.pitch) * 0.6, {"scale": 0.6, "color": "#a8d8ff"})


## Opens the crafting screen for a player: by hand ({}) or at a station {name, position, title}.
func open_crafting(p: ServerPlayer, station := {}) -> void:
	if station.has("position"):
		station = stations.evaluate(station.position)
	p.crafting_station = station
	if station.has("position"):
		sessions.join(p, station.position)
	else:
		sessions.leave(p)
	if p._online():
		var info: Dictionary = station.duplicate(true) if not station.is_empty() else {"name": "", "title": "Crafting"}
		info.pull_radius = STATION_PULL_RADIUS + int(station.get("pull_radius", 0))
		Net.s_crafting_open.rpc_id(p.peer_id, info, crafting_stock(p))


## Station screen buttons: "upgrade" uses the next tier's kit, "guide" shows a structure's missing blocks.
func on_station_action(peer_id: int, action: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.edit_tokens < 1.0 or not _station_valid(p):
		return
	p.edit_tokens -= 1.0
	var pos: Vector3i = p.crafting_station.position
	match action:
		"upgrade":
			if stations.upgrade(p, pos):
				open_crafting(p, {"position": pos})
		"guide":
			var def: Dictionary = stations.defs.get(p.crafting_station.name, {})
			if not def.get("multiblock", {}).is_empty() and p._online():
				Net.s_structure_guide.rpc_id(p.peer_id, stations.structure_missing(pos, def.multiblock).slice(0, 256))


## Mods: opens the crafting screen for a player as if they pressed the crafting key.
func show_crafting(p: ServerPlayer) -> void:
	open_crafting(p, {})


## Crafts a recipe up to `times` times, taking ingredients from the inventory first and then from the
## station's nearby chests. Returns how many times it crafted.
func craft(p: ServerPlayer, index: int, times := 1) -> int:
	if index < 0 or index >= recipes.recipes.size() or p.dead:
		return 0
	var recipe: Dictionary = recipes.recipes[index]
	if p.crafting_station.has("position") and _station_valid(p):
		p.crafting_station = stations.evaluate(p.crafting_station.position)  # workshop blocks may have changed
	if recipe.get("project", false):
		return 0  # projects are built together through the station screen (see StationSessions)
	var n := craftable_times(p, recipe, clampi(times, 1, 64))
	if n <= 0:
		return 0
	if not p.inventory.creative:
		var sources := _stock_containers(p)
		var at_station := _station_valid(p)
		for id: int in recipe.inputs:
			var needed: int = int(recipe.inputs[id]) * n
			var from_inventory := mini(needed, p.inventory.count_of(id))
			p.inventory.remove(id, from_inventory)
			needed -= from_inventory
			if at_station and needed > 0:
				needed -= sessions.consume_tray(p, p.crafting_station.position, id, needed)
			for c in sources:
				for i in c.size():
					if needed <= 0:
						break
					var s: Dictionary = c.get_item(i)
					if s.item == id and s.data.is_empty():
						needed -= int(c.take(i, needed).count)
		if float(recipe.get("time", 0.0)) > 0.0 and at_station:
			# Timed recipes are crafted in the station's queue; players there speed it up.
			sessions.add_job(p, p.crafting_station.position, index, n)
			p.sync_inventory()
			if p._online():
				Net.s_crafting_stock.rpc_id(p.peer_id, crafting_stock(p))
			return n
	var total: int = recipe.count * n
	var left := p.inventory.add(recipe.output, total, items.max_stack(recipe.output))
	if left > 0:
		p.drop(recipe.output, left)
	p.sync_inventory()
	emit("item_crafted", {"player": p, "item": recipe.output, "count": total, "recipe": recipe.id})
	var at: Vector3 = Vector3(p.crafting_station.position) + Vector3(0.5, 1.1, 0.5) if _station_valid(p) \
		else p.get_eye_position() + PlayerPhysics.look_direction(p.yaw, p.pitch) * 0.7
	play_effect("engine:craft", at, {"scale": 0.6})
	play_sound_at("engine:craft", at, 0.8, randf_range(0.95, 1.1))
	if p._online():
		Net.s_crafted.rpc_id(p.peer_id, index, n, crafting_stock(p))
	return n


func on_craft(peer_id: int, index: int, times: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.edit_tokens < 1.0:
		return
	p.edit_tokens -= 1.0
	craft(p, index, times)


func on_crafting_closed(peer_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		p.crafting_station = {}
		sessions.leave(p)


## Co-op actions at the player's station: "view" (recipe index), "deposit" (backpack slot), "take" (tray
## index), "start_project" (recipe index), "contribute", "cancel_project".
func on_station_coop(peer_id: int, action: String, arg: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.dead or not _station_valid(p):
		return
	if action != "view":
		if p.edit_tokens < 1.0:
			return
		p.edit_tokens -= 1.0
	var pos: Vector3i = p.crafting_station.position
	match action:
		"view": sessions.viewing(p, arg)
		"deposit": sessions.deposit(p, pos, arg)
		"take": sessions.take(p, pos, arg)
		"start_project":
			if arg >= 0 and arg < recipes.recipes.size() and _at_station(p, recipes.recipes[arg]):
				sessions.start_project(p, pos, arg)
		"contribute": sessions.contribute(p, pos)
		"cancel_project": sessions.cancel_project(p, pos)
	if p._online() and action in ["deposit", "take", "contribute", "cancel_project"]:
		Net.s_crafting_stock.rpc_id(p.peer_id, crafting_stock(p))


## Tells players crafting near a changed container what their station can draw from now.
func _refresh_crafting_stock(pos: Vector3i) -> void:
	for p: ServerPlayer in players.values():
		if not p.crafting_station.has("position") or not p._online():
			continue
		var d: Vector3i = p.crafting_station.position - pos
		if absi(d.x) <= STATION_PULL_RADIUS and absi(d.y) <= STATION_PULL_RADIUS and absi(d.z) <= STATION_PULL_RADIUS:
			Net.s_crafting_stock.rpc_id(p.peer_id, crafting_stock(p))


func on_ui_action(peer_id: int, ui_id: String, action: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
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
		if not containers.type_of_block(old).is_empty():
			containers.block_removed(pos, get_block_data(pos), old)
		clear_block_data(pos)
	block_ticks.block_changed(pos, old, block)
	for p: ServerPlayer in players.values():
		if p.sent_chunks.has(coord):
			Net.s_block_changed.rpc_id(p.peer_id, pos, block, state & 255)
	# Blocks that need support (plants, torches) break when what holds them goes away.
	if old != block and pos.y + 1 < Chunk.SIZE_Y:
		var above := world.get_block_v(pos + Vector3i.UP)
		if above != BlockRegistry.AIR and above != BlockRegistry.UNLOADED and not is_supported(pos + Vector3i.UP, above):
			break_block(pos + Vector3i.UP, true)


## Whether `block` may stand at `pos`: its `support` rule ("solid" or [block names]) must accept the block
## below. Blocks without a rule always can.
func is_supported(pos: Vector3i, block: int) -> bool:
	if not _support_rules.has(block):
		var rule = registry.defs[block].get("support")
		var resolved = null
		if rule is String and rule == "solid":
			resolved = true
		elif rule is Array or rule is String:
			resolved = {}
			for block_name in (rule if rule is Array else [rule]):
				var id := registry.id_of(String(block_name))
				if id > 0:
					resolved[id] = true
		_support_rules[block] = resolved
	var needed = _support_rules[block]
	if needed == null:
		return true
	var below := world.get_block_v(pos + Vector3i.DOWN)
	return registry.solid_lut[below] == 1 and below != BlockRegistry.UNLOADED if needed is bool else needed.has(below)


## Breaks a block without a player (support lost, explosions, mods): drops items, plays its sound.
func break_block(pos: Vector3i, drop := true) -> void:
	var block := world.get_block_v(pos)
	if block == BlockRegistry.AIR or block == BlockRegistry.UNLOADED:
		return
	var drops := _default_drops(block) if drop else []
	var ev := emit("block_destroyed", {"position": pos, "block": block, "drops": drops})
	_apply_block(pos, BlockRegistry.AIR)
	play_sound_at(block_sound(block, "break"), Vector3(pos) + Vector3.ONE * 0.5, 0.8, randf_range(0.9, 1.1))
	for d in (ev.drops if ev.drops is Array else []):
		if d is Array and d.size() == 2 and items.is_valid(int(d[0])) and int(d[1]) > 0:
			entities.drop_item(int(d[0]), int(d[1]), Vector3(pos) + Vector3(0.5, 0.3, 0.5),
				Vector3(randf_range(-1.0, 1.0), randf_range(2.0, 3.5), randf_range(-1.0, 1.0)), 0.3)


## Tells the client the authoritative block and inventory so it can roll back its prediction.
func _reject_edit(p: ServerPlayer, pos: Vector3i) -> void:
	var block := world.get_block_v(pos)
	if block != BlockRegistry.UNLOADED and _started:
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
	block_ticks.clock = float(_meta.get("clock", 0.0))
	if _meta.get("time") is Array and _meta.time.size() == 2:
		_time_of_day = float(_meta.time[0])
		_day_length = float(_meta.time[1])


## Returns [path, json text] for a chunk's delta, or [path, null] when there is nothing to keep.
func _serialize_chunk(coord: Vector2i, entity_records = null) -> Array:
	var deltas: Dictionary = _deltas.get(coord, {})
	var entries: Dictionary = _block_data.get(coord, {})
	var chunk = world.chunks.get(coord)
	var states: PackedInt32Array = chunk.encode_states() if chunk != null else PackedInt32Array()
	var records: Array = entity_records if entity_records is Array else entities.serialize_chunk(coord)
	if records.is_empty():
		_entity_chunks.erase(coord)
	else:
		_entity_chunks[coord] = true
	var tick_state = block_ticks.save_chunk(coord)
	if deltas.is_empty() and entries.is_empty() and states.is_empty() and records.is_empty() and tick_state == null:
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
	return [_chunk_path(coord), JSON.stringify({"version": 1, "palette": palette, "blocks": edits, "states": Array(states), "data": data, "entities": records, "ticks": tick_state})]

func _store_player(p: ServerPlayer) -> void:
	_meta.players[p.player_id] = {
		"name": p.name,
		"position": [p.state.position.x, p.state.position.y, p.state.position.z],
		"inventory": p.save_inventory().inventory,
		"item_data": p.save_inventory().item_data,
		"equipment": p.save_inventory().equipment,
		"modifiers": p.modifiers.duplicate(true),
		"creative": p.inventory.creative,
		"data": p.data,
		"cosmetics": p.owned_cosmetics.keys(),
		"server_wear": p.server_wear,
		"recipes": p.known_recipes.keys(),
		"seen_items": p.seen_items.keys(),
		"health": maxf(p.health, 1.0) if not p.dead else p.max_health,
		"spawn_point": [p.spawn_point.x, p.spawn_point.y, p.spawn_point.z] if p.spawn_point != Vector3.INF else null,
	}


## Serializes changed chunks and metadata on this thread, then writes files on a worker.
func _save_all(wait := false) -> void:
	if _save_dir.is_empty():
		return
	var writes := []
	var coords := _save_dirty.duplicate()
	for coord: Vector2i in _block_data:
		coords[coord] = true  # block data dictionaries may have been mutated in place
	for coord: Vector2i in _entity_chunks.keys():
		coords[coord] = true  # persistent entities may have left the chunk
	for coord: Vector2i in block_ticks.ticking_chunks():
		coords[coord] = true  # keeps the tick clock current so catch-up never counts loaded time
	for e: Entity in entities.entities.values():
		if e.def.persistent:
			coords[VoxelWorld.chunk_coord_of(e.body.position)] = true
	for coord: Vector2i in coords:
		if world.chunks.has(coord):
			writes.append(_serialize_chunk(coord))
	_save_dirty.clear()
	if not coords.is_empty():
		_activity_since_backup = true
	for p: ServerPlayer in players.values():
		_store_player(p)
	_meta.time = [_time_of_day, _day_length]
	_meta.clock = block_ticks.clock
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
