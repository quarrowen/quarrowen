extends RefCounted
## A connected, in-game player. Mods receive these in events; public members and methods below the
## "Mod API" line are the supported surface. Underscore-free engine fields are read-only for mods.

const PlayerPhysics = preload("res://engine/shared/player_physics.gd")
const Inventory = preload("res://engine/shared/inventory.gd")
const PlayerStats = preload("res://engine/server/player_stats.gd")

var peer_id := 0
var name := ""
## Permanent id derived from the player's identity key.
var player_id := ""
var state := PlayerPhysics.State.new()
var inventory: Inventory
var yaw := 0.0
var pitch := 0.0
## Free-form per-player data owned by mods; persisted with the world. Namespace your keys.
var data := {}
var health := 20.0
var max_health := 20.0
## Hunger 0-20 and hidden saturation (see engine/server/hunger.gd).
var hunger := 20.0
var saturation := 5.0
var exhaustion := 0.0
var dead := false
## Where the player respawns; Vector3.INF uses their bed, then the game's spawn handler.
var spawn_point := Vector3.INF
## The bed they last used (Vector3i, foot) or null; checked when respawning.
var spawn_bed = null
## {bed, since, head_dir, return} while asleep in a bed.
var sleeping := {}
## Timed stat modifiers: id -> {stat, amount, op, expires (server time, 0 = permanent)}.
var modifiers := {}

# Engine bookkeeping.
var input_queue: Array = []
var last_received_seq := -1
var last_processed_seq := -1
var sent_chunks := {}
var pending_chunks: Array[Vector2i] = []
var stream_center := Vector2i(1 << 30, 0)
var edit_tokens := 0.0
var ui_ids := {}
var known_entities := {}  # entity id -> true (replicated to this player)
var known_entities_stale := true
var last_damage_time := -100.0
var hurt_timer := 0.0
var regen_timer := 0.0
var starve_timer := 0.0
var eating := {}  # {slot, item, started, sound} while holding use on food
var _sent_hunger := Vector2(-1, -1)
var void_timer := 0.0
var contact_timer := 0.0
var last_attack_time := -100.0
var fall_velocity := 0.0
var inventory_open := false
var mining := {}  # {position, started} while breaking a block
## Physics rules adjusted by this player's move_speed stat (null = the server's rules).
var physics_rules = null
## Last appearance sent to clients (held item, visible armor, cosmetics).
var appearance := {}
## The look others see (Cosmetics avatar data), recomputed by the server from the fields below.
var avatar := {}
## The player's own built-in look, sent by their client.
var portable_avatar := {}
## Server cosmetics the player picked on this server: {category: {id, color}}.
var server_wear := {}
## Avatar data mods lay over the player's look (see set_avatar_override).
var avatar_override := {}
## The avatar the client last asked for (creations in it may still be uploading or awaiting approval).
var requested_avatar := {}
## Server cosmetics granted to this player: name -> true.
var owned_cosmetics := {}
var avatar_changed_at := -100.0
## Position of the container whose screen is open (null when none).
var open_container = null
## {name, position, title} of the crafting station in use ({} = crafting by hand).
var crafting_station := {}
## Recipes this player has discovered: recipe id -> true (see RecipeRegistry unlock rules).
var known_recipes := {}
## Items this player has held at least once: item name -> true (drives "pickup" discoveries).
var seen_items := {}
## Team name ("" = none). Teams share station trays and projects; mods decide who is on which team.
var team := ""
## Guidebook progress (see engine/server/guide.gd).
var guide := {}
## Tutorial progress and tips seen (see engine/server/tutorials.gd).
var tutorial := {}
var _stats := {}
var _stats_dirty := true
var _sent_stats := {}
var _equipment_ids := PackedInt32Array()

var _server


func _init(server, id: int, player_name: String) -> void:
	_server = server
	peer_id = id
	name = player_name
	inventory = Inventory.new(server.items.slot_names())


