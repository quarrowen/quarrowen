extends Node3D
## Universal game client. Knows nothing about any particular game: it downloads the server's block
## definitions, textures and physics rules, renders streamed chunks, predicts local movement and
## edits (the server confirms or corrects them), and draws server-described UI.

signal exited(message: String)
## Leave this server for a friend's (engine/main.gd switches).
signal join_friend_requested(address: String, port: int, server_name: String)
## The server sent this player to another server (engine/main.gd connects there with the ticket).
signal transfer_requested(address: String, port: int, server_name: String, ticket: Dictionary)

## Set when the server announced a full reload: whoever owns the client should reconnect (see main.gd).
var reload_pending := false

const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const Chunk = preload("res://engine/shared/chunk.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")
const VoxelRaycast = preload("res://engine/shared/voxel_raycast.gd")
const Inventory = preload("res://engine/shared/inventory.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const ChunkMesher = preload("res://engine/client/chunk_mesher.gd")
const TextureAtlas = preload("res://engine/client/texture_atlas.gd")
const ContentCache = preload("res://engine/client/content_cache.gd")
const RemotePlayer = preload("res://engine/client/remote_player.gd")
const ServerUI = preload("res://engine/client/server_ui.gd")
const VoxelMaterial = preload("res://engine/client/voxel_material.gd")
const ModelLibrary = preload("res://engine/client/model_library.gd")
const WorldTime = preload("res://engine/shared/world_time.gd")
const ItemRegistry = preload("res://engine/shared/item_registry.gd")
const GraphicsSettings = preload("res://engine/client/graphics_settings.gd")
const ClientSettings = preload("res://engine/client/settings/client_settings.gd")
const SettingsScreen = preload("res://engine/client/settings/settings_screen.gd")
const FriendsPanel = preload("res://engine/client/social/friends_panel.gd")
const PlayersPanel = preload("res://engine/client/admin/players_panel.gd")
const ServerPanel = preload("res://engine/client/admin/server_panel.gd")
const WorldsPanel = preload("res://engine/client/admin/worlds_panel.gd")
const MapScreen = preload("res://engine/client/map_screen.gd")
const Compass = preload("res://engine/client/compass.gd")
const MenuTheme = preload("res://engine/client/menu/menu_theme.gd")
const Identity = preload("res://engine/shared/identity.gd")
const EntityRegistry = preload("res://engine/shared/entity_registry.gd")
const EntityView = preload("res://engine/client/entity_view.gd")
const EntityPhysics = preload("res://engine/shared/entity_physics.gd")
const SoundPlayer = preload("res://engine/client/sound_player.gd")
const MusicPlayer = preload("res://engine/client/music_player.gd")
const InventoryScreen = preload("res://engine/client/inventory_screen.gd")
const Mining = preload("res://engine/shared/mining.gd")
const ItemVisuals = preload("res://engine/client/item_visuals.gd")
const PlayerRig = preload("res://engine/shared/player_rig.gd")
const Avatar = preload("res://engine/client/avatar/avatar.gd")
const SkinCompositor = preload("res://engine/client/avatar/skin_compositor.gd")
const Cosmetics = preload("res://engine/shared/cosmetics.gd")
const LookBuilder = preload("res://engine/client/avatar/look_builder.gd")
const AvatarStore = preload("res://engine/client/avatar/avatar_store.gd")
const AvatarEditor = preload("res://engine/client/avatar/avatar_editor.gd")
const EffectPlayer = preload("res://engine/client/effects/effect_player.gd")
const CraftingScreen = preload("res://engine/client/crafting_screen.gd")
const GuideScreen = preload("res://engine/client/guide_screen.gd")
const TutorialHud = preload("res://engine/client/tutorial_hud.gd")
const DevOverlay = preload("res://engine/client/dev_overlay.gd")
const DebugDraw = preload("res://engine/client/debug_draw.gd")
const UgcClient = preload("res://engine/client/ugc_client.gd")
const CreationLibrary = preload("res://engine/client/creation_library.gd")
const UgcReview = preload("res://engine/client/ugc_review.gd")
const Creations = preload("res://engine/shared/creations.gd")
const InviteCode = preload("res://engine/shared/invite_code.gd")
const ServerPinger = preload("res://engine/client/menu/server_pinger.gd")
const MinigameScreen = preload("res://engine/client/minigame_screen.gd")
const EatingVisuals = preload("res://engine/client/eating_visuals.gd")
const ItemIcons = preload("res://engine/client/item_icons.gd")
const Assembly = preload("res://engine/shared/assembly.gd")
const RecipeRegistry = preload("res://engine/shared/recipe_registry.gd")
const PINS_PATH := "user://crafting_pins.cfg"
const ItemMesh = preload("res://engine/client/avatar/item_mesh.gd")
const ViewModel = preload("res://engine/client/avatar/view_model.gd")

enum CameraMode { FIRST_PERSON, THIRD_PERSON, FRONT }

const MAX_CONNECT_ATTEMPTS := 20
const MESH_WORKERS := 4
const MOUSE_SENSITIVITY := 0.0025
const REACH := 5.0
const EDIT_REPEAT_DELAY := 0.25
const INPUT_REDUNDANCY := 3
const MAX_PENDING_INPUTS := 240
const TELEPORT_DISTANCE := 3.0
const RENDER_DISTANCE := 8 * 16
const CHAT_LINES := 8
const CHAT_LINE_LIFETIME := 10.0
const ATTACK_REACH := 4.5
const ATTACK_REPEAT := 0.3
const STEP_DISTANCE := 1.7

enum Phase { CONNECTING, DOWNLOADING, JOINING, PLAYING }

var server_address := "127.0.0.1"
var server_port := 24565
var player_name := "Player"
## Passed by the menu when this client launched a local server it should stop on exit.
var admin_token := ""
## Which saved identity (user://identity/<name>.pem) to log in with.
var identity_name := "default"
## Tests only: sign challenges with this key instead of the identity (must fail authentication).
var test_signing_key: CryptoKey = null
## Tests: announce this protocol version instead of the real one.
var test_protocol := -1
## Accept gameplay input without a captured mouse (headless bots / tests).
var ignore_mouse_capture := false
## Your portable avatar (Cosmetics data) sent to the server on join; null loads the saved one.
var avatar = null

var phase := Phase.CONNECTING
var server_info := {}
var registry := BlockRegistry.new()
var items := ItemRegistry.new(registry)
var rules := PlayerPhysics.Rules.new()
var world := VoxelWorld.new()
var inventory := Inventory.new()
var cosmetics := Cosmetics.new()
var recipes := RecipeRegistry.new()
## Server cosmetics you own on this server.
var owned_cosmetics := PackedStringArray()
## Effect name -> times the server played it for us (debug overlay and tests).
var effects_seen := {}
var entity_types := EntityRegistry.new()
var health := 20.0
var max_health := 20.0
var hunger := 20.0
var saturation := 5.0
var dead := false
## Stats the server computed for this player (reach, attack_cooldown, mining_speed, armor, ...).
var stats := {}
var graphics := GraphicsSettings.new()
var my_id := 0
var state := PlayerPhysics.State.new()
var yaw := 0.0
var pitch := 0.0

var _identity: CryptoKey
var _welcomed := false
var _connect_attempts := 0
var _exiting := false
## A ticket to hand to the server right after hello, when arriving through a transfer: {ticket, signature}.
var transfer_ticket := {}
## Set when the server sent us elsewhere: {address, port, name, ticket}.
var transfer := {}
## Why the game ended, for the menu: "" or "identity" (the server's identity no longer matches the pinned one).
var exit_kind := ""
var _input_seq := 0
var _pending_inputs: Array = []
var _recent_packets: Array[PackedByteArray] = []
var _prev_position := Vector3.ZERO
var _render_offset := Vector3.ZERO
var _correction_count := 0

var _manifest := {}  # asset name -> {hash, size}
var _downloads := {}  # hash -> PackedByteArray being received
## Lazy assets being fetched while playing: hash -> {buffer, callbacks}. Separate from _downloads so a
## slow music track can never be mistaken for part of the join and stall the progress bar.
var _lazy := {}
var _download_total := 0
var _download_received := 0
var _asset_textures := {}  # asset name -> ImageTexture
var _mesh_context := {}

var _chunk_nodes := {}  # Vector2i -> MeshInstance3D
var _mesh_dirty := {}  # Vector2i -> true
## Block changes for chunks that have not arrived yet (chunks come on their own channel): coord -> [[pos, block, state]].
var _early_edits := {}
var _entity_clock_offset := INF  # local seconds minus server tick seconds, for entity update timestamps
var _early_edit_count := 0
const MAX_EARLY_EDITS := 20000
var _mesh_urgent := {}  # Vector2i -> true
var _mesh_jobs := {}  # Vector2i -> Dictionary
var _remote_players := {}  # peer_id -> RemotePlayer
var _entities := {}  # entity id -> EntityView
var _entity_parts := {}  # type id -> Array of model parts
var _entity_sprites := {}  # type id -> Texture2D
var _entity_target := {}  # {kind: 0 entity / 1 player, id, distance} or empty
var _attack_timer := 0.0
var _step_distance := 0.0
var _sounds: SoundPlayer
var _music: MusicPlayer
var _base_rules := {}
var _mining := {}  # {position, started, seconds} while breaking a block in survival
var _mining_sound_at := 0.0
var _cracks := {}  # peer id (0 = me) -> {node, position, started, seconds}
var _armor_bar: HBoxContainer
var _player_rig := PlayerRig.default_rig()
var _item_meshes: ItemMesh
var _asset_images := {}  # asset name -> Image
var _appearances := {}  # peer id -> appearance from the server
var _look_cache := {}  # key -> ImageTexture (players sharing armor share textures)
var _looks: LookBuilder
var _avatar_editor: AvatarEditor
var _effects: EffectPlayer
var _crafting_screen: CraftingScreen
var _pin_panel: PanelContainer
var _pin_rows: VBoxContainer
var _toast: PanelContainer
var _pending_lookup := {}
var _guide_root: Node3D
var _station_labels := {}  # Vector3i -> Label3D
var _learned_batch: Array = []
var _item_icons := ItemIcons.new()
## Follows your own body so effects can follow you even while the avatar is hidden in first person.
var _self_anchor := Node3D.new()
var _view_model_look := ""
var _held_effect: Node3D
var _self_avatar: Avatar
var camera_mode := CameraMode.FIRST_PERSON
var _view_model: ViewModel
var _look_delta := Vector2.ZERO
var _armor_textures := []

var _edit_timer := 0.0
var _target := {}

var _atlas := {}
var _solid_material: ShaderMaterial
var _translucent_material: ShaderMaterial
var _model_meshes := {}  # block id -> ArrayMesh
var _arm_meshes := {}  # block id -> ArrayMesh drawn toward connected neighbours
var _connect_groups := {}  # block id -> group name
var _model_nodes := {}  # Vector2i chunk -> Array of MultiMeshInstance3D
var _time_of_day := 0.5
var _day_length := 0.0
var _daylight := 1.0
var _applied_daylight := -1.0
var _sky_material: ProceduralSkyMaterial
var _environment: Environment
var _sun: DirectionalLight3D
var _camera: Camera3D
var _highlight: MeshInstance3D

var _hud_root: Control
var _server_ui: ServerUI
var _status_label: Label
var _debug_label: Label
var _hotbar: HBoxContainer
## Name of what the player is holding, shown above the hotbar for a moment when it changes.
var _held_label: Label
var _look_label: Label
var _held_shown := 0
var _held_until := 0.0
var _hotbar_slots: Array[Panel] = []
var _chat_log: VBoxContainer
var _chat_input: LineEdit
var _pause_panel: PanelContainer
var _hearts: HBoxContainer
var _heart_textures := []  # [full, half, empty]
var _hunger_bar: HBoxContainer
var _hunger_textures := []  # [full, half, empty]
var _eating := {}  # {item, next_chomp} while holding use on food
var _hurt_flash: ColorRect
var _death_panel: Control
## {sleeping, since, asleep, needed, seconds, head_dir, started (local)} while in bed.
var _sleep := {}
var _sleep_panel: Control
var _sleep_fade: ColorRect
var _sleep_label: Label
var _leave_bed_sent := 0.0
var _death_label: Label
var _respawn_button: Button
var _inventory_screen: InventoryScreen
var _minigame_screen: MinigameScreen
var _guide_screen: GuideScreen
var _guide_badge: Label
var _tutorial_hud: TutorialHud
var _dev_alerts: VBoxContainer
var _dev_overlay: DevOverlay
var _debug_draw: DebugDraw
## Player creations: uploads, downloads and the server library (see engine/client/ugc_client.gd).
var ugc := UgcClient.new(self)
## Model files of downloaded creations: asset name -> GLB bytes.
var ugc_models := {}
var _ugc_review: UgcReview
var _settings_overlay: Control
var _players_panel: Control
var _server_panel: Control
var _worlds_panel: Control
var _map_screen: Control
var _compass: Control
var _map_timer := 0.0
## What the server last sent about players and markers (the map screen and the compass share it).
var _map_state := {}
## engine/client/social/social_client.gd when main.gd runs the game (null in tests).
var social
var _sprint_on := false  # the sprint key toggles (accessibility setting)
var _last_jump_press := 0.0  # for the double-tap that starts flying


func _ready() -> void:
	graphics.load_saved()
	if not (avatar is Dictionary):
		avatar = AvatarStore.load_avatar()
	_register_input_actions()
	_build_scene()
	_build_hud()
	_apply_graphics(false)
	_apply_accessibility()
	ClientSettings.shared().changed.connect(_on_setting_changed)
	Net.client = self
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Net.handshake_failed.connect(_on_handshake_failed)
	_connect()


func _exit_tree() -> void:
	for job: Dictionary in _mesh_jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_mesh_jobs.clear()
	if Net.client == self:
		Net.client = null
	if Net.handshake_failed.is_connected(_on_handshake_failed):
		Net.handshake_failed.disconnect(_on_handshake_failed)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Connection ---------------------------------------------------------------------------------

func _connect() -> void:
	if _identity == null:
		_identity = Identity.load_or_create(identity_name)
	_connect_attempts += 1
	_set_status("Connecting to %s:%d..." % [server_address, server_port])
	var err := Net.create_client(server_address, server_port, test_protocol)
	if err != OK:
		_leave("Could not start client: %s" % error_string(err))


func _on_connected() -> void:
	_set_status("Handshaking...")
	Net.c_hello.rpc_id(1, Protocol.VERSION, player_name, Identity.public_pem(_identity))
	if not transfer_ticket.is_empty():
		Net.c_transfer_ticket.rpc_id(1, str(transfer_ticket.get("ticket", "")), str(transfer_ticket.get("signature", "")))


func on_challenge(nonce: PackedByteArray) -> void:
	# Sign only what a server challenge looks like, so a server cannot get anything else signed with the
	# identity key (such as a hub sign-in).
	if nonce.size() != Identity.NONCE_BYTES:
		_leave("The server sent an invalid login challenge")
		return
	_set_status("Authenticating...")
	Net.c_auth.rpc_id(1, Identity.sign(test_signing_key if test_signing_key != null else _identity, nonce))


func _on_connection_failed() -> void:
	if _connect_attempts < MAX_CONNECT_ATTEMPTS and not _exiting:
		Net.close()
		await get_tree().create_timer(0.5).timeout
		if not _exiting:
			_connect()
		return
	exit_kind = "connect"
	var message := "Could not connect to %s:%d" % [server_address, server_port]
	if Net.has_pinned_identity(server_address, server_port):
		exit_kind = "identity"
		message = "Could not connect to %s:%d. If the server is running, its identity has changed since your last visit: it was reinstalled or its data was reset, or someone is impersonating it." % [server_address, server_port]
	_leave(message)


func _on_handshake_failed(reason: String) -> void:
	_leave(reason)


func _on_server_disconnected() -> void:
	_leave("Disconnected from server")


func disconnect_from_server() -> void:
	if not admin_token.is_empty() and multiplayer.has_multiplayer_peer() \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		Net.c_shutdown.rpc_id(1, admin_token)
		# Give ENet a moment to flush the reliable packet before the peer is closed.
		await get_tree().create_timer(0.2).timeout
	_leave("")


func _leave(message: String) -> void:
	if _exiting:
		return
	_exiting = true
	Net.close()
	exited.emit(message)


# --- Mod reloads -----------------------------------------------------------------------------------

## A mod was reloaded: take the new definitions, recipe book, guide and tutorials (ids are unchanged).
func on_content_update(content: Dictionary) -> void:
	_update_defs(content.get("blocks"), BlockRegistry.NETWORK_FIELDS, func(n): return registry.id_of(n) > 0, func(d): registry.register(d, true))
	_update_defs(content.get("items"), ItemRegistry.NETWORK_FIELDS, func(n): return items.id_of(n) > 0, func(d): items.register(d, true))
	_update_defs(content.get("entities"), EntityRegistry.NETWORK_FIELDS, func(n): return entity_types.id_of(n) >= 0, func(d): entity_types.register(d, true))
	if content.get("recipes") is Dictionary:
		recipes.clear()
		recipes.load_network(content.recipes)
	_crafting_screen.processes = content.get("processes", {}) if content.get("processes") is Dictionary else _crafting_screen.processes
	_crafting_screen.stations = content.get("stations", {}) if content.get("stations") is Dictionary else _crafting_screen.stations
	_crafting_screen.assembly.load_network(content.get("assembly"))
	_crafting_screen.minigames = content.get("minigames", {}) if content.get("minigames") is Dictionary else _crafting_screen.minigames
	if content.get("guide") is Dictionary:
		_guide_screen.registry.clear()
		_guide_screen.registry.load_network(content.guide)
		if _guide_screen.visible:
			_guide_screen.open(_guide_screen.current)
	if content.get("tutorials") is Array:
		_tutorial_hud.tutorials = content.tutorials
	_crafting_screen.refresh()
	_refresh_pin()


func _update_defs(data, fields: Array, exists: Callable, apply: Callable) -> void:
	for entry in (data if data is Array else []):
		if not (entry is Dictionary) or not (entry.get("name") is String) or not exists.call(entry.name):
			continue
		var clean := {}
		for field in fields:
			if entry.has(field):
				clean[field] = entry[field]
		apply.call(clean)


func on_server_reloading(message: String) -> void:
	reload_pending = true
	_server_ui.show_title(message, "The server restarts with the new mods; you will be back in a moment", 10.0)


## Where to actually go when a server sends us somewhere. A server that names itself 127.0.0.1 means "this
## machine" - but the client reads that as the *player's* machine, and the destination is wherever the
## server we are talking to lives. Unless we really are playing on our own computer, use the host we are
## already connected to. (A network.json written with loopback addresses is an easy mistake and used to
## leave nobody able to travel at all.)
static func resolve_transfer_address(address: String, current: String) -> String:
	const LOOPBACK := ["127.0.0.1", "localhost", "::1"]
	if address.strip_edges() in LOOPBACK and not (current.strip_edges() in LOOPBACK):
		return current
	return address


func on_transfer(address: String, port: int, server_name: String, ticket: String, signature: String) -> void:
	if not transfer.is_empty():
		return
	address = resolve_transfer_address(address, server_address)
	transfer = {"address": address.left(253), "port": clampi(port, 1, 65535), "name": server_name.left(64),
		"ticket": {"ticket": ticket, "signature": signature}}
	_set_status("Travelling to %s…" % transfer.name)
	transfer_requested.emit(transfer.address, transfer.port, transfer.name, transfer.ticket)


func on_kick(reason: String) -> void:
	# Most reasons already read as a sentence to the player; only prefix the ones that do not.
	_leave(reason if reason.length() > 24 or reason.ends_with(".") else "Kicked: %s" % reason)


# --- Content download ---------------------------------------------------------------------------

func on_server_info(info: Dictionary, content: Dictionary, manifest: Array) -> void:
	if phase != Phase.CONNECTING:
		return
	server_info = info
	if not registry.load_network(content.get("blocks")) or not items.load_network(content.get("items", []), content.get("equipment_slots"), content.get("stats")):
		_leave("This server’s world did not arrive properly. Try joining again.")
		return
	inventory.set_equipment_slots(items.slot_names())
	_player_rig = PlayerRig.sanitize(content.get("player_rig"))
	cosmetics.load_network(content.get("cosmetics"))
	CreationLibrary.register_all(cosmetics, _asset_images)  # the player's own creations
	recipes.load_network(content.get("recipes"))
	# Where things come from, for the tooltip's "Dropped by" line.
	ItemVisuals.sources = content.get("loot", {}) if content.get("loot") is Dictionary else {}
	_crafting_screen.processes = content.get("processes", {}) if content.get("processes") is Dictionary else {}
	_crafting_screen.stations = content.get("stations", {}) if content.get("stations") is Dictionary else {}
	_crafting_screen.assembly.load_network(content.get("assembly"))
	_crafting_screen.minigames = content.get("minigames", {}) if content.get("minigames") is Dictionary else {}
	_crafting_screen.player_name = player_name
	_guide_screen.registry.load_network(content.get("guide"))
	_tutorial_hud.tutorials = content.get("tutorials") if content.get("tutorials") is Array else []
	if not _effects.registry.load_network(content.get("effects", [])):
		_leave("Server sent invalid effect definitions")
		return
	Net.c_set_avatar.rpc_id(1, avatar)
	stats = items.stats.duplicate()
	if content.get("rules") is Dictionary:
		on_rules(content.rules)
	if not entity_types.load_network(content.get("entities", [])) or not _sounds.registry.load_network(content.get("sounds", [])) \
			or not _music.registry.load_network(content.get("music", [])):
		_leave("Server sent invalid entity or sound definitions")
		return

	var total_size := 0
	var missing := PackedStringArray()
	for entry in manifest.slice(0, Protocol.MAX_ASSETS):
		if not (entry is Array) or entry.size() < 3 or not (entry[0] is String) or not (entry[1] is String):
			continue
		var hash: String = entry[1]
		var size := int(entry[2])
		var lazy: bool = entry.size() > 3 and int(entry[3]) == 1
		if not ContentCache.is_valid_hash(hash) or size < 0 or size > Protocol.MAX_ASSET_SIZE:
			continue
		total_size += size
		if total_size > Protocol.MAX_TOTAL_ASSET_SIZE:
			_leave("This server has more in it than the game can take in. Ask whoever runs it.")
			return
		_manifest[entry[0]] = {"hash": hash, "size": size, "lazy": lazy}
		# A lazy asset is listed but not waited for. Music is megabytes; a join that downloads the
		# soundtrack first is a join a child gives up on.
		if lazy:
			continue
		if not ContentCache.has(hash) and not _downloads.has(hash):
			_downloads[hash] = PackedByteArray()
			_download_total += size
			missing.append(hash)

	print("[client] Server '%s' running %s: %d blocks, %d assets (%d to download)" % [
		info.get("name", "?"), info.get("game", "?"), registry.defs.size() - 1, _manifest.size(), missing.size()])
	phase = Phase.DOWNLOADING
	Net.c_request_assets.rpc_id(1, missing)
	_update_download_status()
	if _downloads.is_empty():
		_finish_content()


## Fetches a lazy asset, calling `then(asset_name)` once it is on disk. Calling it again for something
## already arriving just adds another listener rather than asking the server twice.
func fetch_lazy_asset(asset_name: String, then: Callable) -> void:
	var entry = _manifest.get(asset_name)
	if entry == null:
		return
	var hash: String = entry.hash
	if ContentCache.has(hash):
		then.call(asset_name)
		return
	if _lazy.has(hash):
		_lazy[hash].waiting.append(then)
		return
	_lazy[hash] = {"buffer": PackedByteArray(), "name": asset_name, "waiting": [then]}
	Net.c_request_assets.rpc_id(1, PackedStringArray([hash]))


func _lazy_piece(hash: String, offset: int, total: int, bytes: PackedByteArray) -> void:
	var entry: Dictionary = _lazy[hash]
	var buffer: PackedByteArray = entry.buffer
	if offset != buffer.size() or offset + bytes.size() > mini(total, Protocol.MAX_ASSET_SIZE):
		_lazy.erase(hash)  # give up quietly: this is music, not the world
		return
	buffer.append_array(bytes)
	if buffer.size() < total:
		entry.buffer = buffer
		return
	_lazy.erase(hash)
	if not ContentCache.store(hash, buffer):
		return
	for callback in entry.waiting:
		callback.call(entry.name)


func on_asset_piece(hash: String, offset: int, total: int, bytes: PackedByteArray) -> void:
	if _lazy.has(hash):
		_lazy_piece(hash, offset, total, bytes)
		return
	if phase != Phase.DOWNLOADING or not _downloads.has(hash):
		return
	var buffer: PackedByteArray = _downloads[hash]
	if offset != buffer.size() or offset + bytes.size() > mini(total, Protocol.MAX_ASSET_SIZE):
		_leave("The server’s pictures and sounds did not arrive properly. Try joining again.")
		return
	buffer.append_array(bytes)
	_download_received += bytes.size()
	if buffer.size() < total:
		_downloads[hash] = buffer
	else:
		_downloads.erase(hash)
		if not ContentCache.store(hash, buffer):
			_leave("Something arrived from the server damaged. Try joining again.")
			return
	_update_download_status()
	if _downloads.is_empty():
		_finish_content()


func _update_download_status() -> void:
	if _download_total > 0:
		_set_status("Downloading %s content... %d%%" % [server_info.get("game", "server"), roundi(100.0 * _download_received / _download_total)])


func _finish_content() -> void:
	var images := {}
	for asset_name: String in _manifest:
		if not asset_name.get_extension().to_lower() == "png":
			continue
		var img := Image.new()
		if img.load_png_from_buffer(ContentCache.read(_manifest[asset_name].hash)) != OK:
			push_warning("[client] Could not decode %s" % asset_name)
			continue
		if img.get_width() > Protocol.MAX_TEXTURE_SIZE or img.get_height() > Protocol.MAX_TEXTURE_SIZE:
			push_warning("[client] Texture %s is too large" % asset_name)
			continue
		_asset_images[asset_name] = img
		_asset_textures[asset_name] = ImageTexture.create_from_image(img)
	# The block atlas only holds block faces and item icons (not skins, armor or UI art).
	for d in registry.defs:
		for tex in d.textures:
			if _asset_images.has(tex):
				images[tex] = _asset_images[tex]
	for d in items.defs:
		if _asset_images.has(d.icon):
			images[d.icon] = _asset_images[d.icon]

	_atlas = TextureAtlas.build(images)
	_solid_material = VoxelMaterial.create(_atlas.texture, false)
	_translucent_material = VoxelMaterial.create(_atlas.texture, true)
	_applied_daylight = -1.0
	for d in registry.defs:
		if not d.model.is_empty() and _manifest.has(d.model):
			var mesh := ModelLibrary.load_mesh(ContentCache.read(_manifest[d.model].hash))
			if mesh:
				_model_meshes[d.id] = mesh
			else:
				push_warning("[client] Could not load model %s" % d.model)
		if not d.model_arm.is_empty() and _manifest.has(d.model_arm):
			var arm := ModelLibrary.load_mesh(ContentCache.read(_manifest[d.model_arm].hash))
			if arm:
				_arm_meshes[d.id] = arm
		if not d.connect_group.is_empty():
			_connect_groups[d.id] = d.connect_group
	for d in entity_types.defs:
		if not String(d.model).is_empty() and _manifest.has(d.model):
			var parts := ModelLibrary.load_parts(ContentCache.read(_manifest[d.model].hash))
			if parts.is_empty():
				push_warning("[client] Could not load entity model %s" % d.model)
			_entity_parts[d.id] = parts
		if _asset_textures.has(d.sprite):
			_entity_sprites[d.id] = _asset_textures[d.sprite]
	_sounds.manifest = _manifest
	_music.manifest = _manifest
	_crafting_screen.atlas = _atlas
	_item_icons.items = items
	_item_icons.atlas = _atlas
	_item_icons.images = _asset_images
	_inventory_screen.icons = _item_icons
	_crafting_screen.icons = _item_icons
	_load_pin()
	_effects.textures = _asset_textures
	_effects.play_sound = func(sound_name: String, at: Vector3): _sounds.play_name(sound_name, at)
	_inventory_screen.atlas = _atlas
	_inventory_screen.build_equipment(items.slots)
	_item_meshes = ItemMesh.new(items, registry, _atlas, func(asset: String) -> PackedByteArray:
		return ContentCache.read(_manifest[asset].hash) if _manifest.has(asset) else PackedByteArray())
	_item_meshes.icons = _item_icons
	_looks = LookBuilder.new(cosmetics, _asset_images, func(asset: String) -> PackedByteArray:
		if ugc_models.has(asset):
			return ugc_models[asset]
		if Creations.is_id(asset.get_basename()):
			return CreationLibrary.read_model(asset)
		return ContentCache.read(_manifest[asset].hash) if _manifest.has(asset) else PackedByteArray())
	_self_avatar = Avatar.new()
	add_child(_self_avatar)
	_self_avatar.build(_player_rig)
	_self_avatar.visible = false
	_apply_look(_self_avatar, player_name, _appearances.get(my_id, {}))
	_mesh_context = ChunkMesher.make_context(registry, _atlas.uv)
	_apply_graphics(false)
	_server_ui.textures = _asset_textures
	_rebuild_hotbar()
	phase = Phase.JOINING
	_set_status("Joining %s..." % server_info.get("name", "server"))
	Net.c_ready.rpc_id(1)


func on_time(time_of_day: float, day_length: float) -> void:
	_time_of_day = fposmod(time_of_day, 1.0)
	_day_length = maxf(day_length, 0.0)


func on_rules(values: Dictionary) -> void:
	_base_rules = values.duplicate()
	var speed := float(stats.get("move_speed", 1.0))
	var adjusted := values.duplicate()
	if adjusted.has("walk_speed"):
		adjusted.walk_speed = float(adjusted.walk_speed) * speed
	if adjusted.has("sprint_speed"):
		var sprint := clampf(float(stats.get("sprint", 1.0)), 0.0, 1.0)
		var walk := float(values.get("walk_speed", adjusted.sprint_speed))
		adjusted.sprint_speed = (walk + (float(adjusted.sprint_speed) - walk) * sprint) * speed
	rules.apply_dict(adjusted)
	rules.solid_lut = registry.solid_lut
	rules.shape_lut = registry.shape_lut
	rules.liquid_lut = registry.liquid_lut
	world.set_lookup_tables(registry.solid_lut, registry.liquid_lut, registry.shape_lut)
	world.void_below = rules.void_below


# --- Server messages ----------------------------------------------------------------------------

func on_welcome(peer_id: int, spawn: Vector3, spawn_yaw: float) -> void:
	my_id = peer_id
	state.position = spawn
	_prev_position = spawn
	yaw = spawn_yaw
	_welcomed = true
	phase = Phase.PLAYING
	if _self_avatar != null and _appearances.has(my_id):
		_apply_look(_self_avatar, player_name, _appearances[my_id])  # it may arrive before the welcome
	if not admin_token.is_empty():
		Net.c_claim_admin.rpc_id(1, admin_token)
	ugc.offer_worn(avatar)
	_set_status("Loading terrain...")
	print("[client] Joined as peer %d at %s" % [peer_id, spawn])


func on_chunk(coord: Vector2i, payload: PackedByteArray, states: PackedInt32Array) -> void:
	var data := Chunk.decode_blocks(payload)
	if data.is_empty():
		push_warning("[client] Dropped malformed chunk %s" % coord)
		return
	# Unknown ids from a misbehaving server would index past the lookup tables' valid entries.
	var chunk := Chunk.new(coord, data)
	chunk.load_states(states)
	world.add_chunk(chunk)
	var early: Array = _early_edits.get(coord, [])
	if not early.is_empty():
		_early_edits.erase(coord)
		_early_edit_count -= early.size()
		for edit in early:
			on_block_changed(edit[0], edit[1], edit[2])
	# Neighbours' faces and light near the shared borders depend on this chunk.
	for x in range(-1, 2):
		for z in range(-1, 2):
			_mark_dirty(coord + Vector2i(x, z), false)


func on_unload_chunk(coord: Vector2i) -> void:
	_early_edit_count -= _early_edits.get(coord, []).size()
	_early_edits.erase(coord)  # a later copy of the chunk will include them
	world.remove_chunk(coord)
	_mesh_dirty.erase(coord)
	_mesh_urgent.erase(coord)
	var node: MeshInstance3D = _chunk_nodes.get(coord)
	if node:
		node.queue_free()
		_chunk_nodes.erase(coord)
	_clear_models(coord)


func on_block_changed(pos: Vector3i, block: int, state: int) -> void:
	var coord := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	if not world.chunks.has(coord) and registry.is_valid(block) and pos.y >= 0 and pos.y < Chunk.SIZE_Y:
		if _early_edit_count >= MAX_EARLY_EDITS:
			_early_edits.clear()
			_early_edit_count = 0
		if not _early_edits.has(coord):
			_early_edits[coord] = []
		_early_edits[coord].append([pos, block, state])
		_early_edit_count += 1
		return
	if not registry.is_valid(block) or (world.get_block_v(pos) == block and get_block_state(pos) == state):
		return
	var previous := world.get_block_v(pos)
	if world.set_block(pos.x, pos.y, pos.z, block):
		_set_state(pos, state)
		_on_block_modified(pos)
		if block == BlockRegistry.AIR:
			_block_debris(pos, previous)


func _block_debris(pos: Vector3i, block: int) -> void:
	if not registry.is_valid(block) or block == BlockRegistry.AIR or registry.liquid_lut[block] == 1 or _atlas.is_empty() \
			or _camera.global_position.distance_to(Vector3(pos)) > 32.0:
		return
	var face := String(registry.defs[block].textures[0]) if not registry.defs[block].textures.is_empty() else ""
	if _atlas.uv.has(face):
		_effects.block_break(Vector3(pos) + Vector3.ONE * 0.5, _atlas.texture, _atlas.uv[face], 0.4 + 0.6 * maxf(_applied_daylight, 0.35))


func get_block_state(pos: Vector3i) -> int:
	var chunk = world.chunks.get(VoxelWorld.chunk_coord_at(pos.x, pos.z))
	return chunk.states.get(Chunk.index(pos.x & 15, pos.y, pos.z & 15), 0) if chunk != null and pos.y >= 0 and pos.y < Chunk.SIZE_Y else 0


func _set_state(pos: Vector3i, state: int) -> void:
	var chunk = world.chunks.get(VoxelWorld.chunk_coord_at(pos.x, pos.z))
	if chunk == null:
		return
	var index := Chunk.index(pos.x & 15, pos.y, pos.z & 15)
	if state > 0:
		chunk.states[index] = state & 255
	else:
		chunk.states.erase(index)


func on_inventory(slots: PackedInt32Array, selected: int, creative: bool, item_data: Dictionary) -> void:
	if not inventory.load_packed(slots):
		return
	inventory.load_network_data(item_data)
	inventory.creative = creative
	if selected != inventory.selected:
		# The server may pick the slot (e.g. mods resetting the hotbar); follow it.
		inventory.selected = clampi(selected, 0, Inventory.HOTBAR - 1)
	_refresh_hotbar()
	_inventory_screen.refresh()
	_crafting_screen.refresh()
	_refresh_pin()


func on_player_joined(peer_id: int, remote_name: String) -> void:
	if peer_id == my_id or _remote_players.has(peer_id):
		return
	var remote := RemotePlayer.new()
	remote.setup(peer_id, remote_name, _player_rig)
	add_child(remote)
	_remote_players[peer_id] = remote
	_apply_look(remote.avatar, remote_name, _appearances.get(peer_id, {}))


func on_player_appearance(peer_id: int, appearance: Dictionary) -> void:
	_appearances[peer_id] = appearance
	ugc.ensure_known(appearance.get("avatar", {}))
	if peer_id == my_id and _self_avatar != null:
		_apply_look(_self_avatar, player_name, appearance)
	elif _remote_players.has(peer_id):
		_apply_look(_remote_players[peer_id].avatar, _remote_players[peer_id].player_name, appearance)


## Draws everyone again (a creation someone wears has arrived).
func refresh_looks() -> void:
	if _looks == null:
		return
	_looks.clear_cache()
	for peer_id in _appearances:
		if peer_id == my_id and _self_avatar != null:
			_apply_look(_self_avatar, player_name, _appearances[peer_id])
		elif _remote_players.has(peer_id):
			_apply_look(_remote_players[peer_id].avatar, _remote_players[peer_id].player_name, _appearances[peer_id])


## The admin review panel for player creations.
func open_ugc_review() -> void:
	if _ugc_review != null:
		return
	_set_paused(false)
	_ugc_review = UgcReview.new()
	_ugc_review.cosmetics = cosmetics
	_ugc_review.looks = _looks
	_ugc_review.images = _asset_images
	_ugc_review.rig = _player_rig
	_ugc_review.action_requested.connect(func(action, args): Net.c_ugc_admin.rpc_id(1, action, args))
	_ugc_review.fetch_requested.connect(func(ids): ugc.fetch(ids))
	ugc.creation_ready.connect(_ugc_review.creation_ready)
	_ugc_review.closed.connect(func():
		ugc.creation_ready.disconnect(_ugc_review.creation_ready)
		_ugc_review.queue_free()
		_ugc_review = null
		if not ignore_mouse_capture:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	_hud_root.add_child(_ugc_review)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func on_ugc_admin_list(items: Array, policy: Dictionary) -> void:
	if _ugc_review != null:
		_ugc_review.receive(items, policy)


## Report a creation another player is wearing.
## The invite code for this server. When playing on this computer (a hosted world), people on the same
## network use this computer's local address; from elsewhere they need its public address and the port
## forwarded (the hub service will make that easier).
func invite_text() -> String:
	var address := server_address
	if address in ["127.0.0.1", "localhost", "::1"]:
		address = InviteCode.local_address()
		if address.is_empty():
			return ""
	return InviteCode.share_text(address, server_port)


func open_invite_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Invite friends"
	dialog.ok_button_text = "Close"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 10)
	dialog.add_child(box)
	var text := invite_text()
	var intro := Label.new()
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 460
	var hosted := server_address in ["127.0.0.1", "localhost", "::1"]
	intro.text = ("Friends paste this in Multiplayer → Join. Hosting from this computer works for people on the same network; for others, forward port %d (UDP) on your router and share your public address." % server_port) if hosted \
		else "Friends paste this in Multiplayer → Join."
	box.add_child(intro)
	var code := LineEdit.new()
	code.text = text if not text.is_empty() else "No network address found"
	code.editable = false
	code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.add_theme_font_size_override("font_size", 26)
	box.add_child(code)
	var copy := Button.new()
	copy.text = "Copy"
	copy.disabled = text.is_empty()
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(code.text)
		copy.text = "Copied")
	box.add_child(copy)
	# A server listed on a hub has a short code that works from anywhere: ask the server for it.
	var pinger = ServerPinger.new()
	pinger.result.connect(func(_key, entry: Dictionary):
		if entry.online and not str(entry.info.code).is_empty() and is_instance_valid(code):
			code.text = entry.info.code
			copy.disabled = false
			intro.text = "Friends paste this in Multiplayer → Join (they need the same server list hub in Settings → Network), or use %s." % text if not text.is_empty() \
				else "Friends paste this in Multiplayer → Join (with the same server list hub in Settings → Network).")
	pinger.ping("self", server_address, server_port)
	var poll := Timer.new()
	poll.wait_time = 0.05
	poll.autostart = true
	poll.timeout.connect(pinger.update)
	dialog.add_child(poll)
	dialog.tree_exited.connect(pinger.close)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	_hud_root.add_child(dialog)
	dialog.popup_centered()


