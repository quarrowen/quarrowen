extends Node3D
## Universal game client. Knows nothing about any particular game: it downloads the server's block
## definitions, textures and physics rules, renders streamed chunks, predicts local movement and
## edits (the server confirms or corrects them), and draws server-described UI.

signal exited(message: String)

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
const Identity = preload("res://engine/shared/identity.gd")
const EntityRegistry = preload("res://engine/shared/entity_registry.gd")
const EntityView = preload("res://engine/client/entity_view.gd")
const EntityPhysics = preload("res://engine/shared/entity_physics.gd")
const SoundPlayer = preload("res://engine/client/sound_player.gd")
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
## Server cosmetics you own on this server.
var owned_cosmetics := PackedStringArray()
var entity_types := EntityRegistry.new()
var health := 20.0
var max_health := 20.0
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
var _input_seq := 0
var _pending_inputs: Array = []
var _recent_packets: Array[PackedByteArray] = []
var _prev_position := Vector3.ZERO
var _render_offset := Vector3.ZERO
var _correction_count := 0

var _manifest := {}  # asset name -> {hash, size}
var _downloads := {}  # hash -> PackedByteArray being received
var _download_total := 0
var _download_received := 0
var _asset_textures := {}  # asset name -> ImageTexture
var _mesh_context := {}

var _chunk_nodes := {}  # Vector2i -> MeshInstance3D
var _mesh_dirty := {}  # Vector2i -> true
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
var _hotbar_slots: Array[Panel] = []
var _chat_log: VBoxContainer
var _chat_input: LineEdit
var _pause_panel: PanelContainer
var _hearts: HBoxContainer
var _heart_textures := []  # [full, half, empty]
var _hurt_flash: ColorRect
var _death_panel: Control
var _death_label: Label
var _inventory_screen: InventoryScreen
var _volume_slider: HSlider


func _ready() -> void:
	graphics.load_saved()
	if not (avatar is Dictionary):
		avatar = AvatarStore.load_avatar()
	_register_input_actions()
	_build_scene()
	_build_hud()
	_apply_graphics(false)
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


func on_challenge(nonce: PackedByteArray) -> void:
	_set_status("Authenticating...")
	Net.c_auth.rpc_id(1, Identity.sign(test_signing_key if test_signing_key != null else _identity, nonce))


func _on_connection_failed() -> void:
	if _connect_attempts < MAX_CONNECT_ATTEMPTS and not _exiting:
		Net.close()
		await get_tree().create_timer(0.5).timeout
		if not _exiting:
			_connect()
		return
	var message := "Could not connect to %s:%d" % [server_address, server_port]
	if Net.has_pinned_identity(server_address, server_port):
		message += ". If the server is up, its identity may have changed since your last visit (reinstalled, or someone impersonating it)."
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


func on_kick(reason: String) -> void:
	_leave("Kicked: %s" % reason)


# --- Content download ---------------------------------------------------------------------------

func on_server_info(info: Dictionary, content: Dictionary, manifest: Array) -> void:
	if phase != Phase.CONNECTING:
		return
	server_info = info
	if not registry.load_network(content.get("blocks")) or not items.load_network(content.get("items", []), content.get("equipment_slots"), content.get("stats")):
		_leave("Server sent invalid block or item definitions")
		return
	inventory.set_equipment_slots(items.slot_names())
	_player_rig = PlayerRig.sanitize(content.get("player_rig"))
	cosmetics.load_network(content.get("cosmetics"))
	Net.c_set_avatar.rpc_id(1, avatar)
	stats = items.stats.duplicate()
	if content.get("rules") is Dictionary:
		on_rules(content.rules)
	if not entity_types.load_network(content.get("entities", [])) or not _sounds.registry.load_network(content.get("sounds", [])):
		_leave("Server sent invalid entity or sound definitions")
		return

	var total_size := 0
	var missing := PackedStringArray()
	for entry in manifest.slice(0, Protocol.MAX_ASSETS):
		if not (entry is Array) or entry.size() != 3 or not (entry[0] is String) or not (entry[1] is String):
			continue
		var hash: String = entry[1]
		var size := int(entry[2])
		if not ContentCache.is_valid_hash(hash) or size < 0 or size > Protocol.MAX_ASSET_SIZE:
			continue
		total_size += size
		if total_size > Protocol.MAX_TOTAL_ASSET_SIZE:
			_leave("Server content is too large")
			return
		_manifest[entry[0]] = {"hash": hash, "size": size}
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


