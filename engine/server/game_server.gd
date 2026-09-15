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
const Experiments = preload("res://engine/server/experiments.gd")
const SkillCrafting = preload("res://engine/server/skill_crafting.gd")
const Hunger = preload("res://engine/server/hunger.gd")
const Sleep = preload("res://engine/server/sleep.gd")
const Guide = preload("res://engine/server/guide.gd")
const Tutorials = preload("res://engine/server/tutorials.gd")
const DevLog = preload("res://engine/server/dev_log.gd")
const DevTools = preload("res://engine/server/dev_tools.gd")
const DevWeb = preload("res://engine/server/dev_web.gd")
const StatusQuery = preload("res://engine/server/status_query.gd")
const HubAnnouncer = preload("res://engine/server/hub_announcer.gd")
const ChatFilter = preload("res://engine/server/chat_filter.gd")
const Transfers = preload("res://engine/server/transfers.gd")
const Roles = preload("res://engine/server/roles.gd")
const AntiCheat = preload("res://engine/server/anticheat.gd")
const ModReload = preload("res://engine/server/mod_reload.gd")
const ModValidator = preload("res://engine/server/mod_validator.gd")
const Ugc = preload("res://engine/server/ugc.gd")
const Creations = preload("res://engine/shared/creations.gd")
const Explosions = preload("res://engine/server/explosions.gd")
const Loot = preload("res://engine/server/loot.gd")
const Spawners = preload("res://engine/server/spawners.gd")
const StructureTools = preload("res://engine/server/structure_tools.gd")
const Assembly = preload("res://engine/shared/assembly.gd")

const DEFAULT_MAX_PLAYERS := 64
## world.json "format": 2 = inventories saved by item name (see _migrate_save_format).
const SAVE_FORMAT := 2
## Blocks added after save format 1 (0.35.0-alpha.1), in any mod: format-1 numeric ids are mapped without them.
## Only needed for format-1 worlds; later formats save names.
const FORMAT1_ADDED_BLOCKS := ["base:portal"]
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
const SAVE_BUDGET_USEC := 2000  # serializing per tick during a spread-out save
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
	"pvp": true,  # players can hit each other ("/gameplay pvp false" turns it off)
	"fall_damage": true,
	"natural_regeneration": true,
	"hunger": true,  # survival players get hungry (see engine/server/hunger.gd)
	"starvation_min_health": 1.0,  # starvation stops at this health (0 = players can starve to death)
	"sleeping": true,  # beds let players sleep through the night (they always set the respawn point)
	"sleep_percentage": 100,  # percent of online players who must sleep to skip the night
	"mob_spawning": true,
	"mob_griefing": true,  # explosions caused by mobs break blocks
	"durability": true,  # tools, weapons and armor wear out
	"tray_access": "contributors",  # station trays: "contributors" (plus owner and team) | "anyone"
	"recipe_discovery": true,  # players learn recipes (see RecipeRegistry unlock rules); false = all known
	"minigame_assist": true,  # players may choose relaxed timing for crafting minigames
	"tutorials": true,  # auto-start tutorials for new survival players (see engine/server/tutorials.gd)
	"chat_filter": false,  # mask swear words in chat and refuse such player names (see engine/server/chat_filter.gd)
	"role_tags": true,  # show the player's highest role tag in chat ("[Mod] Name")
}
var server_info := {"name": "VoxelCraft Server", "game": "", "description": "", "motd": "", "mods": []}
var generator: Object = null
## Objects with decorate(chunk, world_seed) run after the generator on worker threads (e.g. ores).
var generation_passes: Array = []
## The engine biome generator once a mod registers biomes (may also be the world generator).
var biome_generator = null
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
var _save_queue := {}  # Vector2i chunk -> true: waiting to be serialized (see _save_all)
var _save_writes: Array = []  # serialized [path, text] waiting for the rest of the save
var _save_meta_pending := false
var _js_mods: Array = []  # keeps JavaScript runtimes alive
## Crafting recipes and categories (sent to clients for the recipe book).
var recipes := RecipeRegistry.new()
## Station tiers, workshop upgrades and multiblock structures.
var stations := Stations.new(self)
## Co-op crafting at stations: presence, shared trays, timed jobs and projects.
var sessions := StationSessions.new(self)
## The experimentation grid (discovering recipes by arranging items).
var experiments := Experiments.new(self)
var skill := SkillCrafting.new(self)
var hunger := Hunger.new(self)
var _mods: Array = []  # loaded GDScript mod instances
var sleep := Sleep.new(self)
## The guidebook: registered pages and what each player has unlocked.
var guide := Guide.new(self)
## Tutorials and contextual tips.
var tutorials := Tutorials.new(self)
## Logs and script errors for mod authors (see engine/server/dev_log.gd).
var dev_log := DevLog.new()
## Profiler, event tracer, inspector and debug drawing (see engine/server/dev_tools.gd).
var dev_tools := DevTools.new(self)
## --dev: every player gets the developer tools (local development).
var dev_mode := false
## The dev dashboard web server (--dev-web=port).
var dev_web := DevWeb.new(self)
var status_query := StatusQuery.new(self)
## Lists the server on a hub (a child node while online; null for offline servers).
var hub: HubAnnouncer
var chat_filter := ChatFilter.new()
var transfers := Transfers.new(self)
var roles := Roles.new(self)
var anticheat := AntiCheat.new(self)
## The game port (0 when offline).
var port := 0
var max_players := DEFAULT_MAX_PLAYERS
## Quick reloads, the file watcher and full reloads (see engine/server/mod_reload.gd).
var mod_reload := ModReload.new(self)
## Player creations: uploads, the server library and serving them (see engine/server/ugc.gd).
var ugc := Ugc.new(self)
## Loaded mods: id -> manifest, in load order, and id -> the running mod (GDScript instance or JsMod).
var mod_manifests := {}
var mod_order: Array = []
var mod_instances := {}
## Emitted by /reload full: the owner (server_main) saves, restarts the server and clients reconnect.
signal full_reload_requested
var explosions := Explosions.new(self)
var loot := Loot.new(self)
var spawners := Spawners.new(self)
var structure_tools := StructureTools.new(self)
## Materials, parts and tools built from parts (see Assembly).
var assembly := Assembly.new()
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
	dev_mode = bool(config.get("dev", false))
	for entry in String(config.get("log_level", "")).split(",", false):
		var parts := entry.strip_edges().split(":")
		dev_log.set_level(parts[0] if parts.size() == 2 else "all", parts[parts.size() - 1])
	dev_log.error_added.connect(_on_dev_error)
	dev_log.error_added.connect(func(e, _first): dev_tools.on_error(e))
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
	dev_log.open_file(_save_dir)
	ugc.load_store(_save_dir)
	if not str(config.get("ugc", "")).is_empty():
		ugc.set_policy({"accept": str(config.ugc), "enabled": str(config.ugc) != "off"})
	_load_meta(int(config.get("seed", -1)))
	world_seed = int(_meta.seed)
	# What the menu's world list shows (mods to host it with, when it was made and last played).
	_meta.mods = Array(config.get("mods", PackedStringArray()))
	if not _meta.has("created_at"):
		_meta.created_at = int(Time.get_unix_time_from_system())
	max_players = int(config.get("max_players", DEFAULT_MAX_PLAYERS))
	_register_builtin_commands()

	var err := _load_mods(config.get("mods", PackedStringArray()), config.get("mod_dirs", PackedStringArray()))
	dev_log.drain()  # script parse errors from loading, so they reach the log file
	if err != OK:
		return err
	_add_part_recipes()
	_migrate_save_format()
	if str(config.get("anticheat", "")) in ["kick", "log", "off"]:
		anticheat.mode = str(config.anticheat)
	chat_filter.load_extra(_save_dir)
	if not str(config.get("default_role", "")).is_empty():
		roles.default_role = str(config.default_role).to_lower()
	roles.migrate(_config_admins)
	if str(config.get("chat_filter", "")) in ["on", "true", "1", "yes"]:
		gameplay.chat_filter = true
	# A private server: only listed players (and admins) may join. Names given here are added to the list.
	if not (_meta.get("allowlist") is Dictionary):
		_meta.allowlist = {"enabled": false, "players": {}}
	for entry in str(config.get("allowlist", "")).split(",", false):
		allowlist_add(entry.strip_edges())
	if not str(config.get("allowlist", "")).is_empty():
		_meta.allowlist.enabled = true
	# The server's own name and message win over what the game mod sets.
	for key in ["name", "motd"]:
		if not str(config.get(key, "")).is_empty():
			server_info[key] = str(config[key]).left(64 if key == "name" else 256)
	if biome_generator != null:
		biome_generator.freeze()
		structure_tools.load_saved()
	spawners.setup()
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
	port = int(config.get("port", 24565))
	status_query.key = tls[0]
	transfers.setup(data_dir, tls[0])
	var query_port := int(config.get("query_port", port + 1))
	if query_port > 0:
		status_query.start(query_port)
	hub = HubAnnouncer.new(self)
	add_child(hub)
	if not str(config.get("hub", "")).is_empty():
		if query_port <= 0:
			dev_log.add("warn", "server", "Hub listing needs status queries (--query-port is 0)")
		else:
			hub.start(str(config.hub), tls[0], str(config.get("public_address", "")), str(config.get("tags", "")).split(",", false))
	var web_port := int(config.get("dev_web", 0))
	if web_port == 0 and dev_mode:
		web_port = int(config.get("port", 24565)) + 15
	if web_port > 0:
		dev_web.start(web_port, str(config.get("dev_web_host", "127.0.0.1")), str(config.get("dev_web_token", "")))
	if dev_mode:
		mod_reload.set_watching(true)
	_started = true
	print("[server] '%s' running game '%s' with mods %s, %d blocks, %d assets, seed %d, port %d" % [
		server_info.name, server_info.game, server_info.mods, registry.defs.size(), _assets.size(), world_seed, config.get("port")])
	return OK


func _exit_tree() -> void:
	dev_web.stop()
	if hub != null:
		hub.leave()
	status_query.stop()
	dev_log.drain()
	dev_log.close()
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
	mod_order = order
	for manifest in order:
		dev_log.add_mod_dir(manifest.id, manifest.dir)
		mod_manifests[manifest.id] = manifest
	for manifest in order:
		if String(manifest.main).get_extension() == "js":
			var js_mod := JsMod.new(self, manifest)
			var js_error := js_mod.load()
			if js_error != OK:
				return js_error
			_js_mods.append(js_mod)
			mod_instances[manifest.id] = js_mod
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
		_mods.append(instance)
		mod_instances[manifest.id] = instance
		server_info.mods.append("%s@%s" % [manifest.id, manifest.version])
		print("[server] Loaded mod %s %s" % [manifest.id, manifest.version])
	# The game is the first requested mod marked as one; add-ons like industry follow it.
	var game: Dictionary = available[requested[requested.size() - 1]]
	for id in requested:
		if available[id].game:
			game = available[id]
			break
	server_info.game = game.name
	server_info.game_id = game.id
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

## `owner`: the mod id (or "engine") the profiler and tracer credit.
func add_handler(event: String, handler: Callable, priority: int, owner := "engine") -> void:
	var list: Array = _handlers.get(event, [])
	list.append([priority, handler, owner])
	list.sort_custom(func(a, b): return a[0] > b[0])
	_handlers[event] = list


func emit(event: String, payload: Dictionary) -> Dictionary:
	var list: Array = _handlers.get(event, [])
	if list.is_empty() and not dev_tools.tracing:
		return payload
	return dev_tools.dispatch(event, list, payload)


## permission: "" (everyone), "admin" (needs the "command.<name>" permission, which admins have) or any
## permission name (see engine/server/roles.gd).
func add_command(command: String, description: String, handler: Callable, mod_id: String, permission := "") -> void:
	_commands[command.to_lower()] = {"name": command.to_lower(), "description": description, "handler": handler, "mod": mod_id, "permission": permission}


