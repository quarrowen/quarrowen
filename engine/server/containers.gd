extends RefCounted
## Container types, open container screens and their click rules.
##
## A container type: {title, groups: [{name, count, columns, label, take_only, accepts}], progress:
## [{name, label, color}]}. `take_only` slots (outputs) can be emptied but not filled by players;
## `accepts` limits what players may put in: an array of item names, "fuel", or a Callable(item) -> bool.
## Blocks become containers with the block key `container: "<type name>"` and open on right-click.
##
## While a player views a container, clicks on container slots arrive as inventory slot
## SLOT_BASE + index and share the player's cursor stack; shift-click moves stacks between the
## container and the backpack.

const ContainerView = preload("res://engine/server/container.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")

const SLOT_BASE := 1000
const MAX_SLOTS := 128
const MAX_DISTANCE := 8.0

## What a container screen is showing, as one string. Three kinds live behind it:
##
##   b:12,64,-3   a block - the store is that block's data
##   i:7          the bag in the viewer's own inventory slot 7 - the store is that item's data
##   s:mod:vault  a shared store - the store is `stores[name]`, saved with the world
##
## **One type rather than a Vector3i that is sometimes something else.** The addressing used to be a
## position everywhere, which is why "a container that is the same wherever you open it" had nowhere
## to live. A tagged string keeps every viewer map, dirty set and open-screen field a single type,
## and the tag says which kind you have rather than leaving it to be inferred. (2026-09-21)
static func block_key(pos: Vector3i) -> String:
	return "b:%d,%d,%d" % [pos.x, pos.y, pos.z]


static func item_key(slot: int) -> String:
	return "i:%d" % slot


static func store_key(store_name: String) -> String:
	return "s:" + store_name


static func is_block_key(key: String) -> bool:
	return key.begins_with("b:")


static func position_of(key: String) -> Vector3i:
	var parts := key.substr(2).split(",")
	if parts.size() != 3:
		return Vector3i.ZERO
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))

## Shared stores: name -> the dictionary a container view is backed by. Saved with the world.
##
## The engine does not decide whose a store is - the *name* does. A mod wanting one vault for the
## server asks for "vault"; a mod wanting one each asks for "vault_" + player_id. That keeps the
## sharing rule where the rule belongs and this table a plain dictionary. (2026-09-21)
var stores := {}
var types := {}  # type name -> def
var _server
var _viewers := {}  # container key -> {peer id: true}
var _dirty := {}  # container key -> true (send to viewers this tick)
var _stock_dirty := {}  # Vector3i -> true (crafting stations nearby need new stock)
var _check_timer := 0.0


func _init(game_server) -> void:
	_server = game_server


## Registers a container type. Returns false when invalid.
func register(type_name: String, def: Dictionary) -> bool:
	var groups := []
	var start := 0
	for g in (def.get("groups") if def.get("groups") is Array else [{"name": "items", "count": int(def.get("slots", 27))}]):
		if not (g is Dictionary):
			continue
		var count := clampi(int(g.get("count", 1)), 1, MAX_SLOTS - start)
		if count <= 0:
			break
		groups.append({"name": String(g.get("name", "slots%d" % groups.size())).left(32), "start": start, "count": count,
			"columns": clampi(int(g.get("columns", mini(count, 9))), 1, 12), "label": String(g.get("label", "")).left(48),
			"take_only": bool(g.get("take_only", false)), "accepts": g.get("accepts")})
		start += count
	if start == 0:
		return false
	var progress := []
	for bar in (def.get("progress") if def.get("progress") is Array else []):
		if bar is Dictionary and bar.get("name") is String:
			progress.append({"name": String(bar.name).left(32), "label": String(bar.get("label", "")).left(48),
				"color": String(bar.get("color", "#ffffff")).left(16)})
	types[type_name] = {"name": type_name, "title": String(def.get("title", type_name.get_slice(":", 1).capitalize())).left(48),
		"size": start, "groups": groups, "progress": progress}
	return true


## The container type of a block, or {}.
func type_of_block(block: int) -> Dictionary:
	if not _server.registry.is_valid(block):
		return {}
	return types.get(String(_server.registry.defs[block].get("container", "")), {})


