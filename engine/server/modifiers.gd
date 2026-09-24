extends RefCounted
## Named marks on a particular item that change what it does: keen, sturdy, kindled, whatever a mod
## calls them. An enchantment, in our own words.
##
## **Most of this already worked.** An item's own data could always carry raw stat modifiers, and
## `player_stats.gd` has always folded them in. What was missing was that they had no *names*: nothing
## could say "this axe is Keen II", check whether it was, take it off again, or tell the player.
##
## So this is a registry and four small operations, not a new system:
##
##     api.register_modifier("keen", {"display_name": "Keen", "max_level": 3,
##         "per_level": [{"stat": "damage", "amount": 1.0}], "applies_to": ["#base:axes"]})
##
##     api.apply_modifier(data, "keen", 2)   # -> new item data
##     api.modifier_level(data, "keen")      # -> 2
##
## **Hooks are not here on purpose.** A mod that wants "on hit, set them alight" listens to the hit
## event it already has and asks whether the weapon is kindled. Giving the engine its own hook system
## would be a second way to do what events already do, and two ways is worse than one.
##
## Applying a mark writes a line of lore into the item's data as well, because the client already
## shows that - so a tooltip says "Keen II" with nothing new on the wire.

const MAX_LEVEL := 10
## Borrowed rather than reimplemented: `clean_glow` already has the clamps and the defaults, and a
## second copy of them here is the reimplementation this codebase keeps writing down.
const ItemRegistry = preload("res://engine/shared/item_registry.gd")

var server

## Name -> {name, display_name, max_level, per_level, applies_to, owner}
var kinds := {}


func _init(game_server) -> void:
	server = game_server


func register(modifier_name: String, def: Dictionary, owner := "engine") -> bool:
	if modifier_name.is_empty() or kinds.has(modifier_name):
		push_error("Invalid or duplicate modifier '%s'" % modifier_name)
		return false
	var per_level := []
	for entry in (def.get("per_level", []) if def.get("per_level") is Array else []):
		if entry is Dictionary and entry.get("stat") is String:
			per_level.append({"stat": String(entry.stat), "amount": float(entry.get("amount", 0.0)),
				"op": String(entry.get("op", "add"))})
	kinds[modifier_name] = {
		"name": modifier_name,
		"display_name": String(def.get("display_name", modifier_name.capitalize())),
		"max_level": clampi(int(def.get("max_level", 1)), 1, MAX_LEVEL),
		"per_level": per_level,
		# A mark may also make the thing glow, and the glow grows with the level. Normalised by the
		# item registry so the clamps are the same ones an item's own `glow` gets - a mark asking for
		# a radius of 400 is a mod bug, not a reason for the night to end.
		"glow": ItemRegistry.clean_glow(def.get("glow")),
		# Item names, or "#tag" for a group. Empty means anything, which is what a mod means by a mark
		# that can go on anything at all.
		"applies_to": (def.get("applies_to", []) as Array).map(func(n) -> String: return String(n)) \
			if def.get("applies_to") is Array else [],
		"owner": owner,
	}
	return true


## Whether this mark may go on this item.
func allows(modifier_name: String, item_name: String) -> bool:
	var kind: Dictionary = kinds.get(modifier_name, {})
	if kind.is_empty():
		return false
	var allowed: Array = kind.applies_to
	if allowed.is_empty():
		return true
	for entry in allowed:
		var spec := String(entry)
		if spec.begins_with("#"):
			if server.tags.has(spec.substr(1), item_name):
				return true
		elif spec == item_name:
			return true
	return false


## The level of a mark on an item, or 0.
func level_of(item_data: Dictionary, modifier_name: String) -> int:
	for mark in (item_data.get("marks", []) if item_data.get("marks") is Array else []):
		if mark is Dictionary and String(mark.get("name", "")) == modifier_name:
			return int(mark.get("level", 0))
	return 0


## Every mark on an item, as [{name, level, display_name}].
func marks_on(item_data: Dictionary) -> Array:
	var out := []
	for mark in (item_data.get("marks", []) if item_data.get("marks") is Array else []):
		if not (mark is Dictionary):
			continue
		var kind: Dictionary = kinds.get(String(mark.get("name", "")), {})
		out.append({"name": String(mark.get("name", "")), "level": int(mark.get("level", 0)),
			"display_name": String(kind.get("display_name", mark.get("name", "")))})
	return out


## Puts a mark on an item, returning the new item data. `level` 0 takes it off again.
##
## Returns the data unchanged if the mark does not exist or does not belong on that item, so a mod
## calling this with something silly gets an item back rather than a broken one.
func apply(item_data: Dictionary, item_name: String, modifier_name: String, level: int) -> Dictionary:
	var kind: Dictionary = kinds.get(modifier_name, {})
	if kind.is_empty() or (level > 0 and not allows(modifier_name, item_name)):
		return item_data
	level = clampi(level, 0, int(kind.max_level))
	var data := item_data.duplicate(true)
	var marks := []
	for mark in (data.get("marks", []) if data.get("marks") is Array else []):
		if mark is Dictionary and String(mark.get("name", "")) != modifier_name:
			marks.append(mark)
	if level > 0:
		marks.append({"name": modifier_name, "level": level})
	data.marks = marks
	_rebuild(data)
	return data


## Works the stat changes and the tooltip out again from the marks. Done wholesale rather than by
## adding and subtracting, so taking a mark off cannot leave part of it behind - which is the way this
## sort of thing usually rots.
func _rebuild(data: Dictionary) -> void:
	var modifiers := []
	var lore := []
	var glow := {}
	for mark in data.marks:
		var kind: Dictionary = kinds.get(String(mark.name), {})
		if kind.is_empty():
			continue
		var level := int(mark.level)
		for effect: Dictionary in kind.per_level:
			modifiers.append({"stat": effect.stat, "amount": float(effect.amount) * level, "op": effect.op})
		lore.append("%s %s" % [kind.display_name, _numeral(level)] if level > 1 else String(kind.display_name))
		# The brightest mark wins rather than the sum, so stacking two lights does not blind anybody.
		# Energy and radius both scale with the level: a Illuminance II lantern-coat is twice the lamp.
		if not (kind.glow as Dictionary).is_empty():
			var lit := {"color": kind.glow.color, "energy": float(kind.glow.energy) * level,
				"light": float(kind.glow.light) * level}
			if float(lit.light) > float(glow.get("light", -1.0)):
				glow = lit
	if modifiers.is_empty():
		data.erase("modifiers")
	else:
		data.modifiers = modifiers
	# Written into the item's own lore, which the client already shows: a tooltip that says "Keen II"
	# with nothing new on the wire and nothing new for a mod to remember to do.
	if lore.is_empty():
		data.erase("lore")
	else:
		data.lore = lore
	# Per-stack `glow` already beats the item's own definition everywhere it is read
	# (ItemRegistry.visuals), so writing it here is all a mark has to do to light the world.
	if glow.is_empty():
		data.erase("glow")
	else:
		data.glow = glow


## I, II, III... Roman up to ten, because "Keen 2" reads like a version number.
static func _numeral(level: int) -> String:
	const NUMERALS := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	return NUMERALS[clampi(level, 0, 10)]
