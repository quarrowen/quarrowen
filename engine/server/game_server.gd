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
const MusicRegistry = preload("res://engine/shared/music_registry.gd")
const WeatherRegistry = preload("res://engine/shared/weather_registry.gd")
const Ambience = preload("res://engine/server/ambience.gd")
const Realm = preload("res://engine/server/realm.gd")
const VoxelRaycast = preload("res://engine/shared/voxel_raycast.gd")
const EntityRegistry = preload("res://engine/shared/entity_registry.gd")
const Mining = preload("res://engine/shared/mining.gd")
const PlayerStats = preload("res://engine/server/player_stats.gd")
const PlayerRig = preload("res://engine/shared/player_rig.gd")
const Cosmetics = preload("res://engine/shared/cosmetics.gd")
const EffectRegistry = preload("res://engine/shared/effect_registry.gd")
const BlockTicks = preload("res://engine/server/block_ticks.gd")
const TagRegistry = preload("res://engine/shared/tag_registry.gd")
const Links = preload("res://engine/server/links.gd")
const Flows = preload("res://engine/server/flows.gd")
const Parcels = preload("res://engine/server/parcels.gd")
const Drives = preload("res://engine/server/drives.gd")
const Assemblies = preload("res://engine/server/assemblies.gd")
const Modifiers = preload("res://engine/server/modifiers.gd")
const Ledgers = preload("res://engine/server/ledgers.gd")
const Objectives = preload("res://engine/server/objectives.gd")
const Conditions = preload("res://engine/server/conditions.gd")
const Fields = preload("res://engine/server/fields.gd")
const Companions = preload("res://engine/server/companions.gd")
const Vehicles = preload("res://engine/server/vehicles.gd")
const Nameplates = preload("res://engine/server/nameplates.gd")
const Characters = preload("res://engine/server/characters.gd")
const Shops = preload("res://engine/server/shops.gd")
const Companies = preload("res://engine/server/companies.gd")
const Plots = preload("res://engine/server/plots.gd")
const Instances = preload("res://engine/server/instances.gd")
const Sources = preload("res://engine/server/sources.gd")
const Conflicts = preload("res://engine/server/conflicts.gd")
const AreaEdits = preload("res://engine/server/area_edits.gd")
const Claims = preload("res://engine/server/claims.gd")
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
const Milestones = preload("res://engine/server/milestones.gd")
const Charging = preload("res://engine/server/charging.gd")
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
const ModSettings = preload("res://engine/server/mod_settings.gd")
const Creations = preload("res://engine/shared/creations.gd")
const Explosions = preload("res://engine/server/explosions.gd")
const Loot = preload("res://engine/server/loot.gd")
const Sightings = preload("res://engine/server/sightings.gd")
const Spawners = preload("res://engine/server/spawners.gd")
const StructureTools = preload("res://engine/server/structure_tools.gd")
const Connect = preload("res://engine/server/connect.gd")
const Assembly = preload("res://engine/shared/assembly.gd")

const DEFAULT_MAX_PLAYERS := 64
## world.json "format": 2 = inventories saved by item name. Nothing persisted has referred to a runtime
## block or item id since this format, which is what makes adding and removing blocks safe. A future
## format bump needs a migration written for it; there is no longer one here, because nothing from
## before alpha 4 is carried forward.
const SAVE_FORMAT := 2

## Other players are replicated only within this distance (blocks) of the recipient...
const INTEREST_RADIUS := 96.0
## ...and beyond this distance only on every other snapshot.
const NEAR_RADIUS := 32.0
## How far a player is sent terrain, and how far the world around them actually runs. Two numbers
## because they cost different things: seeing costs upstream bandwidth, running costs the tick. A
## homelab short of CPU and a house short of upload need different knobs. Simulation never exceeds
## view - a block that ticks where the player cannot see it has changed by the time they look.
const DEFAULT_VIEW_DISTANCE := 8
const DEFAULT_SIMULATION_DISTANCE := 6
const MAX_VIEW_DISTANCE := 24
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
## The worlds this server is running. "" is the overworld - the one a server has always had, and the
## one an old save belongs to. Realms are added by mods before the world loads.
var realms := {}
## The realm everything without a realm of its own means. Every field below that used to hold the world
## directly now reads through it, so the hundred and seventy places that say `world.get_block(...)` did
## not all have to change on the same day. They will change as each becomes realm-aware; until then
## this is the overworld and the behaviour is exactly what it was.
var realm: Realm

var world: VoxelWorld:
	get:
		return realm.world
var world_seed: int:
	get:
		return realm.seed_value
	set(value):
		realm.seed_value = value
var entities: Entities:
	get:
		return realm.entities
var sounds := SoundRegistry.new()
var music := MusicRegistry.new()
var weather := WeatherRegistry.new()
## What the sky is doing: {id, intensity, until}. World state, not per player - everyone standing in the
## same world is standing in the same storm, and somebody joining halfway through arrives in it.
var weather_now := {"id": -1, "intensity": 0.0, "until": 0.0}
## Which way the wind blows and how hard: degrees clockwise from north, and 0 (still) to 1 (a gale).
##
## **The server sends a base vector and the client does the gusting.** Wind that a player can see is
## mostly gusts - grass ripples, a cloud edge tears - and sending that at tick rate would be a lot of
## bandwidth for something nobody can be wrong about. So this changes rarely, and the detail is worked
## out on each client from time and position. `until` matches `weather_now`: 0 means until something
## says otherwise, and while it is unset the engine drifts the wind gently so a world nobody has
## written weather for still breathes. (2026-09-22)
var wind_now := {"angle": 135.0, "strength": 0.3, "until": 0.0, "drifting": true}
var ambience := Ambience.new(self)
## The character body every client draws players with (see PlayerRig; mods may replace it).
var player_rig := PlayerRig.default_rig()
## Built-in and server cosmetics, categories and this server's cosmetics policy.
var cosmetics := Cosmetics.new()
## Named visual effects clients render on request (see EffectRegistry).
var effects := EffectRegistry.new()
## Random and scheduled block ticks, the world clock and server-side light (see BlockTicks). One per
## realm; this is the overworld's, for everything that has not been told which world it means yet.
var block_ticks:
	get:
		return realm.block_ticks
## Signal levels (see engine/server/signals.gd). One per realm; this is the overworld's.
var signals:
	get:
		return realm.signals
## Liquids (see engine/server/liquids.gd). One per realm; this is the overworld's.
var liquids:
	get:
		return realm.liquids
## Machines assembled out of blocks (see engine/server/multiblocks.gd).
var multiblocks:
	get:
		return realm.multiblocks
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
	# Whether flight is available at all here. Off in a survival game: the host of a world is its admin
	# and admin's "*" includes `fly`, so without this the person hosting - often a child on their own
	# world - can always fly, and survival quietly is not survival. `/fly` still works for somebody who
	# has the permission and means it; this only stops the double-tap. (the user, 2026-09-24)
	"flight": true,
	"mob_griefing": true,  # explosions caused by mobs break blocks
	"durability": true,  # tools, weapons and armor wear out
	"tray_access": "contributors",  # station trays: "contributors" (plus owner and team) | "anyone"
	"recipe_discovery": true,  # players learn recipes (see RecipeRegistry unlock rules); false = all known
	"minigame_assist": true,  # players may choose relaxed timing for crafting minigames
	"tutorials": true,  # auto-start tutorials for new survival players (see engine/server/tutorials.gd)
	"chat_filter": false,  # mask swear words in chat and refuse such player names (see engine/server/chat_filter.gd)
	"share_positions": true,  # everyone sees everyone on the map (off: only admins do)
	"role_tags": true,  # show the player's highest role tag in chat ("[Mod] Name")
}
var server_info := {"name": "Quarrowen Server", "game": "", "description": "", "motd": "", "mods": []}
## Map markers mods set for a player: player id -> {marker id: {label, position, color}} (see ModApi.set_map_marker).
var map_markers := {}
## Markers everyone sees (ModApi.set_world_marker); saved in world.json.
var world_markers := {}
## What this realm's terrain is generated by (the overworld's, for callers that have not been told
## which world they mean). A chunk job is handed this.
var generator:
	get:
		return realm.generator
	set(value):
		realm.generator = value
## Objects with decorate(chunk, world_seed) run after the generator on worker threads (e.g. ores).
var generation_passes: Array:
	get:
		return realm.generation_passes
	set(value):
		realm.generation_passes = value
## The engine biome generator once a mod registers biomes (may also be the world generator, but is a
## separate field - see Realm).
var biome_generator:
	get:
		return realm.biome_generator
	set(value):
		realm.biome_generator = value
var spawn_handler := Callable()
## Where a *returning* player appears, if a mod wants a say - a lobby, a hub, wherever their story left
## them. Separate from spawn_handler because "where does a new player start" and "where does somebody
## who has played before come back to" are different questions, and a mod that answers one usually does
## not want to answer the other. Vector3.INF means "leave them where they logged out".
var rejoin_handler := Callable()
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
## Why start() gave up, in words a player can act on. Written next to the worlds so the menu can say it
## instead of "could not connect to 127.0.0.1" (see engine/server_main.gd).
var start_error := ""
var _max_chunk_jobs := maxi(2, OS.get_processor_count() - 2)
var _chunk_jobs: Dictionary:
	get:
		return realm.chunk_jobs
var _save_task := -1
## Delta persistence: only edits relative to freshly generated terrain are saved. Per realm, like
## everything else indexed by chunk coordinate.
var _deltas: Dictionary:
	get:
		return realm.deltas
var _generated: Dictionary:
	get:
		return realm.generated
var _block_data: Dictionary:
	get:
		return realm.block_data
var _save_dirty: Dictionary:
	get:
		return realm.save_dirty
var _save_queue: Dictionary:
	get:
		return realm.save_queue
var _save_writes: Array = []  # serialized [path, text] waiting for the rest of the save
var _save_meta_pending := false
var _js_mods: Array = []  # keeps JavaScript runtimes alive
## Crafting recipes and categories (sent to clients for the recipe book).
var recipes := RecipeRegistry.new()
## Named groups of blocks and items (see engine/shared/tag_registry.gd). Server-side: a tag is a
## question a mod asks while the world runs, not something a client has to know.
var tags := TagRegistry.new()
## What a block *type* does is true of every world, so these tables belong to the server and every
## realm's machinery reads the same one. Registering per realm looked equivalent and was not: a realm
## a mod adds later would have had no handlers at all, silently. (2026-09-20)
var block_tick_handlers := {}
var signal_handlers := {}
var liquid_kinds := {}
var liquid_meetings := {}
var multiblock_patterns := {}
## What is joined to what (see engine/server/links.gd). Server-wide, not per realm: a wireless link may
## have one end in one world and the other somewhere else, so it belongs to neither.
var links := Links.new(self)
## Quantities moving along those links - power, fluid, gas (see engine/server/flows.gd).
var flows := Flows.new(self)
## Things travelling along those links (see engine/server/parcels.gd). Not the same mechanism as
## flows, and the file says why.
var parcels := Parcels.new(self)
## Values driven through the graph with nothing stored - rotation (see engine/server/drives.gd).
var drives := Drives.new(self)
## Blocks that have left the grid and move as one thing (see engine/server/assemblies.gd).
var assemblies := Assemblies.new(self)
## Named marks on particular items - keen, sturdy (see engine/server/modifiers.gd).
var modifiers := Modifiers.new(self)
## Named numbers a player owns - coins, reputation, experience (see engine/server/ledgers.gd).
var ledgers := Ledgers.new(self)
## Things a player has been asked to do (see engine/server/objectives.gd).
var objectives := Objectives.new(self)
## People who stand somewhere and hold a conversation (see engine/server/characters.gd).
var characters := Characters.new(self)
## Buying and selling, drawn the same way everywhere (see engine/server/shops.gd).
var shops := Shops.new(self)
## What somebody is temporarily under - swiftness, poison (see engine/server/conditions.gd).
var conditions := Conditions.new(self)
## Ground that does something to whoever stands in it (see engine/server/fields.gd).
var fields := Fields.new(self)
## What a tamed creature is being told to do (see engine/server/companions.gd).
var companions := Companions.new(self)
## Things you can sit on and steer (see engine/server/vehicles.gd).
var vehicles := Vehicles.new(self)
## The label over a thing's head (see engine/server/nameplates.gd).
var nameplates := Nameplates.new(self)
## Groups of players that things can belong to (see engine/server/companies.gd).
var companies := Companies.new(self)
## Ground with an owner, consulted before an edit (see engine/server/plots.gd).
var plots := Plots.new(self)
## Changing many blocks at once, with the same checks one block gets (see engine/server/area_edits.gd).
var area_edits := AreaEdits.new(self)
## Private copies of a space, made on demand and thrown away (see engine/server/instances.gd).
var instances := Instances.new(self)
## Where a thing comes from when the answer is not a recipe (see engine/server/sources.gd).
var sources := Sources.new(self)
## Two mods quietly standing on each other. Reported, never resolved - see conflicts.gd.
var conflicts := Conflicts.new(self)
## Parts of the world kept awake when nobody is there, and the budget that stops one player doing it
## to everybody else (see engine/server/claims.gd).
var claims := Claims.new(self)
## Recipes whose inputs name a tag, held until every mod has loaded (see _expand_tag_recipes).
var _tag_recipes: Array = []
## Each mod's API object, by mod id. Mods are not obliged to keep their own, so the server does.
var _mod_apis := {}
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
## What a player has done, for as long as the world lasts (see engine/server/milestones.gd).
var milestones := Milestones.new(self)
## Items held down rather than clicked: bows, slings (see engine/server/charging.gd).
var charging := Charging.new(self)
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
## Chunks of terrain a player is sent, and chunks around them that the world actually runs in.
## Both from the host's configuration; see the constants above for why they are separate.
var view_distance := DEFAULT_VIEW_DISTANCE
var simulation_distance := DEFAULT_SIMULATION_DISTANCE
## Quick reloads, the file watcher and full reloads (see engine/server/mod_reload.gd).
var mod_reload := ModReload.new(self)
## Player creations: uploads, the server library and serving them (see engine/server/ugc.gd).
var ugc := Ugc.new(self)
## What mods let a host change without editing them (see engine/server/mod_settings.gd).
var mod_settings := ModSettings.new(self)
## Loaded mods: id -> manifest, in load order, and id -> the running mod (GDScript instance or JsMod).
var mod_manifests := {}
var mod_order: Array = []
var mod_instances := {}
## Emitted by /reload full: the owner (server_main) saves, restarts the server and clients reconnect.
signal full_reload_requested
var explosions := Explosions.new(self)
var loot := Loot.new(self)
## The rare creatures the whole server is told about, and the markers that follow them.
var sightings := Sightings.new(self)
var spawners := Spawners.new(self)
var structure_tools := StructureTools.new(self)
## Blocks that notice their neighbours: fences joining into a run, panes into a window.
var connect := Connect.new(self)
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
## Lower-case names or player ids granted admin by configuration (QW_ADMINS).
var _config_admins := {}
var _save_timer := 0.0
var _unload_timer := 0.0
var _view_offsets: Array[Vector2i] = []
var _simulation_offsets: Array[Vector2i] = []
## Set when somebody crosses a chunk boundary, joins or leaves: the simulated set needs rebuilding.
var _simulation_dirty := true
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
## Per realm, like everything else keyed by chunk coordinate.
var _entity_chunks: Dictionary:
	get:
		return realm.entity_chunks


## config keys:
##   port, max_players, world, seed, admin_token, mods (PackedStringArray), mod_dirs (PackedStringArray, searched
##   before res://mods), data_dir (default user://worlds), metrics (seconds between reports, 0 = off),
##   offline (true = load mods and world without opening a socket, for benchmarks),
##   backup_interval (minutes between automatic backups, 0 = off), backup_keep (archives kept),
##   restore ("latest", a backup file name or an archive path to restore before loading)
## The overworld exists from the moment the server does. `entities` used to be built here and plenty of
## things reach for it long before start() - mod validation among them - so the realm holding it has to
## be ready just as early.
func _init() -> void:
	# Whoever is standing in that world sees a cable appear or vanish as it happens.
	add_handler("link_made", func(ev): _broadcast_link(int(ev.id)); flows.link_changed(ev.a, ev.b); drives.link_changed(ev.a, ev.b), 0, "engine")
	add_handler("link_cut", func(ev): _broadcast_link_gone(int(ev.id), String(ev.a.realm)); flows.link_changed(ev.a, ev.b); drives.link_changed(ev.a, ev.b), 0, "engine")
	realm = Realm.new(self, "", "Overworld")
	realms[""] = realm
	realm.attach()