func _online() -> bool:
	return _server._started and _server.players.get(peer_id) == self


# --- Mod API ------------------------------------------------------------------------------------

var position: Vector3:
	get:
		return state.position

## Index of the selected hotbar slot.
var selected_slot: int:
	get:
		return inventory.selected


## Where the player's eyes are (for aiming and line of sight).
func get_eye_position() -> Vector3:
	return PlayerPhysics.eye_position(state)


## Moves the player to a position and stops their fall.
func teleport(pos: Vector3) -> void:
	state.position = pos
	state.velocity = Vector3.ZERO
	fall_velocity = 0.0
	known_entities_stale = true
	_server.ensure_area_loaded(pos)


## Deals damage from `attacker` (player, entity or null). Creative players are unaffected. Returns
## true if damage applied. `cause`: "attack", "mob", "projectile", "fall", "void", "magic", ...
func damage(amount: float, cause := "magic", attacker = null) -> bool:
	return _server.damage_player(self, amount, cause, attacker)


## Gives back health, up to max_health.
func heal(amount: float) -> void:
	_server.heal_player(self, amount)


## Sets hunger (0-20) and optionally saturation.
func set_hunger(value: float, new_saturation := -1.0) -> void:
	_server.hunger.set_hunger(self, value, new_saturation)


## Adds hunger exhaustion (4 = one point of saturation or hunger).
func add_exhaustion(amount: float) -> void:
	_server.hunger.add_exhaustion(self, amount)


## Restores hunger and saturation as if eating.
func feed(hunger_points: float, saturation_points := 0.0) -> void:
	_server.hunger.set_hunger(self, hunger + hunger_points, minf(saturation + saturation_points, hunger + hunger_points))


## Sets health (0 kills).
func set_health(value: float) -> void:
	health = clampf(value, 0.0, max_health)
	_server.sync_health(self)
	if health <= 0.0 and not dead:
		_server.kill_player(self, "magic", null)


## Sets the base max health for this player (items and effects still modify it).
func set_max_health(value: float) -> void:
	add_modifier("engine:max_health", "max_health", clampf(value, 1.0, 1000.0) - float(_server.items.stats.max_health))


## Kills the player with a cause (shown in the death message).
func kill(cause := "magic") -> void:
	_server.kill_player(self, cause, null)


## Adds velocity (knockback, launch pads). The client is corrected by the next snapshot.
func push(impulse: Vector3) -> void:
	state.velocity += impulse


## Plays a sound only this player hears, not positioned in the world.
func play_sound(sound_name: String, volume := 1.0, pitch := 1.0) -> void:
	_server.play_sound_to(self, sound_name, volume, pitch)


## A chat message only this player sees.
func send_message(text: String) -> void:
	if _online():
		Net.s_chat.rpc_id(peer_id, text)


## Big text in the middle of the player's screen for a few seconds.
func show_title(text: String, subtitle := "", seconds := 3.0) -> void:
	if _online():
		Net.s_title.rpc_id(peer_id, text, subtitle, seconds)


## Shows or replaces a server-defined UI panel. See engine/client/server_ui.gd for the spec format.
func show_ui(ui_id: String, spec: Dictionary) -> void:
	ui_ids[ui_id] = true
	if _online():
		Net.s_ui_show.rpc_id(peer_id, ui_id, spec)


## Closes a server UI panel shown with show_ui.
func hide_ui(ui_id: String) -> void:
	ui_ids.erase(ui_id)
	if _online():
		Net.s_ui_hide.rpc_id(peer_id, ui_id)


## Whether the player is in creative mode.
func is_creative() -> bool:
	return inventory.creative


## Switches the player between creative (true) and survival (false).
func set_creative(enabled: bool) -> void:
	var was := inventory.creative
	inventory.creative = enabled
	sync_inventory()
	if was and not enabled and _online():
		_server.tutorials.on_join(self)  # a sandbox player trying survival gets the first tutorial