## Whether a player may join: always when the allowlist is off; else admins and listed players (by id, or
## by name until that name first joins and binds the entry to the player's identity).
func is_allowed(player_id: String, player_name: String) -> bool:
	var list: Dictionary = _meta.get("allowlist", {})
	if not list.get("enabled", false):
		return true
	if _meta.admins.has(player_id) or _config_admins.has(player_id) or _config_admins.has(player_name.to_lower()) \
			or roles.has(player_id, "admin") or roles.has(player_id, "allowlist.bypass"):
		return true
	var players: Dictionary = list.get("players", {})
	for key: String in players:
		var entry: Dictionary = players[key]
		if entry.get("id", "") == player_id or (str(entry.get("id", "")).is_empty() and key == player_name.to_lower()):
			return true
	return false


## Adds a player by name (or id) to the allowlist.
func allowlist_add(name_or_id: String) -> void:
	if name_or_id.is_empty():
		return
	var players: Dictionary = _meta.allowlist.players
	var key := name_or_id.to_lower()
	if players.has(key):
		return
	var known_id: String = _meta.names.get(key, "")
	players[key] = {"name": name_or_id, "id": known_id if not known_id.is_empty() else (key if key.length() == 32 and key.is_valid_hex_number() else "")}


func allowlist_remove(name_or_id: String) -> bool:
	var players: Dictionary = _meta.allowlist.players
	var key := name_or_id.to_lower()
	for k: String in players.keys():
		if k == key or players[k].get("id", "") == key:
			players.erase(k)
			return true
	return false


## The first time a listed name joins, its entry is tied to that identity (so the name cannot be taken).
func allowlist_bind(player_id: String, player_name: String) -> void:
	var players: Dictionary = _meta.get("allowlist", {}).get("players", {})
	var entry: Dictionary = players.get(player_name.to_lower(), {})
	if not entry.is_empty() and str(entry.get("id", "")).is_empty():
		entry.id = player_id


func is_admin(p) -> bool:
	return has_permission(p, "admin")


func _permitted(p, command: Dictionary) -> bool:
	var permission: String = command.get("permission", "")
	if permission.is_empty():
		return true
	if permission == "admin":
		permission = "command." + str(command.get("name", ""))
	return has_permission(p, permission)


## Whether a player's roles grant a permission (legacy admins and config admins have everything).
func has_permission(p, permission: String) -> bool:
	if p == null:
		return false
	if _meta.admins.has(p.player_id) or _config_admins.has(p.player_id) or _config_admins.has(p.name.to_lower()):
		return true
	return roles.has(p.player_id, permission)


func schedule(seconds: float, callback: Callable, interval: float, owner := "engine") -> int:
	_task_seq += 1
	_tasks[_task_seq] = {"due": _time + maxf(seconds, 0.0), "interval": interval, "callback": callback, "owner": owner}
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
			var t := Time.get_ticks_usec()
			task.callback.call()
			var spent := Time.get_ticks_usec() - t
			dev_tools.record(task.owner, "task", spent)
			if _metrics_interval > 0.0 and spent > _slowest_task[1]:
				_slowest_task = [task.owner, spent]


func _register_builtin_commands() -> void:
	add_command("help", "List commands", _cmd_help, "engine")
	add_command("log", "[mod] [count] | level <mod|all> <debug|info|warn|error> - recent log lines", _cmd_log, "engine", "admin")
	add_command("errors", "[clear [mod] | mute | unmute] - script errors by mod", _cmd_errors, "engine", "admin")
	add_command("validate", "<mod> - check a loaded mod's manifest, files and references", func(player, args):
		if args.is_empty():
			player.send_message("Usage: /validate <mod>   (mods: %s)" % ", ".join(mod_manifests.keys()))
			return
		var result := ModValidator.check_running(self, args[0])
		for line in ModValidator.report(result).slice(-12):
			player.send_message(line), "engine", "admin")
	add_command("ugc", "list [pending|reported|approved|rejected|removed|all] | approve|reject|remove <id> [reason] | trust|untrust <player> | ban|unban <player> [reason] | policy [key value]",
		_cmd_ugc, "engine", "admin")
	add_command("report", "<player> [inappropriate|offensive|copied|spam|other] - report a creation someone is wearing", _cmd_report, "engine")
	add_command("reload", "<mod> | all | full | watch on|off - reload mods while the server runs", _cmd_reload, "engine", "admin")
	add_command("devweb", "- the dev dashboard's address", func(player, _args):
		if dev_web.running():
			player.send_message("Dev dashboard: %s" % dev_web.url())
		else:
			player.send_message("The dev dashboard is off. Start the server with --dev-web=24580 (or --dev)."), "engine", "admin")
	add_command("players", "List online players", _cmd_players, "engine")
	add_command("op", "<player> - grant admin", _cmd_op.bind(true), "engine", "admin")
	add_command("anticheat", "[player | recent | mode kick|log|off] - cheat checks", _cmd_anticheat, "engine", "admin")
	add_command("role", "list | info <role> | give|take <player> <role> | create|delete|allow|deny|tag ... - roles and permissions", _cmd_role, "engine")
	add_command("perms", "[player] - roles and what they allow", _cmd_perms, "engine")
	add_command("network", "[list | id | reload | arrival <id> | arrivals] - servers players can travel to", _cmd_network, "engine", "admin")
	add_command("server", "[name] - list servers you can travel to, or go to one", _cmd_server, "engine")
	add_command("transfer", "<player> <server> [arrival] - send a player to another server", _cmd_transfer, "engine", "admin")
	add_command("portal", "<server> [arrival] - point the nearest portal block at a server", _cmd_portal, "engine", "admin")
	add_command("allow", "[list | add <name> | remove <name> | on | off] - who may join a private server", _cmd_allow, "engine", "admin")
	add_command("deop", "<player> - revoke admin", _cmd_op.bind(false), "engine", "admin")
	add_command("kick", "<player> [reason] - disconnect a player", _cmd_kick, "engine", "admin")
	add_command("whoami", "Show your player id and permissions", _cmd_whoami, "engine")
	add_command("backup", "Back up the world now", _cmd_backup, "engine", "admin")
	add_command("backups", "List world backups", _cmd_backups, "engine", "admin")
	add_command("give", "<item> [count] [player] - give items", _cmd_give, "engine", "admin")
	add_command("tp", "<x> <y> <z> | <player> - teleport", _cmd_tp, "engine", "admin")
	add_command("summon", "<entity> [count] - spawn entities in front of you", _cmd_summon, "engine", "admin")
	add_command("heal", "[player] - restore health", _cmd_heal, "engine", "admin")
	add_command("struct", "pos1 | pos2 | save <name> [keep_air] | place <name> [rotation] | list - build structures", structure_tools.command, "engine", "admin")
	add_command("biome", "- the biome you are standing in", func(player, _args):
		if biome_generator == null:
			player.send_message("This world has no biomes")
		else:
			var biome_name: String = biome_generator.biome_at(floori(player.state.position.x), floori(player.state.position.z))
			player.send_message("Biome: %s" % biome_generator.biomes[biome_generator.biome_ids[biome_name]].display_name), "engine")
	add_command("clearmobs", "[radius] - remove monsters near you", func(player, args):
		var radius := clampf(float(args[0]) if not args.is_empty() and args[0].is_valid_float() else 64.0, 1.0, 512.0)
		var removed := 0
		for e in entities.in_radius(player.state.position, radius):
			if e.def.kind == "mob" and entities.spawning.category_of(e) == "monster":
				e.remove()
				removed += 1
		player.send_message("Removed %d monsters" % removed), "engine", "admin")
	add_command("mobs", "- mobs near you by spawn category, and the caps", func(player, _args):
		var summary: Dictionary = entities.spawning.summary(player.state.position)
		var parts := PackedStringArray()
		for category in summary:
			parts.append("%s %d/%d" % [category, summary[category].near, summary[category].cap])
		player.send_message("Mobs nearby: " + ", ".join(parts)), "engine", "admin")
	add_command("feed", "[player] - restore hunger", func(player, args):
		var target = _target_player(player, args, 0)
		if target != null:
			hunger.set_hunger(target, Hunger.MAX, Hunger.MAX), "engine", "admin")
	add_command("hunger", "<0-20> [player] - set hunger", func(player, args):
		var target = _target_player(player, args, 1)
		if args.is_empty() or not args[0].is_valid_float():
			player.send_message("Usage: /hunger <0-20> [player]")
		elif target != null:
			hunger.set_hunger(target, float(args[0]), 0.0), "engine", "admin")
	add_command("tutorial", "list | start <id> | skip | stop | tips on|off", _cmd_tutorial, "engine")
	add_command("gamemode", "survival | creative [player]", _cmd_gamemode, "engine", "admin")
	add_command("fly", "Toggle flying (creative, or the \"fly\" permission)", _cmd_fly, "engine")
	add_command("kill", "Die and respawn", func(p, _args): kill_player(p, "command", null), "engine")
	add_command("gameplay", "[rule value] - show or change gameplay rules", _cmd_gameplay, "engine", "admin")


# --- Logs and errors ------------------------------------------------------------------------------

func _cmd_log(player, args: PackedStringArray) -> void:
	if args.size() >= 1 and args[0] == "level":
		if args.size() == 3 and dev_log.set_level(args[1], args[2]):
			player.send_message("Log level for %s: %s" % [args[1], args[2]])
		else:
			var parts := PackedStringArray(["default %s" % dev_log.default_level])
			for source in dev_log.levels:
				parts.append("%s %s" % [source, dev_log.levels[source]])
			player.send_message("Usage: /log level <mod|all> <debug|info|warn|error>  (now: %s)" % ", ".join(parts))
		return
	var source := args[0] if args.size() >= 1 and not args[0].is_valid_int() else ""
	var count := int(args[args.size() - 1]) if args.size() >= 1 and args[args.size() - 1].is_valid_int() else 10
	for e in dev_log.recent(clampi(count, 1, 50), source):
		player.send_message("%s[%s] %s" % ["" if e.level == "info" else e.level.to_upper() + " ", e.source, e.message.left(300)])


func _cmd_errors(player, args: PackedStringArray) -> void:
	match args[0] if args.size() > 0 else "":
		"clear":
			dev_log.clear_errors(args[1] if args.size() > 1 else "")
			player.send_message("Errors cleared")
		"mute", "unmute":
			player.data["dev_alerts_muted"] = args[0] == "mute"
			player.send_message("Error alerts %s" % ("muted" if args[0] == "mute" else "on"))
		_:
			var list := dev_log.sorted_errors()
			if list.is_empty():
				player.send_message("No script errors")
			for e in list.slice(0, 10):
				player.send_message("[%s] x%d %s%s" % [e.source, e.count, e.message.left(200), " (%s:%d)" % [e.file.get_file(), e.line] if not e.file.is_empty() else ""])


func _cmd_reload(player, args: PackedStringArray) -> void:
	var what := args[0] if args.size() > 0 else ""
	match what:
		"":
			player.send_message("Usage: /reload <mod> | all | full | watch on|off   (mods: %s)" % ", ".join(mod_manifests.keys()))
		"full":
			request_full_reload()
		"watch":
			mod_reload.set_watching(args.size() < 2 or args[1] != "off")
			player.send_message("File watcher %s" % ("on: saving a mod's scripts reloads it" if mod_reload.watching else "off"))
		"all":
			for result in mod_reload.reload_all():
				player.send_message(ModReload._summary(result))
		_:
			player.send_message(ModReload._summary(mod_reload.reload(what)))


## After a quick reload: clients get the new definitions, recipe book, guide and tutorials.
func after_mod_reload() -> void:
	tutorials.revalidate()
	var content := {"blocks": registry.to_network(), "items": items.to_network(), "entities": entities.registry.to_network(),
		"recipes": recipes.to_network(), "processes": _processes, "stations": stations.to_network(), "assembly": assembly.to_network(),
		"minigames": skill.to_network(), "guide": guide.registry.to_network(), "tutorials": tutorials.to_network()}
	for p: ServerPlayer in players.values():
		if p._online():
			Net.s_content_update.rpc_id(p.peer_id, content)
			open_crafting_refresh(p)
		guide.sync(p)


## Refreshes a player's open crafting screen (the recipe book may have changed).
func open_crafting_refresh(p: ServerPlayer) -> void:
	Net.s_known_recipes.rpc_id(p.peer_id, PackedStringArray(p.known_recipes.keys()), gameplay.recipe_discovery)