func open_report_dialog() -> void:
	var choices := []
	for peer_id in _appearances:
		if peer_id == my_id:
			continue
		var owner := str(_remote_players[peer_id].player_name) if _remote_players.has(peer_id) else "someone"
		for id in UgcClient.worn_ids(_appearances[peer_id].get("avatar", {})):
			var d := cosmetics.get_def(id)
			choices.append([id, "%s's %s \"%s\"" % [owner, d.get("category", "creation"), d.get("display_name", id.left(12))]])
	var dialog := ConfirmationDialog.new()
	dialog.title = "Report a creation"
	dialog.ok_button_text = "Report"
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	dialog.add_child(box)
	if choices.is_empty():
		var none := Label.new()
		none.text = "Nobody near you is wearing a player creation."
		box.add_child(none)
		dialog.get_ok_button().disabled = true
	var which := OptionButton.new()
	for c in choices:
		which.add_item(c[1])
	which.visible = not choices.is_empty()
	box.add_child(which)
	var reason := OptionButton.new()
	for r in [["inappropriate", "Inappropriate"], ["offensive", "Offensive or hateful"], ["copied", "Copied from someone else"], ["spam", "Spam"], ["other", "Something else"]]:
		reason.add_item(r[1])
		reason.set_item_metadata(reason.item_count - 1, r[0])
	reason.visible = not choices.is_empty()
	box.add_child(reason)
	var details := LineEdit.new()
	details.placeholder_text = "Anything the admins should know (optional)"
	details.max_length = 200
	details.visible = not choices.is_empty()
	box.add_child(details)
	dialog.confirmed.connect(func():
		if not choices.is_empty():
			Net.c_ugc_report.rpc_id(1, choices[which.selected][0], reason.get_item_metadata(reason.selected), details.text)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	_hud_root.add_child(dialog)
	dialog.popup_centered()


## A short message for the player (creation statuses and the like).
func notify(text: String) -> void:
	on_chat(text)


func on_cosmetics(owned: PackedStringArray, policy: Dictionary) -> void:
	owned_cosmetics = owned
	cosmetics.set_policy(policy)


## Dresses an avatar: skin and accessories (cosmetics), visible armor and the held item.
func _apply_look(target: Avatar, name_text: String, appearance: Dictionary) -> void:
	if _item_meshes == null:
		return
	_looks.apply(target, appearance.get("avatar", {}) if appearance.get("avatar") is Dictionary else {}, name_text)
	var pieces := {}
	var armor = appearance.get("armor", {})
	if armor is Dictionary:
		for slot in armor:
			var texture := String(items.get_def(int(armor[slot])).get("armor_texture", ""))
			if _asset_images.has(texture):
				pieces[String(slot)] = _asset_images[texture]
	var armor_key := "armor:%s" % str(armor)
	if pieces.is_empty():
		target.set_armor(null)
	else:
		if not _look_cache.has(armor_key):
			_look_cache[armor_key] = ImageTexture.create_from_image(SkinCompositor.compose_armor(pieces))
		target.set_armor(_look_cache[armor_key])
	target.set_armor_glow(appearance.get("armor_glow", {}) if appearance.get("armor_glow") is Dictionary else {})
	var sleeping = appearance.get("sleeping")
	target.set_sleeping(sleeping.get("head", []) if sleeping is Dictionary and sleeping.get("head") is Array else [])
	var held_look: Dictionary = appearance.get("held_look", {}) if appearance.get("held_look") is Dictionary else {}
	var held_node := _item_meshes.node_for(int(appearance.get("held", 0)), false, held_look)
	_dress_held(held_node, held_look)
	target.set_held(held_node, held_look)
	if target == _self_avatar:
		_view_model.set_skin(target._skin_material.albedo_texture)
		_view_model.set_armor(target._armor_material.albedo_texture, appearance.get("armor_glow", {}) if appearance.get("armor_glow") is Dictionary else {})


## Glow and the continuous "held" effect on a held item node.
func _dress_held(node: Node3D, look: Dictionary) -> void:
	if node == null or look.is_empty():
		return
	_item_meshes.apply_glow(node, look.get("glow", {}))
	var held_effect := _effects.registry.id_of(String(look.get("held", "")))
	if held_effect >= 0:
		var tip: Node3D = node.get_child(0).get_node_or_null("tip")
		_effects.play(held_effect, Vector3.ZERO, {"duration": -1, "scale": 0.5}, tip if tip != null else node)


func on_effect(effect_id: int, pos: Vector3, options: Dictionary) -> void:
	if _effects.registry.is_valid(effect_id):
		var effect_name: String = _effects.registry.defs[effect_id].name
		effects_seen[effect_name] = int(effects_seen.get(effect_name, 0)) + 1
	var parent: Node3D = null
	if options.get("follow_entity") is int:
		parent = _entities.get(options.follow_entity)
	elif options.get("follow_player") is int:
		parent = _self_anchor if options.follow_player == my_id else _remote_players.get(options.follow_player)
	if parent != null:
		options = options.duplicate()
		options.erase("direction")
	_effects.play(effect_id, pos, options, parent, _camera.global_position)


func on_health(value: float, max_value: float, is_dead: bool, hurt: bool) -> void:
	var was_dead := dead
	health = value
	max_health = maxf(max_value, 1.0)
	dead = is_dead
	if hurt:
		_hurt_flash.color.a = 0.45 * float(ClientSettings.shared().get_value("accessibility/flashes"))
	if dead and not was_dead:
		_death_panel.visible = true
		_set_inventory_open(false)
		_pause_panel.visible = false  # or it sits under the red overlay swallowing the clicks
		_chat_input.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_respawn_button.grab_focus.call_deferred()  # so Enter or Space works without finding the button
	elif not dead and was_dead:
		_death_panel.visible = false
		_capture_mouse()
	_refresh_hearts()
	_refresh_hunger()


func on_player_stats(values: Dictionary) -> void:
	var moved: bool = float(values.get("move_speed", 1.0)) != float(stats.get("move_speed", 1.0)) \
		or float(values.get("sprint", 1.0)) != float(stats.get("sprint", 1.0))
	for key in values:
		if key is String and (values[key] is float or values[key] is int):
			stats[key] = float(values[key])
	if moved and not _base_rules.is_empty():
		on_rules(_base_rules)
	_refresh_armor()


func on_mining(peer_id: int, pos: Vector3i, seconds: float) -> void:
	if seconds < 0.0:
		_clear_crack(peer_id)
	else:
		_show_crack(peer_id, pos, seconds)


func respawn() -> void:
	if dead:
		Net.c_respawn.rpc_id(1)


func on_entity_spawn(records: Array) -> void:
	for r in records:
		if not (r is Array) or r.size() < 6 or not entity_types.is_valid(int(r[1])) or not (r[2] is Vector3):
			continue
		var id := int(r[0])
		var existing: Node = _entities.get(id)
		if existing:
			existing.queue_free()
		var type_id := int(r[1])
		var view := EntityView.new()
		view.item_id = int(r[4])
		view.item_count = int(r[5])
		var sprite: Texture2D = _entity_sprites.get(type_id)
		if type_id == EntityRegistry.ITEM and items.is_valid(view.item_id) and not _atlas.is_empty():
			var icon := AtlasTexture.new()
			icon.atlas = _atlas.texture
			icon.region = _atlas.pixels.get(items.icon_of(view.item_id), _atlas.pixels[""])
			sprite = icon
		view.setup(id, entity_types.defs[type_id], _entity_parts.get(type_id, []), sprite, r[2], float(r[3]))
		add_child(view)
		_entities[id] = view
		if r.size() > 6 and r[6] is Dictionary and not r[6].is_empty():
			view.set_look(r[6])


func on_entity_look(entity_id: int, look: Dictionary) -> void:
	var view: EntityView = _entities.get(entity_id)
	if view != null:
		view.set_look(look)


func on_entity_despawn(ids: PackedInt32Array) -> void:
	for id in ids:
		var view: EntityView = _entities.get(id)
		if view:
			_entities.erase(id)
			view.despawn()


## The server started or stopped this player's flight.
func on_flying(enabled: bool) -> void:
	state.flying = enabled
	notify("Flying on - jump to rise, crouch to sink" if enabled else "Flying off")


func on_entities(tick: int, payload: PackedByteArray) -> void:
	if payload.size() < 2:
		return
	var buf := StreamPeerBuffer.new()
	buf.data_array = payload
	# Stamp updates by the server tick they describe, not when they happened to arrive, so network jitter
	# does not make mobs speed up and stall. The offset follows the fastest arrivals and drifts slowly.
	var local := Time.get_ticks_msec() / 1000.0
	var server_time := float(tick) / Engine.physics_ticks_per_second
	var offset := local - server_time
	if _entity_clock_offset == INF or offset < _entity_clock_offset or offset - _entity_clock_offset > 1.0:
		_entity_clock_offset = offset
	else:
		_entity_clock_offset += (offset - _entity_clock_offset) * 0.02
	var now := server_time + _entity_clock_offset
	var count := mini(buf.get_u16(), (payload.size() - 2) / 19)
	for i in count:
		var id := buf.get_u32()
		var pos := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
		var entity_yaw := buf.get_u16() / 65535.0 * TAU
		buf.get_u8()
		var view: EntityView = _entities.get(id)
		if view and not view.dying:
			view.push_state(now, pos, entity_yaw)


func on_entity_event(entity_id: int, kind: int, arg: int) -> void:
	var view: EntityView = _entities.get(entity_id)
	if view == null:
		return
	match kind:
		0: view.hurt()
		1: view.die()
		3: view.attack()
		5: view.windup()
		2:
			var collector: Node3D = _camera if arg == my_id else _remote_players.get(arg)
			if collector:
				view.picked_up_by(collector)


func on_player_event(peer_id: int, kind: int) -> void:
	var remote = _remote_players.get(peer_id)
	if remote == null:
		return
	match kind:
		0: remote.hurt()
		1: remote.set_dead(true)
		4: remote.set_dead(false)
		6: remote.swing()


## The server's music instruction. Nothing here can fail loudly: the track may not have arrived yet, or
## may never arrive, and either way the game carries on without it.
func on_music(track_id: int, fade: float, restart: bool) -> void:
	if _music != null:
		_music.play(track_id, fade, restart)


func on_sound(sound_id: int, pos: Vector3, volume: float, pitch: float, positional: bool) -> void:
	_sounds.play(sound_id, pos, volume, pitch, positional)


func on_player_left(peer_id: int) -> void:
	var remote: Node = _remote_players.get(peer_id)
	if remote:
		remote.queue_free()
		_remote_players.erase(peer_id)


func on_snapshot(_tick: int, payload: PackedByteArray) -> void:
	if not _welcomed or payload.size() < 31:
		return
	var buf := StreamPeerBuffer.new()
	buf.data_array = payload
	var last_seq := buf.get_32()
	var pos := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	var vel := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	var on_ground := buf.get_u8() == 1
	_reconcile(last_seq, pos, vel, on_ground)
	var now := Time.get_ticks_msec() / 1000.0
	var count := mini(buf.get_u16(), (payload.size() - 31) / 20)
	for i in count:
		var peer_id := buf.get_32()
		var remote_pos := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
		var remote_yaw := buf.get_u16() / 65535.0 * TAU
		var remote_pitch := buf.get_16() / 32767.0 * PI * 0.5
		if _remote_players.has(peer_id):
			_remote_players[peer_id].push_state(now, remote_pos, remote_yaw, remote_pitch)


func on_chat(text: String) -> void:
	var label := Label.new()
	label.text = text.left(300)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.set_meta("born", Time.get_ticks_msec() / 1000.0)
	_chat_log.add_child(label)
	while _chat_log.get_child_count() > CHAT_LINES:
		var oldest := _chat_log.get_child(0)
		_chat_log.remove_child(oldest)
		oldest.queue_free()


func on_ui_show(ui_id: String, spec: Dictionary) -> void:
	_server_ui.show_panel(ui_id.left(64), spec)
	if _server_ui.has_modal():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func on_ui_hide(ui_id: String) -> void:
	_server_ui.hide_panel(ui_id)


func on_title(text: String, subtitle: String, seconds: float) -> void:
	_server_ui.show_title(text, subtitle, seconds)


# --- Prediction & reconciliation ----------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not _can_simulate():
		return
	var input := PlayerPhysics.PlayerInput.new()
	_input_seq += 1
	input.seq = _input_seq
	if not _sleep.is_empty():
		# In bed: movement keys get you up instead of moving.
		var wants_up := Input.get_vector("move_left", "move_right", "move_back", "move_forward").length() > 0.2 or Input.is_action_pressed("jump")
		if wants_up and not _chat_input.visible:
			leave_bed()
	elif _gameplay_input_enabled():
		input.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		input.jump = Input.is_action_pressed("jump")
		input.sneak = Input.is_action_pressed("sneak")
		if Input.is_action_just_pressed("jump"):
			# Double-tap jump starts (or stops) flying; the server decides whether it may.
			var now := Time.get_ticks_msec() / 1000.0
			if now - _last_jump_press < 0.35 and _welcomed:
				Net.c_set_flying.rpc_id(1, not state.flying)
				_last_jump_press = 0.0
			else:
				_last_jump_press = now
		if ClientSettings.shared().get_value("controls/sprint_toggle"):
			if Input.is_action_just_pressed("sprint"):
				_sprint_on = not _sprint_on
			if input.move.length() < 0.1:
				_sprint_on = false  # stopping ends a toggled sprint
			input.sprint = _sprint_on
		else:
			input.sprint = Input.is_action_pressed("sprint")
	input.yaw = yaw
	input.pitch = pitch

	# Round-trip through the wire format so prediction uses exactly what the server will see.
	var buf := StreamPeerBuffer.new()
	input.write(buf)
	var encoded := buf.data_array
	buf.seek(0)
	input = PlayerPhysics.PlayerInput.read(buf)

	_prev_position = state.position
	PlayerPhysics.step(state, input, world, rules)
	_pending_inputs.append(input)
	if _pending_inputs.size() > MAX_PENDING_INPUTS:
		_pending_inputs.pop_front()

	_recent_packets.append(encoded)
	if _recent_packets.size() > INPUT_REDUNDANCY:
		_recent_packets.pop_front()
	var packet := PackedByteArray([_recent_packets.size()])
	for p in _recent_packets:
		packet.append_array(p)
	Net.c_inputs.rpc_id(1, packet)


func _reconcile(last_seq: int, pos: Vector3, vel: Vector3, on_ground: bool) -> void:
	var predicted := state.position
	state.position = pos
	state.velocity = vel
	state.on_ground = on_ground
	while not _pending_inputs.is_empty() and _pending_inputs[0].seq <= last_seq:
		_pending_inputs.pop_front()
	if _can_simulate():
		for input in _pending_inputs:
			PlayerPhysics.step(state, input, world, rules)
	var error := predicted - state.position
	if error.length_squared() > 0.0001:
		_correction_count += 1
	if error.length() > TELEPORT_DISTANCE:
		_render_offset = Vector3.ZERO
		_prev_position = state.position
	else:
		# Keep the rendered position continuous and blend the correction out over a few frames.
		_render_offset += error
		_prev_position -= error


func _can_simulate() -> bool:
	if not _welcomed:
		return false
	var center := VoxelWorld.chunk_coord_of(state.position)
	for x in range(-1, 2):
		for z in range(-1, 2):
			if not world.has_chunk(center + Vector2i(x, z)):
				return false
	return true


# --- Frame update -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_poll_mesh_jobs()
	_schedule_mesh_jobs()
	if _held_label != null and _held_label.modulate.a > 0.0 and Time.get_ticks_msec() / 1000.0 > _held_until:
		_held_label.modulate.a = maxf(_held_label.modulate.a - delta * 2.0, 0.0)
	if not _welcomed:
		return
	# Who is nearby and where the marked places are: for the compass, and the map when it is open.
	_map_timer -= delta
	if _map_timer <= 0.0 and (_compass.visible or _map_screen != null):
		_map_timer = 2.0
		Net.c_map.rpc_id(1)
	if _compass.visible:
		_compass.look(yaw, state.position)
	ugc.update(delta)

	if _status_label.visible and _can_simulate() and _chunk_nodes.has(VoxelWorld.chunk_coord_of(state.position)):
		_set_status("")

	var fraction := Engine.get_physics_interpolation_fraction()
	_render_offset = _render_offset.lerp(Vector3.ZERO, 1.0 - exp(-delta * 15.0))
	var render_position := _prev_position.lerp(state.position, fraction) + _render_offset
	var eye := PlayerPhysics.EYE_HEIGHT - (PlayerPhysics.SNEAK_EYE_DROP if state.sneaking else 0.0)
	_camera.position = render_position + Vector3(0.0, eye if _sleep.is_empty() else 0.1, 0.0)
	if not _sleep.is_empty():
		_update_sleep()
	_camera.rotation = Vector3(pitch, yaw, 0.0)
	_update_self_avatar(delta, render_position)
	_camera.position += _effects.shake_offset

	_update_time(delta)
	_update_target()
	_handle_edits(delta)
	_update_footsteps(render_position)
	_update_cracks()
	_update_hud()
	_hurt_flash.color.a = move_toward(_hurt_flash.color.a, 0.0, delta * 1.2)


## Your own character: hidden in first person; in third person the camera pulls back (stopping at
## walls) behind you, or in front of you facing back.
func _update_self_avatar(delta: float, render_position: Vector3) -> void:
	if _self_avatar == null:
		return
	_self_avatar.visible = camera_mode != CameraMode.FIRST_PERSON
	_self_avatar.position = render_position
	_self_avatar.rotation.y = _self_avatar.sleep_yaw if _self_avatar.sleep_yaw != null else yaw
	_self_avatar.set_dead(dead)
	_self_avatar.animate(delta, state.velocity, state.on_ground, pitch)
	_view_model.visible = camera_mode == CameraMode.FIRST_PERSON and not dead and _sleep.is_empty()
	var held := inventory.selected_item()
	var look: Dictionary = {}
	if held >= ItemRegistry.FIRST_ITEM:
		var visuals := items.visuals(held, inventory.data[inventory.selected])
		look = {"glow": visuals.glow, "trail": visuals.trail, "held": visuals.effects.get("held", ""),
			"icon_layers": inventory.data[inventory.selected].get("icon_layers", [])}
	var look_key := "%d|%s" % [held, str(look)]
	if look_key != _view_model_look:
		# Follow the hotbar immediately, not the server echo; rebuild when the stack's look changes.
		_view_model_look = look_key
		var node := _item_meshes.node_for(held, true, inventory.data[inventory.selected])
		_dress_held(node, look)
		_view_model.set_held(held, node, look)
	_self_anchor.position = render_position
	_view_model.animate(delta, Vector2(state.velocity.x, state.velocity.z).length(), state.on_ground, _look_delta)
	_look_delta = Vector2.ZERO
	if camera_mode == CameraMode.FIRST_PERSON:
		return
	var eye := _camera.position
	var back := _camera.basis.z if camera_mode == CameraMode.THIRD_PERSON else -_camera.basis.z
	var distance := 4.0
	var ray := VoxelRaycast.cast(world, registry.solid_lut, eye, back, distance)
	if ray.hit:
		distance = maxf(eye.distance_to(Vector3(ray.position) + Vector3.ONE * 0.5) - 1.0, 0.3)
	_camera.position = eye + back * distance
	if camera_mode == CameraMode.FRONT:
		_camera.rotation = Vector3(-pitch, yaw + PI, 0.0)


func _update_target() -> void:
	var origin := _camera.position
	var direction := -_camera.basis.z
	_target = VoxelRaycast.cast(world, registry.targetable_lut, origin, direction, REACH)
	var block_distance := INF
	if _target.hit and registry.solid_lut[_target.block] == 1:  # plants do not shield mobs from hits
		var cell := Vector3(_target.position)
		block_distance = maxf(EntityPhysics.segment_hits_box(origin, direction, REACH + 1.0, cell, cell + Vector3.ONE), 0.0)
	_entity_target = {}
	var best := minf(block_distance, float(stats.get("reach", ATTACK_REACH)))
	for id: int in _entities:
		var view: EntityView = _entities[id]
		if view.dying or String(view.type_def.get("kind", "")) != "mob":
			continue
		var box := view.aabb()
		var t := EntityPhysics.segment_hits_box(origin, direction, best, box.position, box.end)
		if t >= 0.0 and t < best:
			best = t
			_entity_target = {"kind": 0, "id": id, "distance": t}
	for peer_id: int in _remote_players:
		var remote: Node3D = _remote_players[peer_id]
		if not remote.visible:
			continue
		var box := AABB(remote.position - Vector3(0.3, 0, 0.3), Vector3(0.6, 1.8, 0.6))
		var t := EntityPhysics.segment_hits_box(origin, direction, best, box.position, box.end)
		if t >= 0.0 and t < best:
			best = t
			_entity_target = {"kind": 1, "id": peer_id, "distance": t}
	_highlight.visible = _target.hit and _entity_target.is_empty()
	if _target.hit:
		_highlight.position = Vector3(_target.position) + Vector3(0.5, 0.5, 0.5)
	_show_looking_at()


func _handle_edits(delta: float) -> void:
	_edit_timer -= delta
	_attack_timer -= delta
	if not _gameplay_input_enabled():
		return
	if not _entity_target.is_empty():
		if Input.is_action_just_pressed("break") or (Input.is_action_pressed("break") and _attack_timer <= 0.0):
			attack_target()
			_edit_timer = EDIT_REPEAT_DELAY
			return
		if Input.is_action_just_pressed("place") and _entity_target.kind == 0:
			Net.c_interact_entity.rpc_id(1, _entity_target.id)
			_edit_timer = EDIT_REPEAT_DELAY
			return
	if not _eating.is_empty():
		_update_eating()
		return
	if Input.is_action_just_pressed("place") and use_selected_item():
		_edit_timer = EDIT_REPEAT_DELAY
		return
	if not _target.hit:
		_stop_mining()
		return
	var breaking := Input.is_action_just_pressed("break") or (Input.is_action_pressed("break") and _edit_timer <= 0.0)
	var placing := Input.is_action_just_pressed("place") or (Input.is_action_pressed("place") and _edit_timer <= 0.0)
	if not inventory.creative:
		if Input.is_action_pressed("break"):
			_continue_mining(_target.position)
		else:
			_stop_mining()
		breaking = false
	if breaking:
		_edit_timer = EDIT_REPEAT_DELAY
		request_break(_target.position)
	elif placing and Input.is_action_just_pressed("place") and registry.interactive_lut[_target.block] == 1:
		_edit_timer = EDIT_REPEAT_DELAY
		Net.c_interact.rpc_id(1, _target.position)
	elif placing:
		_edit_timer = EDIT_REPEAT_DELAY
		request_place(placement_spot(_target))


func _self_swing() -> void:
	if _self_avatar != null:
		# In first person the arm in view swings with its own trail; the hidden body must not draw one.
		_self_avatar.swing(camera_mode != CameraMode.FIRST_PERSON)
		if camera_mode == CameraMode.FIRST_PERSON:
			_view_model.swing()


## Survival breaking: hold on a block until its break time passes (see Mining), with a crack overlay.
func _continue_mining(pos: Vector3i) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _mining.get("position") != pos:
		_stop_mining()
		var block := world.get_block_v(pos)
		if block == BlockRegistry.UNLOADED or registry.breakable_lut[block] == 0:
			return
		var seconds := Mining.break_time(registry.defs[block], items.tool_of(inventory.selected_item(), inventory.data[inventory.selected]), float(stats.get("mining_speed", 1.0)))
		_mining = {"position": pos, "started": now, "seconds": seconds, "block": block}
		Net.c_mine_start.rpc_id(1, pos)
		_show_crack(0, pos, seconds)
	if now - float(_mining.get("swung", -1.0)) > 0.3:
		_mining.swung = now
		_self_swing()
	var progress := (now - float(_mining.started)) / maxf(float(_mining.seconds), 0.001)
	if now - _mining_sound_at > 0.25:
		_mining_sound_at = now
		_sounds.play_name(String(registry.defs[_mining.block].sounds.get("step", "")), Vector3(pos) + Vector3.ONE * 0.5, 0.5, randf_range(0.8, 1.0))
	if progress >= 1.0:
		_mining = {}
		_clear_crack(0)
		request_break(pos)


func _stop_mining() -> void:
	if _mining.is_empty():
		return
	_mining = {}
	_clear_crack(0)
	if _welcomed:
		Net.c_mine_stop.rpc_id(1)


## Breaks a block the way a player holding the button would (used by tests and automation).
func mine_block(pos: Vector3i) -> void:
	if inventory.creative:
		request_break(pos)
		return
	var block := world.get_block_v(pos)
	var seconds := Mining.break_time(registry.defs[block], items.tool_of(inventory.selected_item(), inventory.data[inventory.selected]), float(stats.get("mining_speed", 1.0)))
	Net.c_mine_start.rpc_id(1, pos)
	_show_crack(0, pos, seconds)
	await get_tree().create_timer(seconds + 0.05).timeout
	_clear_crack(0)
	request_break(pos)


func _show_crack(peer_id: int, pos: Vector3i, seconds: float) -> void:
	_clear_crack(peer_id)
	var node := ItemVisuals.crack_node()
	node.position = Vector3(pos) + Vector3.ONE * 0.5
	add_child(node)
	_cracks[peer_id] = {"node": node, "started": Time.get_ticks_msec() / 1000.0, "seconds": maxf(seconds, 0.001)}


func _clear_crack(peer_id: int) -> void:
	var crack: Dictionary = _cracks.get(peer_id, {})
	if not crack.is_empty():
		crack.node.queue_free()
		_cracks.erase(peer_id)


func _update_cracks() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for peer_id in _cracks.keys():
		var crack: Dictionary = _cracks[peer_id]
		var progress: float = (now - crack.started) / crack.seconds
		if progress > 1.5 and peer_id != 0:
			_clear_crack(peer_id)
			continue
		ItemVisuals.set_crack_stage(crack.node, Mining.stage(progress))


## Attacks the entity or player under the crosshair. Returns false if nothing is targeted.
func attack_target() -> bool:
	if _entity_target.is_empty() or dead:
		return false
	_attack_timer = maxf(float(stats.get("attack_cooldown", ATTACK_REPEAT)), 0.1)
	Net.c_attack.rpc_id(1, _entity_target.kind, _entity_target.id)
	_self_swing()
	_sounds.play_name("engine:swing", _camera.position, 0.7, randf_range(0.9, 1.1))
	return true


## Plays the "step" sound of the block underfoot as the player walks.
func _update_footsteps(render_position: Vector3) -> void:
	if not state.on_ground or dead:
		return
	var horizontal := Vector2(state.velocity.x, state.velocity.z).length()
	_step_distance += horizontal * get_process_delta_time()
	if _step_distance < STEP_DISTANCE:
		return
	_step_distance = 0.0
	var below := world.get_block(floori(render_position.x), floori(render_position.y - 0.2), floori(render_position.z))
	if registry.is_valid(below):
		_sounds.play_name(String(registry.defs[below].sounds.get("step", "")), render_position, 0.35, randf_range(0.9, 1.1))


## Uses the held item on the current target (or on nothing). Returns false if it is not usable.
func use_selected_item() -> bool:
	var item := inventory.selected_item()
	var wearable := item >= ItemRegistry.FIRST_ITEM and not String(items.get_def(item).get("equip_slot", "")).is_empty()
	if item < ItemRegistry.FIRST_ITEM or not (items.is_usable(item) or wearable):
		return false
	Net.c_use_item.rpc_id(1, _target.hit, _target.get("position", Vector3i.ZERO), _target.get("normal", Vector3i.ZERO))
	var food: Dictionary = items.get_def(item).get("food", {})
	if not food.is_empty():
		# Food is eaten while use is held; the server finishes it after eat_time.
		if hunger < 20.0 or food.get("always", false) or inventory.creative:
			var meal := _meal_for(item, inventory.data[inventory.selected], Time.get_ticks_msec() / 1000.0)
			_eating = {"item": item, "slot": inventory.selected, "meal": meal}
			if not meal.is_empty():
				_view_model.start_meal(meal)
				if _self_avatar != null:
					_self_avatar.start_meal(meal)
		return true
	_self_swing()
	return true


func _update_eating() -> void:
	var meal: Dictionary = _eating.get("meal", {})
	var overdue: bool = not meal.is_empty() and Time.get_ticks_msec() / 1000.0 - float(meal.started) > float(meal.duration) + 1.5
	if not Input.is_action_pressed("place") or inventory.selected != int(_eating.slot) or inventory.selected_item() != int(_eating.item) or overdue:
		Net.c_stop_using.rpc_id(1)
		_end_local_meal()


func _end_local_meal() -> void:
	_eating = {}
	_view_model.stop_meal()
	if _self_avatar != null:
		_self_avatar.stop_meal()


## Animation data for eating an item: {style, duration, started, color, meshes (0-2 bites), plate, crumbs}.
func _meal_for(item: int, item_data: Dictionary, started: float) -> Dictionary:
	var food: Dictionary = items.get_def(item).get("food", {})
	if food.is_empty() or _item_meshes == null:
		return {}
	var style := str(food.get("style", "plate"))
	var meshes := []
	for bites in 3:
		meshes.append(_item_meshes.mesh_for(item, item_data) if style == "drink" else _item_meshes.bitten_mesh(item, item_data, bites))
	var color_text := str(food.get("color", "#c8a060"))
	return {"style": style, "duration": float(food.get("eat_time", 1.2)), "started": started, "meshes": meshes,
		"color": Color.html(color_text) if Color.html_is_valid(color_text) else Color(0.8, 0.6, 0.4),
		"plate": _item_meshes.plate_mesh() if style == "plate" else null,
		"crumbs": func(at: Vector3, color: Color, amount: int, size: float): EatingVisuals.crumbs(self, at, color, amount, size)}


var _selection_box: MeshInstance3D


## Outline of a structure selection (/struct pos1, pos2).
func on_selection(a: Vector3i, b: Vector3i, show: bool) -> void:
	if _selection_box == null:
		_selection_box = MeshInstance3D.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.85, 0.2)
		material.no_depth_test = true
		_selection_box.material_override = material
		add_child(_selection_box)
	_selection_box.visible = show
	if not show:
		return
	var lo := Vector3(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z)) + Vector3.ONE
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var corners := []
	for i in 8:
		corners.append(Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z))
	for i in 8:
		for bit in [1, 2, 4]:
			if i & bit == 0:
				mesh.surface_add_vertex(corners[i])
				mesh.surface_add_vertex(corners[i | bit])
	mesh.surface_end()
	_selection_box.mesh = mesh