func on_asset_piece(hash: String, offset: int, total: int, bytes: PackedByteArray) -> void:
	if phase != Phase.DOWNLOADING or not _downloads.has(hash):
		return
	var buffer: PackedByteArray = _downloads[hash]
	if offset != buffer.size() or offset + bytes.size() > mini(total, Protocol.MAX_ASSET_SIZE):
		_leave("Asset transfer error")
		return
	buffer.append_array(bytes)
	_download_received += bytes.size()
	if buffer.size() < total:
		_downloads[hash] = buffer
	else:
		_downloads.erase(hash)
		if not ContentCache.store(hash, buffer):
			_leave("Downloaded asset failed verification")
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
	_inventory_screen.atlas = _atlas
	_inventory_screen.build_equipment(items.slots)
	_item_meshes = ItemMesh.new(items, registry, _atlas, func(asset: String) -> PackedByteArray:
		return ContentCache.read(_manifest[asset].hash) if _manifest.has(asset) else PackedByteArray())
	_looks = LookBuilder.new(cosmetics, _asset_images, func(asset: String) -> PackedByteArray:
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
		adjusted.sprint_speed = float(adjusted.sprint_speed) * speed
	rules.apply_dict(adjusted)
	rules.solid_lut = registry.solid_lut
	rules.liquid_lut = registry.liquid_lut
	world.set_lookup_tables(registry.solid_lut, registry.liquid_lut)
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
	# Neighbours' faces and light near the shared borders depend on this chunk.
	for x in range(-1, 2):
		for z in range(-1, 2):
			_mark_dirty(coord + Vector2i(x, z), false)


func on_unload_chunk(coord: Vector2i) -> void:
	world.remove_chunk(coord)
	_mesh_dirty.erase(coord)
	_mesh_urgent.erase(coord)
	var node: MeshInstance3D = _chunk_nodes.get(coord)
	if node:
		node.queue_free()
		_chunk_nodes.erase(coord)
	_clear_models(coord)


func on_block_changed(pos: Vector3i, block: int, state: int) -> void:
	if not registry.is_valid(block) or (world.get_block_v(pos) == block and get_block_state(pos) == state):
		return
	if world.set_block(pos.x, pos.y, pos.z, block):
		_set_state(pos, state)
		_on_block_modified(pos)


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
	if peer_id == my_id and _self_avatar != null:
		_apply_look(_self_avatar, player_name, appearance)
	elif _remote_players.has(peer_id):
		_apply_look(_remote_players[peer_id].avatar, _remote_players[peer_id].player_name, appearance)


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
	target.set_held(_item_meshes.node_for(int(appearance.get("held", 0))))
	if target == _self_avatar:
		_view_model.set_skin(target._skin_material.albedo_texture)
		_view_model.set_armor(target._armor_material.albedo_texture)


func on_health(value: float, max_value: float, is_dead: bool, hurt: bool) -> void:
	var was_dead := dead
	health = value
	max_health = maxf(max_value, 1.0)
	dead = is_dead
	if hurt:
		_hurt_flash.color.a = 0.45
	if dead and not was_dead:
		_death_panel.visible = true
		_set_inventory_open(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not dead and was_dead:
		_death_panel.visible = false
		if not ignore_mouse_capture:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_hearts()


func on_player_stats(values: Dictionary) -> void:
	var moved: bool = float(values.get("move_speed", 1.0)) != float(stats.get("move_speed", 1.0))
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
		if not (r is Array) or r.size() != 6 or not entity_types.is_valid(int(r[1])) or not (r[2] is Vector3):
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


func on_entity_despawn(ids: PackedInt32Array) -> void:
	for id in ids:
		var view: EntityView = _entities.get(id)
		if view:
			_entities.erase(id)
			view.despawn()


func on_entities(_tick: int, payload: PackedByteArray) -> void:
	if payload.size() < 2:
		return
	var buf := StreamPeerBuffer.new()
	buf.data_array = payload
	var now := Time.get_ticks_msec() / 1000.0
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
	if _gameplay_input_enabled():
		input.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		input.jump = Input.is_action_pressed("jump")
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
	if not _welcomed:
		return

	if _status_label.visible and _can_simulate() and _chunk_nodes.has(VoxelWorld.chunk_coord_of(state.position)):
		_set_status("")

	var fraction := Engine.get_physics_interpolation_fraction()
	_render_offset = _render_offset.lerp(Vector3.ZERO, 1.0 - exp(-delta * 15.0))
	var render_position := _prev_position.lerp(state.position, fraction) + _render_offset
	_camera.position = render_position + Vector3(0.0, PlayerPhysics.EYE_HEIGHT, 0.0)
	_camera.rotation = Vector3(pitch, yaw, 0.0)
	_update_self_avatar(delta, render_position)

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
	_self_avatar.rotation.y = yaw
	_self_avatar.set_dead(dead)
	_self_avatar.animate(delta, state.velocity, state.on_ground, pitch)
	_view_model.visible = camera_mode == CameraMode.FIRST_PERSON and not dead
	var held := inventory.selected_item()
	if held != _view_model._held_id:
		_view_model.set_held(held, _item_meshes.node_for(held, true))  # follow the hotbar immediately, not the server echo
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
	if _target.hit:
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
		request_place(_target.position + _target.normal)


func _self_swing() -> void:
	if _self_avatar != null:
		_self_avatar.swing()
		_view_model.swing()


## Survival breaking: hold on a block until its break time passes (see Mining), with a crack overlay.
func _continue_mining(pos: Vector3i) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _mining.get("position") != pos:
		_stop_mining()
		var block := world.get_block_v(pos)
		if block == BlockRegistry.UNLOADED or registry.breakable_lut[block] == 0:
			return
		var seconds := Mining.break_time(registry.defs[block], items.tool_of(inventory.selected_item()), float(stats.get("mining_speed", 1.0)))
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
	var seconds := Mining.break_time(registry.defs[block], items.tool_of(inventory.selected_item()), float(stats.get("mining_speed", 1.0)))
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
	_self_swing()
	return true


## Predicts the edit locally and asks the server to apply it.
func request_break(pos: Vector3i) -> void:
	var current := world.get_block_v(pos)
	if current == BlockRegistry.UNLOADED or registry.breakable_lut[current] == 0:
		return
	world.set_block(pos.x, pos.y, pos.z, BlockRegistry.AIR)
	_on_block_modified(pos)
	_sounds.play_name(String(registry.defs[current].sounds.get("break", "")), Vector3(pos) + Vector3.ONE * 0.5, 1.0, randf_range(0.85, 1.1))
	Net.c_break_block.rpc_id(1, pos)


## Places the selected hotbar block, predicting the result.
func request_place(pos: Vector3i) -> void:
	var block := inventory.selected_block()
	if block <= 0 or registry.placeable_lut[block] == 0:
		return
	var current := world.get_block_v(pos)
	if current != BlockRegistry.AIR and registry.liquid_lut[current] == 0:
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
		yaw = wrapf(yaw - event.relative.x * MOUSE_SENSITIVITY, -PI, PI)
		_look_delta += event.relative
		pitch = clampf(pitch - event.relative.y * MOUSE_SENSITIVITY, -PI * 0.49, PI * 0.49)
	elif _avatar_editor != null:
		if event.is_action_pressed("pause"):
			_close_avatar_editor()
		return
	elif event.is_action_pressed("pause") and _inventory_screen.visible:
		_set_inventory_open(false)
	elif event.is_action_pressed("inventory") and _welcomed and not dead and (_inventory_screen.visible or _gameplay_input_enabled()):
		_set_inventory_open(not _inventory_screen.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		_set_paused(not _pause_panel.visible)
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not _pause_panel.visible and not _server_ui.has_modal() and not _inventory_screen.visible and not dead:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop") and _welcomed and _gameplay_input_enabled():
		drop_selected(event.ctrl_pressed or event.meta_pressed)
	elif event.is_action_pressed("chat") and _welcomed:
		_open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("crafting") and _welcomed:
		Net.c_open_menu.rpc_id(1, "crafting")
	elif event.is_action_pressed("camera"):
		camera_mode = (camera_mode + 1) % 3 as CameraMode
	elif event.is_action_pressed("graphics"):
		graphics.cycle()
		_apply_graphics(true)
	elif event.is_action_pressed("toggle_debug"):
		_debug_label.visible = not _debug_label.visible
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		select_slot(inventory.selected - 1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		select_slot(inventory.selected + 1)
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
		select_slot(event.physical_keycode - KEY_1)


func _gameplay_input_enabled() -> bool:
	var captured := ignore_mouse_capture or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	return captured and not _chat_input.visible and not _pause_panel.visible and not _server_ui.has_modal() \
		and not _inventory_screen.visible and not dead and _avatar_editor == null


func drop_selected(whole_stack := false) -> void:
	if inventory.selected_item() > 0 and not dead:
		Net.c_drop_item.rpc_id(1, whole_stack)


func _set_inventory_open(open: bool) -> void:
	if _inventory_screen.visible == open:
		return
	_inventory_screen.visible = open
	if open:
		_inventory_screen.refresh()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if _welcomed:
			Net.c_inventory_closed.rpc_id(1)
		if not ignore_mouse_capture and not dead:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	_avatar_editor.setup(cosmetics, _looks, _player_rig, player_name, start, {"in_game": true, "owned": owned_cosmetics})
	_avatar_editor.done.connect(_on_avatar_edited)
	_avatar_editor.cancelled.connect(_close_avatar_editor)
	_hud_root.add_child(_avatar_editor)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_avatar_edited(edited: Dictionary) -> void:
	# Server cosmetics exist only here: the saved portable look keeps its own choice for those categories.
	var portable := edited.duplicate(true)
	var previous: Dictionary = LookBuilder.resolve(avatar, player_name)
	for cat_name in edited.get("wear", {}):
		if not Cosmetics.is_builtin(String(edited.wear[cat_name].id)):
			if previous.get("wear", {}).has(cat_name):
				portable.wear[cat_name] = previous.wear[cat_name]
			else:
				portable.wear.erase(cat_name)
	avatar = cosmetics.sanitize_avatar(portable)
	AvatarStore.save_avatar(avatar)
	Net.c_set_avatar.rpc_id(1, edited)
	_close_avatar_editor()


func _close_avatar_editor() -> void:
	if _avatar_editor != null:
		_avatar_editor.queue_free()
		_avatar_editor = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_paused(paused: bool) -> void:
	_pause_panel.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_chat_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_chat_input.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_chat_input.accept_event()


func _on_ui_action(ui_id: String, action: String) -> void:
	Net.c_ui_action.rpc_id(1, ui_id, action)


static func _register_input_actions() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT, KEY_CTRL],
		"chat": [KEY_T, KEY_ENTER], "toggle_debug": [KEY_F3], "pause": [KEY_ESCAPE], "crafting": [KEY_C], "graphics": [KEY_F4], "camera": [KEY_F5],
		"inventory": [KEY_E, KEY_TAB], "drop": [KEY_Q],
	}
	for action: String in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for pair in [["break", MOUSE_BUTTON_LEFT], ["place", MOUSE_BUTTON_RIGHT]]:
		if InputMap.has_action(pair[0]):
			continue
		InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)


## Pushes the current graphics preset into post-processing, materials and (when AO changes) meshes.
func _apply_graphics(announce: bool) -> void:
	graphics.apply_environment(_environment, get_viewport())
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

	_camera = Camera3D.new()
	_camera.fov = 75.0
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

	_armor_textures = [ItemVisuals.shield_icon(1.0), ItemVisuals.shield_icon(0.5), ItemVisuals.shield_icon(0.0)]
	_armor_bar = HBoxContainer.new()
	_armor_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_armor_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_armor_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_armor_bar.position.y -= 100
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
	var volume_row := HBoxContainer.new()
	var volume_label := Label.new()
	volume_label.text = "Volume"
	volume_row.add_child(volume_label)
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_slider.value = _sounds.volume
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(func(v): _sounds.volume = v)
	_volume_slider.drag_ended.connect(func(_changed): _sounds.save_volume())
	volume_row.add_child(_volume_slider)
	pause_box.add_child(volume_row)

	_inventory_screen = InventoryScreen.new()
	_inventory_screen.inventory = inventory
	_inventory_screen.items = items
	_inventory_screen.visible = false
	_inventory_screen.slot_clicked.connect(inventory_click)
	_hud_root.add_child(_inventory_screen)

	_death_panel = Control.new()
	_death_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_panel.visible = false
	_hud_root.add_child(_death_panel)
	var death_bg := ColorRect.new()
	death_bg.color = Color(0.45, 0.0, 0.0, 0.45)
	death_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_panel.add_child(death_bg)
	var death_box := VBoxContainer.new()
	death_box.set_anchors_preset(Control.PRESET_CENTER)
	death_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	death_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	death_box.add_theme_constant_override("separation", 16)
	_death_panel.add_child(death_box)
	_death_label = _shadow_label()
	_death_label.text = "You died!"
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.add_theme_font_size_override("font_size", 56)
	death_box.add_child(_death_label)
	var respawn_button := Button.new()
	respawn_button.text = "Respawn"
	respawn_button.custom_minimum_size = Vector2(240, 48)
	respawn_button.pressed.connect(respawn)
	death_box.add_child(respawn_button)


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
		_hotbar.add_child(slot)
		_hotbar_slots.append(slot)
	_refresh_hotbar()


func _refresh_hotbar() -> void:
	_refresh_hearts()
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
			var tex := AtlasTexture.new()
			tex.atlas = _atlas.texture
			tex.region = _atlas.pixels.get(items.icon_of(id), _atlas.pixels[""])
			icon.texture = tex
		else:
			icon.texture = null
		count.text = str(inventory.counts[i]) if has_item and not inventory.creative and inventory.counts[i] > 1 else ""
		ItemVisuals.update_wear_bar(slot, items, id if has_item else 0, inventory.data[i])


func _refresh_armor() -> void:
	if _armor_bar == null:
		return
	var armor := float(stats.get("armor", 0.0))
	_armor_bar.visible = _welcomed and not inventory.creative and armor > 0.0
	for i in 10:
		var fill := clampf((armor - i * 2.0) / 2.0, 0.0, 1.0)
		_armor_bar.get_child(i).texture = _armor_textures[0 if fill > 0.75 else (1 if fill > 0.25 else 2)]


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
