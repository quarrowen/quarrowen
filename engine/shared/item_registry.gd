extends RefCounted
## Items. Every block id (1-65534) is implicitly also the item that places it; non-block items (coal,
## wands, ...) get ids from FIRST_ITEM upward. Inventories store these ids.

const FIRST_ITEM := 65536
const MAX_ITEMS := 4096
const NETWORK_FIELDS := ["name", "display_name", "icon", "max_stack", "usable"]

var blocks  # BlockRegistry
var defs: Array[Dictionary] = []  # non-block items; id = FIRST_ITEM + index
var ids := {}  # name -> id


func _init(block_registry) -> void:
	blocks = block_registry


static func is_block_item(id: int) -> bool:
	return id > 0 and id < FIRST_ITEM


## def: name, display_name, icon (asset name), max_stack (default 64), usable (right-click fires
## item_use). Returns the item id or -1.
func register(def: Dictionary) -> int:
	var item_name := String(def.get("name", ""))
	if item_name.is_empty() or ids.has(item_name) or blocks.ids.has(item_name) or defs.size() >= MAX_ITEMS:
		push_error("Invalid or duplicate item '%s'" % item_name)
		return -1
	var d := def.duplicate(true)
	d.name = item_name
	d.display_name = String(def.get("display_name", item_name.get_slice(":", 1).capitalize())).left(64)
	d.icon = String(def.get("icon", "")).left(256)
	d.max_stack = clampi(int(def.get("max_stack", 64)), 1, 999)
	d.usable = bool(def.get("usable", false))
	var id := FIRST_ITEM + defs.size()
	d.id = id
	defs.append(d)
	ids[item_name] = id
	return id


## Resolves block or item names.
func id_of(item_name: String) -> int:
	if ids.has(item_name):
		return ids[item_name]
	return blocks.id_of(item_name)


func is_valid(id: int) -> bool:
	return blocks.is_valid(id) and id > 0 or (id >= FIRST_ITEM and id - FIRST_ITEM < defs.size())


func get_def(id: int) -> Dictionary:
	return defs[id - FIRST_ITEM] if id >= FIRST_ITEM and id - FIRST_ITEM < defs.size() else {}


func name_of(id: int) -> String:
	if id >= FIRST_ITEM:
		return get_def(id).get("name", "")
	return blocks.defs[id].name if blocks.is_valid(id) else ""


func display_name(id: int) -> String:
	if id >= FIRST_ITEM:
		return get_def(id).get("display_name", "?")
	return blocks.display_name(id)


func max_stack(id: int) -> int:
	return get_def(id).get("max_stack", 64) if id >= FIRST_ITEM else 64


func is_usable(id: int) -> bool:
	return get_def(id).get("usable", false)


## Texture asset for inventory icons.
func icon_of(id: int) -> String:
	if id >= FIRST_ITEM:
		return get_def(id).get("icon", "")
	return blocks.defs[id].textures[4] if blocks.is_valid(id) else ""


func to_network() -> Array:
	var out := []
	for d in defs:
		var entry := {}
		for field in NETWORK_FIELDS:
			entry[field] = d[field]
		out.append(entry)
	return out


func load_network(data) -> bool:
	if not (data is Array) or data.size() > MAX_ITEMS:
		return false
	for entry in data:
		if not (entry is Dictionary) or not (entry.get("name") is String):
			return false
		var clean := {}
		for field in NETWORK_FIELDS:
			if entry.has(field):
				clean[field] = entry[field]
		if register(clean) < 0:
			return false
	return true