func on_player_eating(peer_id: int, item: int) -> void:
	if peer_id == my_id:
		if item == 0 and not _eating.is_empty():
			_end_local_meal()  # finished (or refused) on the server
		return
	var remote = _remote_players.get(peer_id)
	if remote == null:
		return
	if item == 0:
		remote.avatar.stop_meal()
	else:
		var meal := _meal_for(item, {}, Time.get_ticks_msec() / 1000.0)
		if not meal.is_empty():
			remote.avatar.start_meal(meal)


## Predicts the edit locally and asks the server to apply it.
func request_break(pos: Vector3i) -> void:
	var current := world.get_block_v(pos)
	if current == BlockRegistry.UNLOADED or registry.breakable_lut[current] == 0:
		return
	world.set_block(pos.x, pos.y, pos.z, BlockRegistry.AIR)
	_on_block_modified(pos)
	_block_debris(pos, current)
	_sounds.play_name(String(registry.defs[current].sounds.get("break", "")), Vector3(pos) + Vector3.ONE * 0.5, 1.0, randf_range(0.85, 1.1))
	Net.c_break_block.rpc_id(1, pos)


## Places the selected hotbar block, predicting the result.
## Where a block goes when placing against a target: into replaceable blocks (tall grass) themselves,
## otherwise against the face that was hit.
func placement_spot(target: Dictionary) -> Vector3i:
	var block := world.get_block_v(target.position)
	return target.position if registry.is_valid(block) and registry.defs[block].replaceable else target.position + target.normal


