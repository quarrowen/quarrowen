extends Node
## Autoload "Net": owns the ENet peer and defines every RPC in one place so the RPC config is
## identical on server and client. Handlers forward to the active GameServer / GameClient.
##
## Naming: c_* = sent by clients to the server, s_* = sent by the server to clients.
## Channel 0 is reliable (content, chunks, edits, UI), channel 1 carries unreliable movement.
##
## Join sequence (over DTLS; the SceneMultiplayer auth step first checks the protocol version and
## pins the server certificate, see _on_auth_message):
##   c_hello(protocol, name, public key) -> s_challenge(nonce) -> c_auth(signature)
##   -> s_server_info(info, content, manifest)
##   c_request_assets(missing hashes) -> s_asset_piece(...)*
##   c_ready() -> s_welcome, s_inventory, s_chunk*, s_snapshot* ...

const MOVEMENT_CHANNEL := 1
const Protocol = preload("res://engine/shared/protocol.gd")
const KnownServers = preload("res://engine/net/known_servers.gd")
## Common name in server certificates; clients verify against a pinned certificate, not a CA.
const CERT_COMMON_NAME := "voxelcraft-server"

## Emitted on clients when the connection handshake refuses to continue (version mismatch, changed
## server identity). The peer is closed afterwards.
signal handshake_failed(reason: String)

## Set by GameServer when running as a server.
var server: Node = null
## Set by GameClient when running as a client.
var client: Node = null
## Server: certificate PEM handed to clients so they can pin it.
var _server_cert_pem := ""
## Client: where the server identity is pinned ("host:port") and the protocol version announced.
var _client_endpoint := ""
var _client_protocol := Protocol.VERSION
## Client: pin server certificates (load-test bots turn this off).
var pin_servers := true


func _ready() -> void:
	_configure_auth()


## The handshake runs through SceneMultiplayer's authentication step, which exchanges raw bytes
## before any RPC. RPC ids depend on each build's RPC list, so versions must match before RPCs flow.
func _configure_auth() -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	scene_multiplayer.auth_timeout = 10.0
	scene_multiplayer.auth_callback = _on_auth_message
	scene_multiplayer.peer_authenticating.connect(_on_peer_authenticating)


