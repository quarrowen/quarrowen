extends Node
## Autoload "Net": owns the ENet peer and defines every RPC in one place so the RPC config is
## identical on server and client. Handlers forward to the active GameServer / GameClient.
##
## Naming: c_* = sent by clients to the server, s_* = sent by the server to clients.
## Channel 0 is reliable (content, chunks, edits, UI), channel 1 carries unreliable movement.
##
## Join sequence:
##   c_hello(protocol, name) -> s_server_info(info, content, manifest)
##   c_request_assets(missing hashes) -> s_asset_piece(...)*
##   c_ready() -> s_welcome, s_inventory, s_chunk*, s_snapshot* ...

const MOVEMENT_CHANNEL := 1

## Set by GameServer when running as a server.
var server: Node = null
## Set by GameClient when running as a client.
var client: Node = null


func create_server(port: int, max_players: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	# Clients may only talk to the server, never relay RPCs to each other.
	(multiplayer as SceneMultiplayer).server_relay = false
	return OK


func create_client(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


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
func c_hello(protocol: int, player_name: String) -> void:
	if server:
		server.on_hello(_sender(), protocol, player_name)


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


## Opens an engine menu ("crafting").
@rpc("any_peer", "call_remote", "reliable")
func c_open_menu(menu: String) -> void:
	if server:
		server.on_open_menu(_sender(), menu)


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
func s_inventory(slots: PackedInt32Array, selected: int, creative: bool) -> void:
	if client:
		client.on_inventory(slots, selected, creative)


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