func request_place(pos: Vector3i) -> void:
	var block := inventory.selected_block()
	if block <= 0 or registry.placeable_lut[block] == 0:
		return
	var current := world.get_block_v(pos)
	if current != BlockRegistry.AIR and registry.liquid_lut[current] == 0 and not (registry.is_valid(current) and registry.defs[current].replaceable):
		return
	if registry.solid_lut[block] == 1:
		if PlayerPhysics.overlaps_block(state.position, pos):
			return
		for remote: Node3D in _remote_players.values():
			if PlayerPhysics.overlaps_block(remote.position, pos):
				return
	world.set_block(pos.x, pos.y, pos.z, block)
	_set_state(pos, BlockRegistry.facing_from_yaw(yaw) if registry.defs[block].orientation == 1 else 0)
	_on_block_modified(pos)
	inventory.consume_selected()
	_refresh_hotbar()
	_sounds.play_name(String(registry.defs[block].sounds.get("place", "")), Vector3(pos) + Vector3.ONE * 0.5, 1.0, randf_range(0.85, 1.1))
	Net.c_place_block.rpc_id(1, pos, yaw)
	_self_swing()


func select_slot(index: int) -> void:
	_stop_mining()
	inventory.selected = wrapi(index, 0, Inventory.HOTBAR)
	_refresh_hotbar()
	if _welcomed:
		Net.c_select_slot.rpc_id(1, inventory.selected)