## Adds blocks or items (optionally with item data); returns how many did not fit.
func give(item: int, count := 1, item_data := {}) -> int:
	var left := inventory.add(item, count, _server.items.max_stack(item), item_data)
	sync_inventory()
	return left


## Removes items if the player has enough; returns false otherwise.
func take(block: int, count := 1) -> bool:
	var ok := inventory.remove(block, count)
	if ok:
		sync_inventory()
	return ok


## How many of a block or item the player carries.
func count_of(block: int) -> int:
	return inventory.count_of(block)


## Empties the player's inventory.
func clear_inventory() -> void:
	inventory.clear()
	sync_inventory()


## Drops items as an entity in front of the player.
func drop(item: int, count := 1, item_data := {}) -> void:
	_server.entities.drop_item(item, count, get_eye_position() - Vector3(0, 0.3, 0),
		PlayerPhysics.look_direction(yaw, pitch) * 5.0 + Vector3(0, 1.5, 0), 1.5, item_data)


## Fills hotbar slots in order with the given block ids.
func set_hotbar(blocks: Array, count := 1) -> void:
	inventory.clear()
	for i in mini(blocks.size(), Inventory.SIZE):
		inventory.set_slot(i, int(blocks[i]), count)
	sync_inventory()


## {item, count, data} in a slot (0-35 backpack, then equipment; see equipment_slot).
func get_item(slot: int) -> Dictionary:
	if slot < 0 or slot >= inventory.total():
		return {"item": 0, "count": 0, "data": {}}
	return {"item": inventory.ids[slot], "count": inventory.counts[slot], "data": inventory.data[slot]}


## Replaces the item data of a slot (a copy is stored). Use it for wear, experience, levels,
## upgrades, custom names ("name"), tooltip lines ("lore") and per-item stat "modifiers".
func set_item_data(slot: int, item_data: Dictionary) -> void:
	if slot < 0 or slot >= inventory.total() or inventory.ids[slot] <= 0:
		return
	if var_to_bytes(item_data).size() > Inventory.MAX_DATA_BYTES:
		push_warning("[server] item data for %s is too large" % name)
		return
	inventory.data[slot] = item_data.duplicate(true)
	sync_inventory()


## Inventory index of a named equipment slot ("head", "chest", ...), or -1.
func equipment_slot(slot_name: String) -> int:
	return inventory.equipment_index(slot_name)


## Wears down the item in a slot (respects the durability gameplay rule and item_durability event).
func damage_item(slot: int, amount := 1, reason := "use") -> void:
	_server.damage_item(self, slot, amount, reason)


## Current stats (see ItemRegistry.BASE_STATS and register_stat).
func get_stats() -> Dictionary:
	if _stats_dirty or _stats.is_empty():
		_server.refresh_stats(self)
	return _stats


## One stat's current value (see get_stats).
func get_stat(stat_name: String) -> float:
	return float(get_stats().get(stat_name, 0.0))


## Adds or replaces a stat modifier. `op`: "add" or "multiply" (amount 0.2 = +20%); `seconds` 0 = until
## removed. Use ids like "my_mod:haste".
func add_modifier(id: String, stat: String, amount: float, op := "add", seconds := 0.0) -> void:
	modifiers[id] = {"stat": stat, "amount": amount, "op": "multiply" if op == "multiply" else "add",
		"expires": _server._time + seconds if seconds > 0.0 else 0.0}
	refresh_stats()


## Removes a stat modifier added with add_modifier.
func remove_modifier(id: String) -> void:
	if modifiers.erase(id):
		refresh_stats()


## Recomputes stats now (after changing item data or modifiers outside the API).
func refresh_stats() -> void:
	_stats_dirty = true
	_server.refresh_stats(self)


