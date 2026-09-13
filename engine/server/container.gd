extends RefCounted
## A container block's contents (chest, furnace, machine). Slots live in the block's data as item names,
## so they are saved with the world and survive mods being added or removed. Mods get one from
## api.get_container(position); changes made through it are shown to everyone viewing it.
##
## Slot groups come from the container type (see Containers.register): e.g. a furnace has "input",
## "fuel" and "output" groups. `state` is free-form data the mod keeps with the container (saved).

var type: Dictionary
var position: Vector3i
## Mod-owned data saved with the container (e.g. how long the fuel still burns).
var state: Dictionary

var _store: Dictionary  # the block data dictionary holding "slots", "state" and "progress"
var _server


func _init(server, pos: Vector3i, container_type: Dictionary, store: Dictionary) -> void:
	_server = server
	position = pos
	type = container_type
	_store = store
	if not (_store.get("slots") is Array):
		_store.slots = []
	var slots: Array = _store.slots
	if slots.size() != type.size:
		slots.resize(type.size)
	if not (_store.get("state") is Dictionary):
		_store.state = {}
	if not (_store.get("progress") is Dictionary):
		_store.progress = {}
	state = _store.state


func size() -> int:
	return type.size


## {item, count, data} for a slot (item 0 when empty).
func get_item(slot: int) -> Dictionary:
	var entry = _store.slots[slot] if slot >= 0 and slot < type.size else null
	if not (entry is Array) or entry.size() < 2:
		return {"item": 0, "count": 0, "data": {}}
	var id: int = _server.items.id_of(String(entry[0]))
	if id <= 0 or int(entry[1]) <= 0:
		return {"item": 0, "count": 0, "data": {}}
	return {"item": id, "count": int(entry[1]), "data": entry[2] if entry.size() > 2 and entry[2] is Dictionary else {}}


func set_item(slot: int, item: int, count: int, item_data := {}) -> void:
	if slot < 0 or slot >= type.size:
		return
	_store.slots[slot] = [_server.items.name_of(item), count, item_data] if item > 0 and count > 0 and _server.items.is_valid(item) else null
	changed()


func clear_slot(slot: int) -> void:
	set_item(slot, 0, 0)


## Slot indices of a named group, or every slot for "".
func group(group_name := "") -> Array:
	if group_name.is_empty():
		return range(type.size)
	for g in type.groups:
		if g.name == group_name:
			return range(g.start, g.start + g.count)
	return []


## The group a slot belongs to ({} if none).
func group_of(slot: int) -> Dictionary:
	for g in type.groups:
		if slot >= g.start and slot < g.start + g.count:
			return g
	return {}


## Adds items to a group (or to every slot players may insert into), merging stacks first. Returns
## how many did not fit.
func add(item: int, count: int, item_data := {}, group_name := "") -> int:
	var slots := group(group_name) if not group_name.is_empty() else range(type.size).filter(func(i): return not group_of(i).get("take_only", false))
	var limit: int = _server.items.max_stack(item)
	var left := count
	for pass_index in 2:
		for i in slots:
			if left <= 0:
				break
			var s := get_item(i)
			var same: bool = s.item == item and s.data == item_data and s.count < limit
			if (pass_index == 0 and same) or (pass_index == 1 and s.item == 0):
				var n := mini(left, limit - s.count)
				set_item(i, item, s.count + n, item_data.duplicate(true))
				left -= n
	return left


## Removes up to `count` items from a slot and returns what was removed as {item, count, data}.
func take(slot: int, count: int) -> Dictionary:
	var s := get_item(slot)
	var n := mini(count, s.count)
	if n <= 0:
		return {"item": 0, "count": 0, "data": {}}
	set_item(slot, s.item, s.count - n, s.data)
	return {"item": s.item, "count": n, "data": s.data}


func is_empty() -> bool:
	for i in type.size:
		if get_item(i).item > 0:
			return false
	return true


## Sets a progress bar of the container type (0-1) for viewers.
func set_progress(bar: String, value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	if not is_equal_approx(float(_store.progress.get(bar, -1.0)), v):
		_store.progress[bar] = v
		changed()


func get_progress(bar: String) -> float:
	return float(_store.progress.get(bar, 0.0))


## Shows the current contents to everyone viewing (called automatically by the setters above).
func changed() -> void:
	_server.containers.mark_changed(position)


## Network form: ids and counts packed, item data by slot, progress values.
func to_network() -> Dictionary:
	var packed := PackedInt32Array()
	packed.resize(type.size * 2)
	var slot_data := {}
	for i in type.size:
		var s := get_item(i)
		packed[i] = s.item
		packed[type.size + i] = s.count
		if s.item > 0 and not s.data.is_empty():
			slot_data[i] = s.data
	return {"slots": packed, "data": slot_data, "progress": _store.progress.duplicate()}