func _on_block_modified(pos: Vector3i) -> void:
	# Light can spread up to 15 blocks, so the surrounding chunks may need new meshes too.
	var coord := VoxelWorld.chunk_coord_at(pos.x, pos.z)
	for x in range(-1, 2):
		for z in range(-1, 2):
			_mark_dirty(coord + Vector2i(x, z), x == 0 and z == 0)


# --- Chunk meshing ------------------------------------------------------------------------------

func _mark_dirty(coord: Vector2i, urgent: bool) -> void:
	if not world.has_chunk(coord):
		return
	_mesh_dirty[coord] = true
	if urgent:
		_mesh_urgent[coord] = true


func _schedule_mesh_jobs() -> void:
	if _mesh_dirty.is_empty() or _mesh_jobs.size() >= MESH_WORKERS or _mesh_context.is_empty():
		return
	var center := VoxelWorld.chunk_coord_of(state.position)
	var candidates: Array = _mesh_dirty.keys().filter(func(c): return not _mesh_jobs.has(c))
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ua := _mesh_urgent.has(a)
		var ub := _mesh_urgent.has(b)
		if ua != ub:
			return ua
		return (a - center).length_squared() < (b - center).length_squared())
	for coord: Vector2i in candidates:
		if _mesh_jobs.size() >= MESH_WORKERS:
			break
		_mesh_dirty.erase(coord)
		_mesh_urgent.erase(coord)
		var chunks := []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				chunks.append(_chunk_blocks(coord + Vector2i(dx, dz)))
		var job := {"chunks": chunks, "context": _mesh_context, "result": []}
		job.task_id = WorkerThreadPool.add_task(_run_mesh_job.bind(job), false, "chunk mesh")
		_mesh_jobs[coord] = job


func _chunk_blocks(coord: Vector2i) -> PackedByteArray:
	var chunk = world.chunks.get(coord)
	return chunk.blocks if chunk != null else PackedByteArray()


## Runs on a worker thread: touches only the job dictionary.
func _run_mesh_job(job: Dictionary) -> void:
	job.result = ChunkMesher.build(job.chunks, job.context)


func _poll_mesh_jobs() -> void:
	for coord: Vector2i in _mesh_jobs.keys():
		var job: Dictionary = _mesh_jobs[coord]
		if not WorkerThreadPool.is_task_completed(job.task_id):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_mesh_jobs.erase(coord)
		if world.has_chunk(coord):
			# Apply even if a newer version is queued: it is still fresher than what is on screen.
			_apply_mesh(coord, job.result)


func _apply_mesh(coord: Vector2i, result: Array) -> void:
	var node: MeshInstance3D = _chunk_nodes.get(coord)
	if node == null:
		node = MeshInstance3D.new()
		node.position = Vector3(coord.x * Chunk.SIZE_X, 0, coord.y * Chunk.SIZE_Z)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_chunk_nodes[coord] = node
	var mesh := ArrayMesh.new()
	for i in 2:
		if not result[i].is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result[i], [], {}, ChunkMesher.SURFACE_FLAGS)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _solid_material if i == 0 else _translucent_material)
	node.mesh = mesh
	_apply_models(coord, result[2] if result.size() > 2 else PackedInt32Array())


## Draws model blocks of a chunk with one MultiMesh per model (plus one per arm model for connected
## blocks). Instance colors carry light; oriented blocks rotate by their state.
func _apply_models(coord: Vector2i, instances: PackedInt32Array) -> void:
	_clear_models(coord)
	var chunk = world.chunks.get(coord)
	if chunk == null:
		return
	var origin := Vector3i(coord.x * Chunk.SIZE_X, 0, coord.y * Chunk.SIZE_Z)
	var batches := {}  # mesh -> {transforms: Array[Transform3D], lights: PackedInt32Array}
	for i in range(0, instances.size() - 5, 6):
		var block := instances[i]
		if not _model_meshes.has(block):
			continue
		var local := Vector3i(instances[i + 1], instances[i + 2], instances[i + 3])
		var light := PackedInt32Array([instances[i + 4], instances[i + 5]])
		var group: String = _connect_groups.get(block, "")
		var centered: bool = not registry.defs[block].model_arm.is_empty()
		var center := Vector3(local) + (Vector3(0.5, 0.5, 0.5) if centered else Vector3(0.5, 0.0, 0.5))
		var state: int = chunk.states.get(Chunk.index(local.x, local.y, local.z), 0)
		var basis := Basis(Vector3.UP, (state & 3) * PI * 0.5) if registry.defs[block].orientation == 1 else Basis.IDENTITY
		_batch(batches, _model_meshes[block], Transform3D(basis, center), light)
		if registry.emission_lut[block] > 0:
			batches[_model_meshes[block]].emissive = true
		if _arm_meshes.has(block) and not group.is_empty():
			for dir in ARM_BASES:
				var neighbor := world.get_block_v(origin + local + dir)
				if _connect_groups.get(neighbor, "") == group:
					_batch(batches, _arm_meshes[block], Transform3D(ARM_BASES[dir], center), light)
	var nodes := []
	for mesh: Mesh in batches:
		var batch: Dictionary = batches[mesh]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = mesh
		multimesh.instance_count = batch.transforms.size()
		for n in multimesh.instance_count:
			multimesh.set_instance_transform(n, batch.transforms[n])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = multimesh
		mmi.position = Vector3(origin)
		mmi.set_meta("lights", batch.lights)
		mmi.set_meta("emissive", batch.get("emissive", false))
		add_child(mmi)
		_color_models(mmi)
		nodes.append(mmi)
	if not nodes.is_empty():
		_model_nodes[coord] = nodes


## Rotations taking an arm modelled along -Z to each neighbour direction.
const ARM_BASES := {
	Vector3i(0, 0, -1): Basis(),
	Vector3i(0, 0, 1): Basis(Vector3.UP, PI),
	Vector3i(1, 0, 0): Basis(Vector3.UP, -PI * 0.5),
	Vector3i(-1, 0, 0): Basis(Vector3.UP, PI * 0.5),
	Vector3i(0, 1, 0): Basis(Vector3.RIGHT, PI * 0.5),
	Vector3i(0, -1, 0): Basis(Vector3.RIGHT, -PI * 0.5),
}


static func _batch(batches: Dictionary, mesh: Mesh, xform: Transform3D, light: PackedInt32Array) -> void:
	if not batches.has(mesh):
		batches[mesh] = {"transforms": [], "lights": PackedInt32Array()}
	batches[mesh].transforms.append(xform)
	batches[mesh].lights.append_array(light)


func _clear_models(coord: Vector2i) -> void:
	for mmi: Node in _model_nodes.get(coord, []):
		mmi.queue_free()
	_model_nodes.erase(coord)


func _color_models(mmi: MultiMeshInstance3D) -> void:
	var list: PackedInt32Array = mmi.get_meta("lights")
	# Emissive models (lit lamps) go above 1.0 so the bloom pass picks them up.
	var boost := 1.8 if mmi.get_meta("emissive", false) and graphics.value("bloom") else 1.0
	for n in mmi.multimesh.instance_count:
		var sky := pow(0.8, 15 - list[n * 2]) * _daylight
		var block := pow(0.8, 15 - list[n * 2 + 1])
		mmi.multimesh.set_instance_color(n, Color(maxf(maxf(sky, block), 0.05), maxf(maxf(sky, block * 0.86), 0.05), maxf(maxf(sky, block * 0.66), 0.05)) * boost)


## Advances the replicated world clock and applies daylight to the sky, fog, materials and models.
func _update_time(delta: float) -> void:
	if _day_length > 0.0:
		_time_of_day = fposmod(_time_of_day + delta / _day_length, 1.0)
	_daylight = WorldTime.daylight(_time_of_day)
	if absf(_daylight - _applied_daylight) < 0.005 or _solid_material == null:
		return
	_applied_daylight = _daylight
	var t := inverse_lerp(WorldTime.NIGHT_LIGHT, 1.0, _daylight)
	# Sun low on the horizon warms the light; night is cool and blue.
	var sun_height := sin((_time_of_day - 0.25) * TAU)
	var sun_tint := Color(0.55, 0.62, 0.9).lerp(Color(1.0, 0.72, 0.5), clampf(t * 3.0, 0.0, 1.0)).lerp(Color(1.0, 0.97, 0.92), clampf((sun_height - 0.15) * 2.5, 0.0, 1.0))
	var sun_direction := Vector3(cos((_time_of_day - 0.25) * TAU), sun_height, 0.35).normalized()
	for material in [_solid_material, _translucent_material]:
		material.set_shader_parameter("daylight", _daylight)
		material.set_shader_parameter("sun_tint", Vector3(sun_tint.r, sun_tint.g, sun_tint.b))
		material.set_shader_parameter("sun_direction", sun_direction)
	var horizon := Color(0.05, 0.06, 0.12).lerp(Color(0.72, 0.84, 0.96), t)
	_sky_material.sky_top_color = Color(0.01, 0.02, 0.06).lerp(Color(0.32, 0.54, 0.92), t)
	_sky_material.sky_horizon_color = horizon
	_sky_material.ground_horizon_color = horizon
	_sky_material.ground_bottom_color = Color(0.02, 0.02, 0.04).lerp(Color(0.3, 0.4, 0.55), t)
	_environment.fog_light_color = horizon
	for material in [_solid_material, _translucent_material]:
		material.set_shader_parameter("sky_color", Vector3(_sky_material.sky_top_color.r, _sky_material.sky_top_color.g, _sky_material.sky_top_color.b))
		material.set_shader_parameter("horizon_color", Vector3(horizon.r, horizon.g, horizon.b))
	for nodes: Array in _model_nodes.values():
		for mmi: MultiMeshInstance3D in nodes:
			_color_models(mmi)