## Messages for admins only (moderation).
func tell_moderators(text: String) -> void:
	dev_log.add("info", "server", text)
	for p: ServerPlayer in players.values():
		if has_permission(p, "moderation.alerts"):
			p.send_message(text)


func tell_admins(text: String) -> void:
	dev_log.add("info", "server", text)
	for p: ServerPlayer in players.values():
		if dev_tools.allowed(p):
			p.send_message(text)


## Saves and asks the owner to restart the server with the same settings; clients are told to reconnect.
func request_full_reload() -> void:
	if not full_reload_requested.get_connections().size():
		tell_admins("Full reload needs the dedicated server (or the Host menu); restart the server instead")
		return
	for p: ServerPlayer in players.values():
		if p._online():
			Net.s_reloading.rpc_id(p.peer_id, "Reloading mods…")
	dev_log.add("info", "server", "Full reload: saving and restarting")
	_save_all(true)
	full_reload_requested.emit()


## New and repeating errors go to online admins (unless they muted alerts).
func _on_dev_error(e: Dictionary, first: bool) -> void:
	if not _started:
		return
	var alert := {"id": e.id, "source": e.source, "level": e.level, "message": e.message.left(300), "file": e.file.get_file(),
		"line": e.line, "count": e.count, "first": first}
	for p: ServerPlayer in players.values():
		if is_admin(p) and not p.data.get("dev_alerts_muted", false):
			Net.s_dev_error.rpc_id(p.peer_id, alert)


## Brings an older world save up to SAVE_FORMAT (after mods registered their blocks and items, before anyone
## joins), backing the world up first. Format 1 (0.35.0-alpha.1 and earlier) kept inventories as numeric ids,
## which shift whenever a block is added: they are turned into names using that version's block order.
func _migrate_save_format() -> void:
	var format := int(_meta.get("format", 1))
	if format >= SAVE_FORMAT:
		return
	if not _meta.players.is_empty() and not _save_dir.is_empty() and not _backup_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_backup_dir)
		var backup := _backup_dir.path_join("%s-before-format%d-%s%s" % [_save_dir.get_file(), SAVE_FORMAT, WorldBackups.timestamp(), WorldBackups.EXTENSION])
		var error := WorldBackups.create(_save_dir, backup)
		dev_log.add("info" if error.is_empty() else "error", "server", "Backed up the world before upgrading its save format: %s" % (backup if error.is_empty() else error))
	var old_names := _format1_block_names()
	var migrated := 0
	for id: String in _meta.players:
		var record = _meta.players[id]
		if not (record is Dictionary) or record.has("items"):
			continue
		record.items = _format1_items(record, old_names)
		for key in ["inventory", "item_data", "equipment"]:
			record.erase(key)
		migrated += 1
	_meta.format = SAVE_FORMAT
	if migrated > 0:
		dev_log.add("info", "server", "Upgraded %d players' inventories to the name-based save format" % migrated)


## Block names in the order format-1 saves numbered them: today's order without blocks added since.
func _format1_block_names() -> Array:
	var names := []
	for d in registry.defs:
		if not FORMAT1_ADDED_BLOCKS.has(str(d.name)):
			names.append(str(d.name))
	return names


## A format-1 player record's numeric inventory as save_items() form.
func _format1_items(record: Dictionary, old_block_names: Array) -> Dictionary:
	var to_name := func(id: int) -> String:
		if id <= 0:
			return ""
		if items.is_block_item(id):
			return old_block_names[id] if id < old_block_names.size() else ""
		return items.name_of(id) if items.is_valid(id) else ""  # non-block items did not move
	var slots := []
	var packed = record.get("inventory", [])
	var item_data: Dictionary = record.get("item_data", {}) if record.get("item_data") is Dictionary else {}
	if packed is Array and packed.size() >= Inventory.SIZE * 2:
		for i in Inventory.SIZE:
			var item_name: String = to_name.call(int(packed[i]))
			if not item_name.is_empty() and int(packed[Inventory.SIZE + i]) > 0:
				slots.append([i, item_name, int(packed[Inventory.SIZE + i]), item_data.get(str(i), {})])
	var equipment := {}
	var worn = record.get("equipment", {})
	if worn is Dictionary:
		for slot_name in worn:
			var e = worn[slot_name]
			if e is Array and e.size() == 3:
				var item_name: String = to_name.call(int(e[0]))
				if not item_name.is_empty():
					equipment[str(slot_name)] = [item_name, int(e[1]), e[2] if e[2] is Dictionary else {}]
	return {"slots": slots, "equipment": equipment}


## Checks a permission; tells the player (at most every few seconds) when it is missing.
func _may(p: ServerPlayer, permission: String, message: String) -> bool:
	if has_permission(p, permission):
		return true
	var now := Time.get_ticks_msec()
	if now - int(p.get_meta("denied_at", -10000)) > 3000:
		p.set_meta("denied_at", now)
		p.send_message(message)
	return false


func _cmd_role(player, args: PackedStringArray) -> void:
	var action := args[0] if args.size() > 0 else "list"
	var a1 := args[1].to_lower() if args.size() > 1 else ""
	var a2 := args[2].to_lower() if args.size() > 2 else ""
	var manage := has_permission(player, "roles.manage")
	var edit := has_permission(player, "roles.owner")
	match action:
		"list":
			for r in roles.role_names():
				var def := roles.role(r)
				player.send_message("%s%s  (priority %d%s)" % [r, " [%s]" % def.tag if not str(def.tag).is_empty() else "", def.priority,
					", inherits %s" % def.inherits if not str(def.inherits).is_empty() else ""])
			player.send_message("New players get: %s" % roles.default_role)
		"info":
			if not roles.exists(a1):
				player.send_message("No role called '%s'" % a1)
				return
			var def := roles.role(a1)
			player.send_message("%s: %s%s" % [a1, ", ".join(def.permissions) if not def.permissions.is_empty() else "no permissions of its own",
				" + everything %s has" % def.inherits if not str(def.inherits).is_empty() else ""])
		"give", "take":
			if not manage:
				player.send_message("You don't have permission to manage roles")
				return
			var id := _player_id_for(a1)
			if id.is_empty() or not roles.exists(a2):
				player.send_message("Usage: /role %s <player> <role> (known players and roles only)" % action)
				return
			if (a2 == "owner" or roles.role(a2).priority >= roles.rank(player.player_id)) and not edit:
				player.send_message("You can only %s roles below your own" % action)
				return
			var changed := roles.give(id, a2) if action == "give" else roles.take(id, a2)
			if changed:
				emit("role_changed", {"player_id": id, "role": a2, "added": action == "give", "by": player.name})
				if action == "give":
					broadcast_chat("%s gave %s the %s role" % [player.name, _name_for(id), a2])
				else:
					player.send_message("%s no longer has the %s role" % [_name_for(id), a2])
				_save_all()
			else:
				player.send_message("Nothing changed (%s %s the %s role)" % [_name_for(id), "already has" if action == "give" else "does not have", a2])
		"create", "delete", "allow", "deny", "remove", "reset", "tag":
			if not edit:
				player.send_message("Only owners can change roles")
				return
			var error := ""
			match action:
				"create": error = roles.create(a1, a2 if not a2.is_empty() else "member")
				"delete": error = roles.delete(a1)
				"allow": error = roles.set_permission(a1, a2)
				"deny": error = roles.set_permission(a1, "-" + a2.trim_prefix("-"))
				"remove": error = roles.set_permission(a1, a2, true)
				"reset": roles.reset(a1)
				"tag":
					if not roles.exists(a1):
						error = "no role called %s" % a1
					else:
						roles.set_look(a1, args[2] if args.size() > 2 else "", args[3] if args.size() > 3 else "")
			player.send_message(error if not error.is_empty() else "Done: /role info %s" % a1)
			if error.is_empty():
				_save_all()
		_:
			player.send_message("Usage: /role list | info <role> | give|take <player> <role> | create <role> [inherits] | delete <role> | allow|deny|remove <role> <permission> | tag <role> <tag> [#color] | reset <role>")


func _cmd_anticheat(player, args: PackedStringArray) -> void:
	var action := args[0] if args.size() > 0 else "recent"
	if action == "mode":
		if args.size() > 1 and args[1] in ["kick", "log", "off"]:
			anticheat.mode = args[1]
		player.send_message("Anti-cheat mode: %s (kick: kick at high scores; log: only tell moderators; off)" % anticheat.mode)
		return
	var target = _find_online(action) if action != "recent" else null
	if target != null:
		var scores := []
		for check: String in AntiCheat.CHECKS:
			if anticheat.score(target, check) > 0.0:
				scores.append("%s %.1f/%d" % [check, anticheat.score(target, check), int(AntiCheat.CHECKS[check].kick)])
		player.send_message("%s: %s" % [target.name, ", ".join(scores) if not scores.is_empty() else "nothing suspicious"])
		return
	var recent := anticheat.recent()
	player.send_message("Anti-cheat (%s): %s" % [anticheat.mode, "no flags" if recent.is_empty() else "%d recent flags" % recent.size()])
	for r in recent.slice(0, 8):
		player.send_message("  %s %s %s (%s, score %.0f) %s" % [Time.get_datetime_string_from_unix_time(r.time).substr(11), r.player, r.action, r.check, r.score, r.detail])


func _cmd_perms(player, args: PackedStringArray) -> void:
	var id: String = player.player_id if args.is_empty() else _player_id_for(args[0])
	if id.is_empty():
		player.send_message("No known player called '%s'" % args[0])
		return
	var entries := roles.entries_of(id)
	player.send_message("%s: roles %s" % [_name_for(id), ", ".join(roles.roles_of(id))])
	var checks := ["build", "interact", "chat", "creative", "ugc.review", "allowlist.manage", "roles.manage", "admin"]
	player.send_message("can: %s" % ", ".join(checks.filter(func(c): return Roles.allows(entries, c))))


func _player_id_for(player_name: String) -> String:
	var online = _find_online(player_name)
	if online != null:
		return online.player_id
	return str(_meta.names.get(player_name.to_lower(), ""))


func _name_for(player_id: String) -> String:
	for p: ServerPlayer in players.values():
		if p.player_id == player_id:
			return p.name
	for n: String in _meta.names:
		if _meta.names[n] == player_id:
			return n
	return player_id.left(8)


func _cmd_help(player, _args: PackedStringArray) -> void:
	var names := _commands.keys()
	names.sort()
	for n in names:
		if _permitted(player, _commands[n]):
			player.send_message("/%s - %s" % [n, _commands[n].description])


func _cmd_op(player, args: PackedStringArray, grant: bool) -> void:
	_cmd_role(player, PackedStringArray(["give" if grant else "take", args[0] if args.size() > 0 else "", "admin"]))
	if not grant and args.size() > 0:
		var target = _find_online(args[0])
		if target != null:
			_meta.admins.erase(target.player_id)  # the old admin list


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


## Starts or stops flight for a player, telling their client. Returns false when they may not fly.
func set_flying(p: ServerPlayer, enabled: bool) -> bool:
	if enabled and not may_fly(p):
		return false
	if p.state.flying == enabled:
		return true
	p.state.flying = enabled
	if not enabled:
		p.state.velocity.y = minf(p.state.velocity.y, 0.0)
	if p._online():
		Net.s_flying.rpc_id(p.peer_id, enabled)
	return true


## Creative players fly; anyone else needs the "fly" permission.
func may_fly(p: ServerPlayer) -> bool:
	return p.inventory.creative or has_permission(p, "fly")


func on_set_flying(peer_id: int, enabled: bool) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.dead:
		return
	if not set_flying(p, enabled):
		p.send_message("Flying is not allowed for you here (creative mode, or ask an admin for the \"fly\" permission)")


func _cmd_fly(player, _args: PackedStringArray) -> void:
	if not set_flying(player, not player.state.flying):
		player.send_message("Flying is not allowed for you here (creative mode, or ask an admin for the \"fly\" permission)")
		return
	player.send_message("Flying: %s (double-tap jump in game; jump rises, crouch sinks)" % ("on" if player.state.flying else "off"))


