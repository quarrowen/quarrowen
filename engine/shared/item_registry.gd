extends RefCounted
## Items. Every block id (1-65534) is implicitly also the item that places it; non-block items (coal,
## tools, armor, wands, ...) get ids from FIRST_ITEM upward. Inventories store these ids.
##
## Item definitions describe what an item *is*; what happens to one particular item (wear, experience,
## upgrades, a custom name) lives in its item data (see Inventory). Equipment slots and player stats
## are registered here too so the client can show them.

const FIRST_ITEM := 65536
const MAX_ITEMS := 4096
const NETWORK_FIELDS := ["name", "display_name", "icon", "max_stack", "usable", "durability", "tool", "weapon",
	"armor", "equip_slot", "modifiers", "model", "lore", "armor_texture"]
const DEFAULT_SLOTS := ["head", "chest", "legs", "feet", "offhand"]
const MAX_SLOTS := 16

## Player stats and their base values. Mods add more with register_stat. Items, item data and timed
## effects change them through modifiers: {stat, amount, op: "add" | "multiply"}.
const BASE_STATS := {
	"max_health": 20.0,
	"armor": 0.0,  # damage reduction points (20 = 80% against small hits)
	"toughness": 0.0,  # keeps armor effective against big hits
	"attack_damage": 1.0,
	"attack_cooldown": 0.25,  # seconds between attacks
	"reach": 4.5,
	"crit_chance": 0.0,
	"crit_multiplier": 1.5,
	"knockback": 1.0,  # multiplier on knockback dealt
	"knockback_resistance": 0.0,
	"mining_speed": 1.0,
	"move_speed": 1.0,
}

var blocks  # BlockRegistry
var defs: Array[Dictionary] = []  # non-block items; id = FIRST_ITEM + index
var ids := {}  # name -> id
## Equipment slots in inventory order: {name, display_name}.
var slots: Array[Dictionary] = []
var stats := BASE_STATS.duplicate()


func _init(block_registry) -> void:
	blocks = block_registry
	for slot_name in DEFAULT_SLOTS:
		register_slot({"name": slot_name})


static func is_block_item(id: int) -> bool:
	return id > 0 and id < FIRST_ITEM


## def keys:
##   name, display_name, icon (asset name), max_stack (default 64; 1 for items with durability)
##   usable: right-click fires item_use
##   durability: uses before it breaks (0 = never); wear is stored in item data as `damage`
##   tool: {type: "pickaxe" | "axe" | "shovel" | any mod type, tier, speed}
##   weapon: {damage, cooldown, reach, crit_chance, knockback, sweep (fraction dealt to nearby mobs)}
##   armor: {armor, toughness, knockback_resistance}
##   equip_slot: equipment slot it goes in ("head", "chest", ...; mods can register more)
##   modifiers: [{stat, amount, op}] applied while equipped, or while held for tools and weapons
##   model: glTF asset for held rendering; lore: tooltip lines
##   armor_texture: worn look in the 64x64 skin layout (the slot picks which regions show)
##   attack_damage (legacy shorthand for weapon.damage)
## Returns the item id or -1.
func register(def: Dictionary) -> int:
	var item_name := String(def.get("name", ""))
	if item_name.is_empty() or ids.has(item_name) or blocks.ids.has(item_name) or defs.size() >= MAX_ITEMS:
		push_error("Invalid or duplicate item '%s'" % item_name)
		return -1
	var d := def.duplicate(true)
	d.name = item_name
	d.display_name = String(def.get("display_name", item_name.get_slice(":", 1).capitalize())).left(64)
	d.icon = String(def.get("icon", "")).left(256)
	d.durability = clampi(int(def.get("durability", 0)), 0, 1000000)
	d.max_stack = clampi(int(def.get("max_stack", 1 if d.durability > 0 else 64)), 1, 999)
	d.usable = bool(def.get("usable", false))
	d.tool = _clean_dict(def.get("tool"), {"type": "", "tier": 0, "speed": 1.0})
	d.weapon = _clean_dict(def.get("weapon"), {"damage": 1.0, "cooldown": 0.25, "reach": 4.5, "crit_chance": 0.0, "knockback": 1.0, "sweep": 0.0})
	if def.has("attack_damage") and d.weapon.is_empty():
		d.weapon = {"damage": float(def.attack_damage), "cooldown": 0.25, "reach": 4.5, "crit_chance": 0.0, "knockback": 1.0, "sweep": 0.0}
	d.armor = _clean_dict(def.get("armor"), {"armor": 0.0, "toughness": 0.0, "knockback_resistance": 0.0})
	d.equip_slot = String(def.get("equip_slot", "")).left(32)
	d.modifiers = clean_modifiers(def.get("modifiers", []))
	d.model = String(def.get("model", "")).left(256)
	d.armor_texture = String(def.get("armor_texture", "")).left(256)
	d.lore = (def.get("lore") as Array).map(func(l): return String(l).left(120)).slice(0, 8) if def.get("lore") is Array else []
	var id := FIRST_ITEM + defs.size()
	d.id = id
	defs.append(d)
	ids[item_name] = id
	return id