## `tls_key`/`tls_cert`: the server's identity. Traffic is always encrypted with DTLS.
func create_server(port: int, max_players: int, tls_key: CryptoKey, tls_cert: X509Certificate, cert_pem: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		return err
	err = peer.host.dtls_server_setup(TLSOptions.server(tls_key, tls_cert))
	if err != OK:
		peer.close()
		return err
	# The PEM text is passed in: X509Certificate.save_to_string() appends a NUL character.
	_server_cert_pem = cert_pem
	multiplayer.multiplayer_peer = peer
	# Clients may only talk to the server, never relay RPCs to each other.
	(multiplayer as SceneMultiplayer).server_relay = false
	return OK


## Connects over DTLS. If this server's certificate was seen before, the DTLS handshake verifies it,
## so an impostor cannot complete the connection; the first connection trusts and pins it.
func create_client(address: String, port: int, protocol_override := -1) -> Error:
	_client_endpoint = "%s:%d" % [address, port]
	_client_protocol = protocol_override if protocol_override >= 0 else Protocol.VERSION
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	var pinned := KnownServers.load_certificate(_client_endpoint) if pin_servers else null
	var options := TLSOptions.client(pinned, CERT_COMMON_NAME) if pinned != null else TLSOptions.client_unsafe()
	err = peer.host.dtls_client_setup(CERT_COMMON_NAME, options)
	if err != OK:
		peer.close()
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func has_pinned_identity(address: String, port: int) -> bool:
	return KnownServers.load_certificate("%s:%d" % [address, port]) != null


## Loads the server's DTLS identity from `dir`, creating a self-signed one on first start.
## Returns [CryptoKey, X509Certificate, certificate PEM text].
static func load_or_create_server_identity(dir: String) -> Array:
	DirAccess.make_dir_recursive_absolute(dir)
	var key_path := dir.path_join("server.key")
	var cert_path := dir.path_join("server.crt")
	var key := CryptoKey.new()
	var cert := X509Certificate.new()
	if FileAccess.file_exists(key_path) and FileAccess.file_exists(cert_path) \
			and key.load(key_path) == OK and cert.load(cert_path) == OK:
		return [key, cert, FileAccess.get_file_as_string(cert_path)]
	var crypto := Crypto.new()
	key = crypto.generate_rsa(2048)
	cert = crypto.generate_self_signed_certificate(key, "CN=%s,O=VoxelCraft" % CERT_COMMON_NAME, "20250101000000", "21000101000000")
	key.save(key_path)
	cert.save(cert_path)
	print("[server] Generated server identity in %s" % ProjectSettings.globalize_path(dir))
	return [key, cert, FileAccess.get_file_as_string(cert_path)]


func _on_peer_authenticating(peer_id: int) -> void:
	if multiplayer.is_server():
		return
	var hello := {"protocol": _client_protocol, "game_version": Protocol.GAME_VERSION}
	(multiplayer as SceneMultiplayer).send_auth(peer_id, JSON.stringify(hello).to_utf8_buffer())


func _on_auth_message(peer_id: int, data: PackedByteArray) -> void:
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if data.is_empty() or data[0] == 0:
		return  # Completion marker from the other side, not a handshake message.
	var message = JSON.parse_string(data.get_string_from_utf8()) if data.size() < 16384 else null
	if not (message is Dictionary):
		scene_multiplayer.disconnect_peer(peer_id)
		return
	if multiplayer.is_server():
		var protocol := int(message.get("protocol", -1))
		if protocol != Protocol.VERSION:
			var newer := protocol < Protocol.VERSION
			var reason := "This server runs %s version %s (protocol %d). %s" % [
				Protocol.GAME_NAME, Protocol.GAME_VERSION, Protocol.VERSION,
				"Please update your client." if newer else "The server needs updating to support your newer client."]
			scene_multiplayer.send_auth(peer_id, JSON.stringify({"ok": false, "reason": reason}).to_utf8_buffer())
			# Give the refusal time to arrive before dropping the peer.
			get_tree().create_timer(0.5).timeout.connect(func():
				if scene_multiplayer.get_authenticating_peers().has(peer_id):
					scene_multiplayer.disconnect_peer(peer_id))
			return
		var reply := {"ok": true, "certificate": _server_cert_pem, "game_version": Protocol.GAME_VERSION}
		scene_multiplayer.send_auth(peer_id, JSON.stringify(reply).to_utf8_buffer())
		scene_multiplayer.complete_auth(peer_id)
		return
	# Client side.
	if not message.get("ok", false):
		_fail_handshake(String(message.get("reason", "The server refused the connection.")))
		return
	var certificate := String(message.get("certificate", ""))
	var pin := KnownServers.check_and_pin(_client_endpoint, certificate) if pin_servers else ""
	if pin != "":
		_fail_handshake(pin)
		return
	scene_multiplayer.complete_auth(peer_id)


func _fail_handshake(reason: String) -> void:
	handshake_failed.emit(reason)
	close()


func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## Server side: a client's round-trip time in milliseconds (0 if unknown).
func peer_rtt_ms(peer_id: int) -> int:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or not multiplayer.is_server():
		return 0
	var packet_peer := peer.get_peer(peer_id)
	return int(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if packet_peer != null else 0


func get_ping_ms() -> int:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or multiplayer.is_server():
		return 0
	var server_peer := peer.get_peer(1)
	if server_peer == null:
		return 0
	return int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


func _sender() -> int:
	return multiplayer.get_remote_sender_id()


# --- Client -> server -------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func c_hello(protocol: int, player_name: String, public_key: String) -> void:
	if server:
		server.on_hello(_sender(), protocol, player_name, public_key)


@rpc("any_peer", "call_remote", "reliable")
func c_auth(signature: PackedByteArray) -> void:
	if server:
		server.on_auth(_sender(), signature)


@rpc("any_peer", "call_remote", "reliable")
func c_claim_admin(token: String) -> void:
	if server:
		server.on_claim_admin(_sender(), token)


@rpc("any_peer", "call_remote", "reliable")
func c_request_assets(hashes: PackedStringArray) -> void:
	if server:
		server.on_request_assets(_sender(), hashes)


@rpc("any_peer", "call_remote", "reliable")
func c_ready() -> void:
	if server:
		server.on_client_ready(_sender())


@rpc("any_peer", "call_remote", "unreliable_ordered", MOVEMENT_CHANNEL)
func c_inputs(packet: PackedByteArray) -> void:
	if server:
		server.on_inputs(_sender(), packet)


@rpc("any_peer", "call_remote", "reliable")
func c_break_block(position: Vector3i) -> void:
	if server:
		server.on_break_block(_sender(), position)


@rpc("any_peer", "call_remote", "reliable")
func c_place_block(position: Vector3i, yaw: float) -> void:
	if server:
		server.on_place_block(_sender(), position, yaw)


@rpc("any_peer", "call_remote", "reliable")
func c_interact(position: Vector3i) -> void:
	if server:
		server.on_interact(_sender(), position)


## Right-click while holding a usable item. `target`/`normal` are only meaningful when `has_target`.
@rpc("any_peer", "call_remote", "reliable")
func c_use_item(has_target: bool, target: Vector3i, normal: Vector3i) -> void:
	if server:
		server.on_use_item(_sender(), has_target, target, normal)


## Get out of bed.
@rpc("any_peer", "call_remote", "reliable")
func c_leave_bed() -> void:
	if server:
		server.on_leave_bed(_sender())


## Use was released (stops eating).
@rpc("any_peer", "call_remote", "reliable")
func c_stop_using() -> void:
	if server:
		server.on_stop_using(_sender())


## Opens an engine menu ("crafting").
@rpc("any_peer", "call_remote", "reliable")
func c_open_menu(menu: String) -> void:
	if server:
		server.on_open_menu(_sender(), menu)


## The player is looking at a guide page (marks it read and remembers it).
@rpc("any_peer", "call_remote", "reliable")
func c_guide_read(page_id: String) -> void:
	if server:
		server.on_guide_read(_sender(), page_id)


@rpc("any_peer", "call_remote", "reliable")
func c_select_slot(slot: int) -> void:
	if server:
		server.on_select_slot(_sender(), slot)


@rpc("any_peer", "call_remote", "reliable")
func c_chat(text: String) -> void:
	if server:
		server.on_chat(_sender(), text)


@rpc("any_peer", "call_remote", "reliable")
func c_ui_action(ui_id: String, action: String) -> void:
	if server:
		server.on_ui_action(_sender(), ui_id, action)


## Left-click on an entity (kind 0) or another player (kind 1).
@rpc("any_peer", "call_remote", "reliable")
func c_attack(kind: int, target_id: int) -> void:
	if server:
		server.on_attack(_sender(), kind, target_id)


@rpc("any_peer", "call_remote", "reliable")
func c_interact_entity(target_id: int) -> void:
	if server:
		server.on_interact_entity(_sender(), target_id)


@rpc("any_peer", "call_remote", "reliable")
func c_respawn() -> void:
	if server:
		server.on_respawn(_sender())


## Inventory screen click: slot 0-35 (-1 = outside, drops the cursor stack), button 1 left, 2 right,
## 3 middle.
@rpc("any_peer", "call_remote", "reliable")
func c_inventory_click(slot: int, button: int, shift: bool) -> void:
	if server:
		server.on_inventory_click(_sender(), slot, button, shift)


@rpc("any_peer", "call_remote", "reliable")
func c_inventory_closed() -> void:
	if server:
		server.on_inventory_closed(_sender())


## Started (or stopped) holding break on a block in survival; the server times the break.
@rpc("any_peer", "call_remote", "reliable")
func c_mine_start(position: Vector3i) -> void:
	if server:
		server.on_mine_start(_sender(), position)


@rpc("any_peer", "call_remote", "reliable")
func c_mine_stop() -> void:
	if server:
		server.on_mine_stop(_sender())


@rpc("any_peer", "call_remote", "reliable")
func c_drop_item(whole_stack: bool) -> void:
	if server:
		server.on_drop_item(_sender(), whole_stack)


## Crafts recipe `index` (see RecipeRegistry) up to `times` times.
@rpc("any_peer", "call_remote", "reliable")
func c_craft(index: int, times: int) -> void:
	if server:
		server.on_craft(_sender(), index, times)


## Station screen buttons: "upgrade" (use the next tier's kit), "guide" (show missing structure blocks).
@rpc("any_peer", "call_remote", "reliable")
func c_station_action(action: String) -> void:
	if server:
		server.on_station_action(_sender(), action)


## Co-op at the open station: "view" | "deposit" | "take" | "start_project" | "contribute" | "cancel_project".
@rpc("any_peer", "call_remote", "reliable")
func c_station_coop(action: String, arg: int) -> void:
	if server:
		server.on_station_coop(_sender(), action, arg)


## Builds a tool from parts: the assembly's name and a backpack slot per assembly slot.
@rpc("any_peer", "call_remote", "reliable")
func c_assemble(assembly_name: String, slots: PackedInt32Array) -> void:
	if server:
		server.on_assemble(_sender(), assembly_name, slots)


## Crafts by hand through the item's minigame: product {recipe: index} or {assembly, slots}; assist =
## relaxed timing; with_partner waits for a helper at the station.
@rpc("any_peer", "call_remote", "reliable")
func c_skill_craft(product: Dictionary, assist: bool, with_partner: bool) -> void:
	if server:
		server.on_skill_craft(_sender(), product, assist, with_partner)


## A minigame input: "strike", "hold" (arg 1/0), "key" (arg direction) or "quit", at game time t.
@rpc("any_peer", "call_remote", "reliable")
func c_minigame_input(action: String, t: float, arg: int) -> void:
	if server:
		server.on_minigame_input(_sender(), action, t, arg)


## Joins a waiting team minigame (id), or starts your own waiting game alone (id 0).
@rpc("any_peer", "call_remote", "reliable")
func c_minigame_join(game_id: int) -> void:
	if server:
		server.on_minigame_join(_sender(), game_id)


## Tries the experimentation grid: 9 item ids row by row (0 = empty).
@rpc("any_peer", "call_remote", "reliable")
func c_experiment(grid: PackedInt32Array) -> void:
	if server:
		server.on_experiment(_sender(), grid)


@rpc("any_peer", "call_remote", "reliable")
func c_crafting_closed() -> void:
	if server:
		server.on_crafting_closed(_sender())


## The player's avatar (Cosmetics data): on join their portable look, in game any change.
@rpc("any_peer", "call_remote", "reliable")
func c_set_avatar(avatar: Dictionary) -> void:
	if server:
		server.on_set_avatar(_sender(), avatar)


@rpc("any_peer", "call_remote", "reliable")
func c_shutdown(token: String) -> void:
	if server:
		server.on_shutdown_request(_sender(), token)


# --- Server -> client -------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func s_kick(reason: String) -> void:
	if client:
		client.on_kick(reason)


@rpc("authority", "call_remote", "reliable")
func s_challenge(nonce: PackedByteArray) -> void:
	if client:
		client.on_challenge(nonce)


@rpc("authority", "call_remote", "reliable")
func s_server_info(info: Dictionary, content: Dictionary, manifest: Array) -> void:
	if client:
		client.on_server_info(info, content, manifest)


@rpc("authority", "call_remote", "reliable")
func s_asset_piece(hash: String, offset: int, total: int, bytes: PackedByteArray) -> void:
	if client:
		client.on_asset_piece(hash, offset, total, bytes)


@rpc("authority", "call_remote", "reliable")
func s_welcome(peer_id: int, spawn: Vector3, yaw: float) -> void:
	if client:
		client.on_welcome(peer_id, spawn, yaw)


@rpc("authority", "call_remote", "reliable")
func s_time(time_of_day: float, day_length: float) -> void:
	if client:
		client.on_time(time_of_day, day_length)


@rpc("authority", "call_remote", "reliable")
func s_rules(rules: Dictionary) -> void:
	if client:
		client.on_rules(rules)


@rpc("authority", "call_remote", "reliable")
func s_chunk(coord: Vector2i, payload: PackedByteArray, states: PackedInt32Array) -> void:
	if client:
		client.on_chunk(coord, payload, states)


@rpc("authority", "call_remote", "reliable")
func s_unload_chunk(coord: Vector2i) -> void:
	if client:
		client.on_unload_chunk(coord)


@rpc("authority", "call_remote", "reliable")
func s_block_changed(position: Vector3i, block: int, state: int) -> void:
	if client:
		client.on_block_changed(position, block, state)


@rpc("authority", "call_remote", "reliable")
func s_inventory(slots: PackedInt32Array, selected: int, creative: bool, item_data: Dictionary) -> void:
	if client:
		client.on_inventory(slots, selected, creative, item_data)


## Plays effect `effect_id` (see EffectRegistry) at a position; options may name an entity or player
## to follow.
@rpc("authority", "call_remote", "reliable")
func s_effect(effect_id: int, position: Vector3, options: Dictionary) -> void:
	if client:
		client.on_effect(effect_id, position, options)


## Opens the crafting screen: station {name ("" = by hand), title, position}, and the items the
## station can draw from nearby chests {item id: count}.
@rpc("authority", "call_remote", "reliable")
func s_crafting_open(station: Dictionary, stock: Dictionary) -> void:
	if client:
		client.on_crafting_open(station, stock)


## Ghost blocks showing where a multiblock station's missing blocks go: [[position, block id], ...]
## (block -1 = any solid block).
@rpc("authority", "call_remote", "reliable")
func s_structure_guide(missing: Array) -> void:
	if client:
		client.on_structure_guide(missing)


## Minigame state: {id, phase: "waiting" | "playing" | "done", def, seed, assist, bonus, team, role,
## names, countdown, wait, item} or, when done, {id, phase, result: {quality, name, color, score, item, data}}.
@rpc("authority", "call_remote", "reliable")
func s_minigame(view: Dictionary) -> void:
	if client:
		client.on_minigame(view)


## The partner's input in a team minigame.
@rpc("authority", "call_remote", "reliable")
func s_minigame_event(action: String, t: float, arg: int) -> void:
	if client:
		client.on_minigame_event(action, t, arg)


## A tool was built from parts: the item and its data.
@rpc("authority", "call_remote", "reliable")
func s_assembled(item: int, item_data: Dictionary) -> void:
	if client:
		client.on_assembled(item, item_data)


## What an experiment did: {status: "discovered" | "known" | "blueprint" | "close" | "nothing" | "invalid",
## recipe (index or -1), hint}.
@rpc("authority", "call_remote", "reliable")
func s_experiment_result(result: Dictionary) -> void:
	if client:
		client.on_experiment_result(result)


## Recipes you know (ids) and whether discovery is on for this server.
@rpc("authority", "call_remote", "reliable")
func s_known_recipes(known: PackedStringArray, discovery: bool) -> void:
	if client:
		client.on_known_recipes(known, discovery)


## You learned recipe `index`: source "pickup" | "blueprint" | "experiment" | "mod".
@rpc("authority", "call_remote", "reliable")
func s_recipe_learned(index: int, source: String) -> void:
	if client:
		client.on_recipe_learned(index, source)


## The shared state of the station you are at: {players, tray, jobs, project, owner, speedup}.
@rpc("authority", "call_remote", "reliable")
func s_station_session(session: Dictionary) -> void:
	if client:
		client.on_station_session(session)


## Floating text above a station (project or job progress); "" removes it.
@rpc("authority", "call_remote", "reliable")
func s_station_label(position: Vector3i, text: String) -> void:
	if client:
		client.on_station_label(position, text)


@rpc("authority", "call_remote", "reliable")
func s_crafting_stock(stock: Dictionary) -> void:
	if client:
		client.on_crafting_stock(stock)


## A craft succeeded: recipe index, times crafted, the station's remaining stock.
@rpc("authority", "call_remote", "reliable")
func s_crafted(index: int, times: int, stock: Dictionary) -> void:
	if client:
		client.on_crafted(index, times, stock)


## A container screen opened: {title, size, groups, bars, slots, data, progress} (see Containers).
@rpc("authority", "call_remote", "reliable")
func s_container_open(view: Dictionary) -> void:
	if client:
		client.on_container_open(view)


## New contents of the open container: {slots, data, progress}.
@rpc("authority", "call_remote", "reliable")
func s_container_update(view: Dictionary) -> void:
	if client:
		client.on_container_update(view)


@rpc("authority", "call_remote", "reliable")
func s_container_close() -> void:
	if client:
		client.on_container_close()


## Server cosmetics you own here and the server's cosmetics policy (see Cosmetics).
@rpc("authority", "call_remote", "reliable")
func s_cosmetics(owned: PackedStringArray, policy: Dictionary) -> void:
	if client:
		client.on_cosmetics(owned, policy)


## How a player looks: {held, armor: {slot: item}, avatar}. Also sent for yourself.
@rpc("authority", "call_remote", "reliable")
func s_player_appearance(peer_id: int, appearance: Dictionary) -> void:
	if client:
		client.on_player_appearance(peer_id, appearance)


@rpc("authority", "call_remote", "reliable")
func s_player_stats(stats: Dictionary) -> void:
	if client:
		client.on_player_stats(stats)


## Another player is breaking a block (`seconds` until it breaks; -1 = stopped).
@rpc("authority", "call_remote", "reliable")
func s_mining(peer_id: int, position: Vector3i, seconds: float) -> void:
	if client:
		client.on_mining(peer_id, position, seconds)


@rpc("authority", "call_remote", "reliable")
func s_player_joined(peer_id: int, player_name: String) -> void:
	if client:
		client.on_player_joined(peer_id, player_name)


@rpc("authority", "call_remote", "reliable")
func s_player_left(peer_id: int) -> void:
	if client:
		client.on_player_left(peer_id)


@rpc("authority", "call_remote", "unreliable_ordered", MOVEMENT_CHANNEL)
func s_snapshot(tick: int, payload: PackedByteArray) -> void:
	if client:
		client.on_snapshot(tick, payload)


@rpc("authority", "call_remote", "reliable")
func s_chat(text: String) -> void:
	if client:
		client.on_chat(text)


@rpc("authority", "call_remote", "reliable")
func s_ui_show(ui_id: String, spec: Dictionary) -> void:
	if client:
		client.on_ui_show(ui_id, spec)


@rpc("authority", "call_remote", "reliable")
func s_ui_hide(ui_id: String) -> void:
	if client:
		client.on_ui_hide(ui_id)


@rpc("authority", "call_remote", "reliable")
func s_title(text: String, subtitle: String, seconds: float) -> void:
	if client:
		client.on_title(text, subtitle, seconds)


## Structure selection box to show (or hide) for a builder.
@rpc("authority", "call_remote", "reliable")
func s_selection(a: Vector3i, b: Vector3i, visible: bool) -> void:
	if client:
		client.on_selection(a, b, visible)


## Guide pages you have unlocked and read, and the page you had open last.
@rpc("authority", "call_remote", "reliable")
func s_guide_state(unlocked: PackedStringArray, read: PackedStringArray, last: String) -> void:
	if client:
		client.on_guide_state(unlocked, read, last)


## New guide pages unlocked (`notify`: show a popup).
@rpc("authority", "call_remote", "reliable")
func s_guide_unlocked(pages: PackedStringArray, notify: bool) -> void:
	if client:
		client.on_guide_unlocked(pages, notify)


## Opens the guidebook at a page ("" = the last page).
@rpc("authority", "call_remote", "reliable")
func s_guide_open(page_id: String) -> void:
	if client:
		client.on_guide_open(page_id)


## Sleeping state for this player: {sleeping, since, asleep, needed, seconds, head_dir}.
@rpc("authority", "call_remote", "reliable")
func s_sleep(state: Dictionary) -> void:
	if client:
		client.on_sleep(state)


## A player started eating an item (0 = stopped or finished), for the eating animation.
@rpc("authority", "call_remote", "reliable")
func s_player_eating(peer_id: int, item: int) -> void:
	if client:
		client.on_player_eating(peer_id, item)


## Hunger 0-20 and saturation.
@rpc("authority", "call_remote", "reliable")
func s_hunger(hunger: float, saturation: float) -> void:
	if client:
		client.on_hunger(hunger, saturation)


@rpc("authority", "call_remote", "reliable")
func s_health(health: float, max_health: float, dead: bool, hurt: bool) -> void:
	if client:
		client.on_health(health, max_health, dead, hurt)


## Entities entering view: [[id, type, position, yaw, item id, item count, look], ...]
@rpc("authority", "call_remote", "reliable")
func s_entity_spawn(records: Array) -> void:
	if client:
		client.on_entity_spawn(records)


## An entity's look changed: {scale, hide, tint}.
@rpc("authority", "call_remote", "reliable")
func s_entity_look(entity_id: int, look: Dictionary) -> void:
	if client:
		client.on_entity_look(entity_id, look)


@rpc("authority", "call_remote", "reliable")
func s_entity_despawn(ids: PackedInt32Array) -> void:
	if client:
		client.on_entity_despawn(ids)


## Compact position updates for visible entities (see Entities.replicate).
@rpc("authority", "call_remote", "unreliable_ordered", MOVEMENT_CHANNEL)
func s_entities(tick: int, payload: PackedByteArray) -> void:
	if client:
		client.on_entities(tick, payload)


## kind: Entities.Event (0 hurt, 1 death, 2 pickup by peer `arg`, 3 attack)
@rpc("authority", "call_remote", "reliable")
func s_entity_event(entity_id: int, kind: int, arg: int) -> void:
	if client:
		client.on_entity_event(entity_id, kind, arg)


@rpc("authority", "call_remote", "reliable")
func s_player_event(peer_id: int, kind: int) -> void:
	if client:
		client.on_player_event(peer_id, kind)


@rpc("authority", "call_remote", "reliable")
func s_sound(sound_id: int, position: Vector3, volume: float, pitch: float, positional: bool) -> void:
	if client:
		client.on_sound(sound_id, position, volume, pitch, positional)