## The container at a position (loads its chunk), or null if the block there is not a container.
func get_container(pos: Vector3i, player = null):
	# A container is a block, and a block is in a world. When a player opened it, it is theirs.
	var into = _server.realm_of(player) if player != null else _server.realm
	var block: int = _server.get_block_loaded(pos, into)
	var t := type_of_block(block)
	if t.is_empty():
		return null
	var store: Dictionary = _server.get_block_data(pos, into)
	if store.is_empty():
		_server.set_block_data(pos, store, into)
		store = _server.get_block_data(pos, into)
	var view := ContainerView.new(_server, pos, t, store, block_key(pos))
	if store.has("loot"):
		_server.loot.fill(view, player)  # structure chests roll their loot on first use
	return view


## The container a key names, whoever it belongs to, or null. The one place that knows where each
## kind of store lives; everything else works in keys.
func at_key(key: String, player = null):
	if is_block_key(key):
		return get_container(position_of(key), player)
	if key.begins_with("i:"):
		return _bag_view(player, int(key.substr(2)))
	if key.begins_with("s:"):
		return _store_view(key.substr(2))
	return null


## A bag: a container whose store is the data of an item a player is carrying.
##
## Contents live in the item's own data, so the bag holds what it holds wherever it goes - into a
## chest, onto the floor, into another player's hands - and needs no bookkeeping to do it.
func _bag_view(player, slot: int):
	if player == null or slot < 0 or slot >= player.inventory.ids.size():
		return null
	var item: int = player.inventory.ids[slot]
	if item <= 0:
		return null
	var t: Dictionary = types.get(String(_server.items.get_def(item).get("container", "")), {})
	if t.is_empty():
		return null
	var data: Dictionary = player.inventory.data[slot]
	if not (data is Dictionary):
		data = {}
		player.inventory.data[slot] = data
	return ContainerView.new(_server, Vector3i.ZERO, t, data, item_key(slot))


## A shared store: the same contents wherever it is opened from.
func _store_view(store_name: String):
	var entry = stores.get(store_name)
	if not (entry is Dictionary):
		return null
	var t: Dictionary = types.get(String(entry.get("type", "")), {})
	if t.is_empty():
		return null
	return ContainerView.new(_server, Vector3i.ZERO, t, entry, store_key(store_name))


## Declares a shared store, if it does not exist yet. Returns false if the type is unknown.
func declare_store(store_name: String, type_name: String) -> bool:
	if not types.has(type_name):
		push_error("Shared store '%s' wants container type '%s', which nothing registered." % [store_name, type_name])
		return false
	if not (stores.get(store_name) is Dictionary):
		stores[store_name] = {"type": type_name}
	return true


func open(p, pos: Vector3i) -> bool:
	return _open(p, block_key(pos))


## Opens the bag in one of a player's own inventory slots.
func open_item(p, slot: int) -> bool:
	return _open(p, item_key(slot))


## Opens a shared store by name.
func open_store(p, store_name: String) -> bool:
	return _open(p, store_key(store_name)) if stores.has(store_name) else false


func _open(p, key: String) -> bool:
	var c = at_key(key, p)
	if c == null:
		return false
	var pos := position_of(key) if is_block_key(key) else Vector3i.ZERO
	if _server.emit("container_open", {"player": p, "position": pos, "container": c, "key": key, "cancelled": false}).cancelled:
		return false
	close(p, false)
	p.open_container = key
	if not _viewers.has(key):
		_viewers[key] = {}
	_viewers[key][p.peer_id] = true
	if p._online():
		Net.s_container_open.rpc_id(p.peer_id, _view(c))
	return true


## Closes the player's container screen (`tell_client`: the server decided, e.g. it was broken).
func close(p, tell_client := true) -> void:
	if p.open_container == null:
		return
	var key: String = p.open_container
	p.open_container = null
	if _viewers.has(key):
		_viewers[key].erase(p.peer_id)
		if _viewers[key].is_empty():
			_viewers.erase(key)
	_server.emit("container_close", {"player": p, "position": position_of(key) if is_block_key(key) else Vector3i.ZERO, "key": key})
	if tell_client and p._online():
		Net.s_container_close.rpc_id(p.peer_id)