## def: name, display_name. Items whose equip_slot matches go in it (the offhand takes anything).
func register_slot(def: Dictionary) -> int:
	var slot_name := String(def.get("name", ""))
	if slot_name.is_empty() or slots.size() >= MAX_SLOTS or slot_index(slot_name) >= 0:
		push_error("Invalid or duplicate equipment slot '%s'" % slot_name)
		return -1
	slots.append({"name": slot_name, "display_name": String(def.get("display_name", slot_name.capitalize())).left(32)})
	return slots.size() - 1


func slot_index(slot_name: String) -> int:
	for i in slots.size():
		if slots[i].name == slot_name:
			return i
	return -1


func slot_names() -> PackedStringArray:
	var out := PackedStringArray()
	for s in slots:
		out.append(s.name)
	return out


func register_stat(stat_name: String, base: float) -> void:
	if not stats.has(stat_name):
		stats[stat_name] = base


## Whether an item may be placed in the named equipment slot. The offhand takes anything.
func fits_slot(id: int, slot_name: String) -> bool:
	if slot_name == "offhand":
		return is_valid(id)
	return id >= FIRST_ITEM and String(get_def(id).get("equip_slot", "")) == slot_name


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


func max_durability(id: int) -> int:
	return get_def(id).get("durability", 0)


func tool_of(id: int) -> Dictionary:
	return get_def(id).get("tool", {})


func weapon_of(id: int) -> Dictionary:
	return get_def(id).get("weapon", {})


## Damage dealt when attacking while holding this item (bare hand and blocks: 1).
func attack_damage(id: int) -> float:
	var weapon := weapon_of(id)
	return float(weapon.damage) if not weapon.is_empty() else 1.0


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


func load_network(data, slot_data = null, stat_data = null) -> bool:
	if not (data is Array) or data.size() > MAX_ITEMS:
		return false
	if slot_data is Array:
		slots.clear()
		for s in slot_data.slice(0, MAX_SLOTS):
			if s is Dictionary and s.get("name") is String:
				register_slot(s)
	if stat_data is Dictionary:
		for key in stat_data:
			if key is String and (stat_data[key] is float or stat_data[key] is int):
				stats[key] = float(stat_data[key])
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


static func clean_modifiers(list) -> Array:
	var out := []
	for m in (list if list is Array else []):
		if m is Dictionary and m.get("stat") is String:
			out.append({"stat": String(m.stat).left(32), "amount": float(m.get("amount", 0.0)),
				"op": "multiply" if m.get("op") == "multiply" else "add"})
	return out.slice(0, 16)


static func _clean_dict(value, defaults: Dictionary) -> Dictionary:
	if not (value is Dictionary) or value.is_empty():
		return {}
	var out := defaults.duplicate()
	for key in defaults:
		if value.has(key):
			out[key] = String(value[key]).left(32) if defaults[key] is String else (int(value[key]) if defaults[key] is int else float(value[key]))
	return out