# --- Input --------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _chat_input.visible:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var settings = ClientSettings.shared()
		var sensitivity: float = MOUSE_SENSITIVITY * float(settings.get_value("controls/mouse_sensitivity"))
		# Screen pixels, so the interface size does not change how fast the camera turns.
		var moved: Vector2 = event.screen_relative
		yaw = wrapf(yaw - moved.x * sensitivity, -PI, PI)
		_look_delta += event.relative
		pitch = clampf(pitch - moved.y * sensitivity * (-1.0 if settings.get_value("controls/invert_y") else 1.0), -PI * 0.49, PI * 0.49)
	elif _avatar_editor != null:
		if event.is_action_pressed("pause"):
			_close_avatar_editor()
		return
	elif _settings_overlay != null:
		if event.is_action_pressed("pause"):
			close_settings()
			get_viewport().set_input_as_handled()
		return
	elif _guide_screen.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("guide"):
			_set_guide_open(false)
			get_viewport().set_input_as_handled()
		return
	elif _crafting_screen.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("crafting") or event.is_action_pressed("inventory"):
			_set_crafting_open(false)
			get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("pause") and _inventory_screen.visible:
		_set_inventory_open(false)
	elif event.is_action_pressed("inventory") and _welcomed and not dead and (_inventory_screen.visible or _gameplay_input_enabled()):
		_set_inventory_open(not _inventory_screen.visible)
		get_viewport().set_input_as_handled()
	elif dead and (event.is_action_pressed("ui_accept") or event.is_action_pressed("jump")):
		respawn()  # never let a player be stuck on the death screen with no way back
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		_set_paused(not _pause_panel.visible)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not _pause_panel.visible and not _server_ui.has_modal() and not _inventory_screen.visible and not dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().gui_release_focus()  # typing in the dev overlay stops when you go back to playing
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and _welcomed and (_map_screen != null or _gameplay_input_enabled()):
		toggle_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop") and _welcomed and _gameplay_input_enabled():
		drop_selected(event.ctrl_pressed or event.meta_pressed)
	elif event.is_action_pressed("chat") and _welcomed:
		_open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("crafting") and _welcomed:
		Net.c_open_menu.rpc_id(1, "crafting")
	elif event.is_action_pressed("dev") and _welcomed:
		_toggle_dev_overlay()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("guide") and _welcomed and not dead and _gameplay_input_enabled():
		_set_guide_open(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera"):
		camera_mode = (camera_mode + 1) % 3 as CameraMode
	elif event.is_action_pressed("graphics"):
		graphics.cycle()
		_apply_graphics(true)
	elif event.is_action_pressed("toggle_debug"):
		_debug_label.visible = not _debug_label.visible
	elif event.is_action_pressed("toggle_hud"):
		# No message about how to get it back: the label that would say so lives inside the thing being
		# hidden. F1 again is the answer, and it is in Settings > Controls.
		_hud_root.visible = not _hud_root.visible
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_wheel(1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_wheel(-1)
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
		select_slot(event.physical_keycode - KEY_1)


func _gameplay_input_enabled() -> bool:
	var captured := ignore_mouse_capture or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	return captured and not _chat_input.visible and not _pause_panel.visible and not _server_ui.has_modal() \
		and not _inventory_screen.visible and not dead and _avatar_editor == null and not _crafting_screen.visible \
		and not _guide_screen.visible and _settings_overlay == null


func drop_selected(whole_stack := false) -> void:
	if inventory.selected_item() > 0 and not dead:
		Net.c_drop_item.rpc_id(1, whole_stack)


func _set_inventory_open(open: bool) -> void:
	if _inventory_screen.visible == open:
		return
	if open:
		_set_crafting_open(false)
	_inventory_screen.visible = open
	if not open and not _inventory_screen.container.is_empty():
		_inventory_screen.set_container({})
	if open:
		_inventory_screen.refresh()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _welcomed:
			Net.c_inventory_closed.rpc_id(1)
		if not ignore_mouse_capture and not dead:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Crafting -------------------------------------------------------------------------------------

func on_crafting_open(station: Dictionary, stock: Dictionary) -> void:
	_set_inventory_open(false)
	# Opening the guide already closes crafting; crafting did not close the guide, and the guide is built
	# later so it is drawn over the top - including its dim and its left page, which also ate the clicks.
	# Whichever screen is opened last is the one wanted, so it closes the others and comes to the front.
	_set_guide_open(false)
	_pause_panel.visible = false
	_tutorial_hud.panel.visible = false
	_crafting_screen.visible = true
	_bring_to_front(_crafting_screen)
	_crafting_screen.open(station, stock)
	if not _pending_lookup.is_empty():
		_crafting_screen.show_lookup(_pending_lookup.item, _pending_lookup.mode)
		_pending_lookup = {}
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Puts a full-screen panel above its siblings. The HUD is one CanvasLayer and nothing sets a z_index,
## so what is drawn on top is simply whatever was added last - which made the order these screens happen
## to be built in decide which one a player could read.
func _bring_to_front(screen: Control) -> void:
	if screen != null and screen.get_parent() == _hud_root:
		_hud_root.move_child(screen, -1)


func on_crafting_stock(stock: Dictionary) -> void:
	_crafting_screen.stock = stock
	_crafting_screen.refresh()
	_refresh_pin()


func on_crafted(index: int, times: int, stock: Dictionary) -> void:
	_crafting_screen.stock = stock
	_crafting_screen.refresh()
	_refresh_pin()
	if index >= 0 and index < recipes.recipes.size():
		var r: Dictionary = recipes.recipes[index]
		_show_toast(r.output, "Crafted %d x %s" % [r.count * times, items.display_name(r.output)])


func on_known_recipes(known: PackedStringArray, discovery: bool) -> void:
	_crafting_screen.known.clear()
	for recipe_id in known:
		_crafting_screen.known[recipe_id] = true
	_crafting_screen.discovery = discovery
	_crafting_screen.refresh()


## A new recipe: remember it and celebrate (several at once are grouped into one toast).
func on_recipe_learned(index: int, source: String) -> void:
	if index < 0 or index >= recipes.recipes.size():
		return
	var r: Dictionary = recipes.recipes[index]
	_crafting_screen.known[r.id] = true
	_learned_batch.append(index)
	if _learned_batch.size() == 1:
		get_tree().create_timer(0.35).timeout.connect(_announce_learned.bind(source))
	if _crafting_screen.visible:
		_crafting_screen.open(_crafting_screen.station, _crafting_screen.stock)


func _announce_learned(source: String) -> void:
	var batch := _learned_batch
	_learned_batch = []
	if batch.is_empty():
		return
	var first: Dictionary = recipes.recipes[batch[0]]
	var text := "New recipe: %s" % items.display_name(first.output) if batch.size() == 1 else "%d new recipes (%s, ...)" % [batch.size(), items.display_name(first.output)]
	if source == "blueprint":
		text += "  (blueprint)"
	_show_toast(first.output, text)
	_sounds.play_name("engine:discover", Vector3.ZERO, 0.8, 1.0, false)


# --- Guidebook ------------------------------------------------------------------------------------

func _set_guide_open(open: bool, page_id := "") -> void:
	if open:
		if dead or not _welcomed:
			return
		_set_inventory_open(false)
		_set_crafting_open(false)
		_pause_panel.visible = false
		_tutorial_hud.panel.visible = false
		if page_id.is_empty():
			page_id = _tutorial_hud.preferred_page(_guide_screen.read)
		_bring_to_front(_guide_screen)
		_guide_screen.open(page_id)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_sounds.play_name("engine:page", Vector3.ZERO, 0.7, 1.0, false)
		return
	if not _guide_screen.visible:
		return
	_guide_screen.visible = false
	_update_guide_badge()
	if not ignore_mouse_capture and not dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func on_guide_state(unlocked: PackedStringArray, read: PackedStringArray, last: String) -> void:
	_guide_screen.set_state(unlocked, read, last)
	_update_guide_badge()


func on_guide_unlocked(pages: PackedStringArray, notify: bool) -> void:
	var fresh := _guide_screen.add_unlocked(pages)
	_update_guide_badge()
	if not notify or fresh.is_empty() or _guide_screen.visible:
		return
	var page := _guide_screen.registry.get_page(fresh[0])
	var text := "Guide: %s  [%s]" % [page.title, GuideScreen.key_name("guide")] if fresh.size() == 1 \
		else "Guide: %d new pages  [%s]" % [fresh.size(), GuideScreen.key_name("guide")]
	var icon := items.id_of(str(page.icon)) if not str(page.icon).is_empty() else -1
	# After any recipe popup from the same pickup.
	get_tree().create_timer(0.9).timeout.connect(func():
		_show_toast(maxi(icon, 0), text)
		_sounds.play_name("engine:page", Vector3.ZERO, 0.6, 1.1, false))


func on_guide_open(page_id: String) -> void:
	if _guide_screen.visible:
		if not page_id.is_empty():
			_guide_screen.show_page(page_id)
		return
	_set_guide_open(true, page_id)


# --- Dev tools ------------------------------------------------------------------------------------

## F8: open the overlay; with it open, F8 frees the mouse from the game, or closes the overlay.
func _toggle_dev_overlay() -> void:
	if not _dev_overlay.visible:
		_dev_overlay.set_open(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_dev_pick()
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not ignore_mouse_capture:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_close_dev_overlay()


func _close_dev_overlay() -> void:
	_dev_overlay.set_open(false)
	get_viewport().gui_release_focus()
	if not ignore_mouse_capture and not dead and _gameplay_input_enabled_ignoring_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _gameplay_input_enabled_ignoring_mouse() -> bool:
	return not _chat_input.visible and not _pause_panel.visible and not _server_ui.has_modal() and not _inventory_screen.visible \
		and _avatar_editor == null and not _crafting_screen.visible and not _guide_screen.visible and _settings_overlay == null


## Inspects what the crosshair points at, up to 64 blocks away: a mob or item, a player, else a block.
func _dev_pick() -> void:
	var origin := _camera.global_position
	var direction := -_camera.global_basis.z
	var ray := VoxelRaycast.cast(world, registry.targetable_lut, origin, direction, 64.0)
	var best := origin.distance_to(Vector3(ray.position) + Vector3(0.5, 0.5, 0.5)) if ray.hit else 64.0
	var args := {"pos": ray.position} if ray.hit else {}
	for id: int in _entities:
		var view: EntityView = _entities[id]
		var box := view.aabb()
		var t := EntityPhysics.segment_hits_box(origin, direction, best, box.position, box.end)
		if t >= 0.0 and t < best:
			best = t
			args = {"entity": id}
	for peer_id: int in _remote_players:
		var remote: Node3D = _remote_players[peer_id]
		var box := AABB(remote.position - Vector3(0.3, 0, 0.3), Vector3(0.6, 1.8, 0.6))
		var t := EntityPhysics.segment_hits_box(origin, direction, best, box.position, box.end)
		if t >= 0.0 and t < best:
			best = t
			args = {"player": peer_id}
	if args.is_empty():
		args = {"player": multiplayer.get_unique_id()}  # nothing in sight: yourself
	Net.c_dev.rpc_id(1, "inspect", args)


func on_dev(kind: String, data) -> void:
	match kind:
		"draw":
			_debug_draw.add_shapes(data if data is Array else [])
		"denied":
			_dev_overlay.set_open(false)
			_server_ui.show_title("", "Dev tools are for admins (or start the server with --dev)", 3.0)
		_:
			_dev_overlay.receive(kind, data)


# --- Tutorials ------------------------------------------------------------------------------------

func on_tutorial(view: Dictionary) -> void:
	_tutorial_hud.set_view(view)


func on_tutorial_event(kind: String, title: String) -> void:
	_tutorial_hud.step_done(kind)
	if kind == "completed":
		_server_ui.show_title("Tutorial complete!", title, 3.0)


## Script errors on the server, for admins: a red card per error (repeats update its count).
func on_dev_error(e: Dictionary) -> void:
	var key := str(e.get("id", 0))
	var card: PanelContainer = _dev_alerts.get_node_or_null(key)
	if card == null:
		card = PanelContainer.new()
		card.name = key
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.04, 0.04, 0.88) if e.get("level") == "error" else Color(0.16, 0.12, 0.02, 0.88)
		style.border_color = Color(0.95, 0.3, 0.25) if e.get("level") == "error" else Color(0.95, 0.75, 0.25)
		style.border_width_left = 3
		style.set_content_margin_all(8)
		style.set_corner_radius_all(4)
		card.add_theme_stylebox_override("panel", style)
		var label := RichTextLabel.new()
		label.name = "Text"
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.custom_minimum_size = Vector2(420, 0)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("normal_font_size", 13)
		label.add_theme_font_size_override("bold_font_size", 13)
		card.add_child(label)
		_dev_alerts.add_child(card)
		_dev_alerts.move_child(card, 0)
		while _dev_alerts.get_child_count() > 4:
			_dev_alerts.get_child(_dev_alerts.get_child_count() - 1).free()
	var where := " [color=#aaaaaa]%s:%d[/color]" % [e.file, int(e.line)] if not str(e.get("file", "")).is_empty() else ""
	var times := "  [color=#ffcc66]×%d[/color]" % int(e.count) if int(e.get("count", 1)) > 1 else ""
	(card.get_node("Text") as RichTextLabel).text = "[b]%s %s[/b]%s%s\n%s\n[color=#888888]/errors for the list[/color]" % [
		"Error in" if e.get("level") == "error" else "Warning in", e.source, where, times, str(e.message).left(240).replace("[", "[lb]")]
	card.modulate.a = 1.0
	var tween := card.create_tween()
	tween.tween_interval(10.0)
	tween.tween_property(card, "modulate:a", 0.0, 1.0)
	tween.tween_callback(card.queue_free)


func on_tip(tip: Dictionary) -> void:
	_tutorial_hud.show_tip(tip)
	_sounds.play_name("engine:page", Vector3.ZERO, 0.5, 1.2, false)


## "G  Guide (3 new)" in the corner while there are unread pages.
func _update_guide_badge() -> void:
	var count := _guide_screen.unread_count()
	_guide_badge.visible = count > 0 and not _guide_screen.visible
	_guide_badge.text = "[%s] Guide · %d new" % [GuideScreen.key_name("guide"), count]


func _entity_portrait(entity_name: String) -> Node3D:
	var type_id := entity_types.id_of(entity_name)
	if type_id < 0 or (not _entity_parts.has(type_id) and not _entity_sprites.has(type_id)):
		return null
	var view := EntityView.new()
	view.setup(0, entity_types.defs[type_id], _entity_parts.get(type_id, []), _entity_sprites.get(type_id), Vector3.ZERO, 0.0)
	return view


func on_assembled(item: int, item_data: Dictionary) -> void:
	_show_toast(item, "Forged: %s" % String(item_data.get("name", items.display_name(item))))
	_crafting_screen.refresh()


func on_minigame(view: Dictionary) -> void:
	_minigame_screen.set_view(view)
	if String(view.get("phase", "")) == "done":
		var result: Dictionary = view.get("result", {})
		var data: Dictionary = result.get("data", {})
		_show_toast(int(result.get("item", 0)), "%s: %s" % [String(result.get("name", "")), String(data.get("name", items.display_name(int(result.get("item", 0)))))])
		if int(result.get("quality", 0)) >= 3:
			_sounds.play_name("engine:discover", Vector3.ZERO, 0.9, 1.0, false)
		_crafting_screen.refresh()


func on_minigame_event(action: String, t: float, arg: int) -> void:
	_minigame_screen.partner_event(action, t, arg)
	if action == "strike":
		_sounds.play_name("engine:craft", Vector3.ZERO, 0.6, 1.1, false)


func _on_minigame_feedback(kind: String) -> void:
	match kind:
		"perfect":
			_sounds.play_name("engine:crit", Vector3.ZERO, 0.9, randf_range(1.0, 1.1), false)
		"good", "key_hit":
			_sounds.play_name("engine:craft", Vector3.ZERO, 0.7, randf_range(1.05, 1.2), false)
		"miss", "burnt", "key_miss":
			_sounds.play_name("engine:ui_click", Vector3.ZERO, 0.7, 0.6, false)


func on_experiment_result(result: Dictionary) -> void:
	_crafting_screen.set_experiment_result(result)
	if String(result.get("status", "")) == "close":
		_sounds.play_name("engine:ui_click", Vector3.ZERO, 0.6, 0.7, false)


func on_station_session(view: Dictionary) -> void:
	_crafting_screen.set_session(view)


## Floating progress text above a station for everyone nearby ("" removes it).
func on_station_label(pos: Vector3i, text: String) -> void:
	var label: Label3D = _station_labels.get(pos)
	if text.is_empty():
		if label != null:
			label.queue_free()
			_station_labels.erase(pos)
		return
	if label == null:
		label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.pixel_size = 0.006
		label.font_size = 42
		label.outline_size = 10
		label.modulate = Color(1.0, 0.9, 0.55)
		label.no_depth_test = false
		label.position = Vector3(pos) + Vector3(0.5, 1.7, 0.5)
		add_child(label)
		_station_labels[pos] = label
	label.text = text


## Ghost blocks where a structure's missing blocks go (red where a block is in the way). Clears after
## a minute or when the guide is requested again.
func on_structure_guide(missing: Array) -> void:
	if _guide_root != null:
		_guide_root.queue_free()
	_guide_root = Node3D.new()
	add_child(_guide_root)
	var root := _guide_root
	for entry in missing.slice(0, 256):
		if not (entry is Array) or entry.size() != 2 or not (entry[0] is Vector3i):
			continue
		var id := int(entry[1])
		var ghost := MeshInstance3D.new()
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		if id > 0 and registry.is_valid(id):
			ghost.mesh = _item_meshes.mesh_for(id)
			ghost.scale = Vector3.ONE * (0.98 / ItemMesh.BLOCK_SIZE)
			material.albedo_texture = _atlas.texture
			material.albedo_color = Color(0.7, 0.9, 1.0, 0.45)
			material.vertex_color_use_as_albedo = true
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		else:
			var box := BoxMesh.new()
			box.size = Vector3.ONE * 0.98
			ghost.mesh = box
			material.albedo_color = Color(1.0, 0.25, 0.2, 0.35) if id == 0 else Color(1, 1, 1, 0.3)
		ghost.material_override = material
		ghost.position = Vector3(entry[0]) + Vector3.ONE * 0.5
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ghost)
		var tween := ghost.create_tween().set_loops(30)
		tween.tween_property(material, "albedo_color:a", material.albedo_color.a * 0.4, 0.8)
		tween.tween_property(material, "albedo_color:a", material.albedo_color.a, 0.8)
	get_tree().create_timer(60.0).timeout.connect(func():
		if is_instance_valid(root):
			root.queue_free())
	if not missing.is_empty():
		_show_toast(0, "Build guide: %d blocks to place" % missing.size())


## Asks the server to craft a recipe (see RecipeRegistry indices).
func craft_recipe(index: int, times := 1) -> void:
	if index >= 0 and times > 0:
		Net.c_craft.rpc_id(1, index, times)


func _set_crafting_open(open: bool) -> void:
	if open:
		Net.c_open_menu.rpc_id(1, "crafting")
		return
	if not _crafting_screen.visible:
		return
	_crafting_screen.visible = false
	if _welcomed:
		Net.c_crafting_closed.rpc_id(1)
	if not ignore_mouse_capture and not dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Opens the recipe book filtered to what makes (`mode` "make") or uses ("use") an item.
func lookup_recipes(item: int, mode: String) -> void:
	if _crafting_screen.visible:
		_crafting_screen.show_lookup(item, mode)
		return
	_pending_lookup = {"item": item, "mode": mode}
	_set_crafting_open(true)


## Pins a recipe to the HUD (-1 unpins). Saved per server.
func pin_recipe(index: int) -> void:
	_crafting_screen.pinned = index
	var cfg := ConfigFile.new()
	cfg.load(PINS_PATH)
	cfg.set_value("pins", "%s:%d" % [server_address, server_port], recipes.recipes[index].id if index >= 0 else "")
	cfg.save(PINS_PATH)
	_crafting_screen.refresh()
	_refresh_pin()


func _load_pin() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PINS_PATH)
	_crafting_screen.pinned = recipes.index_of(String(cfg.get_value("pins", "%s:%d" % [server_address, server_port], "")))
	_refresh_pin()


func _build_pin_panel() -> void:
	_pin_panel = PanelContainer.new()
	_pin_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pin_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_pin_panel.position = Vector2(-16, 110)
	_pin_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin_panel.add_theme_stylebox_override("panel", CraftingScreen._box(Color(0.05, 0.05, 0.07, 0.7), 8))
	_pin_panel.visible = false
	_hud_root.add_child(_pin_panel)
	_pin_rows = VBoxContainer.new()
	_pin_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin_panel.add_child(_pin_rows)
	_toast = PanelContainer.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.position.y = 70
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel", CraftingScreen._box(Color(0.08, 0.07, 0.04, 0.9), 10))
	_toast.modulate.a = 0.0
	_hud_root.add_child(_toast)


## The pinned recipe's ingredients with what you have, updated as you gather.
func _refresh_pin() -> void:
	if _pin_panel == null:
		return
	var index := _crafting_screen.pinned
	_pin_panel.visible = index >= 0 and index < recipes.recipes.size() and _item_meshes != null
	if not _pin_panel.visible:
		return
	for child in _pin_rows.get_children():
		_pin_rows.remove_child(child)
		child.queue_free()
	var r: Dictionary = recipes.recipes[index]
	var ready: bool = _crafting_screen.craftable_times(index) > 0 or (r.station != "" and _crafting_screen.have_all(index))
	_pin_rows.add_child(_pin_row(r.output, "%s%s" % [items.display_name(r.output), "  ✓" if ready else ""], Color(1.0, 0.82, 0.4)))
	for id: int in r.inputs:
		var got := _crafting_screen.have(id)
		var need := int(r.inputs[id])
		_pin_rows.add_child(_pin_row(id, "%d / %d  %s" % [mini(got, 999), need, items.display_name(id)],
			Color(0.55, 0.9, 0.5) if got >= need else Color(1, 1, 1, 0.85)))
	if r.station != "":
		var hint := Label.new()
		hint.text = "at a %s" % CraftingScreen.station_title(r.station)
		hint.add_theme_font_size_override("font_size", 12)
		hint.modulate = Color(1, 1, 1, 0.55)
		_pin_rows.add_child(hint)


func _pin_row(item: int, text: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = _crafting_screen._icon(item)
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)
	var label := _shadow_label()
	label.text = text
	label.add_theme_color_override("font_color", color)
	row.add_child(label)
	return row


## A short popup with an item icon ("Crafted 4 x Planks"), also used for discoveries.
func _show_toast(item: int, text: String) -> void:
	for child in _toast.get_children():
		_toast.remove_child(child)
		child.queue_free()
	_toast.add_child(_pin_row(item, text, Color(1.0, 0.9, 0.6)))
	_toast.reset_size()
	_toast.pivot_offset = _toast.size * 0.5
	var tween := _toast.create_tween()
	_toast.modulate.a = 1.0
	_toast.scale = Vector2(0.8, 0.8)
	tween.tween_property(_toast, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.6)
	tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func on_container_open(view: Dictionary) -> void:
	_set_crafting_open(false)
	_inventory_screen.set_container(view)
	_set_inventory_open(true)


func on_container_update(view: Dictionary) -> void:
	_inventory_screen.update_container(view)


func on_container_close() -> void:
	if not _inventory_screen.container.is_empty():
		_inventory_screen.set_container({})
		_set_inventory_open(false)


func inventory_click(slot: int, button := 1, shift := false) -> void:
	Net.c_inventory_click.rpc_id(1, slot, button, shift)
	_sounds.play_name("engine:ui_click", Vector3.ZERO, 0.4, 1.0, false)