## Every write to a container passes through here - a player clicking, a hopper, a parcel arriving, a
## station consuming its inputs, loot filling a chest, a mod.
##
## `container_changed` is raised from here, so automation is visible: a hopper, a parcel arriving, a
## station taking its inputs, loot filling a chest. It used to fire only from the two player-click
## handlers.
##
## **Immediate, not deferred.** Deferring it to the end of the tick was tried and it broke the furnace:
## lighting when fuel goes in is gameplay and has to happen now. The re-entrancy that made deferring
## look necessary was never the engine's problem - a QuickJS runtime cannot be re-entered, and that is
## handled in `_invoke` in js_mod.gd, where it belongs. (2026-09-21)
func mark_changed(pos: Vector3i, p = null, slot := -1) -> void:
	changed(block_key(pos), p, slot)


## The same, for any container: a bag or a shared store has no position to be marked at.
func changed(key: String, p = null, slot := -1) -> void:
	if _viewers.has(key):
		_dirty[key] = true
	var c = at_key(key, p)
	if is_block_key(key):
		_stock_dirty[position_of(key)] = true
	if c != null:
		_server.emit("container_changed", {"player": p, "position": c.position, "container": c, "key": key, "slot": slot})


## Sends changed contents to viewers and closes screens players walked away from.
func update(delta: float) -> void:
	for key: String in _dirty:
		for peer_id: int in _viewers.get(key, {}):
			var p = _server.players.get(peer_id)
			if p == null or not p._online():
				continue
			# Resolved per viewer, not once: a bag key names a slot in *that* player's inventory, so
			# one view cannot be shared the way a block's can.
			var c = at_key(key, p)
			if c != null:
				Net.s_container_update.rpc_id(peer_id, c.to_network())
	_dirty.clear()
	for pos: Vector3i in _stock_dirty:
		_server.refresh_crafting_stock(pos)
	_stock_dirty.clear()
	_check_timer += delta
	if _check_timer < 0.5:
		return
	_check_timer = 0.0
	for p in _server.players.values():
		if p.open_container == null:
			continue
		var key: String = p.open_container
		if p.dead:
			close(p)
			continue
		if is_block_key(key):
			# Walking away closes a chest. A bag travels with you and a shared store is nowhere, so
			# neither has a distance to walk out of.
			var pos := position_of(key)
			var far: bool = p.get_eye_position().distance_to(Vector3(pos) + Vector3.ONE * 0.5) > MAX_DISTANCE
			if far or type_of_block(_server.realm_of(p).world.get_block_v(pos)).is_empty():
				close(p)
		elif at_key(key, p) == null:
			close(p)  # the bag was put down, or the store went away


## A container block was removed: close screens and spill the contents.
func block_removed(pos: Vector3i, store: Dictionary, old_block: int) -> void:
	for peer_id: int in _viewers.get(block_key(pos), {}).keys():
		var p = _server.players.get(peer_id)
		if p != null:
			close(p)
	var t := type_of_block(old_block)
	if t.is_empty() or not (store.get("slots") is Array):
		return
	var c := ContainerView.new(_server, pos, t, store.duplicate(true))
	for i in t.size:
		var s: Dictionary = c.get_item(i)
		if s.item > 0:
			_server.entities.drop_item(s.item, s.count, Vector3(pos) + Vector3(0.5, 0.5, 0.5),
				Vector3(randf_range(-1.5, 1.5), randf_range(2.0, 4.0), randf_range(-1.5, 1.5)), 0.4, s.data)


# --- Clicks ---------------------------------------------------------------------------------------

## Whether this inventory slot is the bag the player currently has open.
func holds_open_bag(p, slot: int) -> bool:
	return p.open_container != null and String(p.open_container) == item_key(slot)