## Adds a world beside the overworld. A mod calls this while it is setting up, before the world loads,
## and then gives the realm a generator the same way it gives the overworld one.
##
## Returns the realm, or null when the name is taken or empty. The id is the mod's own qualified name
## ("mymod:emberdeep"), so two mods can both have an underworld without colliding.
func add_realm(realm_id: String, realm_name := "") -> Realm:
	if realm_id.is_empty() or realms.has(realm_id):
		push_error("Invalid or duplicate realm '%s'" % realm_id)
		return null
	var made := Realm.new(self, realm_id, realm_name)
	realms[realm_id] = made
	made.attach()
	# Derived from the world's seed and the realm's name rather than copied. Two realms given the same
	# number are the same terrain with different blocks in it, which is a reskin and not a second world;
	# derived means the Emberdeep is still the same Emberdeep every time this world is loaded.
	made.seed_value = hash([world_seed, realm_id])
	# Only once the world directory is known; before start() picks it, set_storage runs with the rest.
	if not _save_dir.is_empty():
		made.set_storage(_save_dir)
	return made


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
	var map_error := _install_map(config)
	if not map_error.is_empty():
		start_error = map_error
		printerr("[server] " + map_error)
		return FAILED
	for r: Realm in realms.values():  # <world>/chunks for the overworld, <world>/realms/<id>/chunks for the rest
		r.set_storage(_save_dir)
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
	view_distance = clampi(int(config.get("view_distance", DEFAULT_VIEW_DISTANCE)), 2, MAX_VIEW_DISTANCE)
	# Never more than the view: a chunk that runs where nobody has been sent it is work spent on a
	# place the player finds already changed when they arrive.
	simulation_distance = clampi(int(config.get("simulation_distance", DEFAULT_SIMULATION_DISTANCE)), 1, view_distance)
	# A share of the tick, not a share of the machine: anything above about half a tick and the people
	# actually playing start to feel the machines of the people who are not.
	claims.budget_usec = clampi(int(config.get("awake_budget", 2000)), 0, 8000)
	_register_builtin_commands()
	# Before the mods load, so a mod can read its own settings while it is still starting up.
	mod_settings.load_sources(_meta, data_dir, str(config.get("mod_settings", "")))

	var err := _load_mods(config.get("mods", PackedStringArray()), config.get("mod_dirs", PackedStringArray()))
	dev_log.drain()  # script parse errors from loading, so they reach the log file
	if err != OK:
		return err
	_expand_tag_recipes()  # before part recipes: every mod has had its say about what is in a tag
	_add_part_recipes()
	_migrate_save_format()
	if str(config.get("anticheat", "")) in ["kick", "log", "off"]:
		anticheat.mode = str(config.anticheat)
	chat_filter.load_extra(_save_dir)
	if not str(config.get("default_role", "")).is_empty():
		roles.default_role = str(config.default_role).to_lower()
	roles.apply_config_admins(_config_admins)
	if _meta.get("loot") is Dictionary:
		loot.rate = clampf(float(_meta.loot.get("rate", 1.0)), 0.0, 10.0)
		loot.boosts = _meta.loot.get("boosts", {}) if _meta.loot.get("boosts") is Dictionary else {}
	if _meta.get("world_markers") is Dictionary:
		world_markers = _meta.world_markers  # markers mods put on everyone's map, from the last session
	# After the mods have registered their link kinds, or every saved link would be dropped as belonging
	# to a kind nothing knows about.
	# The engine listening to its own event, the way it already does for link_made and link_cut, rather
	# than sync_inventory reaching into the server to call this by name.
	add_handler("inventory_changed", func(ev): check_discoveries(ev.player), 0, "engine")
	links.load_saved(_meta.get("links"))
	# Merged over the declarations, not assigned in place of them: the mods have already run by here,
	# so replacing the table threw away every `shared_store` they declared and left an empty vault.
	# Saved contents whose mod is gone are kept too, so uninstalling a mod does not eat what was in
	# its store - the same promise the chunk delta format makes about blocks. (2026-09-21)
	var saved_stores = _meta.get("stores")
	if saved_stores is Dictionary:
		for store_name in saved_stores:
			var declared: Dictionary = containers.stores.get(store_name, {})
			var kept: Dictionary = saved_stores[store_name]
			if declared.has("type") and not kept.has("type"):
				kept["type"] = declared.type
			containers.stores[store_name] = kept
	companies.load_saved(_meta.get("companies"))
	plots.load_saved(_meta.get("plots"))
	shops.load_saved(_meta.get("shop_stock"))
	fields.load_saved(_meta.get("fields"))
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
		start_error = "Port %d is already in use - another copy of the game may still be running." % int(config.get("port", 24565))
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
	# Needs the server clock, so it starts with the server rather than being built with one.
	sightings.start()
	sightings.rebuild()
	# Said once at startup, as a warning rather than a refusal: every one of these can be deliberate,
	# and the author is the only one who knows. Saying nothing is what the genre does, and it leaves
	# pack authors to notice duplicate ores by playing far enough to find both. (2026-09-22)
	for clash: Dictionary in conflicts.find():
		dev_log.add("warn", "content", String(clash.detail))
	print("[server] '%s' running game '%s' with mods %s, %d blocks, %d assets, seed %d, port %d" % [
		server_info.name, server_info.game, server_info.mods, registry.defs.size(), _assets.size(), world_seed, config.get("port")])
	return OK


func _exit_tree() -> void:
	dev_web.stop()
	if hub != null:
		hub.leave()
	status_query.stop()
	for r: Realm in realms.values():
		for job: Dictionary in r.chunk_jobs.values():
			WorkerThreadPool.wait_for_task_completion(job.task_id)
		r.chunk_jobs.clear()
	if not _save_dir.is_empty():
		_save_all(true)
	if _backup_task != -1:
		WorkerThreadPool.wait_for_task_completion(_backup_task)
		_backup_task = -1
	# The log closes last, after the final save and the backup it might be waiting on. Closing it first
	# is the one ordering that loses the message you most want: "could not write the world".
	dev_log.drain()
	dev_log.close()
	if Net.server == self:
		Net.server = null


# --- Mods ---------------------------------------------------------------------------------------

## An authored world shipped by a mod: a valley someone built for a story rather than terrain the
## generator made. Restored on the **first** start of a world using that mod, and never afterwards.
##
## No new format was needed for this, which is the good part. A world save already *is* a portable map -
## `chunks/x_z.json` deltas plus `world.json` - and WorldBackups packs and unpacks exactly that. So
## authoring a map is: play a world, build the thing, `/backup`, and put the archive in your mod. The
## distribution channel is the mod list, and the "editor" is the game.
##
## Two rules it will not bend. It only ever runs when there is no `world.json`, so a world somebody has
## played is never overwritten by a mod update - losing a child's build to a version bump is not a thing
## that may happen. And a failure stops the server rather than quietly generating terrain instead: a
## story mod whose valley is missing is not a story mod, and starting anyway would strand players in a
## world the triggers do not fit.
func _install_map(config: Dictionary) -> String:
	if FileAccess.file_exists(_save_dir.path_join("world.json")):
		return ""  # already played; never touched again
	var dirs := ModLoader.search_dirs(config.get("mod_dirs", PackedStringArray()))
	var available := ModLoader.discover(dirs)
	for id in config.get("mods", PackedStringArray()):
		var manifest = available.get(str(id))
		if manifest == null or String(manifest.get("world", "")).is_empty():
			continue
		var archive: String = manifest.dir.path_join(String(manifest.world))
		if not FileAccess.file_exists(archive):
			return "%s says it ships the world '%s', and that file is not in the mod" % [id, manifest.world]
		var error := WorldBackups.restore(archive, _save_dir)
		if not error.is_empty():
			return "%s's world could not be unpacked: %s" % [id, error]
		print("[server] Laid out %s's world from %s" % [id, String(manifest.world)])
		return ""  # the first mod asked for that has one; a game brings its own world, add-ons do not
	return ""


func _load_mods(requested: PackedStringArray, extra_dirs: PackedStringArray) -> Error:
	# External folders come first so a deployment can override bundled mods.
	var dirs := ModLoader.search_dirs(extra_dirs)
	var available := ModLoader.discover(dirs)
	if requested.is_empty():
		start_error = "No mods were chosen. This world does not say which game to run."
		printerr("[server] No mods requested. Available: %s" % ", ".join(available.keys()))
		return ERR_INVALID_PARAMETER
	var order := ModLoader.resolve(requested, available)
	if order.is_empty():
		var missing: Array = Array(requested).filter(func(id): return not available.has(id))
		start_error = "The mod '%s' is not installed." % missing[0] if not missing.is_empty() \
			else "The mods %s need something that is missing." % ", ".join(requested)
		return ERR_CANT_RESOLVE
	mod_order = order
	for manifest in order:
		dev_log.add_mod_dir(manifest.id, manifest.dir)
		mod_manifests[manifest.id] = manifest
		# Gathered before anything registers, which is the whole point: never-registered is safe where
		# registered-then-removed is not. Taking a block out afterwards shifts every id behind it and
		# leaves every recipe that named it dangling.
		for pattern in (manifest.excludes if manifest.get("excludes") is Array else []):
			_excludes.append(String(pattern))
	if not _excludes.is_empty():
		print("[server] excluding %s" % ", ".join(_excludes))
	# Which mod is the game is decided before any of them run, not after: a mod asking api.is_game() in
	# its own setup() - to decide whether to drive the music, say - would otherwise always be told no,
	# and would be told it silently. Nothing here needs a mod to have started; it is the requested list
	# and the manifests, both of which are known already.
	var game: Dictionary = available[requested[requested.size() - 1]]
	for id in requested:
		if available[id].game:
			game = available[id]
			break
	server_info.game = game.name
	server_info.game_id = game.id
	if server_info.description.is_empty():
		server_info.description = game.description
	for manifest in order:
		loot.load_files(manifest.id, manifest.dir)  # loot/*.json, before the mod runs so it can build on them
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
			start_error = "The mod '%s' has a mistake in %s and could not start." % [manifest.id, manifest.main]
			printerr("[server] Mod '%s' failed to load %s" % [manifest.id, manifest.main])
			return ERR_PARSE_ERROR
		var instance = script.new()
		if not instance.has_method("setup"):
			start_error = "The mod '%s' is missing its setup(api) function." % manifest.id
			printerr("[server] Mod '%s' has no setup(api) method" % manifest.id)
			return ERR_INVALID_DATA
		var mod_api := ModApi.new(self, manifest)
		_mod_apis[manifest.id] = mod_api  # kept so deferred work can run as the mod that asked for it
		# Anything raised in here is this mod's, however Godot happens to describe it.
		dev_log.current_mod = manifest.id
		instance.setup(mod_api)
		dev_log.drain()
		dev_log.current_mod = ""
		_mods.append(instance)
		mod_instances[manifest.id] = instance
		server_info.mods.append("%s@%s" % [manifest.id, manifest.version])
		print("[server] Loaded mod %s %s" % [manifest.id, manifest.version])
	return OK


func mod_storage(mod_id: String) -> Dictionary:
	if not _meta.mod_storage.has(mod_id):
		_meta.mod_storage[mod_id] = {}
	return _meta.mod_storage[mod_id]


## `lazy` assets are in the manifest but are not part of the download a player waits through to join.
## The client fetches one the first time something actually needs it. Music lives here: a track is
## megabytes where a texture is a few hundred bytes, and a child should not wait through the soundtrack
## to get into the world.
func add_asset(asset_name: String, path: String, lazy := false) -> void:
	if _assets.has(asset_name):
		# Something already asked for this file eagerly, and that wins: an asset needed to draw the world
		# cannot become optional because a second caller was relaxed about it.
		if not lazy:
			_assets[asset_name].lazy = false
		return
	if not FileAccess.file_exists(path):
		push_error("[server] Asset not found: %s (%s)" % [asset_name, path])
		return
	_assets[asset_name] = {"path": path, "lazy": lazy}


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
		if _assets[asset_name].get("lazy", false):
			_lazy_hashes[hash] = true


func set_rules(values: Dictionary) -> void:
	rules.apply_dict(values)
	_apply_rules_to_world()
	for p: ServerPlayer in players.values():
		_update_player_rules(p)
		if _started:
			Net.s_rules.rpc_id(p.peer_id, rules.to_dict())


func _apply_rules_to_world() -> void:
	rules.solid_lut = registry.solid_lut
	rules.shape_lut = registry.shape_lut
	rules.liquid_lut = registry.liquid_lut
	world.set_lookup_tables(registry.solid_lut, registry.liquid_lut, registry.shape_lut)
	world.void_below = rules.void_below
	entities.ai.update_tables()


# --- Events, commands, scheduler ----------------------------------------------------------------

## `owner`: the mod id (or "engine") the profiler and tracer credit.
func add_handler(event: String, handler: Callable, priority: int, owner := "engine") -> void:
	var list: Array = _handlers.get(event, [])
	list.append([priority, handler, owner])
	list.sort_custom(func(a, b): return a[0] > b[0])
	_handlers[event] = list


## Names a mod asked to be left out, from every manifest's `excludes`. Patterns may end in "*".
var _excludes: Array = []


## Whether a fully qualified name was excluded by some mod's manifest. Checked at registration, so an
## excluded thing is never given an id at all - and anything that later names it simply finds nothing,
## which is a warning rather than a dangling reference to an id that moved. (2026-09-21)
func is_excluded(full_name: String) -> bool:
	for pattern: String in _excludes:
		if pattern.ends_with("*"):
			if full_name.begins_with(pattern.left(pattern.length() - 1)):
				return true
		elif full_name == pattern:
			return true
	return false


func emit(event: String, payload: Dictionary) -> Dictionary:
	var list: Array = _handlers.get(event, [])
	if list.is_empty() and not dev_tools.tracing:
		return payload
	return dev_tools.dispatch(event, list, payload)


## permission: "" (everyone), "admin" (needs the "command.<name>" permission, which admins have) or any
## permission name (see engine/server/roles.gd).
func add_command(command: String, description: String, handler: Callable, mod_id: String, permission := "") -> void:
	# A command name and its description are both Strings sitting next to each other, so swapping them
	# type-checks and registers a command called "Fills your hotbar" that nobody can type. Whitespace
	# is the tell: no command has any, and every description does. Caught here rather than left to be
	# discovered by a child typing the command and getting nothing. (2026-09-21)
	if command.strip_edges() != command or " " in command or command.is_empty():
		push_error("[%s] register_command(%s): a command name cannot contain spaces - the name comes first, then the description." % [mod_id, JSON.stringify(command)])
		return
	_commands[command.to_lower()] = {"name": command.to_lower(), "description": description, "handler": handler, "mod": mod_id, "permission": permission}


## Whether a player may join: always when the allowlist is off; else admins and listed players (by id, or
## by name until that name first joins and binds the entry to the player's identity).
func is_allowed(player_id: String, player_name: String) -> bool:
	var list: Dictionary = _meta.get("allowlist", {})
	if not list.get("enabled", false):
		return true
	if _config_admins.has(player_id) or _config_admins.has(player_name.to_lower()) \
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


## Whether a player's roles grant a permission (config admins have everything).
func has_permission(p, permission: String) -> bool:
	if p == null:
		return false
	if _config_admins.has(p.player_id) or _config_admins.has(p.name.to_lower()):
		return true
	return roles.has(p.player_id, permission)


## Seconds since the server started ticking. What `schedule` measures against, so anything timing an
## event of its own should ask here rather than reach for a wall clock - a paused or slow server then
## counts the same time everything else does.
func uptime() -> float:
	return _time


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
	add_command("help", "[all | word] - the commands worth knowing, or search them", _cmd_help, "engine")
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
	add_command("realm", "[list | <id>] - the worlds on this server, and travel to one", _cmd_realm, "engine", "admin")
	add_command("perf", "[mods | tick | awake] - where the server's time is going", _cmd_perf, "engine", "admin")
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
	# The engine's own, because the admin panel's Time control calls it (see _run_panel_command). It
	# used to live in the vanilla mod, which meant the engine's panel quietly depended on a mod being
	# installed - found when that mod was deleted. (2026-09-21)
	add_command("time", "day | night | noon | midnight | <0-1> - set the time of day", func(player, args):
		var word: String = String(args[0]).to_lower() if not args.is_empty() else ""
		var at: float = {"day": 0.3, "noon": 0.5, "dusk": 0.75, "night": 0.9, "midnight": 0.0}.get(word, -1.0)
		if at < 0.0 and word.is_valid_float():
			at = fposmod(float(word), 1.0)
		if at < 0.0:
			player.send_message("Usage: /time day | night | noon | midnight | <0-1>")
			return
		set_world_time(float(at), get_day_length())
		player.send_message("set the time to %s" % (word if not word.is_empty() else "%.2f" % at)), "engine", "admin")
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
	# The twin of /hunger, which existed while this did not - so there was no way to look at anything
	# that depends on being hurt without going and getting hurt. (2026-09-22)
	add_command("health", "<0-20> [player] - set health", func(player, args):
		var target = _target_player(player, args, 1)
		if args.is_empty() or not args[0].is_valid_float():
			player.send_message("Usage: /health <0-20> [player]")
		elif target != null:
			target.health = clampf(float(args[0]), 0.0, target.max_health)
			sync_health(target), "engine", "admin")
	add_command("tutorial", "list | start <id> | skip | stop | tips on|off", _cmd_tutorial, "engine")
	add_command("milestones", "What you have done, and what is still out there", _cmd_milestones, "engine")
	add_command("music", "Who made the music this server plays", _cmd_music, "engine")
	add_command("weather", "<kind> [seconds] | clear - change the sky", _cmd_weather, "engine", "admin")
	add_command("wind", "<degrees> [strength] | drift - which way it blows", _cmd_wind, "engine", "admin")
	add_command("gamemode", "survival | creative [player]", _cmd_gamemode, "engine", "admin")
	add_command("fly", "Toggle flying (creative, or the \"fly\" permission)", _cmd_fly, "engine")
	add_command("kill", "Die and respawn", func(p, _args): kill_player(p, "command", null), "engine")
	add_command("gameplay", "[rule value] - show or change gameplay rules", _cmd_gameplay, "engine", "admin")
	add_command("conflicts", "- content two mods both claim", func(player, _args):
		var found: Array = conflicts.find()
		if found.is_empty():
			player.send_message("No two mods are standing on each other.")
			return
		for clash: Dictionary in found:
			player.send_message("%s" % String(clash.detail))
		player.send_message("%d in total. Any of these may be on purpose; excludes, a rename or a climate nudge fixes the ones that are not." % found.size()),
		"engine", "admin")
	add_command("modsettings", "[mod] [setting value|reset] - show or change what a mod lets you change", _cmd_mod_settings, "engine", "admin")
	add_command("loot", "rate <x> | boost <table or item> <x> [minutes] | clear | show - how much things drop", _cmd_loot, "engine", "admin")


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
		"minigames": skill.to_network(), "guide": guide.registry.to_network(), "tutorials": tutorials.to_network(),
		"loot": loot.sources_index()}
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