## In game: your look with this server's cosmetics; saved built-in choices travel to other servers.
func open_avatar_editor() -> void:
	if _avatar_editor != null or _looks == null:
		return
	_set_paused(false)
	var current: Dictionary = _appearances.get(my_id, {}).get("avatar", {})
	var start := LookBuilder.resolve(avatar, player_name).duplicate(true)
	for cat_name in current.get("wear", {}):
		if not Cosmetics.is_builtin(String(current.wear[cat_name].id)):
			var wear: Dictionary = start.get("wear", {})
			wear[cat_name] = current.wear[cat_name]
			start.wear = wear
	_avatar_editor = AvatarEditor.new()
	_avatar_editor.setup(cosmetics, _looks, _player_rig, player_name, start, {"in_game": true, "owned": owned_cosmetics,
		"creations": true, "author": Identity.player_id(_identity) if _identity != null else "", "ugc": ugc})
	_avatar_editor.done.connect(_on_avatar_edited)
	_avatar_editor.cancelled.connect(_close_avatar_editor)
	_hud_root.add_child(_avatar_editor)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_avatar_edited(edited: Dictionary) -> void:
	# Server cosmetics exist only here: the saved portable look keeps its own choice for those categories.
	var portable := edited.duplicate(true)
	var previous: Dictionary = LookBuilder.resolve(avatar, player_name)
	for cat_name in edited.get("wear", {}):
		var worn_id := String(edited.wear[cat_name].id)
		# Built-in cosmetics and the player's own creations travel; other picks belong to this server.
		if not Cosmetics.is_builtin(worn_id) and CreationLibrary.get_manifest(worn_id).is_empty():
			if previous.get("wear", {}).has(cat_name):
				portable.wear[cat_name] = previous.wear[cat_name]
			else:
				portable.wear.erase(cat_name)
	avatar = cosmetics.sanitize_avatar(portable)
	AvatarStore.save_avatar(avatar)
	ugc.offer_worn(edited)
	Net.c_set_avatar.rpc_id(1, edited)
	_close_avatar_editor()


func _close_avatar_editor() -> void:
	if _avatar_editor != null:
		_avatar_editor.queue_free()
		_avatar_editor = null
	_capture_mouse()


## Gives the mouse back to the game, unless something still needs the pointer. Dying is the important
## case: a player who dies, opens chat and closes it again must not lose the cursor the Respawn button
## needs - that left them with no way out but quitting the game.
func _capture_mouse() -> void:
	if dead or ignore_mouse_capture or _pause_panel.visible or _inventory_screen.visible or _server_ui.has_modal():
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_paused(paused: bool) -> void:
	_pause_panel.visible = paused
	_tutorial_hud.panel.visible = false
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_capture_mouse()


func _open_chat() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_chat_input.visible = true
	_chat_input.text = ""
	_chat_input.grab_focus.call_deferred()


func _on_chat_submitted(text: String) -> void:
	_chat_input.visible = false
	_chat_input.release_focus()
	if not text.strip_edges().is_empty():
		Net.c_chat.rpc_id(1, text)
	_capture_mouse()


func _on_chat_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_chat_input.visible = false
		_capture_mouse()
		_chat_input.accept_event()


func _on_ui_action(ui_id: String, action: String) -> void:
	Net.c_ui_action.rpc_id(1, ui_id, action)


## The wheel zooms the map while it is open, and picks a hotbar slot the rest of the time. Reaching for
## the wheel over a map is what everybody does; it used to change the hotbar hidden behind it instead.
func _wheel(steps: int) -> void:
	if _map_screen != null and is_instance_valid(_map_screen) and _map_screen.visible:
		_map_screen.zoom_by(steps)
		get_viewport().set_input_as_handled()
		return
	select_slot(inventory.selected - steps)


## Registers the input actions with the player's key bindings (engine/client/settings/client_settings.gd).
static func _register_input_actions() -> void:
	ClientSettings.shared().apply_bindings()


func _on_setting_changed(key: String) -> void:
	var section := key.get_slice("/", 0)
	if section == "graphics":
		if key in ["graphics/window_mode", "graphics/vsync", "graphics/max_fps"]:
			ClientSettings.shared().apply_display(get_window())
		elif key == "graphics/fov":
			_camera.fov = ClientSettings.shared().get_value(key)
		elif key != "graphics/menu_backdrop":
			_apply_graphics(false)
	elif section == "audio":
		ClientSettings.shared().apply_audio()
	elif section == "accessibility" or key == "interface/scale":
		_apply_accessibility()
	elif key == "interface/compass":
		if _compass != null:
			_compass.visible = bool(ClientSettings.shared().get_value(key))
	elif key == "crafting/relaxed_timing":
		_crafting_screen.load_settings()


func _apply_accessibility() -> void:
	var settings = ClientSettings.shared()
	_effects.shake_scale = settings.get_value("accessibility/camera_shake")
	_effects.flash_scale = settings.get_value("accessibility/flashes")
	settings.apply_ui_scale(get_window())


## The settings screen over the game (from the pause menu).
func open_settings() -> void:
	if _settings_overlay != null:
		return
	_pause_panel.visible = false
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.theme = MenuTheme.build()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 660)
	center.add_child(panel)
	var screen := SettingsScreen.new()
	screen.closable = true
	screen.closed.connect(close_settings)
	panel.add_child(screen)
	_hud_root.add_child(overlay)
	_settings_overlay = overlay


## Players and roles (admins) over the game, in the settings overlay slot.
func open_players_panel() -> void:
	var panel := PlayersPanel.new()
	panel.action_requested.connect(func(action, args): Net.c_roles_panel.rpc_id(1, action, args))
	panel.closed.connect(close_settings)
	_open_overlay(panel)
	_players_panel = panel


func on_roles_panel(state: Dictionary) -> void:
	if _players_panel != null and is_instance_valid(_players_panel):
		_players_panel.receive(state)


## Server settings (admins) over the game, in the settings overlay slot.
func open_server_panel() -> void:
	var panel := ServerPanel.new()
	panel.action_requested.connect(func(action, args): Net.c_server_panel.rpc_id(1, action, args))
	panel.closed.connect(close_settings)
	_open_overlay(panel)
	_server_panel = panel


func on_server_panel(state: Dictionary) -> void:
	if _server_panel != null and is_instance_valid(_server_panel):
		_server_panel.receive(state)


## The worlds this server is linked to, and travel between them.
func open_worlds_panel() -> void:
	var panel := WorldsPanel.new()
	panel.action_requested.connect(func(action, args): Net.c_worlds.rpc_id(1, action, args))
	panel.closed.connect(close_settings)
	_open_overlay(panel)
	_worlds_panel = panel


func on_worlds(state: Dictionary) -> void:
	if _worlds_panel != null and is_instance_valid(_worlds_panel):
		_worlds_panel.receive(state)


## The map (M): the world from above with everyone on it.
func toggle_map() -> void:
	if _map_screen != null and is_instance_valid(_map_screen):
		close_map()
		return
	var screen := MapScreen.new()
	screen.client = self
	screen.closed.connect(close_map)
	screen.refresh_requested.connect(func(): Net.c_map.rpc_id(1))
	_hud_root.add_child(screen)
	_map_screen = screen
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_map() -> void:
	if _map_screen != null and is_instance_valid(_map_screen):
		_map_screen.queue_free()
	_map_screen = null
	if not _pause_panel.visible and not _inventory_screen.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func on_map(state: Dictionary) -> void:
	_map_state = state
	if _map_screen != null and is_instance_valid(_map_screen):
		_map_screen.receive(state)
	if _compass != null:
		_compass.receive(state)


## Shows a screen over the game in a centred panel (settings, friends, players).
func _open_overlay(content: Control) -> void:
	if _settings_overlay != null:
		return
	_pause_panel.visible = false
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.theme = MenuTheme.build()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(900, 660)
	center.add_child(frame)
	frame.add_child(content)
	_hud_root.add_child(overlay)
	_settings_overlay = overlay


## Friends and party over the game (from the pause menu), reusing the settings overlay slot.
func open_friends() -> void:
	if _settings_overlay != null:
		return
	_pause_panel.visible = false
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.theme = MenuTheme.build()
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 660)
	center.add_child(panel)
	if social == null:
		var none := Label.new()
		none.text = "Friends are available when the game is started from the main menu."
		panel.add_child(none)
	else:
		var friends := FriendsPanel.new()
		friends.social = social
		friends.closable = true
		friends.closed.connect(close_settings)
		friends.join_requested.connect(func(address: String, port: int, server_name: String):
			close_settings()
			if address == server_address and port == server_port:
				notify("You are already on %s" % server_name)
			else:
				join_friend_requested.emit(address, port, server_name))
		panel.add_child(friends)
	_hud_root.add_child(overlay)
	_settings_overlay = overlay


func close_settings() -> void:
	if _settings_overlay != null:
		_settings_overlay.queue_free()
		_settings_overlay = null
		_pause_panel.visible = true


## Pushes the current graphics preset into post-processing, materials and (when AO changes) meshes.
func _apply_graphics(announce: bool) -> void:
	graphics.apply_environment(_environment, get_viewport())
	_effects.quality = 0.5 if graphics.preset == "fast" else 1.0
	if _solid_material != null:
		for material in [_solid_material, _translucent_material]:
			material.set_shader_parameter("enable_sway", graphics.value("sway"))
			material.set_shader_parameter("enable_ao", graphics.value("ambient_occlusion"))
			material.set_shader_parameter("fancy_water", graphics.value("fancy_water"))
			material.set_shader_parameter("emissive_boost", 1.6 if graphics.value("bloom") else 1.0)
	if not _mesh_context.is_empty() and _mesh_context.ambient_occlusion != graphics.value("ambient_occlusion"):
		_mesh_context.ambient_occlusion = graphics.value("ambient_occlusion")
		for coord: Vector2i in world.chunks:
			_mark_dirty(coord, false)
	_applied_daylight = -1.0
	for nodes: Array in _model_nodes.values():
		for mmi: MultiMeshInstance3D in nodes:
			_color_models(mmi)
	if announce:
		_server_ui.show_title("", "Graphics: %s" % graphics.preset, 1.5)


# --- Scene & HUD construction -------------------------------------------------------------------

func _build_scene() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	_sky_material = sky_material
	sky_material.sky_top_color = Color(0.32, 0.54, 0.92)
	sky_material.sky_horizon_color = Color(0.72, 0.84, 0.96)
	sky_material.ground_horizon_color = Color(0.72, 0.84, 0.96)
	sky_material.ground_bottom_color = Color(0.3, 0.4, 0.55)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	_environment = env
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Constant ambient + sun give models their shape; their brightness (day/night, torches) comes
	# from per-instance light colors, like the block shader.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.72, 0.84, 0.96)
	env.fog_depth_begin = RENDER_DISTANCE * 0.55
	env.fog_depth_end = RENDER_DISTANCE * 0.95
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.75
	_sun = sun
	add_child(sun)

	_effects = EffectPlayer.new()
	add_child(_effects)
	add_child(_self_anchor)
	_camera = Camera3D.new()
	_camera.fov = ClientSettings.shared().get_value("graphics/fov")
	_camera.near = 0.05
	_camera.far = RENDER_DISTANCE * 1.5
	add_child(_camera)
	_camera.make_current()
	_view_model = ViewModel.new()
	_camera.add_child(_view_model)
	var listener := AudioListener3D.new()
	_camera.add_child(listener)
	listener.make_current()
	_sounds = SoundPlayer.new()
	add_child(_sounds)
	_music = MusicPlayer.new()
	_music.fetch = fetch_lazy_asset
	add_child(_music)

	_highlight = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.004
	_highlight.mesh = box
	var highlight_material := StandardMaterial3D.new()
	highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	highlight_material.albedo_color = Color(1, 1, 1, 0.18)
	_highlight.material_override = highlight_material
	_highlight.visible = false
	add_child(_highlight)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_root = Control.new()
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud_root)

	var crosshair := Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(crosshair)
	for rect in [Rect2(-10, -1, 20, 2), Rect2(-1, -10, 2, 20)]:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.85)
		bar.position = rect.position
		bar.size = rect.size
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crosshair.add_child(bar)

	_server_ui = ServerUI.new()
	_server_ui.action_pressed.connect(_on_ui_action)
	_hud_root.add_child(_server_ui)

	_debug_label = _shadow_label()
	_debug_label.position = Vector2(10, 8)
	_hud_root.add_child(_debug_label)

	_status_label = _shadow_label()
	_status_label.set_anchors_preset(Control.PRESET_CENTER)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status_label.position.y = -60
	_status_label.add_theme_font_size_override("font_size", 28)
	_hud_root.add_child(_status_label)

	_compass = Compass.new()
	_compass.visible = bool(ClientSettings.shared().get_value("interface/compass"))
	_hud_root.add_child(_compass)
	# What the crosshair is on, under the compass. Asked for in the first playtest: a child pointing at
	# something has no other way to learn its name, and the name is what the guide and the recipe book
	# are indexed by. Only shown when there is something there, so it is not a permanent label.
	_look_label = _shadow_label()
	_look_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_look_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_look_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_look_label.position.y = 48  # the compass is 34 tall at the top, plus its own 8 of margin
	_look_label.add_theme_font_size_override("font_size", 15)
	_look_label.modulate.a = 0.0
	_hud_root.add_child(_look_label)
	# Above the whole status stack, not across it. Hearts sit 74 up and the armour row 100, and the name
	# was at 72 - centred, so any item whose name was longer than a word or two ran underneath both rows
	# and could not be read. The z_index is belt and braces: nothing else in the HUD sets one, so this
	# keeps the name on top whatever gets added below it later. (playtest, 2026-09-18)
	_held_label = _shadow_label()
	_held_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_held_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_held_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_held_label.position.y -= 128
	_held_label.z_index = 1
	_held_label.add_theme_font_size_override("font_size", 18)
	_held_label.modulate.a = 0.0
	_hud_root.add_child(_held_label)
	_hotbar = HBoxContainer.new()
	_hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hotbar.position.y -= 12
	_hotbar.add_theme_constant_override("separation", 4)
	_hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_hotbar)

	_heart_textures = [_heart_image(1.0), _heart_image(0.5), _heart_image(0.0)]
	_hearts = HBoxContainer.new()
	_hearts.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hearts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hearts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hearts.position.y -= 74
	_hearts.position.x -= 132  # left of center; hunger is on the right
	_hearts.add_theme_constant_override("separation", 2)
	_hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_hearts)
	for i in 10:
		var heart := TextureRect.new()
		heart.custom_minimum_size = Vector2(22, 22)
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hearts.add_child(heart)

	_hunger_textures = [_drumstick_image(1.0), _drumstick_image(0.5), _drumstick_image(0.0)]
	_hunger_bar = HBoxContainer.new()
	_hunger_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hunger_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hunger_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hunger_bar.position.y -= 74
	_hunger_bar.position.x += 132
	_hunger_bar.add_theme_constant_override("separation", 2)
	_hunger_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hunger_bar.alignment = BoxContainer.ALIGNMENT_END
	_hud_root.add_child(_hunger_bar)
	for i in 10:
		var drumstick := TextureRect.new()
		drumstick.custom_minimum_size = Vector2(22, 22)
		drumstick.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drumstick.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		drumstick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hunger_bar.add_child(drumstick)

	_armor_textures = [ItemVisuals.shield_icon(1.0), ItemVisuals.shield_icon(0.5), ItemVisuals.shield_icon(0.0)]
	_armor_bar = HBoxContainer.new()
	_armor_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_armor_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_armor_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_armor_bar.position.y -= 100
	_armor_bar.position.x -= 132
	_armor_bar.add_theme_constant_override("separation", 2)
	_armor_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_armor_bar.visible = false
	_hud_root.add_child(_armor_bar)
	for i in 10:
		var shield := TextureRect.new()
		shield.custom_minimum_size = Vector2(22, 22)
		shield.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shield.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		shield.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_armor_bar.add_child(shield)

	_hurt_flash = ColorRect.new()
	_hurt_flash.color = Color(0.8, 0.0, 0.0, 0.0)
	_hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_hurt_flash)

	_chat_log = VBoxContainer.new()
	_chat_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chat_log.position = Vector2(12, -110)
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_chat_log)

	_chat_input = LineEdit.new()
	_chat_input.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_input.position = Vector2(12, -100)
	_chat_input.custom_minimum_size = Vector2(480, 0)
	_chat_input.placeholder_text = "Chat or /command (Enter to send, Esc to cancel)"
	_chat_input.max_length = 160
	_chat_input.visible = false
	_chat_input.text_submitted.connect(_on_chat_submitted)
	_chat_input.gui_input.connect(_on_chat_gui_input)
	_hud_root.add_child(_chat_input)

	_pause_panel = PanelContainer.new()
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause_panel.visible = false
	_hud_root.add_child(_pause_panel)
	var pause_box := VBoxContainer.new()
	pause_box.add_theme_constant_override("separation", 10)
	_pause_panel.add_child(pause_box)
	var resume := Button.new()
	resume.text = "Resume"
	resume.custom_minimum_size = Vector2(240, 44)
	resume.pressed.connect(_set_paused.bind(false))
	pause_box.add_child(resume)
	var guide_button := Button.new()
	guide_button.text = "Guidebook"
	guide_button.custom_minimum_size = Vector2(240, 44)
	guide_button.pressed.connect(func(): _set_guide_open(true))
	pause_box.add_child(guide_button)
	for entry in [["Worlds…", open_worlds_panel], ["Server settings…", open_server_panel], ["Players and roles…", open_players_panel], ["Friends…", open_friends], ["Invite friends…", open_invite_dialog], ["Report a creation…", open_report_dialog], ["Review creations (admins)", open_ugc_review]]:
		var ugc_button := Button.new()
		ugc_button.text = entry[0]
		ugc_button.custom_minimum_size = Vector2(240, 44)
		ugc_button.pressed.connect(entry[1])
		pause_box.add_child(ugc_button)
	var tutorials_button := Button.new()
	tutorials_button.text = "Tutorials"
	tutorials_button.custom_minimum_size = Vector2(240, 44)
	tutorials_button.pressed.connect(func():
		_pause_panel.visible = false
		_tutorial_hud.open_panel())
	pause_box.add_child(tutorials_button)
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.custom_minimum_size = Vector2(240, 44)
	settings_button.pressed.connect(open_settings)
	pause_box.add_child(settings_button)
	var customize := Button.new()
	customize.text = "Customize avatar"
	customize.custom_minimum_size = Vector2(240, 44)
	customize.pressed.connect(open_avatar_editor)
	pause_box.add_child(customize)
	var quit := Button.new()
	quit.text = "Stop server & quit to menu" if not admin_token.is_empty() else "Disconnect"
	quit.custom_minimum_size = Vector2(240, 44)
	quit.pressed.connect(disconnect_from_server)
	pause_box.add_child(quit)

	_crafting_screen = CraftingScreen.new()
	_crafting_screen.items = items
	_crafting_screen.recipes = recipes
	_crafting_screen.inventory = inventory
	_crafting_screen.visible = false
	_crafting_screen.craft_requested.connect(craft_recipe)
	_crafting_screen.pin_requested.connect(func(index): pin_recipe(-1 if index == _crafting_screen.pinned else index))
	_crafting_screen.closed.connect(_set_crafting_open.bind(false))
	_crafting_screen.station_action.connect(func(action): Net.c_station_action.rpc_id(1, action))
	_crafting_screen.coop_action.connect(func(action, arg): Net.c_station_coop.rpc_id(1, action, arg))
	_crafting_screen.experiment_requested.connect(func(grid): Net.c_experiment.rpc_id(1, grid))
	_crafting_screen.assemble_requested.connect(func(assembly_name, slots): Net.c_assemble.rpc_id(1, assembly_name, slots))
	_crafting_screen.skill_requested.connect(func(product, assist, with_partner): Net.c_skill_craft.rpc_id(1, product, assist, with_partner))
	_crafting_screen.minigame_join_requested.connect(func(game_id): Net.c_minigame_join.rpc_id(1, game_id))
	_crafting_screen.load_settings()
	_hud_root.add_child(_crafting_screen)
	_minigame_screen = MinigameScreen.new()
	_minigame_screen.items = items
	_minigame_screen.visible = false
	_minigame_screen.input_sent.connect(func(action, t, arg): Net.c_minigame_input.rpc_id(1, action, t, arg))
	_minigame_screen.join_requested.connect(func(game_id): Net.c_minigame_join.rpc_id(1, game_id))
	_minigame_screen.feedback.connect(_on_minigame_feedback)
	_hud_root.add_child(_minigame_screen)
	_guide_badge = Label.new()
	_guide_badge.visible = false
	# Left side, above the tutorial tracker.
	_guide_badge.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_guide_badge.position = Vector2(18, -182)
	_guide_badge.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	_guide_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_guide_badge.add_theme_constant_override("outline_size", 5)
	_hud_root.add_child(_guide_badge)
	_dev_alerts = VBoxContainer.new()
	_dev_alerts.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dev_alerts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dev_alerts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dev_alerts.position = Vector2(-16, -150)
	_dev_alerts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_dev_alerts)
	_debug_draw = DebugDraw.new()
	add_child(_debug_draw)
	_tutorial_hud = TutorialHud.new()
	_tutorial_hud.client = self
	_tutorial_hud.action_requested.connect(func(action, arg): Net.c_tutorial.rpc_id(1, action, arg))
	_hud_root.add_child(_tutorial_hud)
	_guide_screen = GuideScreen.new()
	_guide_screen.items = items
	_guide_screen.recipes = recipes
	_guide_screen.entity_types = entity_types
	_guide_screen.crafting = _crafting_screen
	_guide_screen.make_entity_view = _entity_portrait
	_guide_screen.texture_of = func(asset: String) -> Texture2D: return _asset_textures.get(asset)
	_guide_screen.visible = false
	_guide_screen.closed.connect(_set_guide_open.bind(false))
	_guide_screen.page_viewed.connect(func(page_id):
		Net.c_guide_read.rpc_id(1, page_id)
		_update_guide_badge())
	_guide_screen.lookup_requested.connect(func(item, mode):
		_set_guide_open(false)
		lookup_recipes(item, mode))
	_hud_root.add_child(_guide_screen)
	_dev_overlay = DevOverlay.new()
	_dev_overlay.visible = false
	_dev_overlay.request.connect(func(action, args):
		if _welcomed:  # the overlay subscribes while it is built, before there is a server to ask
			Net.c_dev.rpc_id(1, action, args))
	_dev_overlay.pick_requested.connect(_dev_pick)
	_dev_overlay.closed.connect(_close_dev_overlay)
	_hud_root.add_child(_dev_overlay)
	_build_pin_panel()

	_inventory_screen = InventoryScreen.new()
	_inventory_screen.inventory = inventory
	_inventory_screen.items = items
	_inventory_screen.visible = false
	_inventory_screen.slot_clicked.connect(inventory_click)
	_inventory_screen.lookup_requested.connect(lookup_recipes)
	_hud_root.add_child(_inventory_screen)

	_death_panel = Control.new()
	_death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_panel.visible = false
	_hud_root.add_child(_death_panel)
	var death_bg := ColorRect.new()
	death_bg.color = Color(0.45, 0.0, 0.0, 0.45)
	death_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_panel.add_child(death_bg)
	var death_box := VBoxContainer.new()
	death_box.set_anchors_preset(Control.PRESET_CENTER)
	death_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	death_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	death_box.add_theme_constant_override("separation", 16)
	_death_panel.add_child(death_box)
	_death_label = _shadow_label()
	_death_label.text = "You died"
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.add_theme_font_size_override("font_size", 56)
	death_box.add_child(_death_label)
	var death_hint := _shadow_label()
	death_hint.text = "Press Enter to come back"
	death_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_hint.add_theme_font_size_override("font_size", 20)
	death_box.add_child(death_hint)
	_build_sleep_panel()
	_respawn_button = Button.new()
	_respawn_button.text = "Respawn"
	_respawn_button.custom_minimum_size = Vector2(240, 48)
	_respawn_button.pressed.connect(respawn)
	death_box.add_child(_respawn_button)