## Sends the inventory to the player after changing it directly (give and take do this for you).
func sync_inventory() -> void:
	_stats_dirty = true
	_server.check_discoveries(self)
	if _online():
		Net.s_inventory.rpc_id(peer_id, inventory.to_packed(), inventory.selected, inventory.creative, inventory.data_to_network())
		_server.refresh_stats(self)


## Lets the player wear a server cosmetic registered with `unlocked: false`. Saved with the world.
func grant_cosmetic(cosmetic_name: String) -> void:
	_server.grant_cosmetic(self, cosmetic_name, true)


## Takes back a server cosmetic granted with grant_cosmetic.
func revoke_cosmetic(cosmetic_name: String) -> void:
	_server.grant_cosmetic(self, cosmetic_name, false)


## Whether the player may wear a server cosmetic.
func has_cosmetic(cosmetic_name: String) -> bool:
	return owned_cosmetics.has(cosmetic_name)


## Avatar data laid over this player's look, e.g. a team uniform: {wear: {shirt: {id, color}}}; an
## empty id takes a category off. Pass {} to clear. Not saved.
func set_avatar_override(values: Dictionary) -> void:
	avatar_override = _server.cosmetics.sanitize_avatar(values, Callable(), true)
	_server.refresh_avatar(self)


## Whether the player can craft a recipe (discovered, or discovery is off).
func knows_recipe(recipe_id: String) -> bool:
	return _server.knows_recipe(self, recipe_id)


## Teaches a recipe (source is passed to recipe_learned). Returns true if it was new.
func learn_recipe(recipe_id: String, source := "mod") -> bool:
	return _server.learn_recipe(self, recipe_id, source)


## Whether the player is a server admin.
func is_admin() -> bool:
	return _server.is_admin(self)


## Disconnects the player with a reason.
func kick(reason: String) -> void:
	_server.kick(peer_id, reason)


# --- Persistence --------------------------------------------------------------------------------

## The inventory, equipment and item data as saved with the world.
func save_inventory() -> Dictionary:
	var backpack := PackedInt32Array()
	backpack.append_array(inventory.ids.slice(0, Inventory.SIZE))
	backpack.append_array(inventory.counts.slice(0, Inventory.SIZE))
	var item_data := {}
	for i in Inventory.SIZE:
		if inventory.ids[i] > 0 and not inventory.data[i].is_empty():
			item_data[str(i)] = inventory.data[i]
	var equipment := {}
	for i in inventory.equipment_slots.size():
		var index := Inventory.SIZE + i
		if inventory.ids[index] > 0:
			equipment[inventory.equipment_slots[i]] = [inventory.ids[index], inventory.counts[index], inventory.data[index]]
	return {"inventory": Array(backpack), "item_data": item_data, "equipment": equipment}


## Restores an inventory saved by save_inventory.
func load_inventory(saved: Dictionary) -> void:
	inventory.load_packed(PackedInt32Array(saved.get("inventory", [])))
	var item_data = saved.get("item_data", {})
	if item_data is Dictionary:
		for key in item_data:
			var i := int(key)
			if i >= 0 and i < Inventory.SIZE and item_data[key] is Dictionary and inventory.ids[i] > 0:
				inventory.data[i] = item_data[key]
	var equipment = saved.get("equipment", {})
	if equipment is Dictionary:
		for slot_name in equipment:
			var entry = equipment[slot_name]
			var index := inventory.equipment_index(String(slot_name))
			if index >= 0 and entry is Array and entry.size() == 3 and _server.items.is_valid(int(entry[0])):
				inventory.set_slot(index, int(entry[0]), int(entry[1]), entry[2] if entry[2] is Dictionary else {})
			elif entry is Array and entry.size() == 3 and _server.items.is_valid(int(entry[0])):
				inventory.add(int(entry[0]), int(entry[1]), 1, entry[2] if entry[2] is Dictionary else {})  # slot no longer exists
	_stats_dirty = true