## Refuses a world this version cannot read, and stamps the format on one it can. There is no converter:
## a world older than alpha 4 is not something this game carries forward, and pretending to upgrade one
## by relabelling it - which is what used to happen here - is worse than saying so.
func _migrate_save_format() -> void:
	var format := int(_meta.get("format", SAVE_FORMAT))
	if format < SAVE_FORMAT:
		dev_log.add("warn", "server", "This world was saved in format %d; this version reads %d and cannot convert it." % [format, SAVE_FORMAT])
	_meta.format = SAVE_FORMAT


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
				# What the role is *for*, which the permission list never answered.
				if not str(def.get("description", "")).is_empty():
					player.send_message("    " + str(def.description))
			player.send_message("New players get: %s" % roles.default_role)
		"info":
			if not roles.exists(a1):
				player.send_message("No role called '%s'" % a1)
				return
			var def := roles.role(a1)
			if not str(def.get("description", "")).is_empty():
				player.send_message(str(def.description))
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


## Tells a client whether it is riding, and on what. The client stops predicting its own movement while
## it is, which is the whole reason this crosses the wire at all.
func tell_riding(p: ServerPlayer) -> void:
	if p == null or not players.has(p.peer_id):
		return
	var entity = entities.entities.get(p.riding) if p.riding > 0 else null
	if entity == null:
		Net.s_riding.rpc_id(p.peer_id, {})
		return
	var c := Vehicles.config(entity.def)
	Net.s_riding.rpc_id(p.peer_id, {"entity": int(entity.id), "seat_height": float(c.get("seat_height", 0.4)),
		"driver": Vehicles.riders_of(entity).find(String(p.player_id)) == 0})