## A click on container slot `slot` by a player whose screen shows it. Returns true if handled.
func click(p, slot: int, button: int, shift: bool) -> void:
	if p.open_container == null:
		return
	var c = at_key(p.open_container, p)
	if c == null or slot < 0 or slot >= c.size():
		return
	var inv = p.inventory
	# A bag inside a bag is a duplication bug waiting to be found: the outer one holds the inner one's
	# item data, so copying the outer stack copies everything in it. Refused rather than fixed,
	# because there is no version of nesting that is not somebody's exploit. (2026-09-21)
	if not String(p.open_container).begins_with("b:") and inv.cursor_count > 0 \
			and not String(_server.items.get_def(inv.cursor_id).get("container", "")).is_empty():
		return
	var s: Dictionary = c.get_item(slot)
	var g: Dictionary = c.group_of(slot)
	var limit: int = _server.items.max_stack(inv.cursor_id if inv.cursor_count > 0 else s.item)
	if shift:
		if s.item > 0:
			var left: int = inv.add(s.item, s.count, _server.items.max_stack(s.item), s.data)
			c.set_item(slot, s.item, left, s.data)
	elif inv.cursor_count <= 0:
		if s.item <= 0:
			return
		var n: int = s.count if button == 1 else (s.count + 1) / 2
		inv.cursor_id = s.item
		inv.cursor_count = n
		inv.cursor_data = s.data.duplicate(true)
		c.set_item(slot, s.item, s.count - n, s.data)
	elif g.get("take_only", false):
		# Output slots: a matching cursor collects the stack if it fits.
		if s.item == inv.cursor_id and s.data == inv.cursor_data and inv.cursor_count + s.count <= limit:
			inv.cursor_count += s.count
			c.clear_slot(slot)
		else:
			return
	elif not accepts(g, inv.cursor_id):
		return
	elif s.item <= 0 or (s.item == inv.cursor_id and s.data == inv.cursor_data):
		var put := mini(inv.cursor_count if button == 1 else 1, limit - s.count)
		if put <= 0:
			return
		c.set_item(slot, inv.cursor_id, s.count + put, inv.cursor_data.duplicate(true))
		inv.cursor_count -= put
		if inv.cursor_count <= 0:
			inv.cursor_id = 0
			inv.cursor_data = {}
	elif button == 1:
		c.set_item(slot, inv.cursor_id, inv.cursor_count, inv.cursor_data)
		inv.cursor_id = s.item
		inv.cursor_count = s.count
		inv.cursor_data = s.data
	else:
		return
	# The player's own key, not c.position: a bag and a shared store both sit at ZERO.
	changed(p.open_container, p, slot)
	p.sync_inventory()


## Shift-click on a backpack slot while a container is open: move the stack into the container.
func quick_move_in(p, slot: int) -> bool:
	if p.open_container == null:
		return false
	var c = at_key(p.open_container, p)
	var inv = p.inventory
	if c == null or slot < 0 or slot >= inv.SIZE or inv.ids[slot] <= 0 or inv.counts[slot] <= 0:
		return c != null
	var id: int = inv.ids[slot]
	var left: int = inv.counts[slot]
	# Groups made for this item (a fuel slot for fuel) fill before general-purpose groups.
	var ordered: Array = c.type.groups.filter(func(g): return g.accepts != null) + c.type.groups.filter(func(g): return g.accepts == null)
	for g in ordered:
		if g.take_only or not accepts(g, id):
			continue
		left = c.add(id, left, inv.data[slot], g.name)
		if left <= 0:
			break
	if left == inv.counts[slot]:
		return true
	if left <= 0:
		inv.clear_slot(slot)
	else:
		inv.counts[slot] = left
	changed(p.open_container, p)
	p.sync_inventory()
	return true


func accepts(g: Dictionary, item: int) -> bool:
	var rule = g.get("accepts")
	if rule == null:
		return true
	if rule is Callable:
		return rule.call(item)
	if rule is String and rule == "fuel":
		return _server.get_fuel(item) > 0.0
	if rule is Array:
		return rule.has(_server.items.name_of(item))
	return true


func _view(c) -> Dictionary:
	var view: Dictionary = c.to_network()
	var groups := []
	for g in c.type.groups:
		groups.append({"name": g.name, "start": g.start, "count": g.count, "columns": g.columns, "label": g.label, "take_only": g.take_only})
	view.merge({"title": c.type.title, "size": c.type.size, "groups": groups, "bars": c.type.progress})
	return view
