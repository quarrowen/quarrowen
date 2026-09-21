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

var types := {}  # type name -> def
var _server
var _viewers := {}  # Vector3i -> {peer id: true}
var _dirty := {}  # Vector3i -> true (send to viewers this tick)
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
	var view := ContainerView.new(_server, pos, t, store)
	if store.has("loot"):
		_server.loot.fill(view, player)  # structure chests roll their loot on first use
	return view


func open(p, pos: Vector3i) -> bool:
	var c = get_container(pos, p)
	if c == null:
		return false
	if _server.emit("container_open", {"player": p, "position": pos, "container": c, "cancelled": false}).cancelled:
		return false
	close(p, false)
	p.open_container = pos
	if not _viewers.has(pos):
		_viewers[pos] = {}
	_viewers[pos][p.peer_id] = true
	if p._online():
		Net.s_container_open.rpc_id(p.peer_id, _view(c))
	return true


## Closes the player's container screen (`tell_client`: the server decided, e.g. it was broken).
func close(p, tell_client := true) -> void:
	if p.open_container == null:
		return
	var pos: Vector3i = p.open_container
	p.open_container = null
	if _viewers.has(pos):
		_viewers[pos].erase(p.peer_id)
		if _viewers[pos].is_empty():
			_viewers.erase(pos)
	_server.emit("container_close", {"player": p, "position": pos})
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
	if _viewers.has(pos):
		_dirty[pos] = true
	_stock_dirty[pos] = true
	var c = get_container(pos)
	if c != null:
		_server.emit("container_changed", {"player": p, "position": pos, "container": c, "slot": slot})


## Sends changed contents to viewers and closes screens players walked away from.
func update(delta: float) -> void:
	for pos: Vector3i in _dirty:
		var c = get_container(pos)
		var view: Dictionary = c.to_network() if c != null else {}
		for peer_id: int in _viewers.get(pos, {}):
			var p = _server.players.get(peer_id)
			if p != null and p._online() and c != null:
				Net.s_container_update.rpc_id(peer_id, view)
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
		var pos: Vector3i = p.open_container
		var far: bool = p.get_eye_position().distance_to(Vector3(pos) + Vector3.ONE * 0.5) > MAX_DISTANCE
		if far or p.dead or type_of_block(_server.realm_of(p).world.get_block_v(pos)).is_empty():
			close(p)


## A container block was removed: close screens and spill the contents.
func block_removed(pos: Vector3i, store: Dictionary, old_block: int) -> void:
	for peer_id: int in _viewers.get(pos, {}).keys():
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

## A click on container slot `slot` by a player whose screen shows it. Returns true if handled.
func click(p, slot: int, button: int, shift: bool) -> void:
	if p.open_container == null:
		return
	var c = get_container(p.open_container)
	if c == null or slot < 0 or slot >= c.size():
		return
	var inv = p.inventory
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
	mark_changed(c.position, p, slot)
	p.sync_inventory()


## Shift-click on a backpack slot while a container is open: move the stack into the container.
func quick_move_in(p, slot: int) -> bool:
	if p.open_container == null:
		return false
	var c = get_container(p.open_container)
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
	mark_changed(c.position, p)
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