func _cmd_gamemode(player, args: PackedStringArray) -> void:
	if args.is_empty() or not args[0] in ["survival", "creative"]:
		player.send_message("Usage: /gamemode survival | creative [player]")
		return
	var target = _target_player(player, args, 1)
	if target == null:
		return
	target.set_creative(args[0] == "creative")
	target.send_message("Game mode: %s" % args[0])


func _cmd_network(player, args: PackedStringArray) -> void:
	match args[0] if args.size() > 0 else "list":
		"id":
			player.send_message("This server's id: %s (other servers put it in their network.json)" % transfers.own_id)
		"reload":
			var problem := transfers.reload()
			player.send_message(problem if not problem.is_empty() else "Network reloaded: %d servers" % transfers.servers.size())
		"arrival":
			if args.size() < 2:
				player.send_message("Usage: /network arrival <id> (sets it where you stand)")
				return
			transfers.set_arrival(args[1], player.state.position)
			player.send_message("Arrival point '%s' set here" % args[1].to_lower())
			_save_all()
		"arrivals":
			var points: Dictionary = _meta.get("arrivals", {}) if _meta.get("arrivals") is Dictionary else {}
			player.send_message("Arrival points: %s" % (", ".join(points.keys()) if not points.is_empty() else "none (/network arrival <id>)"))
		_:
			player.send_message("This server's id: %s" % transfers.own_id)
			if transfers.servers.is_empty():
				player.send_message("No other servers: add them to network.json in the data folder, then /network reload")
			for e: Dictionary in transfers.servers.values():
				player.send_message("%s (%s) %s:%d%s%s%s" % [e.key, e.name, e.address, e.port, "" if e.send else "  no travel there",
					"" if e.receive else "  no arrivals", "  carries inventories" if e.inventory else ""])


func _cmd_server(player, args: PackedStringArray) -> void:
	var allowed: Array = transfers.servers.values().filter(func(e): return e.send and (e.hop or has_permission(player, "command.transfer")))
	if args.is_empty():
		player.send_message("Servers you can go to: %s" % (", ".join(allowed.map(func(e): return "%s (%s)" % [e.key, e.name])) if not allowed.is_empty() else "none"))
		return
	var entry := transfers.find(args[0])
	if entry.is_empty() or not allowed.has(entry):
		player.send_message("You cannot travel to '%s' from here" % args[0])
		return
	var error := transfers.transfer(player, entry.key)
	if not error.is_empty():
		player.send_message(error)


func _cmd_transfer(player, args: PackedStringArray) -> void:
	if args.size() < 2:
		player.send_message("Usage: /transfer <player> <server> [arrival]")
		return
	var target = _find_online(args[0])
	if target == null:
		player.send_message("No player named '%s' online" % args[0])
		return
	var error := transfers.transfer(target, args[1], {"arrival": args[2] if args.size() > 2 else ""})
	player.send_message(error if not error.is_empty() else "Sending %s to %s" % [target.name, args[1]])