func on_ride(peer_id: int, entity_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	if p.riding > 0:
		vehicles.dismount(p)
		return
	var entity = entities.entities.get(entity_id)
	if entity == null:
		return
	if not vehicles.mount(p, entity) and not vehicles.problem.is_empty():
		p.send_message(vehicles.problem)


## The online player with this id, or null. Two loops already did this by hand.
func player_by_id(player_id: String):
	for p: ServerPlayer in players.values():
		if p.player_id == player_id:
			return p
	return null


func _name_for(player_id: String) -> String:
	for p: ServerPlayer in players.values():
		if p.player_id == player_id:
			return p.name
	for n: String in _meta.names:
		if _meta.names[n] == player_id:
			return n
	return player_id.left(8)


## The handful worth knowing first. An owner can run forty commands, and printing all of them scrolls the
## chat log away before anyone can read it - which is what the welcome message used to send children to.
const HELP_FIRST := ["spawn", "sethome", "home", "back", "players", "time", "guide", "help"]


func _cmd_help(player, args: PackedStringArray) -> void:
	var names := _commands.keys()
	names.sort()
	var permitted: Array = names.filter(func(n): return _permitted(player, _commands[n]))
	var wanted := str(args[0]).to_lower() if args.size() > 0 else ""
	if wanted == "all":
		for n in permitted:
			player.send_message("/%s - %s" % [n, _commands[n].description])
		return
	if not wanted.is_empty():
		var found: Array = permitted.filter(func(n): return str(n).contains(wanted))
		if found.is_empty():
			player.send_message("No command like '%s'. Try /help for the usual ones, or /help all." % wanted)
		for n in found:
			player.send_message("/%s - %s" % [n, _commands[n].description])
		return
	player.send_message("Commands you will want:")
	for n in HELP_FIRST:
		if permitted.has(n):
			player.send_message("  /%s - %s" % [n, _commands[n].description])
	player.send_message("/help all lists every one (%d), /help <word> searches them." % permitted.size())


func _cmd_op(player, args: PackedStringArray, grant: bool) -> void:
	_cmd_role(player, PackedStringArray(["give" if grant else "take", args[0] if args.size() > 0 else "", "admin"]))


func _cmd_kick(player, args: PackedStringArray) -> void:
	var target = _find_online(args[0] if args.size() > 0 else "")
	if target == null:
		player.send_message("No online player named '%s'" % (args[0] if args.size() > 0 else ""))
		return
	kick(target.peer_id, " ".join(args.slice(1)) if args.size() > 1 else "Kicked by %s" % player.name)


## Attribution is required when a track is registered precisely so that this can exist. A player, or a
## parent, can always find out what they are listening to and under what licence.
func _cmd_music(player, _args: PackedStringArray) -> void:
	var lines := music.credits()
	if lines.is_empty():
		player.send_message("This server has no music.")
		return
	player.send_message("Music on this server:")
	for line in lines:
		player.send_message("  " + line)


func _cmd_wind(player, args: PackedStringArray) -> void:
	var now: Dictionary = wind_state()
	if args.is_empty():
		player.send_message("The wind is %d degrees at %d%%." % [int(now.angle), int(float(now.strength) * 100.0)])
		return
	if args[0] == "drift":
		wind_now.until = 0.0
		wind_now.drifting = true
		wind_now.next_drift = 0.0
		player.send_message("The wind is its own again.")
		return
	if not args[0].is_valid_float():
		player.send_message("Which way? A number of degrees, or 'drift' to let it wander.")
		return
	var strength := float(args[1]) if args.size() > 1 and args[1].is_valid_float() else 0.5
	set_wind(float(args[0]), strength)
	player.send_message("The wind turns to %d degrees at %d%%." % [int(wind_now.angle), int(float(wind_now.strength) * 100.0)])


func _cmd_weather(player, args: PackedStringArray) -> void:
	if args.is_empty():
		var now: Dictionary = weather_state()
		var names := []
		for d in weather.defs:
			names.append(str(d.name))
		player.send_message("Weather: %s. Kinds: %s" % [
			"clear" if str(now.name).is_empty() else "%s (%d%%)" % [now.name, roundi(float(now.intensity) * 100)],
			", ".join(names) if not names.is_empty() else "none on this server"])
		return
	if args[0] in ["clear", "none", "stop"]:
		set_weather("")
		player.send_message("The sky clears.")
		return
	var wanted := args[0] if args[0].contains(":") else ""
	if wanted.is_empty():
		for d in weather.defs:
			if str(d.name).get_slice(":", 1) == args[0]:
				wanted = str(d.name)
				break
	if weather.id_of(wanted) < 0:
		player.send_message("No weather called '%s'." % args[0])
		return
	set_weather(wanted, 1.0, float(args[1]) if args.size() > 1 and args[1].is_valid_float() else 0.0)
	player.send_message("Weather: %s." % wanted)


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
	var left: int = target.give_overflow(id, count)
	player.send_message("Gave %d %s to %s%s" % [count, items.display_name(id), target.name,
		" (%d of them at their feet - their pack is full)" % left if left > 0 else ""])


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
func set_flying(p: ServerPlayer, enabled: bool, deliberate := false) -> bool:
	if enabled and not may_fly(p, deliberate):
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
## Whether `p` may fly. `deliberate` is a command rather than a double-tap on the jump key: a game that
## turns flight off is saying "this is not a game you fly in", not "the admin may never fly", so an
## explicit `/fly` still goes through and an accidental double-tap does not.
func may_fly(p: ServerPlayer, deliberate := false) -> bool:
	if p.inventory.creative:
		return true
	return has_permission(p, "fly") and (deliberate or bool(gameplay.get("flight", true)))


func on_set_flying(peer_id: int, enabled: bool) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or p.dead:
		return
	if not set_flying(p, enabled):
		p.send_message("Flying is not allowed for you here (creative mode, or ask an admin for the \"fly\" permission)")


func _cmd_fly(player, _args: PackedStringArray) -> void:
	if not set_flying(player, not player.state.flying, true):
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
	var into: Realm = realm_of(player)
	for x in range(-4, 5):
		for y in range(-2, 4):
			for z in range(-4, 5):
				var cell := center + Vector3i(x, y, z)
				var block := into.world.get_block_v(cell)
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
		var data := get_block_data(cell, into).duplicate()
		data.portal = settings
		set_block_data(cell, data, into)
		for d in [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var next: Vector3i = cell + d
			var b := into.world.get_block_v(next)
			if not done.has(next) and registry.is_valid(b) and bool(registry.defs[b].get("portal", false)):
				todo.append(next)
	player.send_message("Portal (%d blocks) now leads to %s%s" % [done.size(), args[0], " at '%s'" % settings.arrival if not settings.arrival.is_empty() else ""])


## /realm            what worlds exist, and which one you are in
## /realm <id>       go to one, standing where you are standing now
## /perf         which mods are costing what, worst first
## /perf tick     where a tick goes, and how long the whole thing takes
## /perf awake    what is being kept awake, what it costs, and what the budget is
##
## The profiler has been here all along behind the dev dashboard, which means it was only reachable by
## somebody who knew to restart the server with --dev. A lag complaint arrives while people are
## playing, so the answer should too. (2026-09-19)
func _cmd_perf(player, args: PackedStringArray) -> void:
	var what := args[0].to_lower() if args.size() > 0 else "mods"
	match what:
		"tick":
			var m := _metrics
			if m.is_empty() or int(m.get("ticks", 0)) == 0:
				player.send_message("No tick figures yet - start the server with --metrics=10 to collect them.")
				return
			var average := float(m.total) / maxf(1.0, float(m.ticks)) / 1000.0
			var lines := ["Tick: %.2f ms average, %.2f ms worst, over %d ticks" % [average, float(m.max) / 1000.0, int(m.ticks)]]
			var sections: Dictionary = m.get("max_sections", {})
			var worst := sections.keys()
			worst.sort_custom(func(a, b): return float(sections[a]) > float(sections[b]))
			for key in worst.slice(0, 6):
				lines.append("  %s: %.2f ms in the worst tick" % [key, float(sections[key]) / 1000.0])
			player.send_message("\n".join(lines))
		"awake":
			var lines := ["Kept awake: %d us of tick allowed, %d claims" % [claims.budget_usec, claims.claims.size()]]
			var ids := claims.claims.keys()
			ids.sort_custom(func(a, b): return int(claims.claims[a].cost) > int(claims.claims[b].cost))
			for id in ids.slice(0, 8):
				var c: Dictionary = claims.claims[id]
				lines.append("  %s at %d, %d: %d us%s" % [c.name, int(c.centre.x), int(c.centre.z), int(c.cost),
					" (asleep: over budget)" if c.paused else ""])
			if ids.is_empty():
				lines.append("  nothing - no machine is running while nobody is there")
			player.send_message("\n".join(lines))
		_:
			var rows: Array = dev_tools.perf().filter(func(r: Dictionary) -> bool: return str(r.category) == "total")
			if rows.is_empty():
				player.send_message("Nothing has cost anything measurable in the last few seconds.")
				return
			var lines := ["Where the last %d seconds went, worst first:" % DevTools.WINDOWS]
			for row: Dictionary in rows.slice(0, 8):
				lines.append("  %s: %.2f ms/s over %d calls, worst single %.2f ms" % [row.owner, row.ms_per_s, int(row.calls), row.max_ms])
			lines.append("Try /perf tick for where a tick goes, or /perf awake for machines running unattended.")
			player.send_message("\n".join(lines))


func _cmd_realm(player, args: PackedStringArray) -> void:
	var here: Realm = realm_of(player)
	if args.is_empty() or args[0] == "list":
		var names := []
		for r: Realm in realms.values():
			var who := players.values().filter(func(p: ServerPlayer) -> bool: return realm_of(p) == r).size()
			names.append("%s%s (%s, %d here%s)" % ["-> " if r == here else "", r.display_name,
				r.id if not r.id.is_empty() else "overworld", who, ", asleep" if not r.is_awake() else ""])
		player.send_message("Worlds: %s" % ", ".join(names))
		return
	var wanted := args[0]
	if wanted == "overworld":
		wanted = ""
	if not realms.has(wanted):
		player.send_message("No world '%s' (/realm list)" % args[0])
		return
	if not send_to_realm(player, wanted, player.state.position):
		player.send_message("You are already in %s" % here.display_name)
		return
	player.send_message("You are in %s" % realms[wanted].display_name)


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


## /modsettings                      every mod's settings and what they are set to
## /modsettings <mod>                 one mod's, with what each one accepts
## /modsettings <mod> <key> <value>   change one (or "reset" to put it back to the default)
func _cmd_mod_settings(player, args: PackedStringArray) -> void:
	var which := args[0] if args.size() > 0 else ""
	if not which.is_empty() and not mod_settings.mods().has(which):
		player.send_message("No loaded mod called '%s' has settings (%s)" % [which, ", ".join(mod_settings.mods())])
		return
	if args.size() >= 3:
		var key := args[1]
		var value := " ".join(Array(args).slice(2))
		var problem := mod_settings.reset(which, key) if value == "reset" else mod_settings.set_value(which, key, value)
		if problem.is_empty():
			broadcast_chat("%s set %s's %s to %s" % [player.name, which, key, mod_settings.get_value(which, key)])
		else:
			player.send_message(problem)
		return
	var settings := mod_settings.list(which)
	if settings.is_empty():
		player.send_message("No mod has settings" if which.is_empty() else "%s has no settings" % which)
		return
	for entry: Dictionary in settings:
		var line := "%s %s = %s" % [entry.mod, entry.key, entry.value]
		if not which.is_empty():
			line += "  (%s; default %s)" % [ModSettings.describe(entry), entry.default]
		player.send_message(line)


## /loot                          what is turned up or down right now
## /loot rate 2                    everything drops twice as much
## /loot boost base:coal 3 60      coal three times as often, for an hour (an event)
## /loot boost vanilla:dungeon 2   richer dungeon chests, until it is changed back
## /loot clear                     back to normal
func _cmd_loot(player, args: PackedStringArray) -> void:
	match args[0].to_lower() if args.size() > 0 else "show":
		"rate":
			if args.size() < 2 or not args[1].is_valid_float():
				player.send_message("Usage: /loot rate <multiplier>, e.g. /loot rate 2")
				return
			loot.rate = clampf(args[1].to_float(), 0.0, 10.0)
			_meta.loot = {"rate": loot.rate, "boosts": loot.boosts}
			broadcast_chat("%s set how much things drop to %sx" % [player.name, loot.rate])
		"boost":
			if args.size() < 3 or not args[2].is_valid_float():
				player.send_message("Usage: /loot boost <table or item> <multiplier> [minutes]")
				return
			var minutes := args[3].to_float() if args.size() > 3 and args[3].is_valid_float() else 0.0
			var refused := loot.set_boost(args[1], args[2].to_float(), minutes * 60.0)
			if not refused.is_empty():
				player.send_message(refused)
				return
			_meta.loot = {"rate": loot.rate, "boosts": loot.boosts}
			broadcast_chat("%s made %s %sx more common%s" % [player.name, args[1], args[2],
				" for %d minutes" % int(minutes) if minutes > 0.0 else ""])
		"clear":
			loot.rate = 1.0
			loot.boosts = {}
			_meta.loot = {"rate": 1.0, "boosts": {}}
			broadcast_chat("%s put drops back to normal" % player.name)
		_:
			player.send_message("Everything drops %sx" % loot.rate)
			for boost: Dictionary in loot.active_boosts():
				player.send_message("  %s %sx%s" % [boost.target, boost.factor,
					" (%d minutes left)" % int(boost.ends_in / 60.0) if boost.ends_in > 0 else ""])


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
	if _simulation_dirty:
		_refresh_simulation()
	for r: Realm in realms.values():
		r.block_ticks.update(delta, r.simulated)
	var t_blocks := Time.get_ticks_usec()
	flows.settle()  # costs nothing on a tick where no network changed, which is nearly all of them
	drives.settle()
	parcels.update(delta)
	claims.update(delta)
	instances.update(delta)
	containers.update(delta)
	transfers.update(delta)
	ambience.update(delta)
	if float(weather_now.until) > 0.0 and _time >= float(weather_now.until):
		set_weather("")
	_drift_wind()
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
	# An empty realm costs nothing rather than costing a little. A server the children have logged off
	# from should be idle, and the realms nobody is in are free even when the server is busy.
	for r: Realm in realms.values():
		if r.is_awake():
			r.entities.tick(delta)
	for p: ServerPlayer in players.values():
		_update_health(p, delta)
	conditions.tick(delta)
	fields.tick(delta)
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
		# Each world replicates its own creatures to its own people; a realm nobody is in has nobody to
		# tell, which is most of why an empty one costs nothing.
		for r: Realm in realms.values():
			var watchers := players.values().filter(func(p: ServerPlayer) -> bool: return realm_of(p) == r)
			if not watchers.is_empty():
				r.entities.replicate(watchers)
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
	# Riding is the third of these: the rider's position comes from the vehicle and their input is
	# steering, so they do not walk. Beside dead and sleeping on purpose - a player who is not moving
	# themselves is a shape this function already knew. (2026-09-20)
	if p.riding > 0:
		vehicles.simulate(p)
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
		PlayerPhysics.step(p.state, input, realm_of(p).world, p.physics_rules if p.physics_rules != null else rules)
		p.last_processed_seq = input.seq
		budget -= 1
		p.input_credit -= 1.0
		steps += 1
		_track_fall(p, falling_speed)
	var tick_time := 1.0 / Engine.physics_ticks_per_second
	hunger.update(p, tick_time, p.state.position - start, steps * tick_time, was_on_ground)
	charging.update(p)  # a draw belongs to the item that started it
	if tick % 15 == 0 and p.state.on_ground and Vector2(p.state.velocity.x, p.state.velocity.z).length() > rules.walk_speed + 0.5:
		entities.ai.make_noise(p.state.position, 7.0, p)  # sprinting footsteps


func _track_fall(p: ServerPlayer, speed_before: float) -> void:
	var feet := realm_of(p).world.get_block(floori(p.state.position.x), floori(p.state.position.y + 0.2), floori(p.state.position.z))
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
	var pw = realm_of(p).world
	for dy in [0.2, 1.2]:
		var block := pw.get_block(floori(p.state.position.x), floori(p.state.position.y + dy), floori(p.state.position.z))
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
	broadcast_player_event(p, Entities.Event.HURT)
	if p.health <= 0.0:
		kill_player(p, cause, attacker)
	return true


func heal_player(p: ServerPlayer, amount: float) -> void:
	if p.dead or p.health >= p.max_health:
		return
	p.health = minf(p.health + amount, p.max_health)
	sync_health(p)


func sync_health(p: ServerPlayer, hurt := false) -> void:
	# One place rather than beside every call to this: damage and healing both come through here, and
	# so do respawn, the max-health clamp, loading and arriving from another server.
	nameplates.health_changed(p)
	# The post half of `player_damage`. The engine already keeps this convention - block_break has
	# block_broken, block_place has block_placed - and damage kept only the pre half, so nothing could
	# react to what health actually ended up being. (2026-09-21)
	emit("player_damaged", {"player": p, "health": p.health, "max_health": p.max_health,
		"hurt": hurt, "dead": p.dead})
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
	var attacker_type := str(attacker.def.name) if attacker != null and attacker.get("def") != null else ""
	var message := _death_message(p.name, cause, attacker_name, attacker_type)
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
	broadcast_player_event(p, Entities.Event.DEATH)
	play_sound_at("engine:death", p.get_eye_position())
	# Tell the player what happened to them and to their things, in that order. "You died!" on its own
	# leaves a child wondering what they did wrong and whether they have lost everything.
	var reasons := {"fall": "You landed hard", "void": "You dropped off the edge of the world",
		"starvation": "You were too hungry", "attack": "You were beaten in a fight", "mob": "You were beaten in a fight",
		"projectile": "You were shot", "lava": "You burned", "fire": "You burned", "drowning": "You ran out of air"}
	var belongings := "Your things are safe" if ev.keep_inventory or p.inventory.creative \
		else "Your things are where you died - press M for the map"
	p.show_title(str(reasons.get(cause, "You died")), belongings, 6.0)
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
	broadcast_player_event(p, Entities.Event.RESPAWN)


func broadcast_player_event(p: ServerPlayer, kind: int) -> void:
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
## Effects that are still going: handle -> {realm, effect, position, options}. Remembered so somebody
## who walks up to a running machine sees it working, rather than only those who were there when it
## started. (2026-09-20)
var _running_effects := {}
var _next_effect_handle := 1


## Starts an effect that keeps going until stop_effect. Returns a handle, or 0.
##
## For a machine that should smoke *while it runs*: play_effect is a burst and forgets itself, which
## cannot express "this is working now".
## Leaves a mark on the world for everyone near enough to see it.
func play_decal(pos: Vector3, normal: Vector3i, look := {}, realm_id := "") -> void:
	if not _started:
		return
	var clean := {"color": String(look.get("color", "#000000")),
		"size": clampf(float(look.get("size", 1.0)), 0.1, 8.0),
		"seconds": clampf(float(look.get("seconds", 0.0)), 0.0, 600.0)}
	for p: ServerPlayer in players.values():
		if realm_of(p).id == realm_id and p.state.position.distance_to(pos) <= 64.0:
			Net.s_decal.rpc_id(p.peer_id, pos, normal, clean)


## Draws a line between two places for a moment, for everyone near enough to see it.
func play_beam(from: Vector3, to: Vector3, look := {}, realm_id := "") -> void:
	if not _started:
		return
	var clean := {"color": String(look.get("color", "#ffffff")),
		"width": clampf(float(look.get("width", 0.08)), 0.01, 1.0),
		"seconds": clampf(float(look.get("seconds", 0.25)), 0.02, 10.0),
		"sag": clampf(float(look.get("sag", 0.0)), 0.0, 1.0)}
	var middle := (from + to) * 0.5
	var reach := 64.0 + from.distance_to(to) * 0.5
	for p: ServerPlayer in players.values():
		if realm_of(p).id == realm_id and p.state.position.distance_to(middle) <= reach:
			Net.s_beam.rpc_id(p.peer_id, from, to, clean)


func start_effect(effect_name: String, pos: Vector3, options := {}, realm_id := "") -> int:
	var id := effects.id_of(effect_name)
	if id < 0:
		return 0
	var handle := _next_effect_handle
	_next_effect_handle += 1
	var clean := EffectRegistry.clean_options(options)
	# Recorded whether or not there is a socket open. What the server knows is running is a fact about
	# the world; only telling somebody about it needs a network. (2026-09-20)
	_running_effects[handle] = {"realm": realm_id, "effect": id, "position": pos, "options": clean}
	if not _started:
		return handle
	var reach: float = effects.defs[id].range
	for p: ServerPlayer in players.values():
		if realm_of(p).id == realm_id and p.state.position.distance_to(pos) <= reach:
			Net.s_effect_start.rpc_id(p.peer_id, handle, id, pos, clean)
	return handle


func stop_effect(handle: int) -> bool:
	if not _running_effects.erase(handle):
		return false
	if not _started:
		return true
	for p: ServerPlayer in players.values():
		Net.s_effect_stop.rpc_id(p.peer_id, handle)
	return true


## Everything still going in a world, for somebody who has just arrived in it.
func _send_running_effects(p: ServerPlayer) -> void:
	if not _started:
		return
	var in_realm: String = realm_of(p).id
	for handle: int in _running_effects:
		var running: Dictionary = _running_effects[handle]
		if running.realm != in_realm:
			continue
		if p.state.position.distance_to(running.position) <= float(effects.defs[running.effect].range):
			Net.s_effect_start.rpc_id(p.peer_id, handle, running.effect, running.position, running.options)


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


## How far a floating word carries. Past this it is unreadable anyway, and sending it costs a packet
## to somebody who will never see it.
const TEXT_RANGE := 48.0


## Words that float in the world for a moment and then go: damage off a hit, "+3 copper" over a
## chest, a name over a thing. Transient on purpose - nothing is stored, nobody has to clean it up, and
## a client that was not listening has missed nothing that matters.
##
## options: color, seconds, rise (how far it drifts up), size, follow (a player or entity it sticks to).
func float_text(text: String, pos: Vector3, options := {}, realm_id := "") -> void:
	if not _started or text.is_empty():
		return
	var clean := {
		"color": String(options.get("color", "#ffffff")),
		"seconds": clampf(float(options.get("seconds", 1.2)), 0.1, 10.0),
		"rise": clampf(float(options.get("rise", 1.0)), -4.0, 8.0),
		"size": clampf(float(options.get("size", 1.0)), 0.3, 4.0),
	}
	var follow = options.get("follow")
	if follow is ServerPlayer:
		clean["follow_player"] = follow.peer_id
	elif follow != null and follow is Object and follow.get("id") is int:
		clean["follow_entity"] = follow.id
	var cut := text.left(64)
	for p: ServerPlayer in players.values():
		if p.realm_id == realm_id and p.state.position.distance_to(pos) <= TEXT_RANGE:
			Net.s_float_text.rpc_id(p.peer_id, cut, pos, clean)


## Tells a player (or everyone, when `p` is null) what music to play. -1 means stop. The track each
## player is on is remembered so a mod can call this on every biome change without restarting anything,
## and so a player who reconnects hears the same thing rather than silence.
func send_music(p, track_id: int, fade := 2.0, restart := false) -> void:
	var targets: Array = players.values() if p == null else [p]
	for target in targets:
		if target == null:
			continue
		if not restart and int(target.get_meta("music", -1)) == track_id:
			continue
		# Kept as metadata on the connection rather than in player data, which is written to the save:
		# what a player is listening to right now is not something a world should remember, and a
		# reconnecting client starts from silence and must be told again.
		target.set_meta("music", track_id)
		if target._online():
			Net.s_music.rpc_id(target.peer_id, track_id, clampf(fade, 0.0, 30.0), restart)


## Starts weather, or stops it with an empty name. `seconds` of 0 means until something says otherwise.
func set_weather(weather_name: String, intensity := 1.0, seconds := 0.0) -> void:
	var id: int = weather.id_of(weather_name) if not weather_name.is_empty() else -1
	if not weather_name.is_empty() and id < 0:
		push_error("[server] No weather called '%s'" % weather_name)
		return
	weather_now.id = id
	# A clear sky is not "no weather at full strength". Without this the state reads as intensity 1.0
	# with no weather in it, which is nonsense to anything asking, and the client fades from it wrongly.
	weather_now.intensity = clampf(intensity, 0.0, 1.0) if id >= 0 else 0.0
	weather_now.until = (_time + seconds) if seconds > 0.0 else 0.0
	_meta.weather = {"name": weather_name, "intensity": weather_now.intensity}
	for p: ServerPlayer in players.values():
		if p._online():
			Net.s_weather.rpc_id(p.peer_id, weather_now.id, float(weather_now.intensity))
	emit("weather_changed", {"weather": weather_name, "intensity": weather_now.intensity})


## Sets the wind: `degrees` clockwise from north, `strength` 0 (still) to 1 (a gale). `seconds` of 0
## means until something says otherwise, matching `set_weather`.
##
## While a mod holds the wind the engine stops drifting it, so a storm's gale does not wander off on
## its own halfway through.
func set_wind(degrees: float, strength := 0.5, seconds := 0.0) -> void:
	wind_now.angle = fposmod(degrees, 360.0)
	wind_now.strength = clampf(strength, 0.0, 1.0)
	wind_now.until = (_time + seconds) if seconds > 0.0 else 0.0
	wind_now.drifting = false
	_send_wind()
	emit("wind_changed", {"angle": float(wind_now.angle), "strength": float(wind_now.strength)})


## The wind as a mod sees it: {angle, strength}.
func wind_state() -> Dictionary:
	return {"angle": float(wind_now.angle), "strength": float(wind_now.strength)}


## Nudges the wind along when nothing is holding it, and hands it back when a mod's hold runs out.
##
## Only sent when it has moved enough to see - a degree of heading or a hundredth of strength is below
## what any shader will show, and sending it would be a packet a tick for nothing.
func _drift_wind() -> void:
	if float(wind_now.until) > 0.0 and _time >= float(wind_now.until):
		wind_now.until = 0.0
		wind_now.drifting = true
	if not bool(wind_now.drifting):
		return
	if _time < float(wind_now.get("next_drift", 0.0)):
		return
	wind_now.next_drift = _time + randf_range(20.0, 60.0)
	var angle := fposmod(float(wind_now.angle) + randf_range(-35.0, 35.0), 360.0)
	var strength := clampf(float(wind_now.strength) + randf_range(-0.18, 0.18), 0.05, 0.75)
	if absf(angle - float(wind_now.angle)) < 1.0 and absf(strength - float(wind_now.strength)) < 0.01:
		return
	wind_now.angle = angle
	wind_now.strength = strength
	_send_wind()


func _send_wind() -> void:
	for p: ServerPlayer in players.values():
		if p._online():
			Net.s_wind.rpc_id(p.peer_id, float(wind_now.angle), float(wind_now.strength))


## The weather as a mod sees it: {name, intensity}. "" when the sky is clear.
func weather_state() -> Dictionary:
	var id: int = weather_now.id
	return {"name": weather.defs[id].name if weather.is_valid(id) else "",
		"intensity": float(weather_now.intensity)}


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
	# One world at a time. Somebody in the Emberdeep is not far away from somebody in the overworld,
	# they are not there at all, and interest radius cannot express that - they may be standing on the
	# same coordinates. Grouping here rather than teaching the builder about realms is deliberate: the
	# native snapshot code and its GDScript twin must agree exactly, and neither has to change.
	if realms.size() == 1:
		_send_snapshots_to(players.values(), full_rate)
		return
	var by_realm := {}
	for p: ServerPlayer in players.values():
		if not by_realm.has(p.realm_id):
			by_realm[p.realm_id] = []
		by_realm[p.realm_id].append(p)
	for group: Array in by_realm.values():
		_send_snapshots_to(group, full_rate)


func _send_snapshots_to(list: Array, full_rate: bool) -> void:
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


## Other players per snapshot (20 bytes each), nearest first, so a crowd stays under the network MTU.
const SNAPSHOT_MAX_PLAYERS := 64

func _advance_time(delta: float) -> void:
	if _day_length > 0.0:
		var was := WorldTime.phase(_time_of_day)
		_time_of_day = fposmod(_time_of_day + delta / _day_length, 1.0)
		# `weather_changed` existed and its time equivalent did not, so three bundled mods polled
		# get_daylight() every five seconds to notice nightfall. Only on a crossing, not every tick.
		# (2026-09-21)
		var now := WorldTime.phase(_time_of_day)
		if now != was:
			emit("time_changed", {"phase": now, "previous": was, "time_of_day": _time_of_day,
				"daylight": WorldTime.daylight(_time_of_day)})
	_time_sync_timer += delta
	if _time_sync_timer >= TIME_SYNC_INTERVAL:
		_time_sync_timer = 0.0
		_broadcast_time()


## `time_of_day`: 0 = midnight, 0.25 = sunrise, 0.5 = noon. `day_length` in seconds, 0 = frozen.
func set_world_time(time_of_day: float, day_length: float) -> void:
	var was := WorldTime.phase(_time_of_day)
	_time_of_day = fposmod(time_of_day, 1.0)
	_day_length = maxf(day_length, 0.0)
	_broadcast_time()
	# Setting the clock counts as crossing: /time night should wake whatever nightfall wakes.
	if WorldTime.phase(_time_of_day) != was:
		emit("time_changed", {"phase": WorldTime.phase(_time_of_day), "previous": was,
			"time_of_day": _time_of_day, "daylight": WorldTime.daylight(_time_of_day)})


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
	# Only a real peer may start a join. 0 is Godot's broadcast id and a negative id means "everyone but
	# this one", so either would turn the replies below - including a kick - into messages to the whole
	# server. Net._sender() hands out 0 for a peer that is flooding. (security review, 2026-09-18)
	if peer_id <= 1:
		return
	if players.has(peer_id) or _joining.has(peer_id):
		return
	if protocol != Protocol.VERSION:
		kick(peer_id, "This server runs Quarrowen %s. Your game is a different version - update it from quarrowen.com and try again."
			% Protocol.GAME_VERSION)
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
		kick(peer_id, "Someone else here is already called '%s'. Pick a different name under 'Playing as' in the main menu." % clean_name)
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
		kick(peer_id, "This server only lets in players on its list. Ask whoever runs it to add '%s' - and check that is the name under 'Playing as' in the main menu." % j.name)
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
			manifest.append([asset_name, a.hash, a.size, 1 if a.get("lazy", false) else 0])
	var content := {"blocks": registry.to_network(), "items": items.to_network(), "rules": rules.to_dict(),
		"entities": entities.registry.to_network(), "sounds": sounds.to_network(), "music": music.to_network(), "weather": weather.to_network(),
		"equipment_slots": items.slots.duplicate(true), "stats": items.stats.duplicate(),
		"player_rig": player_rig, "cosmetics": cosmetics.to_network(), "effects": effects.to_network(), "recipes": recipes.to_network(), "processes": _processes,
		"stations": stations.to_network(), "assembly": assembly.to_network(), "minigames": skill.to_network(), "guide": guide.registry.to_network(), "tutorials": tutorials.to_network(),
		"loot": loot.sources_index()}
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


## How many lazy assets one player may have in flight. A player in the world can ask for these at any
## time, unlike the single join burst, so the queue is short on purpose: serving assets is pure egress,
## and a peer that asks in a loop should cost a trickle rather than a bill.
const LAZY_QUEUE := 4
const LAZY_BYTES_PER_TICK := 48 * 1024

## peer_id -> {queue, offset} for players in the world fetching lazy assets (music).
var _lazy_streams := {}


func on_request_assets(peer_id: int, hashes: PackedStringArray) -> void:
	var j: Dictionary = _joining.get(peer_id, {})
	if j.is_empty() or j.requested or not j.authenticated:
		# Not joining: a player already in the world asking for a lazy asset. Only lazy ones - the eager
		# assets went out with the join, and re-serving them on request is free bandwidth for a stranger.
		if players.has(peer_id):
			var stream: Dictionary = _lazy_streams.get(peer_id, {"queue": [], "offset": 0})
			_lazy_streams[peer_id] = stream
			for hash in hashes.slice(0, LAZY_QUEUE):
				if stream.queue.size() >= LAZY_QUEUE:
					break
				if _asset_bytes.has(hash) and not stream.queue.has(hash) and _lazy_hashes.has(hash):
					stream.queue.append(hash)
		return
	j.requested = true
	for hash in hashes.slice(0, Protocol.MAX_ASSETS):
		if _asset_bytes.has(hash) and not j.queue.has(hash):
			j.queue.append(hash)


## Hashes of lazy assets, as a set. Built with the hashes rather than searched for per request: this is
## reached from a network handler, and a scan of every asset per message is how a cheap message becomes
## an expensive one.
var _lazy_hashes := {}


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
	for peer_id: int in _lazy_streams.keys():
		var stream: Dictionary = _lazy_streams[peer_id]
		if not players.has(peer_id):
			_lazy_streams.erase(peer_id)
			continue
		var budget := LAZY_BYTES_PER_TICK
		while budget > 0 and not stream.queue.is_empty():
			var hash: String = stream.queue[0]
			var bytes: PackedByteArray = _asset_bytes[hash]
			var piece := bytes.slice(stream.offset, stream.offset + Protocol.ASSET_PIECE_SIZE)
			Net.s_asset_piece.rpc_id(peer_id, hash, stream.offset, bytes.size(), piece)
			stream.offset += piece.size()
			budget -= maxi(piece.size(), 1)
			if stream.offset >= bytes.size():
				stream.queue.pop_front()
				stream.offset = 0


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
		p.load_items(saved.get("items", {}))
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
		# A realm a mod no longer registers puts them back in the overworld rather than nowhere: the
		# position is meaningless there, but the overworld is at least somewhere to stand.
		p.realm_id = String(saved.get("realm", ""))
		if not realms.has(p.realm_id):
			p.realm_id = ""
	players[peer_id] = p
	_simulation_dirty = true
	if first_time:
		p.state.position = spawn_handler.call(p) if spawn_handler.is_valid() else _default_spawn()
	elif rejoin_handler.is_valid():
		var at = rejoin_handler.call(p, p.state.position)
		if at is Vector3 and at != Vector3.INF:
			p.state.position = at
	if not transfer.is_empty() and transfers.arrival_position(transfer) != Vector3.INF:
		p.state.position = transfers.arrival_position(transfer)
	ensure_area_loaded(p.state.position, realm_of(p))

	Net.s_welcome.rpc_id(peer_id, peer_id, p.state.position, 0.0)
	var strung := links_for(realm_of(p).id)
	if not strung.is_empty():
		Net.s_links.rpc_id(peer_id, strung)
	_send_running_effects(p)
	_set_client_avatar(p, avatar, true)
	Net.s_cosmetics.rpc_id(peer_id, PackedStringArray(p.owned_cosmetics.keys()), cosmetics.policy)
	Net.s_known_recipes.rpc_id(peer_id, PackedStringArray(p.known_recipes.keys()), gameplay.recipe_discovery)
	Net.s_time.rpc_id(peer_id, _time_of_day, _day_length)
	# Somebody joining halfway through a storm arrives in it, rather than in sunshine everyone else lost.
	if int(weather_now.id) >= 0:
		Net.s_weather.rpc_id(peer_id, int(weather_now.id), float(weather_now.intensity))
	Net.s_wind.rpc_id(peer_id, float(wind_now.angle), float(wind_now.strength))
	p.sync_inventory()
	refresh_stats(p)
	sync_health(p)
	hunger.set_hunger(p, p.hunger)  # applies the no-sprint modifier when starving
	hunger.sync(p, true)
	guide.sync(p)
	objectives.sync(p)  # a task list they were halfway through is the first thing they look for
	for other: ServerPlayer in players.values():
		if other != p:
			Net.s_player_joined.rpc_id(peer_id, other.peer_id, other.name)
			Net.s_player_joined.rpc_id(other.peer_id, peer_id, player_name)
			Net.s_player_appearance.rpc_id(peer_id, other.peer_id, other.appearance)
			Net.s_player_appearance.rpc_id(other.peer_id, peer_id, p.appearance)
	if not server_info.motd.is_empty():
		p.send_message(server_info.motd)
	broadcast_chat("%s is here" % player_name)
	print("[server] %s joined (peer %d, player id %s%s)" % [player_name, peer_id, player_id, ", admin" if is_admin(p) else ""])
	# Before the event, so a mod asking what somebody is under during player_join gets the truth.
	conditions.resume(p)
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
	ambience.player_left(peer_id)
	anticheat.player_left(peer_id)
	characters.player_left(peer_id)
	shops.player_left(peer_id)
	companions.player_left(peer_id)
	if p.riding > 0:
		vehicles.dismount(p)  # a rider who logs off leaves the boat where it is, rather than inside it
	conditions.before_save(p)  # how long is *left*, since server time restarts with the server
	conditions.forget(p)
	_store_player(p)
	players.erase(peer_id)
	_simulation_dirty = true
	for other: ServerPlayer in players.values():
		Net.s_player_left.rpc_id(other.peer_id, peer_id)
	if p.get_meta("transferring", false):
		broadcast_chat("%s travelled to %s" % [p.name, p.get_meta("transferring")])
	else:
		broadcast_chat("%s has gone" % p.name)
	print("[server] %s left (peer %d)" % [p.name, peer_id])


func kick(peer_id: int, reason: String) -> void:
	if peer_id <= 1:
		return  # 0 is the broadcast id: "kicking" it throws everybody off the server
	print("[server] Kicking peer %d: %s" % [peer_id, reason])
	Net.s_kick.rpc_id(peer_id, reason)
	# Delay the disconnect so the kick message is flushed first.
	get_tree().create_timer(0.2).timeout.connect(_disconnect_peer.bind(peer_id))


func _disconnect_peer(peer_id: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer and multiplayer.get_peers().has(peer_id):
		peer.disconnect_peer(peer_id)


# --- Chunk streaming ----------------------------------------------------------------------------

## Which world a player is standing in. The one place that answers this, so that when players really
## do belong to a realm it is one function that changes rather than every caller. Until then everybody
## is in the overworld, which is exactly what the server did before realms existed.
## The drawable links in a realm, as the client wants them. A wireless link draws nothing, so it is
## not sent at all - there is no point putting it on the wire to be ignored.
func _broadcast_link(id: int) -> void:
	var link: Dictionary = links.links.get(id, {})
	if link.is_empty():
		return
	var drawable := links_for(String(link.a.realm)).filter(func(e: Dictionary) -> bool: return int(e.id) == id)
	if drawable.is_empty():
		return  # wireless, or a kind that draws nothing
	for p: ServerPlayer in players.values():
		if realm_of(p).id == String(link.a.realm):
			Net.s_links.rpc_id(p.peer_id, drawable)


func _broadcast_link_gone(id: int, realm_id: String) -> void:
	for p: ServerPlayer in players.values():
		if realm_of(p).id == realm_id:
			Net.s_link_gone.rpc_id(p.peer_id, id)


func links_for(realm_id: String) -> Array:
	var out := []
	for id: int in links.links:
		var link: Dictionary = links.links[id]
		var kind: Dictionary = links.kinds.get(link.kind, {})
		if kind.is_empty() or String(kind.get("draw", "")).is_empty():
			continue
		if link.a.realm != realm_id or link.b.realm != realm_id:
			continue
		out.append({"id": id, "draw": kind.draw, "color": String(kind.get("color", "#b87333")),
			"a": Vector3(link.a.position) + Vector3(0.5, 0.5, 0.5) + Vector3(Links.FACE_OFFSETS[link.a.face]) * 0.5,
			"b": Vector3(link.b.position) + Vector3(0.5, 0.5, 0.5) + Vector3(Links.FACE_OFFSETS[link.b.face]) * 0.5})
	return out


## Says the simulated set needs working out again. Claims call it; so does anything else that changes
## which part of the world should be running.
func mark_simulation_stale() -> void:
	_simulation_dirty = true


## What each spinning block was last *told* to be doing, so a speed that wobbles does not become a
## message every tick. A windmill follows the wind, which changes constantly and by tiny amounts.
var _drive_sent := {}
## How finely a speed is reported. Two hundredths of a turn is far below what an eye can tell apart on
## a spinning wheel, and it turns "the wind moved a hair" into no message at all. (2026-09-20)
const DRIVE_STEP := 0.02


## A face is being driven at a new speed: tell whoever is standing in that world and holds the chunk.
## Only for blocks that say they turn, because telling a client about a shaft it will not animate is
## bytes spent on nothing.
## Everything an assembly is made of, once, to whoever is in that world.
func tell_assembly(id: int) -> void:
	var assembly: Dictionary = assemblies.assemblies.get(id, {})
	if assembly.is_empty():
		return
	var packed := PackedInt32Array()
	for cell: Dictionary in assembly.cells:
		var at: Vector3i = cell.offset
		packed.append_array([int(cell.block), at.x, at.y, at.z, int(cell.state)])
	for p: ServerPlayer in players.values():
		if realm_of(p).id == assembly.realm:
			Net.s_assembly.rpc_id(p.peer_id, id, assembly.origin, packed)


## Where it has got to. Unreliable and ordered, like movement: a position that arrives late is worth
## nothing, and the next one is along in a moment.
func tell_assembly_moved(id: int) -> void:
	var assembly: Dictionary = assemblies.assemblies.get(id, {})
	if assembly.is_empty():
		return
	for p: ServerPlayer in players.values():
		if realm_of(p).id == assembly.realm:
			Net.s_assembly_at.rpc_id(p.peer_id, id, assembly.offset)


func tell_assembly_gone(id: int) -> void:
	for p: ServerPlayer in players.values():
		Net.s_assembly_gone.rpc_id(p.peer_id, id)


func drive_changed(node: Dictionary, value: float) -> void:
	var pos: Vector3i = node.position
	var in_realm: String = String(node.get("realm", ""))
	var world_of: Realm = realms.get(in_realm)
	if world_of == null:
		return
	var block: int = world_of.world.get_block_v(pos)
	if not registry.is_valid(block) or (registry.defs[block].get("spins") as Dictionary).is_empty():
		return
	# Rounded before comparing: a wheel that speeds up and slows with the wind would otherwise send a
	# message for every hair's breadth of change, which is exactly the cost this design avoids.
	var rounded := snappedf(value, DRIVE_STEP)
	if is_equal_approx(float(_drive_sent.get(pos, 0.0)), rounded):
		return
	if absf(rounded) < DRIVE_STEP:
		_drive_sent.erase(pos)
	else:
		_drive_sent[pos] = rounded
	var coord := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	var where := PackedVector3Array([Vector3(pos)])
	var how_fast := PackedFloat32Array([rounded])
	for p: ServerPlayer in players.values():
		if realm_of(p).id == in_realm and p.sent_chunks.has(coord):
			Net.s_drives.rpc_id(p.peer_id, where, how_fast)


## Takes a realm out of the server. Only for instances: a realm a mod declared is part of the world
## and stays for the session.
##
## Everything a realm owns hangs off the Realm object - its world, its entities, its tickers - so
## dropping the reference is most of the job. What is not automatic is the simulated set, which is
## rebuilt from players, and anything holding the realm id.
func remove_realm(realm_id: String) -> bool:
	var going: Realm = realms.get(realm_id)
	if going == null or going.is_overworld():
		return false
	realms.erase(realm_id)
	# Claims name their realm by id, and a claim on a realm that no longer exists would keep asking
	# for chunks nobody can load. Dropped here rather than left to `awake_chunks` to skip, so nothing
	# accumulates across a long session of dungeon runs.
	for claim_id in claims.claims.keys():
		if String(claims.claims[claim_id].realm) == realm_id:
			claims.claims.erase(claim_id)
	_simulation_dirty = true
	return true


func realm_of(p: ServerPlayer) -> Realm:
	return realms.get(p.realm_id, realm)


## Moves a player to another world, standing at `position`. Portals, the command and the mod API all
## end here, so the order below is the only place it has to be right.
##
## Returns false when there is no such realm, or they are already in it.
func send_to_realm(p: ServerPlayer, realm_id: String, position: Vector3) -> bool:
	var into: Realm = realms.get(realm_id)
	if into == null or p.realm_id == realm_id:
		return false
	var from := realm_of(p)
	var ev: Dictionary = emit("player_realm_change", {"player": p, "from": from.id, "to": realm_id,
		"position": position, "cancelled": false})
	if bool(ev.get("cancelled", false)):
		return false
	position = ev.get("position", position)

	# Everybody watching loses sight of them: they are not somewhere else in this world, they are not
	# in it at all. Told before the move so the message describes a world they are both still in.
	for other: ServerPlayer in players.values():
		if other.peer_id != p.peer_id and realm_of(other) == from:
			Net.s_player_left.rpc_id(other.peer_id, p.peer_id)

	p.realm_id = realm_id
	p.state.position = position
	p.state.velocity = Vector3.ZERO
	p.fall_velocity = 0.0

	# Then the client, which drops the whole world it is holding - and only then may a chunk of the new
	# one be sent. Both travel on BULK_CHANNEL so this order survives the wire (see Net.s_realm).
	Net.s_realm.rpc_id(p.peer_id, into.id, into.display_name)
	var arriving := links_for(into.id)
	if not arriving.is_empty():
		Net.s_links.rpc_id(p.peer_id, arriving)
	p.sent_chunks.clear()
	p.pending_chunks.clear()
	p.stream_center = Vector2i(1 << 30, 0)  # no chunk coordinate, so the next tick rebuilds the list
	p.known_entities.clear()
	p.known_entities_stale = true
	_simulation_dirty = true
	ensure_area_loaded(position, into)
	emit("player_arrived_realm", {"player": p, "from": from.id, "to": realm_id})
	return true


func _build_view_offsets() -> void:
	_view_offsets = _disc(view_distance)
	_view_offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.length_squared() < b.length_squared())
	_simulation_offsets = _disc(simulation_distance)


## Works out which chunks of each realm are close enough to somebody to run. Rebuilt only when
## somebody crosses a chunk boundary, joins or leaves, since between those it is the same answer.
##
## This is deliberately not the same set as the chunks that stay loaded: a player is sent terrain out
## to `view_distance` and it stays in memory a margin beyond that, but only `simulation_distance`
## around them actually ticks. Walking away from a farm stops it rather than unloading it.
func _refresh_simulation() -> void:
	_simulation_dirty = false
	for r: Realm in realms.values():
		r.simulated.clear()
	for p: ServerPlayer in players.values():
		var into: Realm = realm_of(p)
		var center := VoxelWorld.chunk_coord_of(p.state.position)
		for offset in _simulation_offsets:
			into.simulated[center + offset] = true
	# And whatever is being kept awake on somebody's behalf. This is the only way a realm with nobody
	# in it runs at all, which is why is_awake() asks the simulated set rather than counting players.
	for r: Realm in realms.values():
		for coord: Vector2i in claims.awake_chunks(r.id):
			r.simulated[coord] = true


## Chunk offsets within `radius` chunks, as a disc rather than a square, so a player is not sent (or
## running) a great deal more world diagonally than straight ahead.
func _disc(radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if x * x + z * z <= radius * radius + radius:
				out.append(Vector2i(x, z))
	return out


func _stream_chunks(p: ServerPlayer) -> void:
	var center := VoxelWorld.chunk_coord_of(p.state.position)
	if center != p.stream_center:
		p.stream_center = center
		_simulation_dirty = true
		p.pending_chunks.clear()
		for offset in _view_offsets:
			var coord := center + offset
			if not p.sent_chunks.has(coord):
				p.pending_chunks.append(coord)
		for coord: Vector2i in p.sent_chunks.keys():
			var d := coord - center
			if maxi(absi(d.x), absi(d.y)) > view_distance + UNLOAD_MARGIN:
				p.sent_chunks.erase(coord)
				Net.s_unload_chunk.rpc_id(p.peer_id, coord)

	# Send the nearest chunks that are ready; ask workers to prepare the ones that are not.
	var into: Realm = realm_of(p)
	var sends := 0
	var i := 0
	while i < p.pending_chunks.size() and i < STREAM_SCAN and sends < CHUNK_SENDS_PER_PLAYER_PER_TICK:
		var coord: Vector2i = p.pending_chunks[i]
		var chunk = into.world.chunks.get(coord)
		if chunk == null:
			_request_chunk(into, coord)
			i += 1
			continue
		p.pending_chunks.remove_at(i)
		p.sent_chunks[coord] = true
		Net.s_chunk.rpc_id(p.peer_id, coord, chunk.encode(), chunk.encode_states())
		sends += 1


## Starts loading/generating a chunk on a worker thread if capacity allows. The worker budget is the
## machine's, not each world's, so a second realm loading its spawn cannot take a core per realm.
func _request_chunk(into: Realm, coord: Vector2i) -> void:
	if into.world.chunks.has(coord) or into.chunk_jobs.has(coord) or _running_chunk_jobs() >= _max_chunk_jobs:
		return
	var job := _make_chunk_job(into, coord)
	job.task_id = WorkerThreadPool.add_task(_run_chunk_job.bind(job), false, "chunk %s %s" % [into.id, coord])
	into.chunk_jobs[coord] = job


func _running_chunk_jobs() -> int:
	var running := 0
	for r: Realm in realms.values():
		running += r.chunk_jobs.size()
	return running


## Everything the worker needs, copied out of the realm here on the main thread - the job must not
## reach back into a realm while another tick is changing it.
func _make_chunk_job(into: Realm, coord: Vector2i) -> Dictionary:
	return {"coord": coord, "realm": into.id, "path": into.chunk_path(coord), "generator": into.generator,
		"passes": into.generation_passes, "seed": into.seed_value, "result": {}, "task_id": -1,
		"scan_ids": into.block_ticks.scan_ids()}


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
	for r: Realm in realms.values():
		for coord: Vector2i in r.chunk_jobs.keys():
			var job: Dictionary = r.chunk_jobs[coord]
			if WorkerThreadPool.is_task_completed(job.task_id):
				WorkerThreadPool.wait_for_task_completion(job.task_id)
				r.chunk_jobs.erase(coord)
				_integrate_chunk(job)


func _integrate_chunk(job: Dictionary) -> void:
	var r: Dictionary = job.result
	var into: Realm = realms.get(job.realm)
	if into == null or into.world.chunks.has(job.coord) or r.is_empty():
		return
	# A freshly generated chunk can never legitimately hold UNLOADED, so finding one means a generator
	# wrote an id it never had - almost always `api.block("...")` called before that block was
	# registered, which returns -1 and encodes as exactly this. One native byte search per chunk, and
	# it turns "the player falls for ever" into a sentence naming the cause. (2026-09-21)
	if Chunk.contains(r.chunk.blocks, BlockRegistry.UNLOADED):
		push_error("Generator for realm '%s' wrote an unknown block id at chunk %s: check that every "
			% [into.id, job.coord] + "api.block(...) it uses is registered before the generator is made")
	into.world.add_chunk(r.chunk)
	into.block_ticks.load_chunk(job.coord, r.tickable, r.lights, r.ticks)
	if not r.deltas.is_empty():
		into.deltas[job.coord] = r.deltas
		into.generated[job.coord] = r.generated
	if not r.data.is_empty():
		into.block_data[job.coord] = r.data
	if not r.entities.is_empty():
		into.entity_chunks[job.coord] = true
		into.entities.load_chunk(r.entities)
	# Emitted once the chunk is fully live, so a mod indexing machines by position finds them present.
	# mods/industry rebuilt its whole power network every five seconds for want of this. (2026-09-21)
	emit("chunk_loaded", {"realm": into.id, "chunk": job.coord})
	if not _metrics.is_empty():
		_metrics.gen += 1
		_metrics.gen_usec += r.usec


## Returns the chunk, loading or generating it synchronously if needed.
func _ensure_chunk(coord: Vector2i, into: Realm = null):
	if into == null:
		into = realm
	var chunk = into.world.chunks.get(coord)
	if chunk != null:
		return chunk
	var job: Dictionary = into.chunk_jobs.get(coord, {})
	if job.is_empty():
		job = _make_chunk_job(into, coord)
		_run_chunk_job(job)
	else:
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		into.chunk_jobs.erase(coord)
	_integrate_chunk(job)
	return into.world.chunks.get(coord)


## Loads the chunks around a position so players placed there have ground to stand on.
func ensure_area_loaded(pos: Vector3, into: Realm = null) -> void:
	var center := VoxelWorld.chunk_coord_of(pos)
	for x in range(-1, 2):
		for z in range(-1, 2):
			_ensure_chunk(center + Vector2i(x, z), into)


func _unload_unused_chunks() -> void:
	# Worked out per realm: a chunk the overworld needs says nothing about the same coordinate in the
	# Emberdeep, and a realm nobody is in keeps only its spawn.
	var needed := {}
	var margin := view_distance + UNLOAD_MARGIN
	for p: ServerPlayer in players.values():
		var in_realm: String = realm_of(p).id
		if not needed.has(in_realm):
			needed[in_realm] = {}
		var center := VoxelWorld.chunk_coord_of(p.state.position)
		for x in range(-margin, margin + 1):
			for z in range(-margin, margin + 1):
				needed[in_realm][center + Vector2i(x, z)] = true
	if _queued_chunks() > 0 or _save_meta_pending:
		# A save in progress holds chunks serialized earlier; they must reach the disk before newer copies below.
		_drain_save_queue(-1)
	var writes := []
	for r: Realm in realms.values():
		var keep: Dictionary = needed.get(r.id, {})
		# The spawn area stays loaded everywhere, so arriving in a realm never lands on nothing.
		for x in range(-SPAWN_RADIUS, SPAWN_RADIUS + 1):
			for z in range(-SPAWN_RADIUS, SPAWN_RADIUS + 1):
				keep[Vector2i(x, z)] = true
		for coord: Vector2i in r.world.chunks.keys():
			if keep.has(coord):
				continue
			var records: Array = r.entities.unload_chunk(coord)
			if r.save_dirty.has(coord) or r.block_data.has(coord) or not records.is_empty() or r.entity_chunks.has(coord) \
					or r.block_ticks.save_chunk(coord) != null:
				writes.append(_serialize_chunk(r, coord, records))
			r.block_ticks.unload_chunk(coord)
			r.signals.unload_chunk(coord)
			r.entity_chunks.erase(coord)
			r.save_dirty.erase(coord)
			r.deltas.erase(coord)
			r.generated.erase(coord)
			r.block_data.erase(coord)
			r.world.remove_chunk(coord)
			emit("chunk_unloaded", {"realm": r.id, "chunk": coord})
	if not writes.is_empty():
		_write_async(writes, false)


# --- World access for mods ----------------------------------------------------------------------

## Every function here takes the world to act in, and `null` means the overworld. A position alone
## does not say which world any more - the same coordinates exist in all of them - so anything acting
## for a player passes `realm_of(p)`, and anything acting for a creature passes its realm.
func get_block_loaded(pos: Vector3i, into: Realm = null) -> int:
	into = into if into != null else realm
	if pos.y >= 0 and pos.y < Chunk.SIZE_Y:
		_ensure_chunk(VoxelWorld.chunk_coord_at(pos.x, pos.z), into)
	return into.world.get_block_v(pos)


func set_block_authoritative(pos: Vector3i, id: int, keep_data := false, state := 0, into: Realm = null) -> void:
	into = into if into != null else realm
	if not registry.is_valid(id):
		# Said out loud rather than refused quietly. `id_of` returns -1 for a name it does not know, and
		# -1 stored as the u16 a block id is *becomes 65535, which is UNLOADED* - so a bad id used to
		# mean "this chunk is not here" rather than "that block does not exist". (2026-09-21)
		push_error("set_block: %d is not a block id (from id_of on a name that is not registered?)" % id)
		return
	if pos.y < 0 or pos.y >= Chunk.SIZE_Y:
		return
	_ensure_chunk(VoxelWorld.chunk_coord_at(pos.x, pos.z), into)
	if into.world.get_block_v(pos) != id or into.block_state(pos) != state:
		_apply_block(pos, id, keep_data, state, into)


## Y of the highest solid or liquid block in the column (loading it if needed), or -1. Plants and
## other non-solid decorations are skipped, so things placed on the surface stand on the ground.
func surface_height(x: int, z: int, into: Realm = null) -> int:
	into = into if into != null else realm
	_ensure_chunk(VoxelWorld.chunk_coord_at(x, z), into)
	for y in range(Chunk.SIZE_Y - 1, -1, -1):
		var block := into.world.get_block(x, y, z)
		if block != BlockRegistry.AIR and (registry.solid_lut[block] == 1 or registry.liquid_lut[block] == 1):
			return y
	return -1


## Targetable blocks *and* liquids, for a mod that needs to find the surface of water. Built once and
## thrown away whenever the registry changes, because block ids move when mods are added or reloaded.
var _liquid_ray_lut := PackedByteArray()


func raycast_lut_with_liquids() -> PackedByteArray:
	if _liquid_ray_lut.size() != registry.targetable_lut.size():
		_liquid_ray_lut = registry.targetable_lut.duplicate()
		for id in registry.liquid_lut.size():
			if registry.liquid_lut[id] == 1:
				_liquid_ray_lut[id] = 1
	return _liquid_ray_lut


func get_block_state(pos: Vector3i, into: Realm = null) -> int:
	return (into if into != null else realm).block_state(pos)


# --- Block data (block entities) ----------------------------------------------------------------

## Live dictionary for the block at `pos`, or an empty one if it has none. Mutations to a returned
## dictionary are saved; call set_block_data to attach data to a block that has none yet.
func get_block_data(pos: Vector3i, into: Realm = null) -> Dictionary:
	into = into if into != null else realm
	return into.block_data.get(VoxelWorld.chunk_coord_at(pos.x, pos.z), {}).get(pos, {})


func set_block_data(pos: Vector3i, data: Dictionary, into: Realm = null) -> void:
	into = into if into != null else realm
	var coord := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	_ensure_chunk(coord, into)
	if not into.block_data.has(coord):
		into.block_data[coord] = {}
	into.block_data[coord][pos] = data
	into.save_dirty[coord] = true


func clear_block_data(pos: Vector3i, into: Realm = null) -> void:
	into = into if into != null else realm
	var coord := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	var entries: Dictionary = into.block_data.get(coord, {})
	if entries.erase(pos):
		into.save_dirty[coord] = true
		if entries.is_empty():
			into.block_data.erase(coord)


## Positions of loaded blocks that have data, optionally only of one block type.
func find_block_data(block := -1, into: Realm = null) -> Array[Vector3i]:
	into = into if into != null else realm
	var out: Array[Vector3i] = []
	for entries: Dictionary in into.block_data.values():
		for pos: Vector3i in entries:
			if block < 0 or into.world.get_block_v(pos) == block:
				out.append(pos)
	return out


## What the server says when somebody dies. A few of each, picked at random and never the same one twice
## in a row, so it stays light rather than becoming a drone - dying is already annoying enough.
##
## The rules these follow, for whoever adds more: say what happened, never who deserved it. Nothing about
## how anyone looks, speaks, believes, or who they are; no teasing, no "noob", no gloating on a mob's
## behalf. A child reading their own name in chat should smile, and so should the one who killed them.
const DEATH_LINES := {
	"fall": ["%s landed hard", "%s found the ground in a hurry", "%s forgot about gravity", "%s tried flying"],
	"void": ["%s dropped off the edge of the world", "%s went looking for the bottom", "%s fell out of everything"],
	"starvation": ["%s ran out of food", "%s should have packed a snack", "%s went hungry"],
	"drowning": ["%s ran out of air", "%s stayed under too long", "%s forgot to come up"],
	"lava": ["%s found the hot rock", "%s went for a swim in the wrong thing"],
	"fire": ["%s got too warm", "%s should have stepped back"],
	"explosion": ["%s was standing a bit too close", "%s heard the bang from very nearby"],
	"attack": ["%s lost a fight with %s", "%s came second to %s", "%s was no match for %s today"],
	"mob": ["%s lost a fight with %s", "%s was caught out by %s", "%s met %s and did not come back"],
	"projectile": ["%s was hit by an arrow from %s", "%s did not see %s taking aim"],
	"magic": ["%s was out-sparkled by %s", "%s ran into something magical"],
	"": ["%s died", "%s is having a day of it", "%s needs a moment"],
}
## The last line used for each pool, so the same one never comes round twice running.
var _last_death_line := {}
## Lines mods added, by cause ("lava") or by the entity that did it ("mymod:dragon"). Theirs are used
## alongside the engine's, so a mod colours its own mobs without taking the rest away.
var _mod_death_lines := {}


## Adds ways of saying somebody died (see ModApi.add_death_messages). `key` is a cause, or the name of an
## entity so a mod's own mob gets its own send-off; "%s" is the player, and a second "%s" is what did it.
func add_death_messages(key: String, lines: Array) -> void:
	var clean := []
	for line in lines:
		var text := str(line).strip_edges().left(160)
		if text.count("%s") in [1, 2] and not text.is_empty():
			clean.append(text)
	if clean.is_empty():
		return
	var existing: Array = _mod_death_lines.get(key, [])
	existing.append_array(clean)
	_mod_death_lines[key] = existing


func _death_message(who: String, cause: String, attacker_name: String, attacker_type := "") -> String:
	# A mod's lines for its own mob come first, then anything it added for this cause, then the engine's.
	var lines: Array = []
	if not attacker_type.is_empty():
		lines.append_array(_mod_death_lines.get(attacker_type, []))
	lines.append_array(_mod_death_lines.get(cause, []))
	lines.append_array(DEATH_LINES.get(cause, DEATH_LINES[""]))
	# A line naming the attacker is no use when there is not one.
	var usable: Array = lines.filter(func(line): return not attacker_name.is_empty() or String(line).count("%s") == 1)
	if usable.is_empty():
		usable = DEATH_LINES[""]
	var pool := attacker_type if not attacker_type.is_empty() else cause
	var fresh: Array = usable.filter(func(line): return line != _last_death_line.get(pool, ""))
	var line: String = str((fresh if not fresh.is_empty() else usable).pick_random())
	_last_death_line[pool] = line
	return line % ([who, attacker_name] if line.count("%s") == 2 else [who])


## A find worth noticing: a sparkle where it landed, a sound for whoever found it, and a line in chat so
## the rest of the server shares the moment. The sparkle repeats for a little while, so a rare drop in
## long grass can still be found. Rarity comes from the table's own weights - nothing is marked by hand.
func announce_rare_loot(player, item: int, count: int, position: Vector3) -> void:
	var display := items.display_name(item)
	play_effect("engine:sparkle", position + Vector3(0, 0.4, 0), {"scale": 1.4})
	play_sound_at("engine:discover", position)
	if player != null and player._online():
		player.send_message("✦ You found %s%s!" % ["%d × " % count if count > 1 else "", display])
		broadcast_chat("✦ %s found %s" % [player.name, display])
	var left := [5]
	var marker := [0]
	marker[0] = schedule(2.5, func():
		play_effect("engine:sparkle", position + Vector3(0, 0.4, 0), {"scale": 0.7})
		left[0] -= 1
		if left[0] <= 0:
			cancel_task(marker[0]), 2.5)


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
	var into := realm_of(p)
	var current := into.world.get_block_v(pos)
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
	break_block_for(p, pos, into, harvest)


## Breaks one block *on a player's behalf*: the pre-event, the loot roll, the drops, the tool wear, the
## hunger and the post-event, exactly as breaking it by hand does.
##
## Split out of `on_break_block` so area tools get all of that without copying it. What stays with the
## caller is what an area tool decides differently: reach and mining time are per-block questions when
## you are swinging at one, and whole-selection questions when you are not. Everything below here is
## the same either way. (2026-09-21)
func break_block_for(p: ServerPlayer, pos: Vector3i, into: Realm, harvest := true) -> bool:
	var current := into.world.get_block_v(pos)
	if current == BlockRegistry.AIR or current == BlockRegistry.UNLOADED or registry.breakable_lut[current] == 0:
		return false
	var held := p.inventory.selected_item()
	var held_data: Dictionary = p.inventory.data[p.inventory.selected]
	# Rolled without consequences until the break really happens: a cancelled break, or a creative player
	# who keeps nothing, must not use up a pity streak or announce a find nobody received.
	var loot_context := {"player": p, "tool": held, "cause": "player", "position": Vector3(pos), "source": "block"}
	var loot_table := loot.table_for_block(current, _default_drops(current))
	var ev := emit("block_break", {"player": p, "position": pos, "block": current, "item": held, "slot": p.inventory.selected,
		"drops": loot.preview(loot_table, loot_context) if harvest and not p.inventory.creative else [], "cancelled": false})
	if ev.cancelled:
		_reject_edit(p, pos)
		return false
	if harvest and not p.inventory.creative and ev.drops is Array:
		loot.awarded(loot_table, ev.drops, loot_context)
	_apply_block(pos, BlockRegistry.AIR, false, 0, into)
	into.entities.ai.make_noise(Vector3(pos) + Vector3.ONE * 0.5, 10.0, p)
	play_sound_at(block_sound(current, "break"), Vector3(pos) + Vector3.ONE * 0.5, 1.0, randf_range(0.85, 1.1), p.peer_id)
	if not p.inventory.creative and ev.drops is Array:
		for drop in ev.drops:
			if not (drop is Array and drop.size() >= 2 and items.is_valid(int(drop[0]))):
				continue
			var data: Dictionary = drop[2] if drop.size() > 2 and drop[2] is Dictionary else {}
			if gameplay.item_drops == "entity":
				entities.drop_item(int(drop[0]), int(drop[1]), Vector3(pos) + Vector3(0.5, 0.3, 0.5),
					Vector3(randf_range(-1.0, 1.0), randf_range(2.0, 3.5), randf_range(-1.0, 1.0)), 0.3, data)
			else:
				p.inventory.add(int(drop[0]), int(drop[1]), items.max_stack(int(drop[0])), data)
		if registry.defs[current].hardness > 0.0 and items.max_durability(held, held_data) > 0:
			damage_item(p, p.inventory.selected, 1, "mine")
		hunger.add_exhaustion(p, Hunger.BREAK_BLOCK)
		p.sync_inventory()
	emit("block_broken", {"player": p, "position": pos, "block": current, "item": held, "slot": p.inventory.selected, "harvested": harvest})
	return true


func on_place_block(peer_id: int, pos: Vector3i, yaw: float) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var into := realm_of(p)
	var block := p.inventory.selected_block()
	var current := into.world.get_block_v(pos)
	if block > 0 and not _may(p, "build", "You can't build on this server"):
		_reject_edit(p, pos)
		return
	var valid: bool = _can_edit(p, pos) and block > 0 and registry.placeable_lut[block] == 1 \
		and _can_replace(current) and _has_solid_neighbor(pos, into) and is_supported(pos, block, into)
	var state := BlockRegistry.facing_from_yaw(yaw) if valid and registry.defs[block].orientation == 1 and is_finite(yaw) else 0
	# Stairs and the like: the carried block places the variant that faces the player.
	var variants: Array = registry.defs[block].get("facing_blocks", []) if valid else []
	if variants.size() == 4 and is_finite(yaw):
		var variant := registry.id_of(str(variants[BlockRegistry.facing_from_yaw(yaw)]))
		if variant > 0:
			block = variant
	# Slabs: the half you aimed at. Clicking the underside of something, or the upper half of a side,
	# puts the slab in the top half of the cell, the way stairs already follow where you are looking.
	var top_name := str(registry.defs[block].get("top_block", "")) if valid else ""
	if not top_name.is_empty() and _aimed_high(p, pos):
		var top := registry.id_of(top_name)
		if top > 0:
			block = top
	# Two slabs make a whole block: putting one on the flat face of another of the same material fills
	# that cell instead of starting a second slab beside it, which is what anyone laying a floor expects.
	var merge := _slab_merge(p, block, pos) if valid else {}
	if not merge.is_empty():
		p.inventory.consume_selected()
		if not p.inventory.creative:
			p.sync_inventory()
		_apply_block(merge.position, merge.block, true, 0, into)
		_reject_edit(p, pos)  # the client guessed the cell next door; put it back
		play_sound_at(block_sound(merge.block, "place"), Vector3(merge.position) + Vector3.ONE * 0.5, 1.0, randf_range(0.85, 1.1))
		broadcast_player_event(p, Entities.Event.SWING)
		emit("block_placed", {"player": p, "position": merge.position, "block": merge.block})
		return

	# Two-block pieces (beds) also need room for their other half.
	var pair = registry.defs[block].get("pair") if valid else null
	var pair_pos := pos
	var pair_block := 0
	if pair is Dictionary:
		pair_pos = pos + pair_offset(pair, state)
		pair_block = registry.id_of(str(pair.block))
		valid = pair_block > 0 and _can_edit(p, pair_pos) and _can_replace(into.world.get_block_v(pair_pos)) and is_supported(pair_pos, pair_block, into)
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
	_apply_block(pos, block, false, state, into)
	if pair_block > 0:
		_apply_block(pair_pos, pair_block, false, state, into)
	if not str(registry.defs[block].get("station", "")).is_empty():
		sessions.claim(pos, p)
	into.entities.ai.make_noise(Vector3(pos) + Vector3.ONE * 0.5, 8.0, p)
	play_sound_at(block_sound(block, "place"), Vector3(pos) + Vector3.ONE * 0.5, 1.0, randf_range(0.85, 1.1), peer_id)
	broadcast_player_event(p, Entities.Event.SWING)
	emit("block_placed", {"player": p, "position": pos, "block": block})


## Places one block *on a player's behalf* at a chosen cell, for area tools.
##
## Deliberately not `on_place_block`'s path. Almost everything in that function is about placing the
## thing you are *holding* where you are *aiming* - the slab that merges with the slab below, the
## stair that turns to face you, the bed that needs room for its other half - and none of it means
## anything when a mod names a block and a cell. What does carry over is what protects the world:
## the block must be placeable, the cell replaceable, the result supported, and nobody standing in it.
##
## `_has_solid_neighbor` is the one hand-placement rule left out on purpose. It stops a player
## hanging blocks in mid-air off nothing; an area fill building a floating platform is doing that
## deliberately, and one cell at a time would refuse its own interior. (2026-09-21)
func place_block_for(p: ServerPlayer, pos: Vector3i, block: int, into: Realm) -> bool:
	if block <= 0 or not registry.is_valid(block) or registry.placeable_lut[block] == 0:
		return false
	if not _can_replace(into.world.get_block_v(pos)) or not is_supported(pos, block, into):
		return false
	if registry.solid_lut[block] == 1:
		for other: ServerPlayer in players.values():
			if not other.dead and PlayerPhysics.overlaps_block(other.state.position, pos):
				return false
	# Survival pays for what it builds. Creative does not, and neither runs out mid-selection without
	# the caller being told: `apply` stops as soon as this returns false.
	if not p.inventory.creative and p.inventory.count_of(_item_for_block(block)) <= 0:
		return false
	if emit("block_place", {"player": p, "position": pos, "block": block, "cancelled": false}).cancelled:
		return false
	if not p.inventory.creative:
		p.inventory.remove(_item_for_block(block), 1)
	_apply_block(pos, block, false, 0, into)
	play_sound_at(block_sound(block, "place"), Vector3(pos) + Vector3.ONE * 0.5, 0.7, randf_range(0.85, 1.1))
	emit("block_placed", {"player": p, "position": pos, "block": block})
	return true


## The item that places a block, for paying for an area fill. Block and item ids are separate spaces,
## so this asks the registry rather than assuming they line up.
func _item_for_block(block: int) -> int:
	var by_name := items.id_of(registry.defs[block].name)
	return by_name if by_name > 0 else block


func on_interact(peer_id: int, pos: Vector3i) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	var block := realm_of(p).world.get_block_v(pos)
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
	if charging.start(p, item):  # held rather than clicked: fires on release (see Charging)
		return
	var teaches: Array = p.inventory.data[p.inventory.selected].get("teaches", items.get_def(item).get("teaches", []))
	if teaches is Array and not teaches.is_empty():
		_read_blueprint(p, teaches)
		return
	if has_target and (not realm_of(p).world.has_chunk(VoxelWorld.chunk_coord_at(target.x, target.z)) \
			or p.get_eye_position().distance_to(Vector3(target) + Vector3.ONE * 0.5) > REACH + 0.87):
		has_target = false
	broadcast_player_event(p, Entities.Event.SWING)
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
		charging.release(p)


func on_open_menu(peer_id: int, menu: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	if menu == "crafting":
		open_crafting(p, {})
	elif menu == "palette":
		open_palette(p)


## Everything that exists, for a creative player to take from.
##
## **A creative game ships no recipes**, so the recipe book - which is how a player finds out what
## exists - is empty in exactly the game where finding out what exists matters most. This is the
## other half of that: a browser of every block and item, grouped the way they were registered.
##
## Sent rather than derived on the client because the client does not know which items a mod meant
## to be takeable; `hidden` on a definition keeps the plumbing out (block data holders, half-slabs
## that are placed rather than carried). (2026-09-22)
func open_palette(p: ServerPlayer) -> void:
	if not _started or not p._online():
		return
	Net.s_palette.rpc_id(p.peer_id, palette_groups())


## What the palette lists, split out from the sending so a test can read it.
##
## **The first version of this listed nothing at all, for two reasons, and shipped that way**
## (written 2026-09-22, found 2026-09-23). Both are worth keeping, because both look right:
##
##   - `range(ItemRegistry.FIRST_ITEM, items.defs.size())` reads like "every item", and is
##     `range(65536, 30)` - **empty**. Item ids start at `FIRST_ITEM` and run to
##     `FIRST_ITEM + defs.size()`; `defs.size()` on its own is a count, not an end.
##   - It looked for blocks by asking which *items* are also blocks. None are, and none can be:
##     a block **is** its own item id (below `FIRST_ITEM`), and `items.register` refuses a name a
##     block already holds. So that branch could never have been true.
##
## What made it survive is the sharper lesson: the Proving Ground asserted that a creative player
## could *take* from the palette, which worked, and never that the palette *listed* anything. Half a
## feature tested is a feature that reports itself working.
##
## `group` on a definition names the drawer. Without one, blocks and items fall into two default
## drawers - which is all a small mod wants, and is what every mod had before this existed.
func palette_groups() -> Dictionary:
	var groups := {}
	for id in registry.defs.size():
		if palette_lists(id):
			_palette_add(groups, registry.defs[id], id, "Blocks")
	for index in items.defs.size():
		var id := ItemRegistry.FIRST_ITEM + index
		if palette_lists(id):
			_palette_add(groups, items.defs[index], id, "Items")
	return groups


## Whether the palette offers this id at all - asked by the listing *and* by the handing out, so the
## two can never disagree about what is takeable. They disagreeing is the bug class that produced an
## empty palette in the first place.
func palette_lists(id: int) -> bool:
	if id >= ItemRegistry.FIRST_ITEM:
		var item: Dictionary = items.get_def(id)
		return not item.is_empty() and not bool(item.get("hidden", false))
	if id == BlockRegistry.AIR or id < 0 or id >= registry.defs.size():
		return false
	var def: Dictionary = registry.defs[id]
	# `placeable` is already false on every half and state a player never carries - the top of a
	# door, a pane's other axis, a lit furnace - so the palette gets that distinction for free
	# rather than needing a second flag that would drift out of step with it.
	return not bool(def.get("hidden", false)) and bool(def.get("placeable", true))


## Files one entry under "<mod>/<group>". By mod first so two mods' stone never merge into one
## drawer under a name they happened to share.
func _palette_add(groups: Dictionary, def: Dictionary, id: int, fallback: String) -> void:
	var owner := String(def.get("name", "")).get_slice(":", 0)
	var named := String(def.get("group", ""))
	var group := "%s/%s" % [owner, named if not named.is_empty() else fallback]
	if not groups.has(group):
		groups[group] = PackedInt32Array()
	groups[group].append(id)


## A creative player asking for a stack of something from the palette.
func on_palette_take(peer_id: int, item: int, whole_stack: bool) -> void:
	var p: ServerPlayer = players.get(peer_id)
	# Creative only, and checked here rather than trusted from the client: this hands out items.
	if p == null or not p.inventory.creative or not items.is_valid(item):
		return
	# The same question the listing asks. Asking it a second way here is how a block the palette
	# refuses to show stayed takeable by a client that simply sent its id.
	if not palette_lists(item):
		return
	p.inventory.cursor_id = item
	p.inventory.cursor_count = items.max_stack(item) if whole_stack else 1
	p.inventory.cursor_data = {}
	p.sync_inventory()


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


## Shown as a panel rather than chat lines: this is the one screen a child goes to to feel pleased with
## themselves, and a wall of grey text does not do that.
func _cmd_milestones(player, _args: PackedStringArray) -> void:
	var rows := milestones.view(player)
	var children: Array = [{"type": "label", "text": "What you have done", "size": 22, "color": "#ffd166"}]
	if rows.is_empty():
		children.append({"type": "label", "text": "Nothing to chase yet. This world's mods have set no milestones."})
	var done := 0
	for row in rows:
		if row.done:
			done += 1
			children.append({"type": "label", "text": "✦ %s" % row.title, "color": "#8ce99a"})
			children.append({"type": "label", "text": "    %s" % row.description, "size": 12, "color": "#9aa4b8"})
		else:
			var progress := "" if row.goal <= 1 else "  (%d of %d)" % [row.progress, row.goal]
			children.append({"type": "label", "text": "○ %s%s" % [row.title, progress], "color": "#c9b896"})
	if not rows.is_empty():
		children.append({"type": "spacer", "size": 6})
		children.append({"type": "label", "text": "%d of %d" % [done, rows.size()], "size": 12, "color": "#9aa4b8"})
	children.append({"type": "button", "text": "Close", "action": "close"})
	player.show_ui("engine:milestones", {"anchor": "center", "modal": true, "children": children})


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
	var ray := VoxelRaycast.cast(realm_of(p).world, registry.solid_lut, eye, center - eye, eye.distance_to(center))
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
	broadcast_player_event(p, Entities.Event.SWING)
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
	if ev.cancelled:
		return
	# Getting on comes before taming and feeding: a horse you have already tamed should carry you when
	# you click it, not sit down.
	if vehicles.is_vehicle(e) and vehicles.mount(p, e):
		return
	if not entities.taming.interact(p, e):
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
	elif containers.holds_open_bag(p, slot):
		# The bag you are looking into cannot be picked up while you are looking into it: its address
		# is the slot it sits in, so moving it would leave the screen pointing at whatever landed
		# there. Refusing is simpler to explain than re-addressing mid-click. (2026-09-21)
		return
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
	var block := realm_of(p).world.get_block_v(pos)
	if block == BlockRegistry.UNLOADED or registry.breakable_lut[block] == 0:
		return
	p.mining = {"position": pos, "started": _time}
	broadcast_player_event(p, Entities.Event.SWING)
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
## Which world a player is in. One world today ("" is it); mods that add dimensions set this key on the
## player, and the map, compass and markers follow them there.
func dimension_of(p) -> String:
	return str(p.data.get("dimension", "")) if p != null else ""


## What the player's map shows: everyone in the same dimension (unless the server hides them) and the
## markers mods set, also filtered to that dimension.
func on_map(peer_id: int) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null or not p._online():
		return
	var here := dimension_of(p)
	var people := []
	if gameplay.share_positions or has_permission(p, "admin"):
		for other: ServerPlayer in players.values():
			if dimension_of(other) == here:
				people.append({"name": other.name, "position": other.state.position, "you": other == p})
	else:
		people.append({"name": p.name, "position": p.state.position, "you": true})
	var markers := []
	for id: String in world_markers:
		var shared: Dictionary = world_markers[id]
		if str(shared.get("dimension", "")) != here:
			continue
		var at = shared.get("position", [0, 0, 0])
		markers.append({"id": id, "label": shared.get("label", id), "color": shared.get("color", "#ffd166"),
			"position": Vector3(float(at[0]), float(at[1]), float(at[2])) if at is Array and at.size() == 3 else Vector3.ZERO})
	for id: String in map_markers.get(p.player_id, {}):
		var marker: Dictionary = map_markers[p.player_id][id]
		if str(marker.get("dimension", "")) != here:
			continue
		markers.append({"id": id, "label": marker.get("label", id), "position": marker.get("position", Vector3.ZERO),
			"color": marker.get("color", "#ffd166")})
	Net.s_map.rpc_id(peer_id, {"players": people, "markers": markers, "spawn": _default_spawn(), "dimension": here})


## The worlds panel: the servers this one is linked to (network.json), and travel.
func on_worlds_panel(peer_id: int, action: String, args: Dictionary) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if p == null:
		return
	if action == "travel":
		_cmd_server(p, PackedStringArray([str(args.get("server", ""))]))
	if not p._online():
		return
	var may_send := has_permission(p, "command.transfer")
	var list := []
	for entry: Dictionary in transfers.servers.values():
		if not entry.send:
			continue
		list.append({"key": entry.key, "name": entry.name, "carries_inventory": entry.inventory,
			"allowed": entry.hop or may_send, "here": false})
	list.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	list.push_front({"key": "", "name": str(server_info.name), "carries_inventory": false, "allowed": false, "here": true})
	Net.s_worlds.rpc_id(peer_id, {"worlds": list, "hint": "Portals lead to these too (/portal <world> points one at a world)."})


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
		"modset":
			var mod_args := PackedStringArray([str(args.get("mod", "")), str(args.get("key", "")), str(args.get("value", ""))])
			_run_panel_command(p, "modsettings", mod_args)
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
		"mod_settings": mod_settings.list(),
		"mod_names": _mod_titles(mod_settings.mods()),
	})


## Display names for mod ids, for the settings screen's section headings.
func _mod_titles(ids: Array) -> Dictionary:
	var out := {}
	for id in ids:
		out[id] = str(mod_manifests.get(id, {}).get("name", id))
	return out


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
	p.physics_rules.shape_lut = rules.shape_lut
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
	if s.is_empty() or not s.has("position") or str(registry.defs[realm_of(p).world.get_block_v(s.position)].get("station", "")) != s.name:
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
	for pos: Vector3i in find_block_data(-1, realm_of(p)):
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
## Recipes with a tag input are held back while mods load, because a mod loading later may add to the
## tag, and then written out as one real recipe per member.
##
## Written out rather than matched at craft time on purpose: the recipe book can then show a child
## exactly what to put where, which "any of eleven things" cannot. The cost is the product of the tags
## in one recipe, so it is capped, and a recipe that would go past the cap is refused loudly rather
## than quietly making three hundred entries nobody wants to scroll past.
const MAX_TAG_RECIPES := 64


func defer_tag_recipe(entry: Dictionary) -> void:
	_tag_recipes.append(entry)


func _expand_tag_recipes() -> void:
	for entry: Dictionary in _tag_recipes:
		var api = _api_for(str(entry.mod))
		if api == null:
			continue
		# Each tag input becomes a list of choices; the recipe is written once per combination.
		var fixed := {}
		var choices := []  # [[input name, [member names]], ...]
		var missing := false
		for input_name: String in entry.inputs:
			if not input_name.begins_with("#"):
				fixed[input_name] = entry.inputs[input_name]
				continue
			var tag_name := input_name.substr(1)
			var names: Array = tags.names_in(tag_name)
			if names.is_empty():
				dev_log.add("warn", entry.mod, "recipe for %s wants tag '%s', which nothing has put anything in" % [entry.output, tag_name])
				missing = true
				break
			names.sort()  # so the recipe book is in the same order every run
			choices.append([input_name, names, int(entry.inputs[input_name])])
		if missing:
			continue
		var combinations := 1
		for choice in choices:
			combinations *= (choice[1] as Array).size()
		if combinations > MAX_TAG_RECIPES:
			dev_log.add("error", entry.mod, "recipe for %s would make %d recipes from its tags (limit %d)"
				% [entry.output, combinations, MAX_TAG_RECIPES])
			continue
		for n in combinations:
			var inputs := fixed.duplicate()
			var rest := n
			var suffix := ""
			for choice in choices:
				var names: Array = choice[1]
				var picked: String = names[rest % names.size()]
				rest /= names.size()
				inputs[picked] = int(inputs.get(picked, 0)) + int(choice[2])
				suffix += "_" + picked.get_slice(":", 1) if picked.contains(":") else "_" + picked
			var options: Dictionary = entry.options.duplicate(true)
			# A distinct id per combination, or they overwrite one another in the recipe book.
			options.id = str(options.get("id", str(entry.output).get_slice(":", 1))) + suffix
			api._register_recipe_now(inputs, str(entry.output), int(entry.count), options)
	_tag_recipes.clear()


## The mod API object a mod is using, so a deferred recipe is registered as that mod rather than as
## the engine - its id, its permissions, its name in the recipe book. Held here rather than asked of
## the mod, because a mod is not obliged to keep a reference to its own api and several do not.
func _api_for(owner: String):
	return _mod_apis.get(owner)


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
## Called from containers.gd when a container a station draws from changed. Public because it is
## reached across files: a leading underscore that another script calls is a lie about what is private.
func refresh_crafting_stock(pos: Vector3i) -> void:
	for p: ServerPlayer in players.values():
		if not p.crafting_station.has("position") or not p._online():
			continue
		var d: Vector3i = p.crafting_station.position - pos
		if absi(d.x) <= STATION_PULL_RADIUS and absi(d.y) <= STATION_PULL_RADIUS and absi(d.z) <= STATION_PULL_RADIUS:
			Net.s_crafting_stock.rpc_id(p.peer_id, crafting_stock(p))


func on_ui_action(peer_id: int, ui_id: String, action: String) -> void:
	var p: ServerPlayer = players.get(peer_id)
	if not p or not p.ui_ids.has(ui_id):
		return
	emit("ui_action", {"player": p, "ui_id": ui_id.left(64), "action": action.left(64)})
	# The engine drew these panels, so the engine answers their buttons. Both say whether the action
	# was theirs, so a mod's own "say:"-prefixed action in its own panel still reaches the mod.
	if ui_id == "engine:talk" and characters.on_action(p, action):
		return
	if ui_id == "engine:shop" and shops.on_action(p, action):
		return
	if ui_id == "engine:orders" and companions.on_action(p, action):
		return
	# "close" is handled here rather than left to the mod. The engine writes Close buttons into its own
	# panels, and every mod copied that, but nothing ever acted on the action - so a modal panel with a
	# Close button trapped the player until they quit the game. The event is still emitted first, so a
	# mod can do something on the way out. (playtest, 2026-09-18)
	if action == "close" and p.ui_ids.has(ui_id):
		p.hide_ui(ui_id)


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
	if pos.y < 0 or pos.y >= Chunk.SIZE_Y or not realm_of(p).world.has_chunk(VoxelWorld.chunk_coord_at(pos.x, pos.z)):
		return false
	var distance := p.get_eye_position().distance_to(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
	if distance > REACH + 3.0:
		anticheat.record(p, "reach", 1.0, "a block %.1f blocks away" % distance)
	if distance > REACH + 0.87:
		return false
	# Somebody else's ground. Checked here rather than in each of break, place and interact, so a
	# capability added later cannot quietly miss one of them.
	if not plots.may_build(p, realm_of(p).id, pos):
		var plot := plots.at(realm_of(p).id, pos)
		p.send_message("This is %s." % (String(plot.name) if not String(plot.name).is_empty() else "somebody else's ground"))
		return false
	return true


## Whether the player was looking at the upper half of the cell they are placing into: the underside of
## a block, or above the middle of a side face. Worked out from where they are looking rather than asked
## of the client, so it needs nothing new on the wire and cannot be fibbed about.
func _aimed_high(p: ServerPlayer, pos: Vector3i) -> bool:
	var origin := p.get_eye_position()
	var direction := PlayerPhysics.look_direction(p.yaw, p.pitch)
	var hit := VoxelRaycast.cast(realm_of(p).world, registry.targetable_lut, origin, direction, REACH)
	if not hit.hit or hit.position + hit.normal != pos:
		return false
	if hit.normal.y != 0:
		return hit.normal.y < 0  # the underside of a block: the slab goes up against it
	# A side face: find where the ray crosses it, and compare with the middle of the cell.
	var axis := 0 if hit.normal.x != 0 else 2
	var along := direction.x if axis == 0 else direction.z
	if absf(along) < 0.0001:
		return false
	var face := float(hit.position.x if axis == 0 else hit.position.z) + (1.0 if (hit.normal.x if axis == 0 else hit.normal.z) > 0 else 0.0)
	var t := (face - (origin.x if axis == 0 else origin.z)) / along
	return origin.y + direction.y * t - float(pos.y) > 0.5


## Whether this placement should fill a slab that is already there, as {position, block}: the player is
## holding the matching slab and aimed at its flat face (a bottom slab from above, a top slab from below).
func _slab_merge(p: ServerPlayer, block: int, pos: Vector3i) -> Dictionary:
	var material := str(registry.defs[block].get("full_block", ""))
	if material.is_empty():
		return {}
	var into := realm_of(p)
	var hit := VoxelRaycast.cast(into.world, registry.targetable_lut, p.get_eye_position(),
		PlayerPhysics.look_direction(p.yaw, p.pitch), REACH)
	if not hit.hit or hit.position + hit.normal != pos or not _can_edit(p, hit.position):
		return {}
	var there := into.world.get_block_v(hit.position)
	if str(registry.defs[there].get("full_block", "")) != material:
		return {}  # empty, another material, or not a slab at all
	var shape := registry.shape_lut[there]
	if shape == BlockRegistry.Shape.SLAB_BOTTOM and hit.normal.y <= 0:
		return {}
	if shape == BlockRegistry.Shape.SLAB_TOP and hit.normal.y >= 0:
		return {}
	var full := registry.id_of(material)
	return {"position": hit.position, "block": full} if full > 0 else {}


func _has_solid_neighbor(pos: Vector3i, into: Realm = null) -> bool:
	var w = (into if into != null else realm).world
	for dir in [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		if registry.solid_lut[w.get_block_v(pos + dir)] == 1 and w.get_block_v(pos + dir) != BlockRegistry.UNLOADED:
			return true
	return false


func _apply_block(pos: Vector3i, block: int, keep_data := false, state := 0, into: Realm = null) -> void:
	into = into if into != null else realm
	var coord := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	var chunk = into.world.chunks.get(coord)
	if chunk == null:
		return
	if not into.generated.has(coord):
		into.generated[coord] = chunk.blocks.duplicate()
	var old := into.world.get_block_v(pos)
	var old_state := into.block_state(pos)
	into.world.set_block(pos.x, pos.y, pos.z, block)
	var index := Chunk.index(pos.x & 15, pos.y, pos.z & 15)
	if not into.deltas.has(coord):
		into.deltas[coord] = {}
	if into.generated[coord].decode_u16(index << 1) == block:
		into.deltas[coord].erase(index)
	else:
		into.deltas[coord][index] = block
	if state > 0:
		chunk.states[index] = state & 255
	else:
		chunk.states.erase(index)
	into.save_dirty[coord] = true
	if old != block and not keep_data:
		if not containers.type_of_block(old).is_empty():
			containers.block_removed(pos, get_block_data(pos, into), old, into)
		clear_block_data(pos, into)
	into.block_ticks.block_changed(pos, old, block)
	into.signals.block_changed(pos, old, block)
	into.liquids.block_changed(pos, old, block)
	into.multiblocks.block_changed(pos, old, block)
	links.block_changed(into.id, pos, old, block)
	if old != block:
		connect.refresh_around(pos, into)
	# Every change to the world, however it happened: a player, liquid spreading, a structure pasted, a
	# support collapsing, a blast. block_placed and block_broken only ever fired for a player, so a
	# protection or world-log mod could watch somebody build and never see a blast take the same wall
	# down. Emitted after the subsystems above, so a handler sees a consistent world. (2026-09-21)
	if old != block:
		emit("block_changed", {"realm": into.id, "position": pos, "block": block, "previous": old})
	# Removing one half of a two-block piece removes the other (its drops come from the half broken).
	if old != block and registry.defs[old].get("pair") is Dictionary:
		var other: Vector3i = pos + pair_offset(registry.defs[old].pair, old_state)
		if into.world.get_block_v(other) == registry.id_of(str(registry.defs[old].pair.block)):
			_apply_block(other, BlockRegistry.AIR, false, 0, into)
	# Only the people standing in this world: chunk (0, 0) has been sent to somebody in every realm,
	# and a coordinate alone would have the Emberdeep's edits redrawn in the overworld.
	for p: ServerPlayer in players.values():
		if p.sent_chunks.has(coord) and realm_of(p) == into:
			Net.s_block_changed.rpc_id(p.peer_id, pos, block, state & 255)
	# Blocks that need support (plants, torches) break when what holds them goes away.
	if old != block and pos.y + 1 < Chunk.SIZE_Y:
		var above := into.world.get_block_v(pos + Vector3i.UP)
		if above != BlockRegistry.AIR and above != BlockRegistry.UNLOADED and not is_supported(pos + Vector3i.UP, above, into):
			break_block(pos + Vector3i.UP, true, into)


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
func pair_position(pos: Vector3i, into: Realm = null) -> Vector3i:
	into = into if into != null else realm
	var block := into.world.get_block_v(pos)
	if not registry.is_valid(block) or not (registry.defs[block].get("pair") is Dictionary):
		return pos
	var pair: Dictionary = registry.defs[block].pair
	var other := pos + pair_offset(pair, into.block_state(pos))
	return other if into.world.get_block_v(other) == registry.id_of(str(pair.block)) else pos


## Whether `block` may stand at `pos`: its `support` rule ("solid" or [block names]) must accept the block
## below. Blocks without a rule always can.
func is_supported(pos: Vector3i, block: int, into: Realm = null) -> bool:
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
	var below := (into if into != null else realm).world.get_block_v(pos + Vector3i.DOWN)
	return registry.solid_lut[below] == 1 and below != BlockRegistry.UNLOADED if needed is bool else needed.has(below)


## Breaks a block without a player (support lost, explosions, mods): drops items, plays its sound.
##
## `sound` is off for a blast, which breaks fifty blocks in one instant: fifty break sounds on top of
## the explosion is a noise, not fifty pieces of feedback.
func break_block(pos: Vector3i, drop := true, into: Realm = null, sound := true) -> void:
	into = into if into != null else realm
	var block := into.world.get_block_v(pos)
	if block == BlockRegistry.AIR or block == BlockRegistry.UNLOADED:
		return
	var drops := _default_drops(block) if drop else []
	var ev := emit("block_destroyed", {"position": pos, "block": block, "drops": drops, "realm": into.id})
	_apply_block(pos, BlockRegistry.AIR, false, 0, into)
	if sound:
		play_sound_at(block_sound(block, "break"), Vector3(pos) + Vector3.ONE * 0.5, 0.8, randf_range(0.9, 1.1))
	for d in (ev.drops if ev.drops is Array else []):
		if d is Array and d.size() == 2 and items.is_valid(int(d[0])) and int(d[1]) > 0:
			into.entities.drop_item(int(d[0]), int(d[1]), Vector3(pos) + Vector3(0.5, 0.3, 0.5),
				Vector3(randf_range(-1.0, 1.0), randf_range(2.0, 3.5), randf_range(-1.0, 1.0)), 0.3)


## Tells the client the authoritative block and inventory so it can roll back its prediction.
func _reject_edit(p: ServerPlayer, pos: Vector3i) -> void:
	var into := realm_of(p)
	var block := into.world.get_block_v(pos)
	if block != BlockRegistry.UNLOADED and _started:
		Net.s_block_changed.rpc_id(p.peer_id, pos, block, into.block_state(pos))
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
	block_ticks.clock = float(_meta.get("clock", 0.0))
	if _meta.get("time") is Array and _meta.time.size() == 2:
		_time_of_day = float(_meta.time[0])
		_day_length = float(_meta.time[1])


## Returns [path, json text] for a chunk's delta, or [path, null] when there is nothing to keep.
func _serialize_chunk(from: Realm, coord: Vector2i, entity_records = null) -> Array:
	var deltas: Dictionary = from.deltas.get(coord, {})
	var entries: Dictionary = from.block_data.get(coord, {})
	var chunk = from.world.chunks.get(coord)
	var states: PackedInt32Array = chunk.encode_states() if chunk != null else PackedInt32Array()
	var records: Array = entity_records if entity_records is Array else from.entities.serialize_chunk(coord)
	if records.is_empty():
		from.entity_chunks.erase(coord)
	else:
		from.entity_chunks[coord] = true
	var tick_state = from.block_ticks.save_chunk(coord)
	if deltas.is_empty() and entries.is_empty() and states.is_empty() and records.is_empty() and tick_state == null:
		return [from.chunk_path(coord), null]
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
	return [from.chunk_path(coord), JSON.stringify({"version": 1, "palette": palette, "blocks": edits, "states": Array(states), "data": data, "entities": records, "ticks": tick_state})]


## How many chunks are waiting to be written, across every world.
func _queued_chunks() -> int:
	var queued := 0
	for r: Realm in realms.values():
		queued += r.save_queue.size()
	return queued


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
		"realm": p.realm_id,
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
	for r: Realm in realms.values():
		if r.ephemeral:
			continue  # an instance is thrown away when it empties; writing it would outlive the run
		var coords := r.save_dirty.duplicate()
		for coord: Vector2i in r.block_data:
			coords[coord] = true  # block data dictionaries may have been mutated in place
		for coord: Vector2i in r.entity_chunks.keys():
			coords[coord] = true  # persistent entities may have left the chunk
		for coord: Vector2i in r.block_ticks.ticking_chunks():
			coords[coord] = true  # keeps the tick clock current so catch-up never counts loaded time
		for e: Entity in r.entities.entities.values():
			if e.def.persistent:
				coords[VoxelWorld.chunk_coord_of(e.body.position)] = true
		if not coords.is_empty():
			_activity_since_backup = true
		r.save_queue.merge(coords)
	_save_meta_pending = true
	_drain_save_queue(-1 if wait else SAVE_BUDGET_USEC, wait)


## Serializes queued chunks until `budget_usec` is spent (-1: all), then players and world.json.
func _drain_save_queue(budget_usec: int, wait := false) -> void:
	if not _save_meta_pending and _queued_chunks() == 0:
		return
	var start := Time.get_ticks_usec()
	for r: Realm in realms.values():
		for coord: Vector2i in r.save_queue.keys():
			if budget_usec >= 0 and Time.get_ticks_usec() - start > budget_usec:
				return
			r.save_queue.erase(coord)
			if r.world.chunks.has(coord):
				_save_writes.append(_serialize_chunk(r, coord))
				r.save_dirty.erase(coord)
	if not _save_meta_pending:
		return
	_save_meta_pending = false
	for p: ServerPlayer in players.values():
		_store_player(p)
	_meta.time = [_time_of_day, _day_length]
	_meta.game = server_info.get("game_id", "")
	_meta.last_played = int(Time.get_unix_time_from_system())
	_meta.clock = block_ticks.clock
	_meta.world_markers = world_markers
	_meta.links = links.to_saved()
	_meta.stores = containers.stores
	_meta.companies = companies.to_saved()
	_meta.plots = plots.to_saved()
	_meta.shop_stock = shops.to_saved()
	_meta.fields = fields.to_saved()
	_meta.mod_settings = mod_settings.to_saved()
	_meta.loot = {"rate": loot.rate, "boosts": loot.boosts}
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
