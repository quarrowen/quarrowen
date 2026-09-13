extends RefCounted
## A connected, in-game player. Mods receive these in events; public members and methods below the
## "Mod API" line are the supported surface. Underscore-free engine fields are read-only for mods.

const PlayerPhysics = preload("res://engine/shared/player_physics.gd")
const Inventory = preload("res://engine/shared/inventory.gd")

var peer_id := 0
var name := ""
var state := PlayerPhysics.State.new()
var inventory := Inventory.new()
var yaw := 0.0
var pitch := 0.0
## Free-form per-player data owned by mods; persisted with the world. Namespace your keys.
var data := {}

# Engine bookkeeping.
var input_queue: Array = []
var last_received_seq := -1
var last_processed_seq := -1
var sent_chunks := {}
var pending_chunks: Array[Vector2i] = []
var stream_center := Vector2i(1 << 30, 0)
var edit_tokens := 0.0
var ui_ids := {}

var _server


func _init(server, id: int, player_name: String) -> void:
	_server = server
	peer_id = id
	name = player_name


# --- Mod API ------------------------------------------------------------------------------------

var position: Vector3:
	get:
		return state.position


func get_eye_position() -> Vector3:
	return PlayerPhysics.eye_position(state)


func teleport(pos: Vector3) -> void:
	state.position = pos
	state.velocity = Vector3.ZERO
	_server.ensure_area_loaded(pos)


func send_message(text: String) -> void:
	Net.s_chat.rpc_id(peer_id, text)


func show_title(text: String, subtitle := "", seconds := 3.0) -> void:
	Net.s_title.rpc_id(peer_id, text, subtitle, seconds)


## Shows or replaces a server-defined UI panel. See engine/client/server_ui.gd for the spec format.
func show_ui(ui_id: String, spec: Dictionary) -> void:
	ui_ids[ui_id] = true
	Net.s_ui_show.rpc_id(peer_id, ui_id, spec)


func hide_ui(ui_id: String) -> void:
	ui_ids.erase(ui_id)
	Net.s_ui_hide.rpc_id(peer_id, ui_id)


func is_creative() -> bool:
	return inventory.creative


func set_creative(enabled: bool) -> void:
	inventory.creative = enabled
	sync_inventory()


## Adds blocks or items; returns how many did not fit.
func give(item: int, count := 1) -> int:
	var left := inventory.add(item, count, _server.items.max_stack(item))
	sync_inventory()
	return left


## Removes items if the player has enough; returns false otherwise.
func take(block: int, count := 1) -> bool:
	var ok := inventory.remove(block, count)
	if ok:
		sync_inventory()
	return ok


func count_of(block: int) -> int:
	return inventory.count_of(block)


func clear_inventory() -> void:
	inventory.clear()
	sync_inventory()


## Fills hotbar slots in order with the given block ids.
func set_hotbar(blocks: Array, count := 1) -> void:
	inventory.clear()
	for i in mini(blocks.size(), Inventory.SIZE):
		inventory.set_slot(i, int(blocks[i]), count)
	sync_inventory()


func sync_inventory() -> void:
	Net.s_inventory.rpc_id(peer_id, inventory.to_packed(), inventory.selected, inventory.creative)


func kick(reason: String) -> void:
	_server.kick(peer_id, reason)