func _build_sleep_panel() -> void:
	_sleep_panel = Control.new()
	_sleep_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sleep_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sleep_panel.visible = false
	_hud_root.add_child(_sleep_panel)
	_sleep_fade = ColorRect.new()
	_sleep_fade.color = Color(0.02, 0.02, 0.06, 0.0)
	_sleep_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sleep_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sleep_panel.add_child(_sleep_fade)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.position.y -= 140
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	_sleep_panel.add_child(box)
	_sleep_label = _shadow_label()
	_sleep_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sleep_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_sleep_label)
	var leave := Button.new()
	leave.text = "Leave bed"
	leave.custom_minimum_size = Vector2(200, 44)
	leave.pressed.connect(leave_bed)
	box.add_child(leave)


func leave_bed() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _leave_bed_sent > 0.5:
		_leave_bed_sent = now
		Net.c_leave_bed.rpc_id(1)


func on_sleep(state_info: Dictionary) -> void:
	var was := not _sleep.is_empty()
	if bool(state_info.get("sleeping", false)):
		var started: float = _sleep.get("started", Time.get_ticks_msec() / 1000.0 - float(state_info.get("since", 0.0)))
		_sleep = state_info.duplicate()
		_sleep.started = started
		_sleep_panel.visible = true
		if not was:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_update_sleep()
	else:
		_sleep = {}
		_sleep_panel.visible = false
		_sleep_fade.color.a = 0.0
		if was and not dead and not _inventory_screen.visible and not _crafting_screen.visible:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Darkens the screen while asleep and shows who else is in bed.
func _update_sleep() -> void:
	var t := Time.get_ticks_msec() / 1000.0 - float(_sleep.get("started", 0.0))
	_sleep_fade.color.a = clampf(t / maxf(float(_sleep.get("seconds", 3.0)), 0.1), 0.0, 1.0) * 0.85
	var asleep := int(_sleep.get("asleep", 1))
	var needed := int(_sleep.get("needed", 1))
	var dots := ".".repeat(1 + int(t * 2.0) % 3)
	_sleep_label.text = "Sleeping%s" % dots if asleep >= needed else "Sleeping%s  %d / %d players in bed" % [dots, asleep, needed]


func _rebuild_hotbar() -> void:
	for slot in _hotbar_slots:
		slot.queue_free()
	_hotbar_slots.clear()
	for i in Inventory.HOTBAR:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(52, 52)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.45)
		style.set_border_width_all(3)
		slot.add_theme_stylebox_override("panel", style)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var count := _shadow_label()
		count.name = "Count"
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 4)
		count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count.grow_vertical = Control.GROW_DIRECTION_BEGIN
		slot.add_child(count)
		# The key that picks this slot, so nobody has to be told that 1-9 work.
		var key := _shadow_label()
		key.name = "Key"
		key.text = str(i + 1)
		key.add_theme_font_size_override("font_size", 11)
		key.modulate = Color(1, 1, 1, 0.55)
		key.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 3)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(key)
		_hotbar.add_child(slot)
		_hotbar_slots.append(slot)
	_refresh_hotbar()


func _refresh_hotbar() -> void:
	_refresh_hearts()
	_refresh_hunger()
	if _hotbar_slots.is_empty() or _atlas.is_empty():
		return
	for i in Inventory.HOTBAR:
		var slot := _hotbar_slots[i]
		var style: StyleBoxFlat = slot.get_theme_stylebox("panel")
		style.border_color = Color.WHITE if i == inventory.selected else Color(0, 0, 0, 0.6)
		var id := inventory.ids[i]
		var has_item := items.is_valid(id) and (inventory.creative or inventory.counts[i] > 0)
		var icon: TextureRect = slot.get_node("Icon")
		var count: Label = slot.get_node("Count")
		if has_item:
			icon.texture = _item_icons.texture(id, inventory.data[i])
		else:
			icon.texture = null
		count.text = str(inventory.counts[i]) if has_item and not inventory.creative and inventory.counts[i] > 1 else ""
		ItemVisuals.update_wear_bar(slot, items, id if has_item else 0, inventory.data[i])
	_show_held_name()


func _refresh_armor() -> void:
	if _armor_bar == null:
		return
	var armor := float(stats.get("armor", 0.0))
	_armor_bar.visible = _welcomed and not inventory.creative and armor > 0.0
	for i in 10:
		var fill := clampf((armor - i * 2.0) / 2.0, 0.0, 1.0)
		_armor_bar.get_child(i).texture = _armor_textures[0 if fill > 0.75 else (1 if fill > 0.25 else 2)]


## Drumsticks fill from the right (like hunger draining toward the hotbar's center).
func _refresh_hunger() -> void:
	if _hunger_bar == null:
		return
	_hunger_bar.visible = _welcomed and not inventory.creative and hunger >= 0.0
	var now := Time.get_ticks_msec() / 1000.0
	for i in 10:
		var fill := clampf((hunger - i * 2.0) / 2.0, 0.0, 1.0)
		var icon: TextureRect = _hunger_bar.get_child(9 - i)
		icon.texture = _hunger_textures[0 if fill > 0.75 else (1 if fill > 0.25 else 2)]
		# Shake when starving; saturation shows as a faint golden tint.
		icon.position.y = sin(now * 30.0 + i * 1.7) * 1.5 if hunger <= 6.0 and hunger >= 0.0 else 0.0
		icon.modulate = Color(1.0, 0.95, 0.75) if saturation > float(i) * 2.0 else Color.WHITE


## 9x8 pixel drumstick: `fill` 1 = full, 0.5 = half, 0 = empty outline.
static func _drumstick_image(fill: float) -> ImageTexture:
	var rows := ["00011100", "00111110", "00111110", "00111110", "01011100", "01100000", "11000000"]
	var img := Image.create(9, 8, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in 8:
			if rows[y][x] != "1":
				continue
			var bone := x < 3 and y >= 4
			var filled := fill >= 1.0 or (fill > 0.0 and x >= 4)
			var color := Color(0.92, 0.88, 0.8) if bone else Color(0.72, 0.42, 0.18)
			img.set_pixel(x, y + 1, color if filled else Color(0.12, 0.08, 0.05, 0.85))
	return ImageTexture.create_from_image(img)


func on_hunger(value: float, sat: float) -> void:
	var before := hunger
	hunger = value
	saturation = sat
	_refresh_hunger()
	if value > before and before >= 0.0 and _hunger_bar != null and _hunger_bar.visible:
		# A meal landed: the drumsticks that filled pop one after another with a warm flash.
		var first := floori(before / 2.0)
		var last := mini(ceili(value / 2.0), 10)
		for i in range(first, last):
			var icon: TextureRect = _hunger_bar.get_child(9 - i)
			icon.pivot_offset = icon.size * 0.5
			var tween := icon.create_tween()
			tween.tween_interval(0.05 * (i - first))
			tween.tween_property(icon, "scale", Vector2.ONE * 1.45, 0.08)
			tween.parallel().tween_property(icon, "self_modulate", Color(1.6, 1.3, 0.7), 0.08)
			tween.tween_property(icon, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.parallel().tween_property(icon, "self_modulate", Color.WHITE, 0.25)


func _refresh_hearts() -> void:
	if _hearts == null:
		return
	_hearts.visible = _welcomed and not inventory.creative
	var per_heart := max_health / 10.0
	for i in 10:
		var fill := clampf((health - i * per_heart) / per_heart, 0.0, 1.0)
		_hearts.get_child(i).texture = _heart_textures[0 if fill > 0.75 else (1 if fill > 0.25 else 2)]


## 9x9 pixel heart: `fill` 1 = full, 0.5 = left half, 0 = empty outline.
static func _heart_image(fill: float) -> ImageTexture:
	var rows := ["01100110", "11111111", "11111111", "11111111", "01111110", "00111100", "00011000"]
	var img := Image.create(9, 8, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in 8:
			if rows[y][x] != "1":
				continue
			var red := fill >= 1.0 or (fill > 0.0 and x < 4)
			img.set_pixel(x, y + 1, Color(0.9, 0.1, 0.15) if red else Color(0.18, 0.05, 0.06, 0.85))
	return ImageTexture.create_from_image(img)


## Names what is in hand when the selection (or the item in that slot) changes.
## Names whatever the crosshair is on: a creature if one is in the way, otherwise the block. Fades out
## when there is nothing, so an empty sky is an empty screen.
func _show_looking_at() -> void:
	if _look_label == null:
		return
	var text := ""
	if not _entity_target.is_empty():
		var id := int(_entity_target.get("id", 0))
		if int(_entity_target.get("kind", 0)) == 1:
			var other = _remote_players.get(id)
			text = str(other.player_name) if other != null and "player_name" in other else ""
		else:
			var view: EntityView = _entities.get(id)
			text = str(view.type_def.get("display_name", "")) if view != null else ""
	elif _target.hit and registry.is_valid(int(_target.block)):
		text = str(registry.defs[int(_target.block)].get("display_name", ""))
	if text.is_empty():
		_look_label.modulate.a = maxf(_look_label.modulate.a - 0.08, 0.0)
		return
	if _look_label.text != text:
		_look_label.text = text
	_look_label.modulate.a = 0.85


func _show_held_name() -> void:
	if _held_label == null:
		return
	var id := inventory.ids[inventory.selected]
	var empty: bool = not items.is_valid(id) or (not inventory.creative and inventory.counts[inventory.selected] <= 0)
	var key := 0 if empty else id
	if key == _held_shown:
		return
	_held_shown = key
	_held_label.text = "" if empty else items.display_name(id)
	_held_label.modulate.a = 0.0 if empty else 1.0
	_held_until = Time.get_ticks_msec() / 1000.0 + 2.0


func _shadow_label() -> Label:
	var label := Label.new()
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _set_status(text: String) -> void:
	_status_label.text = text
	_status_label.visible = not text.is_empty()


func _update_hud() -> void:
	if hunger <= 6.0 and hunger >= 0.0:
		_refresh_hunger()  # the drumsticks shake
	var now := Time.get_ticks_msec() / 1000.0
	for line in _chat_log.get_children():
		var age: float = now - float(line.get_meta("born", now))
		line.modulate.a = clampf((CHAT_LINE_LIFETIME - age) / 2.0, 0.0, 1.0) if not _chat_input.visible else 1.0

	if not _debug_label.visible:
		return
	var p := state.position
	var target_text := "none"
	if _target.hit:
		target_text = "%s %s" % [registry.display_name(_target.block), _target.position]
	var selected := inventory.selected_item()
	_debug_label.text = "\n".join([
		"%s - %s  %d fps" % [server_info.get("name", "?"), server_info.get("game", "?"), Engine.get_frames_per_second()],
		"XYZ %.2f / %.2f / %.2f   chunk %s   time %02d:%02d (light %.2f)" % [p.x, p.y, p.z, VoxelWorld.chunk_coord_of(p),
			int(_time_of_day * 24.0), int(fmod(_time_of_day * 1440.0, 60.0)), _daylight],
		"Ping %d ms   pending inputs %d   corrections %d" % [Net.get_ping_ms(), _pending_inputs.size(), _correction_count],
		"Chunks %d   meshed %d   mesh queue %d (+%d running)" % [world.chunks.size(), _chunk_nodes.size(), _mesh_dirty.size(), _mesh_jobs.size()],
		"Players %d   %s   holding %s   target %s" % [_remote_players.size() + 1, "creative" if inventory.creative else "survival",
			items.display_name(selected) if selected > 0 else "nothing", target_text],
		"Entities %d   health %.1f / %.0f   sounds played %d" % [_entities.size(), health, max_health, _sounds.played],
		"Graphics: %s (%d%% render scale)   [F4] change" % [graphics.preset, roundi(graphics.value("render_scale") * 100)],
		"[F3] debug  [T] chat  [E] inventory  [Q] drop  [C] crafting  [Esc] menu  [1-9 / wheel] slot",
	])