func _cmd_portal(player, args: PackedStringArray) -> void:
	if args.is_empty():
		player.send_message("Usage: /portal <server> [arrival] (stand next to a portal block)")
		return
	var best := Vector3i(0, -9999, 0)
	var best_d := INF
	var center := Vector3i(player.state.position.floor())
	for x in range(-4, 5):
		for y in range(-2, 4):
			for z in range(-4, 5):
				var cell := center + Vector3i(x, y, z)
				var block := world.get_block_v(cell)
				if registry.is_valid(block) and bool(registry.defs[block].get("portal", false)):
					var d := Vector3(cell).distance_to(player.state.position)
					if d < best_d:
						best_d = d
						best = cell
	if best.y == -9999:
		player.send_message("No portal block within 4 blocks (place base:portal first)")
		return
	if transfers.find(args[0]).is_empty():
		player.send_message("Note: '%s' is not in this server's network.json yet" % args[0])
	# Every portal block touching this one gets the same settings (a portal is usually a whole frame).
	var settings := {"server": args[0].to_lower(), "arrival": args[1].to_lower() if args.size() > 1 else ""}
	var todo: Array[Vector3i] = [best]
	var done := {}
	while not todo.is_empty() and done.size() < 64:
		var cell: Vector3i = todo.pop_back()
		if done.has(cell):
			continue
		done[cell] = true
		var data := get_block_data(cell).duplicate()
		data.portal = settings
		set_block_data(cell, data)
		for d in [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var next: Vector3i = cell + d
			var b := world.get_block_v(next)
			if not done.has(next) and registry.is_valid(b) and bool(registry.defs[b].get("portal", false)):
				todo.append(next)
	player.send_message("Portal (%d blocks) now leads to %s%s" % [done.size(), args[0], " at '%s'" % settings.arrival if not settings.arrival.is_empty() else ""])


func _cmd_allow(player, args: PackedStringArray) -> void:
	var list: Dictionary = _meta.allowlist
	var action := args[0] if args.size() > 0 else "list"
	var target := " ".join(args.slice(1)).strip_edges()
	match action:
		"on", "off":
			list.enabled = action == "on"
			if list.enabled:
				for p: ServerPlayer in players.values():
					allowlist_add(p.name)  # everyone here now stays welcome
					allowlist_bind(p.player_id, p.name)
			player.send_message("The allowlist is %s%s" % [action, " (everyone online was added)" if list.enabled else ""])
		"add":
			if target.is_empty():
				player.send_message("Usage: /allow add <name>")
				return
			allowlist_add(target)
			player.send_message("%s may join%s" % [target, "" if list.enabled else " (the allowlist is off: /allow on)"])
		"remove":
			player.send_message(("%s removed from the allowlist" if allowlist_remove(target) else "%s is not on the allowlist") % target)
		_:
			var names: Array = list.players.values().map(func(e): return str(e.name) + ("" if not str(e.id).is_empty() else " (not joined yet)"))
			player.send_message("Allowlist %s: %s" % ["on" if list.enabled else "off", ", ".join(names) if not names.is_empty() else "empty"])
	_save_all()


func _cmd_gameplay(player, args: PackedStringArray) -> void:
	if args.size() < 2:
		for key in gameplay:
			player.send_message("%s = %s" % [key, gameplay[key]])
		return
	if not gameplay.has(args[0]):
		player.send_message("Unknown rule '%s'" % args[0])
		return
	var value = args[1] if gameplay[args[0]] is String else args[1] in ["true", "on", "1", "yes"]
	if gameplay[args[0]] is int or gameplay[args[0]] is float:
		value = args[1].to_float()
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
		elif gameplay[key] is int:
			gameplay[key] = int(values[key])
		elif gameplay[key] is float:
			gameplay[key] = float(values[key])
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
	dev_log.drain()
	_time += delta
	_stream_assets()
	_poll_chunk_jobs()
	var t_jobs := Time.get_ticks_usec()
	_advance_time(delta)
	block_ticks.update(delta)
	var t_blocks := Time.get_ticks_usec()
	containers.update(delta)
	transfers.update(delta)
	anticheat.update(delta)
	sessions.update(delta)
	skill.update()
	sleep.update(delta)
	guide.update(delta)
	dev_tools.update(delta)
	dev_web.update(delta)
	status_query.update()
	mod_reload.update(delta)
	ugc.update(delta)
	tutorials.update(delta)
	var t_systems := Time.get_ticks_usec()
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
	var te := Time.get_ticks_usec()
	entities.tick(delta)
	for p: ServerPlayer in players.values():
		_update_health(p, delta)
	var t1 := Time.get_ticks_usec()
	dev_tools.record("engine", "tick:entities and AI", t1 - te)
	dev_tools.record("engine", "tick:players", sim_usec)
	dev_tools.record("engine", "tick:chunk streaming", stream_usec)
	_run_tasks()
	emit("tick", {"delta": delta, "tick": tick})
	var t2 := Time.get_ticks_usec()
	var t_snap := t2

	if tick % SNAPSHOT_INTERVAL_TICKS == 0 and not players.is_empty():
		_send_snapshots()
		t_snap = Time.get_ticks_usec()
		entities.replicate(players.values())
	var t3 := Time.get_ticks_usec()
	dev_tools.record("engine", "tick:snapshots", t3 - t2)
	dev_tools.record("engine", "tick:whole server tick", t3 - t0)

	_poll_backup(delta)
	_save_timer += delta
	if _save_timer >= SAVE_INTERVAL:
		_save_timer = 0.0
		_save_all()
	else:
		_drain_save_queue(SAVE_BUDGET_USEC)
	var t4 := Time.get_ticks_usec()
	_unload_timer += delta
	if _unload_timer >= WORLD_UNLOAD_INTERVAL:
		_unload_timer = 0.0
		_unload_unused_chunks()
	var t5 := Time.get_ticks_usec()
	if _metrics_interval > 0.0:
		var sections := {"chunk jobs": t_jobs - t0, "block ticks": t_blocks - t_jobs, "systems": t_systems - t_blocks, "players": sim_usec, "streaming": stream_usec, "entities": t1 - te,
			"tasks+mods": t2 - t1, "snapshots": t_snap - t2, "entity replication": t3 - t_snap, "saving": t4 - t3, "unloading": t5 - t4}
		for key: String in entities.last_sections:
			sections["mob " + key] = entities.last_sections[key]
		_record_metrics(delta, t5 - t0, sections)


## Tick timings by section, printed every --metrics seconds: averages, and the slowest tick's breakdown.
var _slowest_task: Array = ["-", 0]  # [owner, usec] this metrics interval


func _record_metrics(delta: float, total: int, sections: Dictionary) -> void:
	var m := _metrics
	if m.is_empty():
		m.merge({"elapsed": 0.0, "ticks": 0, "total": 0, "max": 0, "max_sections": {}, "sections": {}, "gen": 0, "gen_usec": 0, "slow": 0,
			"wall": Time.get_ticks_msec()})
	m.elapsed += delta
	m.ticks += 1
	m.total += total
	if total > int(1000000.0 / Engine.physics_ticks_per_second):
		m.slow += 1
	if total > m.max:
		m.max = total
		m.max_sections = sections
	for key: String in sections:
		m.sections[key] = int(m.sections.get(key, 0)) + int(sections[key])
	if m.elapsed < _metrics_interval:
		return
	var sent := 0
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer and peer.host:
		sent = int(peer.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
	var n := float(m.ticks)
	var average := PackedStringArray()
	for key: String in m.sections:
		average.append("%s %.2f" % [key, m.sections[key] / n / 1000.0])
	var worst := PackedStringArray()
	var keys: Array = m.max_sections.keys()
	keys.sort_custom(func(a, b): return m.max_sections[a] > m.max_sections[b])
	for key: String in keys.slice(0, 3):
		worst.append("%s %.1f" % [key, m.max_sections[key] / 1000.0])
	print("[metrics] players %d  mobs %d  chunks %d  ticks %d/s (%d over budget)  tick avg %.2f ms  [%s]  max %.1f ms [%s]  slowest task %s %.1f ms  gens %d (%.1f ms each)  out %.1f KB/s (%.1f per player)" % [
		players.size(), entities.entities.size(), world.chunks.size(), roundi(n / maxf((Time.get_ticks_msec() - m.wall) / 1000.0, 0.001)), m.slow, m.total / n / 1000.0, ", ".join(average), m.max / 1000.0, ", ".join(worst), _slowest_task[0], _slowest_task[1] / 1000.0,
		m.gen, (m.gen_usec / maxf(m.gen, 1.0)) / 1000.0, sent / m.elapsed / 1024.0, sent / m.elapsed / 1024.0 / maxf(players.size(), 1)])
	_metrics = {}
	_slowest_task = ["-", 0]


func _simulate_player(p: ServerPlayer) -> void:
	if p.dead:
		# Dead players do not move; acknowledge inputs so the client's prediction queue drains.
		if not p.input_queue.is_empty():
			p.last_processed_seq = p.input_queue.back().seq
			p.input_queue.clear()
		return
	# Normally one input per tick; consume two when the client is ahead to drain jitter backlog.
	if not p.sleeping.is_empty():
		# Sleepers stay in bed; moving or jumping gets them up.
		var getting_up := false
		for input in p.input_queue:
			getting_up = getting_up or input.jump or input.move.length() > 0.2
		if not p.input_queue.is_empty():
			p.last_processed_seq = p.input_queue.back().seq
			p.input_queue.clear()
		if getting_up:
			sleep.wake(p, "moved")
		return
	# Inputs cannot run faster than real time: steps are paid from a credit that grows with the wall clock (60
	# per second, 5% extra for clock drift), with a burst for inputs that arrive in a clump after jitter or a slow
	# server tick. A client sending sped-up inputs just builds a queue instead of moving faster (and the timer
	# check in AntiCheat notices its input rate).
	var now := anticheat.now_usec()
	if p.credit_usec > 0:
		p.input_credit = minf(p.input_credit + (now - p.credit_usec) / 1000000.0 * Engine.physics_ticks_per_second * AntiCheat.INPUT_RATE,
			AntiCheat.INPUT_BURST)
	p.credit_usec = now
	var budget := mini(3, floori(p.input_credit)) if not p.input_queue.is_empty() else 0
	var start := p.state.position
	var was_on_ground := p.state.on_ground
	var steps := 0
	while budget > 0 and not p.input_queue.is_empty():
		var input = p.input_queue.pop_front()
		var falling_speed := -p.state.velocity.y
		PlayerPhysics.step(p.state, input, world, p.physics_rules if p.physics_rules != null else rules)
		p.last_processed_seq = input.seq
		budget -= 1
		p.input_credit -= 1.0
		steps += 1
		_track_fall(p, falling_speed)
	var tick_time := 1.0 / Engine.physics_ticks_per_second
	hunger.update(p, tick_time, p.state.position - start, steps * tick_time, was_on_ground)
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
	_contact_damage(p, delta)
	if p.state.position.y < VOID_DAMAGE_Y:
		p.void_timer += delta
		if p.void_timer >= 0.5:
			p.void_timer = 0.0
			damage_player(p, 4.0, "void", null, Vector3.ZERO, true)
	var regen_interval := hunger.regen_interval(p, REGEN_INTERVAL)
	if gameplay.natural_regeneration and regen_interval > 0.0 and p.health < p.max_health and _time - p.last_damage_time > REGEN_DELAY:
		p.regen_timer += delta
		if p.regen_timer >= regen_interval:
			p.regen_timer = 0.0
			heal_player(p, 1.0)
			hunger.healed(p, 1.0)


## Blocks with `contact_damage: {amount, interval, cause}` (lava) hurt a player standing or swimming in them.
func _contact_damage(p: ServerPlayer, delta: float) -> void:
	var worst := {}
	for dy in [0.2, 1.2]:
		var block := world.get_block(floori(p.state.position.x), floori(p.state.position.y + dy), floori(p.state.position.z))
		if registry.is_valid(block) and registry.defs[block].get("contact_damage") is Dictionary:
			worst = registry.defs[block].contact_damage
	if worst.is_empty():
		p.contact_timer = 0.0
		return
	p.contact_timer += delta
	if p.contact_timer >= float(worst.get("interval", 0.5)):
		p.contact_timer = 0.0
		damage_player(p, float(worst.get("amount", 2.0)), str(worst.get("cause", "contact")), null, Vector3.ZERO, true, 0.0)


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
	if cause != "starvation":
		hunger.add_exhaustion(p, Hunger.DAMAGED)
	entities.taming.owner_hurt(p, attacker)
	sleep.wake(p, "hurt")
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
	var messages := {"fall": "%s fell from a high place", "void": "%s fell out of the world", "starvation": "%s starved to death",
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
		spawn = sleep.respawn_position(p)
	if spawn == Vector3.INF:
		spawn = spawn_handler.call(p) if spawn_handler.is_valid() else _default_spawn()
	var ev := emit("player_respawn", {"player": p, "position": spawn})
	p.dead = false
	p.health = p.max_health
	p.exhaustion = 0.0
	hunger.set_hunger(p, Hunger.MAX, 5.0)
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


## Other players per snapshot (20 bytes each), nearest first, so a crowd stays under the network MTU.
const SNAPSHOT_MAX_PLAYERS := 64

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
	var picked := []  # [dist_sq, player]
	for other: ServerPlayer in players.values():
		if other == p:
			continue
		var dist_sq: float = other.state.position.distance_squared_to(s.position)
		if dist_sq > radius_sq or (dist_sq > near_sq and not full_rate):
			continue
		picked.append([dist_sq, other])
	if picked.size() > SNAPSHOT_MAX_PLAYERS:
		picked.sort_custom(func(x, y): return x[0] < y[0])
		picked.resize(SNAPSHOT_MAX_PLAYERS)
	for entry in picked:
		var other: ServerPlayer = entry[1]
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
		if p._online():
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
	if gameplay.chat_filter and not chat_filter.is_clean(clean_name):
		kick(peer_id, "Please choose a different name")
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
	if j.has("ticket"):
		var accepted := transfers.accept(j.ticket[0], j.ticket[1], j.player_id)
		j.erase("ticket")
		if accepted.has("error"):
			j.transfer_error = accepted.error
			dev_log.add("warn", "server", "%s arrived with a transfer ticket that was refused: %s" % [j.name, accepted.error])
		else:
			j.transfer = accepted
	if not (j.has("transfer") and j.transfer.entry.admit) and not is_allowed(j.player_id, j.name):
		_joining.erase(peer_id)
		dev_log.add("info", "server", "%s (%s) is not on the allowlist" % [j.name, j.player_id])
		kick(peer_id, "This server is private. Ask an admin to add you: /allow add %s" % j.name)
		return
	j.authenticated = true
	_meta.names[String(j.name).to_lower()] = j.player_id
	if _config_admins.has(String(j.name).to_lower()) or _config_admins.has(j.player_id):
		roles.give(j.player_id, "owner")  # --admins names become owners once they have joined
	allowlist_bind(j.player_id, j.name)
	var manifest := []
	for asset_name: String in _assets:
		var a: Dictionary = _assets[asset_name]
		if a.has("hash"):
			manifest.append([asset_name, a.hash, a.size])
	var content := {"blocks": registry.to_network(), "items": items.to_network(), "rules": rules.to_dict(),
		"entities": entities.registry.to_network(), "sounds": sounds.to_network(),
		"equipment_slots": items.slots.duplicate(true), "stats": items.stats.duplicate(),
		"player_rig": player_rig, "cosmetics": cosmetics.to_network(), "effects": effects.to_network(), "recipes": recipes.to_network(), "processes": _processes,
		"stations": stations.to_network(), "assembly": assembly.to_network(), "minigames": skill.to_network(), "guide": guide.registry.to_network(), "tutorials": tutorials.to_network()}
	Net.s_server_info.rpc_id(peer_id, server_info, content, manifest)


func on_transfer_ticket(peer_id: int, ticket: String, signature: String) -> void:
	var j: Dictionary = _joining.get(peer_id, {})
	if not j.is_empty() and not j.authenticated and not j.has("ticket"):
		j.ticket = [ticket.left(Transfers.TransferTicket.MAX_SIZE), signature.left(2048)]


## The local host proves it launched this server and becomes a permanent admin.
func on_claim_admin(peer_id: int, token: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or _admin_token.is_empty() or token != _admin_token:
		return
	roles.give(p.player_id, "owner")
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
	_spawn_player(peer_id, j.name, j.player_id, j.get("avatar", {}), j.get("transfer", {}))
	if j.has("transfer_error") and players.has(peer_id):
		players[peer_id].send_message("You arrived, but your trip could not be honoured: %s" % j.transfer_error)


func _spawn_player(peer_id: int, player_name: String, player_id: String, avatar = {}, transfer := {}) -> void:
	var p := ServerPlayer.new(self, peer_id, player_name)
	p.player_id = player_id
	p.edit_tokens = EDITS_PER_SECOND
	var saved = _meta.players.get(player_id)
	var first_time := not (saved is Dictionary)
	if not first_time:
		var pos = saved.get("position")
		if pos is Array and pos.size() == 3:
			p.state.position = Vector3(pos[0], pos[1], pos[2])
		if saved.has("items"):
			p.load_items(saved.items)
		else:
			p.load_inventory(saved)  # a record still in the numeric form (migrated at start; kept as a fallback)
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
		p.hunger = clampf(float(saved.get("hunger", Hunger.MAX)), 0.0, Hunger.MAX)
		p.saturation = clampf(float(saved.get("saturation", 5.0)), 0.0, p.hunger)
		p.exhaustion = clampf(float(saved.get("exhaustion", 0.0)), 0.0, Hunger.EXHAUSTION_PER_POINT)
		if saved.get("spawn_bed") is Array and saved.spawn_bed.size() == 3:
			p.spawn_bed = Vector3i(int(saved.spawn_bed[0]), int(saved.spawn_bed[1]), int(saved.spawn_bed[2]))
		guide.load_player(p, saved.get("guide"))
		tutorials.load_player(p, saved.get("tutorial"))
		var spawn_point = saved.get("spawn_point")
		if spawn_point is Array and spawn_point.size() == 3:
			p.spawn_point = Vector3(spawn_point[0], spawn_point[1], spawn_point[2])
	players[peer_id] = p
	if first_time:
		p.state.position = spawn_handler.call(p) if spawn_handler.is_valid() else _default_spawn()
	if not transfer.is_empty() and transfers.arrival_position(transfer) != Vector3.INF:
		p.state.position = transfers.arrival_position(transfer)
	ensure_area_loaded(p.state.position)

	Net.s_welcome.rpc_id(peer_id, peer_id, p.state.position, 0.0)
	_set_client_avatar(p, avatar, true)
	Net.s_cosmetics.rpc_id(peer_id, PackedStringArray(p.owned_cosmetics.keys()), cosmetics.policy)
	Net.s_known_recipes.rpc_id(peer_id, PackedStringArray(p.known_recipes.keys()), gameplay.recipe_discovery)
	Net.s_time.rpc_id(peer_id, _time_of_day, _day_length)
	p.sync_inventory()
	refresh_stats(p)
	sync_health(p)
	hunger.set_hunger(p, p.hunger)  # applies the no-sprint modifier when starving
	hunger.sync(p, true)
	guide.sync(p)
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
	transfers.settle_escrow(p, not transfer.is_empty())
	if not transfer.is_empty():
		transfers.arrive(p, transfer)
	tutorials.on_join(p)  # after mods pick the game mode


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
	sleep.wake(p, "left")
	dev_tools.unsubscribe(peer_id)
	ugc.player_left(peer_id)
	skill.player_left(p)
	sessions.leave(p)
	transfers.player_left(peer_id)
	anticheat.player_left(peer_id)
	_store_player(p)
	players.erase(peer_id)
	for other: ServerPlayer in players.values():
		Net.s_player_left.rpc_id(other.peer_id, peer_id)
	if p.get_meta("transferring", false):
		broadcast_chat("%s travelled to %s" % [p.name, p.get_meta("transferring")])
	else:
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
	var data: Dictionary = chunk.generated_data.duplicate(true)  # saved data below replaces it
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
	if not _save_queue.is_empty() or _save_meta_pending:
		# A save in progress holds chunks serialized earlier; they must reach the disk before newer copies below.
		_drain_save_queue(-1)
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
		anticheat.record(p, "bad_packet", 5.0, "an input packet of %d bytes" % packet.size())
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
		anticheat.count_input(p)
		p.yaw = input.yaw
		p.pitch = input.pitch
	while p.input_queue.size() > MAX_QUEUED_INPUTS:
		p.input_queue.pop_front()


func on_break_block(peer_id: int, pos: Vector3i) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var current := world.get_block_v(pos)
	if not _may(p, "build", "You can't build on this server"):
		_reject_edit(p, pos)
		return
	if not _can_edit(p, pos) or current == BlockRegistry.UNLOADED or registry.breakable_lut[current] == 0 or p.dead:
		_reject_edit(p, pos)
		return
	var held := p.inventory.selected_item()
	var held_data: Dictionary = p.inventory.data[p.inventory.selected]
	var tool := items.tool_of(held, held_data)
	var harvest := true
	if not p.inventory.creative:
		var required := Mining.break_time(registry.defs[current], tool, p.get_stat("mining_speed"))
		# Accept a little early for latency; the client times the crack animation itself.
		var mined_long_enough: bool = p.mining.get("position") == pos and _time - float(p.mining.get("started", INF)) >= required * 0.8 - 0.15
		if required > 0.05 and not mined_long_enough:
			var elapsed := _time - float(p.mining.get("started", _time)) if p.mining.get("position") == pos else 0.0
			anticheat.record(p, "fast_break", 1.0 if elapsed < required * 0.5 else 0.25, "%.2f s of %.2f s" % [elapsed, required])
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
		if registry.defs[current].hardness > 0.0 and items.max_durability(held, held_data) > 0:
			damage_item(p, p.inventory.selected, 1, "mine")
		hunger.add_exhaustion(p, Hunger.BREAK_BLOCK)
		p.sync_inventory()
	emit("block_broken", {"player": p, "position": pos, "block": current, "item": held, "slot": p.inventory.selected, "harvested": harvest})


func on_place_block(peer_id: int, pos: Vector3i, yaw: float) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var block := p.inventory.selected_block()
	var current := world.get_block_v(pos)
	if block > 0 and not _may(p, "build", "You can't build on this server"):
		_reject_edit(p, pos)
		return
	var valid: bool = _can_edit(p, pos) and block > 0 and registry.placeable_lut[block] == 1 \
		and _can_replace(current) and _has_solid_neighbor(pos) and is_supported(pos, block)
	var state := BlockRegistry.facing_from_yaw(yaw) if valid and registry.defs[block].orientation == 1 and is_finite(yaw) else 0
	# Two-block pieces (beds) also need room for their other half.
	var pair = registry.defs[block].get("pair") if valid else null
	var pair_pos := pos
	var pair_block := 0
	if pair is Dictionary:
		pair_pos = pos + pair_offset(pair, state)
		pair_block = registry.id_of(str(pair.block))
		valid = pair_block > 0 and _can_edit(p, pair_pos) and _can_replace(world.get_block_v(pair_pos)) and is_supported(pair_pos, pair_block)
	if valid:
		for other: ServerPlayer in players.values():
			for cell in ([pos, pair_pos] if pair_block > 0 else [pos]):
				if registry.solid_lut[block] == 1 and PlayerPhysics.overlaps_block(other.state.position, cell) and not other.dead:
					valid = false
	if valid:
		valid = not emit("block_place", {"player": p, "position": pos, "block": block, "cancelled": false}).cancelled
	if not valid:
		_reject_edit(p, pos)
		return
	p.inventory.consume_selected()
	if not p.inventory.creative:
		p.sync_inventory()
	_apply_block(pos, block, false, state)
	if pair_block > 0:
		_apply_block(pair_pos, pair_block, false, state)
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
	if not _may(p, "interact", "You can't use that here"):
		return
	var ev := emit("block_interact", {"player": p, "position": pos, "block": block, "cancelled": false})
	if ev.cancelled:
		return
	if sleep.is_bed(block):
		sleep.use_bed(p, pos)
	elif not containers.type_of_block(block).is_empty():
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
			var t := Time.get_ticks_usec()
			command.handler.call(p, parts.slice(1))
			dev_tools.record(command.mod, "command:/" + parts[0].to_lower(), Time.get_ticks_usec() - t)
		return
	if not _may(p, "chat", "You can't chat on this server"):
		return
	if gameplay.chat_filter:
		clean = chat_filter.clean(clean)
	if not emit("chat", {"player": p, "text": clean, "cancelled": false}).cancelled:
		var badge := roles.badge(p.player_id)
		broadcast_chat("<%s%s> %s" % ["[%s] " % badge.tag if gameplay.role_tags and not badge.is_empty() else "", p.name, clean])


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
	if not items.get_def(item).get("food", {}).is_empty():
		hunger.start_eating(p)  # finishes while use is held (see Hunger)
		return
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


func on_leave_bed(peer_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		sleep.wake(p, "left bed")


func on_stop_using(peer_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		hunger.stop_eating(p)


func on_open_menu(peer_id: int, menu: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p and menu == "crafting":
		open_crafting(p, {})


## Tutorial buttons: start <id> | skip (the current step) | stop | tips_on | tips_off.
func on_tutorial_action(peer_id: int, action: String, arg: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	match action:
		"start": tutorials.start(p, arg.left(200))
		"skip": tutorials.advance(p, true)
		"stop": tutorials.stop(p)
		"tips_on": tutorials.set_tips(p, true)
		"tips_off": tutorials.set_tips(p, false)


func _cmd_tutorial(player, args: PackedStringArray) -> void:
	var action := args[0] if args.size() > 0 else "list"
	match action:
		"list":
			var s: Dictionary = tutorials.state_of(player)
			for t in tutorials.to_network():
				var status := "active" if s.active == t.id else ("done" if s.done.has(t.id) else "")
				player.send_message("%s - %s%s" % [t.id, t.title, "  (%s)" % status if not status.is_empty() else ""])
		"start":
			if args.size() < 2 or not tutorials.start(player, args[1]):
				player.send_message("Usage: /tutorial start <id> (see /tutorial list)")
		"skip": tutorials.advance(player, true)
		"stop": tutorials.stop(player)
		"tips":
			tutorials.set_tips(player, args.size() < 2 or args[1] != "off")
			player.send_message("Tips %s" % ("off" if tutorials.state_of(player).tips_off else "on"))
		_:
			player.send_message("Usage: /tutorial list | start <id> | skip | stop | tips on|off")


## Dev overlay requests: subscribe {channels}, inspect {pos | entity | player}, trace_filter {filter},
## clear_errors {source}.
func on_dev(peer_id: int, action: String, args: Dictionary) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	if not dev_tools.allowed(p):
		if action == "subscribe" and not (args.get("channels", []) as Array).is_empty():
			Net.s_dev.rpc_id(peer_id, "denied", {})
		return
	match action:
		"subscribe":
			dev_tools.subscribe(p, args.get("channels") if args.get("channels") is Array else [])
		"inspect":
			var target := {}
			if args.get("pos") is Vector3i:
				target.pos = args.pos
			elif args.has("entity"):
				target.entity = int(args.entity)
			elif args.has("player"):
				target.player = int(args.player)
			dev_tools.set_inspect(p, target)
		"trace_filter":
			dev_tools.set_trace_filter(p, str(args.get("filter", "")))
		"clear_errors":
			dev_log.clear_errors(str(args.get("source", "")))
			dev_tools.subscribe(p, dev_tools.viewers.get(peer_id, {}).get("channels", {}).keys())


func on_guide_read(peer_id: int, page_id: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p:
		guide.on_read(p, page_id.left(200))


func on_attack(peer_id: int, kind: int, target_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.dead:
		return
	var stats := p.get_stats()
	if _time - p.last_attack_time < float(stats.attack_cooldown) * 0.9:
		if _time - p.last_attack_time < float(stats.attack_cooldown) * 0.5:
			anticheat.record(p, "attack_rate", 1.0, "%.2f s between hits" % (_time - p.last_attack_time))
		return
	var target = entities.entities.get(target_id) if kind == 0 else players.get(target_id)
	if target == null or target == p or (kind == 0 and not target.is_alive()) or (kind == 1 and target.dead):
		return
	var box: AABB = target.aabb() if kind == 0 else AABB(target.state.position - Vector3(PlayerPhysics.HALF_WIDTH, 0, PlayerPhysics.HALF_WIDTH),
		Vector3(PlayerPhysics.HALF_WIDTH * 2.0, PlayerPhysics.HEIGHT, PlayerPhysics.HALF_WIDTH * 2.0))
	var eye := p.get_eye_position()
	var distance := eye.distance_to(eye.clamp(box.position, box.end))
	if distance > float(stats.reach):
		if distance > float(stats.reach) + 2.0:
			anticheat.record(p, "reach", 1.0, "a hit %.1f blocks away" % distance)
		return
	var center := box.get_center()
	var ray := VoxelRaycast.cast(world, registry.solid_lut, eye, center - eye, eye.distance_to(center))
	if ray.hit and eye.distance_to(Vector3(ray.position) + Vector3.ONE * 0.5) < distance - 0.5:
		return  # a wall is in the way
	p.last_attack_time = _time
	hunger.add_exhaustion(p, Hunger.ATTACK)
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
		if landed:
			entities.taming.owner_attacked(p, target)
		var sweep := float(items.weapon_of(item, p.inventory.data[p.inventory.selected]).get("sweep", 0.0))
		if landed and sweep > 0.0:
			for other in entities.in_radius(target.body.position, 1.8):
				if other != target and other.def.kind == "mob":
					other.hurt_timer = 0.0
					entities.damage(other, float(ev.damage) * sweep, "attack", p, other.body.position - p.state.position)
	elif gameplay.pvp:
		landed = damage_player(target, float(ev.damage), "attack", p, direction, false, 6.0 * float(stats.knockback))
		if landed:
			entities.taming.owner_attacked(p, target)
	if landed:
		var impact := eye.clamp(box.position, box.end).lerp(center, 0.5)
		play_effect(String(look.effects.get("hit", "engine:hit")), impact, {"direction": -direction3})
		if critical:
			play_effect("engine:crit", impact + Vector3(0, 0.3, 0))
	var item_data: Dictionary = p.inventory.data[p.inventory.selected]
	if landed and items.max_durability(item, item_data) > 0:
		damage_item(p, p.inventory.selected, 1 if not items.weapon_of(item, item_data).is_empty() else 2, "attack")


func on_interact_entity(peer_id: int, target_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	var e = entities.entities.get(target_id)
	if p == null or p.dead or e == null or not e.is_alive() or p.edit_tokens < 1.0:
		return
	p.edit_tokens -= 1.0
	if p.get_eye_position().distance_to(e.aabb().get_center()) > ATTACK_REACH + e.def.width:
		return
	var ev := emit("entity_interact", {"player": p, "entity": e, "item": p.inventory.selected_item(), "cancelled": false})
	if not ev.cancelled and not entities.taming.interact(p, e):
		entities.breeding.feed(p, e)


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
	var seconds := Mining.break_time(registry.defs[block], items.tool_of(p.inventory.selected_item(), p.inventory.data[p.inventory.selected]), p.get_stat("mining_speed"))
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
	var max_durability := items.max_durability(id, p.inventory.data[slot] if slot >= 0 and slot < p.inventory.total() else {})
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
	if not p.sleeping.is_empty():
		appearance.sleeping = {"head": [p.sleeping.head_dir.x, p.sleeping.head_dir.z]}  # lies down, head towards the pillow
	var held := p.inventory.selected_item()
	if held >= ItemRegistry.FIRST_ITEM:
		var held_data: Dictionary = p.inventory.data[p.inventory.selected]
		var look := items.visuals(held, held_data)
		if not look.glow.is_empty() or not look.trail.is_empty() or look.effects.has("held") or held_data.get("icon_layers") is Array:
			appearance.held_look = {"glow": look.glow, "trail": look.trail, "held": look.effects.get("held", "")}
			if held_data.get("icon_layers") is Array:
				appearance.held_look.icon_layers = held_data.icon_layers  # tools built from parts look like their parts
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
	p.requested_avatar = avatar.duplicate(true) if avatar is Dictionary else {}
	ugc.ensure_registered(Ugc.worn_ids(avatar))
	var clean := cosmetics.sanitize_avatar(avatar, can_wear.bind(p))
	if not cosmetics.policy.allow_colors:
		clean.erase("skin")
		clean.erase("body")
		for cat_name in clean.get("wear", {}):
			clean.wear[cat_name].erase("color")
	var portable := clean.duplicate(true)
	var server_picks := {}
	for cat_name in clean.get("wear", {}):
		var worn_id: String = clean.wear[cat_name].id
		# Portable: built-in cosmetics and the player's own creations. Everything else is this server's pick.
		var own_creation := Creations.is_id(worn_id) and str(ugc.store.get(worn_id, {}).get("manifest", {}).get("author", "")) == p.player_id
		if not Cosmetics.is_builtin(worn_id) and not own_creation:
			server_picks[cat_name] = clean.wear[cat_name]
			portable.wear.erase(cat_name)
	p.portable_avatar = portable
	if not joining:
		p.server_wear = server_picks
	refresh_avatar(p)


## Whether a player may pick a cosmetic themselves (mods can still dress anyone in anything).
func can_wear(cosmetic_name: String, p: ServerPlayer) -> bool:
	if Creations.is_id(cosmetic_name):
		return ugc.can_wear(p, cosmetic_name)
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


## Applies the avatar the player last asked for again (a creation in it was approved or removed).
func reapply_requested_avatar(p: ServerPlayer) -> void:
	_set_client_avatar(p, p.requested_avatar, true)


# --- Player creations (RPC handlers; see engine/server/ugc.gd) -------------------------------------

func _cmd_ugc(player, args: PackedStringArray) -> void:
	var action := args[0] if args.size() > 0 else "list"
	match action:
		"list":
			var filter := args[1] if args.size() > 1 else "pending"
			var items := ugc.review_list(filter)
			if items.is_empty():
				player.send_message("No %s creations" % filter)
			for item in items.slice(0, 12):
				player.send_message("%s  %s \"%s\" by %s  [%s]%s" % [item.id.left(12), item.manifest.kind, item.manifest.name, item.manifest.author_name,
					item.status, "  %d report%s" % [item.get("reports", []).size(), "" if item.get("reports", []).size() == 1 else "s"] if not item.get("reports", []).is_empty() else ""])
		"approve", "reject", "remove":
			var id := ugc.resolve_id(args[1] if args.size() > 1 else "")
			if id.is_empty():
				player.send_message("No single creation matches '%s' (see /ugc list)" % (args[1] if args.size() > 1 else ""))
				return
			var status: String = {"approve": "approved", "reject": "rejected", "remove": "removed"}[action]
			ugc.set_status(id, status, " ".join(args.slice(2)), player.name)
			player.send_message("%s is now %s" % [ugc.store[id].manifest.name, status])
		"trust", "untrust", "ban", "unban":
			var target_name := args[1] if args.size() > 1 else ""
			var player_id: String = _meta.names.get(target_name.to_lower(), "")
			if player_id.is_empty():
				player.send_message("No known player named '%s'" % target_name)
				return
			if action in ["trust", "untrust"]:
				ugc.set_trusted(player_id, action == "trust")
			else:
				ugc.set_banned(player_id, action == "ban", " ".join(args.slice(2)), player.name)
			player.send_message("%s: %s" % [target_name, {"trust": "trusted creator", "untrust": "no longer trusted", "ban": "may not upload creations", "unban": "may upload again"}[action]])
		"policy":
			if args.size() >= 3:
				var value = args[2]
				if value in ["true", "false"]:
					value = value == "true"
				elif value.is_valid_int():
					value = int(value)
				ugc.set_policy({args[1]: value})
			player.send_message("Creations policy: %s" % JSON.stringify(ugc.policy))
		_:
			player.send_message("Usage: /%s" % _commands.ugc.description)


func _cmd_report(player, args: PackedStringArray) -> void:
	var target = _find_online(args[0] if args.size() > 0 else "")
	if target == null:
		player.send_message("Usage: /report <player> [reason] - reports the creations that player wears")
		return
	var ids := Ugc.worn_ids(target.avatar)
	if ids.is_empty():
		player.send_message("%s is not wearing any player creations" % target.name)
		return
	for id in ids:
		var error := ugc.report(player, id, args[1] if args.size() > 1 else "other")
		player.send_message(error if not error.is_empty() else "Reported \"%s\". Thank you." % ugc.store[id].manifest.name)


func on_ugc_report(peer_id: int, id: String, reason: String, details: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var error := ugc.report(p, id, reason, details)
	p.send_message(error if not error.is_empty() else "Thanks, the report was sent to this server's admins.")


## The players and roles panel. Answers with {players, roles, can_kick, denied?}.
## Gameplay rules the settings screen offers, in the order they are shown: [key, label, help].
const PANEL_RULES := [
	["pvp", "Players can hurt each other", "Off: swings between players do nothing."],
	["keep_inventory", "Keep your things when you die", "Off: everything drops where you died."],
	["mob_spawning", "Monsters and animals appear", "Off: no new creatures (the ones around stay)."],
	["mob_griefing", "Monster blasts break blocks", "Off: explosions still hurt, but leave the world alone."],
	["fall_damage", "Falling hurts", ""],
	["hunger", "Getting hungry", "Off: nobody needs to eat."],
	["natural_regeneration", "Health comes back on its own", ""],
	["sleeping", "Beds skip the night", ""],
	["durability", "Tools and armour wear out", ""],
	["recipe_discovery", "Recipes have to be discovered", "Off: everyone knows every recipe from the start."],
	["tutorials", "Tutorials for new players", ""],
	["chat_filter", "Mask swear words in chat", ""],
	["role_tags", "Show role tags in chat", ""],
]


## The admin settings screen. Every action is the command an admin could type, run with their own
## permissions, so nothing here grants more than chat already does.
func on_server_panel(peer_id: int, action: String, args: Dictionary) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	if not has_permission(p, "admin"):
		if p._online():
			Net.s_server_panel.rpc_id(peer_id, {"denied": true})
		return
	match action:
		"set":
			_run_panel_command(p, "gameplay", PackedStringArray([str(args.get("key", "")), str(args.get("value", ""))]))
		"time":
			_run_panel_command(p, "time", PackedStringArray([str(args.get("value", "day"))]))
		"gamemode":
			_run_panel_command(p, "gamemode", PackedStringArray([str(args.get("mode", "survival")), "all"]))
		"anticheat":
			_run_panel_command(p, "anticheat", PackedStringArray(["mode", str(args.get("mode", "kick"))]))
		"allowlist":
			var allow_args := PackedStringArray([str(args.get("mode", "list"))])
			if args.has("name"):
				allow_args.append(str(args.name))
			_run_panel_command(p, "allow", allow_args)
		"save":
			_run_panel_command(p, "backup", PackedStringArray())
	var rules := []
	for entry in PANEL_RULES:
		if gameplay.has(entry[0]):
			rules.append({"key": entry[0], "label": entry[1], "help": entry[2], "value": bool(gameplay[entry[0]])})
	var list: Dictionary = _meta.get("allowlist", {}) if _meta.get("allowlist") is Dictionary else {}
	var allowed := []
	for key: String in (list.get("players", {}) as Dictionary):
		allowed.append(str(list.players[key].get("name", key)))
	allowed.sort()
	if not p._online():
		return
	Net.s_server_panel.rpc_id(peer_id, {
		"rules": rules,
		"server": {"name": str(server_info.name), "motd": str(server_info.motd), "world": _save_dir.get_file(), "mods": server_info.get("mods", []),
			"version": Protocol.GAME_VERSION, "players": players.size(), "id": transfers.own_id},
		"time_of_day": snappedf(_time_of_day, 0.001), "day_length": _day_length,
		"anticheat": anticheat.mode,
		"allowlist": {"enabled": bool(list.get("enabled", false)), "names": allowed},
		"can_kick": has_permission(p, "command.kick"),
	})


## Runs one of the panel's actions as a command from that player (so its own permission check applies).
func _run_panel_command(p: ServerPlayer, command_name: String, args: PackedStringArray) -> void:
	var command: Dictionary = _commands.get(command_name, {})
	if command.is_empty() or not _permitted(p, command):
		p.send_message("You don't have permission to change that")
		return
	command.handler.call(p, args)


func on_roles_panel(peer_id: int, action: String, args: Dictionary) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	if not has_permission(p, "roles.manage"):
		Net.s_roles_panel.rpc_id(peer_id, {"denied": true})
		return
	match action:
		"give", "take":
			var id := str(args.get("player_id", ""))
			var name_for := _name_for(id)
			_cmd_role(p, PackedStringArray([action, name_for, str(args.get("role", ""))]))
		"kick":
			var target: ServerPlayer = players.get(int(args.get("peer", 0)))
			if target != null and target != p and has_permission(p, "command.kick"):
				kick(target.peer_id, "Kicked by %s" % p.name)
	var my_rank := roles.rank(p.player_id)
	var owner := has_permission(p, "roles.owner")
	var list := []
	var online := {}
	for other: ServerPlayer in players.values():
		online[other.player_id] = other.peer_id
	var known: Array = _meta.names.keys()
	known.sort()
	for n: String in known.slice(0, 300):
		var id: String = _meta.names[n]
		list.append({"id": id, "name": _name_for(id), "online": online.has(id), "peer": online.get(id, 0), "roles": roles.roles_of(id),
			"assigned": _meta.player_roles.get(id, []) if _meta.get("player_roles") is Dictionary else []})
	list.sort_custom(func(a, b): return a.online and not b.online if a.online != b.online else a.name.naturalnocasecmp_to(b.name) < 0)
	var role_list := []
	for r in roles.role_names():
		var def := roles.role(r)
		role_list.append({"name": r, "tag": def.tag, "color": def.color, "priority": def.priority,
			"manageable": owner or (r != "owner" and int(def.priority) < my_rank), "default": r == roles.default_role})
	Net.s_roles_panel.rpc_id(peer_id, {"players": list, "roles": role_list, "can_kick": has_permission(p, "command.kick"), "me": p.player_id})


## The creations review panel (admins): list {filter, text} | set_status {id, status, reason} |
## trust {player_id, on} | ban {player_id, on, reason} | clear_reports {id}. Answers with the list.
func on_ugc_admin(peer_id: int, action: String, args: Dictionary) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	if not has_permission(p, "ugc.review"):
		Net.s_ugc_admin_list.rpc_id(peer_id, [], {"denied": true})
		return
	match action:
		"set_status":
			ugc.set_status(str(args.get("id", "")), str(args.get("status", "")), str(args.get("reason", "")).left(200), p.name)
		"trust":
			ugc.set_trusted(str(args.get("player_id", "")), bool(args.get("on", true)))
		"ban":
			ugc.set_banned(str(args.get("player_id", "")), bool(args.get("on", true)), str(args.get("reason", "")).left(200), p.name)
		"clear_reports":
			ugc.clear_reports(str(args.get("id", "")))
	var items := ugc.review_list(str(args.get("filter", "pending")), str(args.get("text", "")))
	Net.s_ugc_admin_list.rpc_id(peer_id, items.slice(0, 200), ugc.policy)


func on_ugc_offer(peer_id: int, manifests: Array) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		ugc.offer(p, manifests)


func on_ugc_upload(peer_id: int, id: String, offset: int, total: int, bytes: PackedByteArray) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		ugc.upload_piece(p, id, offset, total, bytes)


func on_ugc_fetch(peer_id: int, ids: PackedStringArray) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		ugc.fetch(p, ids)


func on_ugc_library(peer_id: int, query: Dictionary, offset: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null and p._online():
		var page := ugc.library(query, maxi(0, offset))
		Net.s_ugc_library.rpc_id(peer_id, page.items, page.total, ugc.policy)


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
	var sprint := clampf(float(p._stats.get("sprint", 1.0)), 0.0, 1.0) if not p._stats.is_empty() else 1.0
	if is_equal_approx(speed, 1.0) and is_equal_approx(sprint, 1.0):
		p.physics_rules = null
		return
	p.physics_rules = PlayerPhysics.Rules.new()
	var values := rules.to_dict()
	values.walk_speed = rules.walk_speed * speed
	values.sprint_speed = (rules.walk_speed + (rules.sprint_speed - rules.walk_speed) * sprint) * speed
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
		"unlock": options.get("unlock", "pickup"), "hint": options.get("hint", ""), "pattern": options.get("pattern", []),
		"output_data": options.get("output_data", {}), "skill": options.get("skill", ""), "owner": options.get("owner", "")}, items)


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
	if recipe.get("removed", false):
		return 0
	if p.crafting_station.has("position") and _station_valid(p):
		p.crafting_station = stations.evaluate(p.crafting_station.position)  # workshop blocks may have changed
	if recipe.get("project", false):
		return 0  # projects are built together through the station screen (see StationSessions)
	var n := craftable_times(p, recipe, clampi(times, 1, 64))
	if n <= 0:
		return 0
	if not p.inventory.creative:
		var at_station := _station_valid(p)
		_consume_inputs(p, recipe, n)
		if float(recipe.get("time", 0.0)) > 0.0 and at_station:
			# Timed recipes are crafted in the station's queue; players there speed it up.
			sessions.add_job(p, p.crafting_station.position, index, n)
			p.sync_inventory()
			if p._online():
				Net.s_crafting_stock.rpc_id(p.peer_id, crafting_stock(p))
			return n
	var total: int = recipe.count * n
	var output_data: Dictionary = recipe.get("output_data", {})
	var left := p.inventory.add(recipe.output, total, items.max_stack(recipe.output), output_data.duplicate(true))
	if left > 0:
		p.drop(recipe.output, left, output_data.duplicate(true))
	p.sync_inventory()
	emit("item_crafted", {"player": p, "item": recipe.output, "count": total, "recipe": recipe.id})
	var at: Vector3 = Vector3(p.crafting_station.position) + Vector3(0.5, 1.1, 0.5) if _station_valid(p) \
		else p.get_eye_position() + PlayerPhysics.look_direction(p.yaw, p.pitch) * 0.7
	play_effect("engine:craft", at, {"scale": 0.6})
	play_sound_at("engine:craft", at, 0.8, randf_range(0.95, 1.1))
	if p._online():
		Net.s_crafted.rpc_id(p.peer_id, index, n, crafting_stock(p))
	return n


## Takes a recipe's ingredients from the backpack, the station's tray and nearby chests.
func _consume_inputs(p: ServerPlayer, recipe: Dictionary, n: int) -> void:
	if p.inventory.creative:
		return
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


## Takes one craft's ingredients for crafting by hand: {item, count, data, recipe}, or {} if the
## recipe cannot be crafted here.
func take_recipe_inputs(p: ServerPlayer, index: int) -> Dictionary:
	if index < 0 or index >= recipes.recipes.size() or p.dead:
		return {}
	var recipe: Dictionary = recipes.recipes[index]
	if p.crafting_station.has("position") and _station_valid(p):
		p.crafting_station = stations.evaluate(p.crafting_station.position)
	if recipe.get("removed", false) or recipe.get("project", false) or craftable_times(p, recipe, 1) < 1:
		return {}
	_consume_inputs(p, recipe, 1)
	p.sync_inventory()
	if p._online():
		Net.s_crafting_stock.rpc_id(p.peer_id, crafting_stock(p))
	return {"item": recipe.output, "count": recipe.count, "data": recipe.get("output_data", {}).duplicate(true), "recipe": recipe.id}


## Gives a finished item (from crafting by hand or assembling) with effects at the station.
func give_crafted(p: ServerPlayer, item: int, count: int, item_data: Dictionary, forged := false) -> void:
	var left := p.inventory.add(item, count, items.max_stack(item), item_data.duplicate(true))
	if left > 0:
		p.drop(item, left, item_data.duplicate(true))
	p.sync_inventory()
	var at: Vector3 = Vector3(p.crafting_station.position) + Vector3(0.5, 1.1, 0.5) if _station_valid(p) else p.get_eye_position()
	if forged:
		play_effect("engine:crit", at, {"scale": 0.7, "color": "#ffd88a"})
	else:
		play_effect("engine:craft", at, {"scale": 0.6})
	play_sound_at("engine:craft", at, 1.0, 0.85 if forged else 1.0)
	if p._online():
		Net.s_crafting_stock.rpc_id(p.peer_id, crafting_stock(p))


func peer_rtt(p: ServerPlayer) -> float:
	return Net.peer_rtt_ms(p.peer_id) / 1000.0 if p._online() else 0.0


func on_skill_craft(peer_id: int, product: Dictionary, assist: bool, with_partner: bool) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.edit_tokens < 1.0:
		return
	p.edit_tokens -= 1.0
	var clean := {}
	if product.get("recipe") is int:
		clean.recipe = product.recipe
	elif product.get("assembly") is String and (product.get("slots") is Array or product.get("slots") is PackedInt32Array):
		clean = {"assembly": product.assembly, "slots": Array(product.slots).slice(0, 8).map(func(v): return int(v) if v is int else -1)}
	if not clean.is_empty():
		skill.start(p, clean, assist, with_partner)


func on_minigame_input(peer_id: int, action: String, t: float, arg: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		skill.input(p, action, t, arg)


func on_minigame_join(peer_id: int, game_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p != null:
		if game_id <= 0:
			skill.start_alone(p)
		else:
			skill.join(p, game_id)


func on_craft(peer_id: int, index: int, times: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.edit_tokens < 1.0:
		return
	p.edit_tokens -= 1.0
	craft(p, index, times)


## One recipe per part type and material, made at the part type's station (after all mods registered).
func _add_part_recipes() -> void:
	for part_name in assembly.part_types:
		var part: Dictionary = assembly.part_types[part_name]
		for material_name in assembly.materials:
			var m: Dictionary = assembly.materials[material_name]
			if m.item <= 0 or part.item <= 0:
				continue
			add_recipe({m.item: part.cost}, part.item, 1, str(part.get("station", "")), {"category": "parts",
				"id": "%s/%s" % [part_name, material_name], "output_data": assembly.part_data(part_name, material_name)})


## Builds a tool from parts in the player's inventory: `slots` lists a backpack slot per assembly slot.
func assemble(p: ServerPlayer, assembly_name: String, slots: PackedInt32Array) -> bool:
	var built := take_assembly_parts(p, assembly_name, slots)
	if built.is_empty():
		return false
	give_crafted(p, built.item, 1, built.data, true)
	if p._online():
		Net.s_assembled.rpc_id(p.peer_id, built.item, built.data)
	return true


## Takes the parts for an assembly: {item, count, data}, or {} if they are not valid.
func take_assembly_parts(p: ServerPlayer, assembly_name: String, slots: PackedInt32Array) -> Dictionary:
	var a: Dictionary = assembly.assemblies.get(assembly_name, {})
	if a.is_empty() or slots.size() != a.slots.size() or p.dead:
		return {}
	if not p.inventory.creative and not a.station.is_empty() and not (_station_valid(p) and p.crafting_station.name == a.station):
		return {}
	var chosen := {}
	var uses := {}
	for i in a.slots.size():
		var slot := slots[i]
		if slot < 0 or slot >= Inventory.SIZE:
			return {}
		var id := p.inventory.ids[slot]
		var data: Dictionary = p.inventory.data[slot]
		if p.inventory.counts[slot] <= 0 or assembly.part_items.get(id, "") != a.slots[i].part or not assembly.materials.has(str(data.get("material", ""))):
			return {}
		uses[slot] = int(uses.get(slot, 0)) + 1
		if uses[slot] > p.inventory.counts[slot]:
			return {}
		chosen[a.slots[i].name] = str(data.material)
	var result := assembly.build(assembly_name, chosen)
	if result.is_empty():
		return {}
	for slot: int in uses:
		p.inventory.counts[slot] -= uses[slot]
		if p.inventory.counts[slot] <= 0:
			p.inventory.clear_slot(slot)
	var ev := emit("tool_assembled", {"player": p, "assembly": assembly_name, "parts": chosen, "data": result})
	p.sync_inventory()
	return {"item": a.item, "count": 1, "data": ev.data}


func on_assemble(peer_id: int, assembly_name: String, slots: PackedInt32Array) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.edit_tokens < 1.0:
		return
	p.edit_tokens -= 1.0
	assemble(p, assembly_name, slots)


func on_experiment(peer_id: int, grid: PackedInt32Array) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.dead:
		return
	var result := experiments.experiment(p, Array(grid))
	if p._online():
		Net.s_experiment_result.rpc_id(p.peer_id, result)


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
	var distance := p.get_eye_position().distance_to(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	if distance > REACH + 3.0:
		anticheat.record(p, "reach", 1.0, "a block %.1f blocks away" % distance)
	return distance <= REACH + 0.87


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
	var old_state := get_block_state(pos)
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
	# Removing one half of a two-block piece removes the other (its drops come from the half broken).
	if old != block and registry.defs[old].get("pair") is Dictionary:
		var other: Vector3i = pos + pair_offset(registry.defs[old].pair, old_state)
		if world.get_block_v(other) == registry.id_of(str(registry.defs[old].pair.block)):
			_apply_block(other, BlockRegistry.AIR)
	for p: ServerPlayer in players.values():
		if p.sent_chunks.has(coord):
			Net.s_block_changed.rpc_id(p.peer_id, pos, block, state & 255)
	# Blocks that need support (plants, torches) break when what holds them goes away.
	if old != block and pos.y + 1 < Chunk.SIZE_Y:
		var above := world.get_block_v(pos + Vector3i.UP)
		if above != BlockRegistry.AIR and above != BlockRegistry.UNLOADED and not is_supported(pos + Vector3i.UP, above):
			break_block(pos + Vector3i.UP, true)


func _can_replace(current: int) -> bool:
	return current == BlockRegistry.AIR or (current != BlockRegistry.UNLOADED and (registry.liquid_lut[current] == 1 or registry.defs[current].replaceable))


## Offset from one half of a two-block piece to the other: `pair.direction` is "back" (away from the
## player who placed it), "front", "up" or "down".
static func pair_offset(pair: Dictionary, state: int) -> Vector3i:
	var front := BlockRegistry.facing_direction(state)
	match str(pair.get("direction", "back")):
		"front":
			return front
		"up":
			return Vector3i.UP
		"down":
			return Vector3i.DOWN
	return -front


## The other half of a two-block piece at `pos`, or `pos` itself.
func pair_position(pos: Vector3i) -> Vector3i:
	var block := world.get_block_v(pos)
	if not registry.is_valid(block) or not (registry.defs[block].get("pair") is Dictionary):
		return pos
	var pair: Dictionary = registry.defs[block].pair
	var other := pos + pair_offset(pair, get_block_state(pos))
	return other if world.get_block_v(other) == registry.id_of(str(pair.block)) else pos


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
		"items": p.save_items(),
		"modifiers": p.modifiers.duplicate(true),
		"creative": p.inventory.creative,
		"data": p.data,
		"cosmetics": p.owned_cosmetics.keys(),
		"server_wear": p.server_wear,
		"recipes": p.known_recipes.keys(),
		"seen_items": p.seen_items.keys(),
		"health": maxf(p.health, 1.0) if not p.dead else p.max_health,
		"hunger": p.hunger if not p.dead else Hunger.MAX,
		"saturation": p.saturation,
		"exhaustion": p.exhaustion,
		"spawn_point": [p.spawn_point.x, p.spawn_point.y, p.spawn_point.z] if p.spawn_point != Vector3.INF else null,
		"guide": guide.save_player(p),
		"tutorial": tutorials.save_player(p),
		"spawn_bed": [p.spawn_bed.x, p.spawn_bed.y, p.spawn_bed.z] if p.spawn_bed != null else null,
	}


## Serializes changed chunks and metadata on this thread, then writes files on a worker.
## Saves changed chunks, players and world.json. With `wait` everything is serialized and written now
## (shutdown, backups, tests); otherwise the chunks are queued and serialized a few milliseconds per tick
## (see _drain_save_queue) so a big world does not stall one tick, and world.json follows once they are done.
func _save_all(wait := false) -> void:
	if _save_dir.is_empty():
		return
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
	if not coords.is_empty():
		_activity_since_backup = true
	_save_queue.merge(coords)
	_save_meta_pending = true
	_drain_save_queue(-1 if wait else SAVE_BUDGET_USEC, wait)


## Serializes queued chunks until `budget_usec` is spent (-1: all), then players and world.json.
func _drain_save_queue(budget_usec: int, wait := false) -> void:
	if _save_queue.is_empty() and not _save_meta_pending:
		return
	var start := Time.get_ticks_usec()
	for coord: Vector2i in _save_queue.keys():
		if budget_usec >= 0 and Time.get_ticks_usec() - start > budget_usec:
			return
		_save_queue.erase(coord)
		if world.chunks.has(coord):
			_save_writes.append(_serialize_chunk(coord))
			_save_dirty.erase(coord)
	if not _save_meta_pending:
		return
	_save_meta_pending = false
	for p: ServerPlayer in players.values():
		_store_player(p)
	_meta.time = [_time_of_day, _day_length]
	_meta.game = server_info.get("game_id", "")
	_meta.last_played = int(Time.get_unix_time_from_system())
	_meta.clock = block_ticks.clock
	_save_writes.append([_save_dir + "/world.json", JSON.stringify(_meta, "\t")])
	var writes := _save_writes
	_save_writes = []
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
