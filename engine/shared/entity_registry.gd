extends RefCounted
## Entity types (mobs, projectiles, dropped items) registered by mods. The server keeps the whole
## definition (AI, drops, damage); clients get only what they need to draw and animate them.
## Type ids are indexes into `defs`; "engine:item" (dropped item stacks) is always id 0.

const MAX_TYPES := 1024
const ITEM := 0
const NETWORK_FIELDS := ["name", "display_name", "model", "sprite", "width", "height", "scale", "kind", "glow"]
const KINDS := ["item", "mob", "projectile", "object"]

var defs: Array[Dictionary] = []
var ids := {}  # name -> id


func _init() -> void:
	register({"name": "engine:item", "kind": "item", "width": 0.25, "height": 0.25, "gravity": 20.0})


## Definition keys (all optional except name):
##   kind: "mob" | "projectile" | "object" | "item"
##   model: glTF asset (nodes named leg_a / leg_b / arm_a / arm_b swing while walking, head turns)
##   sprite: texture asset drawn as a billboard when there is no model (projectiles, particles)
##   width, height: collision box in blocks; scale: model scale; glow: unshaded (e.g. magic sparks)
##   health (0 = cannot be damaged), speed, gravity, drag, knockback_resistance (0-1)
##   ai: a preset name or a Dictionary of behaviour settings, attacks and phases; see
##       engine/server/ai/mob_config.gd (mobs only)
##   damage (projectiles: damage dealt on hit), lifetime (seconds, 0 = forever)
##   drops: [[item name or id, count], ...] on death; sounds: {hurt, death, ambient, attack}
##   persistent: saved with the chunk it is in (otherwise despawns when no player is near)
##   notable: the whole server is told when one appears, and it is marked on everybody's map and
##            compass - the marker follows it and counts down - until it dies or its time runs out.
##            {announce, slain ("%s" is the killer), gone, label, color, minutes (0 = never leaves)},
##            or `true` for the defaults. For the rare ones worth hunting; see server/sightings.gd.
## `replace`: an existing type of that name gets the new definition in place (same id; mod reloads).
func register(def: Dictionary, replace := false) -> int:
	var type_name := String(def.get("name", ""))
	if type_name.is_empty() or (ids.has(type_name) and not replace) or (defs.size() >= MAX_TYPES and not ids.has(type_name)):
		push_error("Invalid or duplicate entity type '%s'" % type_name)
		return -1
	var d := def.duplicate(true)
	d.name = type_name
	d.display_name = String(def.get("display_name", type_name.get_slice(":", 1).capitalize())).left(64)
	d.kind = String(def.get("kind", "mob")) if String(def.get("kind", "mob")) in KINDS else "mob"
	d.model = String(def.get("model", "")).left(256)
	d.sprite = String(def.get("sprite", "")).left(256)
	d.width = clampf(float(def.get("width", 0.6)), 0.05, 8.0)
	d.height = clampf(float(def.get("height", 1.8 if d.kind == "mob" else 0.25)), 0.05, 16.0)
	d.scale = clampf(float(def.get("scale", 1.0)), 0.05, 10.0)
	d.glow = bool(def.get("glow", false))
	d.health = maxf(float(def.get("health", 10.0 if d.kind == "mob" else 0.0)), 0.0)
	d.speed = clampf(float(def.get("speed", 2.5)), 0.0, 40.0)
	d.gravity = float(def.get("gravity", 32.0 if d.kind != "projectile" else 12.0))
	d.drag = maxf(float(def.get("drag", 0.0)), 0.0)
	d.knockback_resistance = clampf(float(def.get("knockback_resistance", 0.0)), 0.0, 1.0)
	d.ai = def.get("ai", "wander" if d.kind == "mob" else "none")
	d.damage = maxf(float(def.get("damage", 0.0)), 0.0)
	d.lifetime = maxf(float(def.get("lifetime", 10.0 if d.kind == "projectile" else 0.0)), 0.0)
	d.persistent = bool(def.get("persistent", false))
	d.sounds = def.get("sounds", {}) if def.get("sounds") is Dictionary else {}
	d.drops = def.get("drops", []) if def.get("drops") is Array else []
	d.notable = _read_notable(def.get("notable"), d.display_name)
	if ids.has(type_name):
		var existing: int = ids[type_name]
		d.id = existing
		defs[existing].clear()
		defs[existing].merge(d)
		return existing
	var id := defs.size()
	d.id = id
	defs.append(d)
	ids[type_name] = id
	return id


## What a definition asks for by way of being announced, normalised to {announce, slain, gone, label,
## color, minutes} - or `{}`, which is nearly every creature, so a caller can test it as a boolean.
##
## `true` means "notable, with the defaults", because that is all most of them want and a mod should
## not have to write a sentence to get one. Nothing here names anything of the mod's own - no sound,
## no effect - deliberately: a name nested inside a definition has to be qualified at the API
## boundary, four have been missed one at a time, and the announcement sounds the same whoever makes
## it. (2026-09-23)
##
## `minutes` is how long it waits to be found before it leaves (0 = it never does, which is what a
## boss wants). A hunt with no clock is not a hunt: the creature would still be standing there
## tomorrow, and the marker on everybody's compass would stop meaning "go now".
static func _read_notable(value, display_name: String) -> Dictionary:
	if value is bool:
		if not value:
			return {}
		value = {}
	if not (value is Dictionary):
		return {}
	return {
		"announce": String(value.get("announce", "%s is out there somewhere." % display_name)).left(160),
		# "%s" is whoever did it. Kind by default, because the server reads these out to children.
		"slain": String(value.get("slain", "%%s saw off the %s." % display_name)).left(160),
		"gone": String(value.get("gone", "The %s has slipped away." % display_name)).left(160),
		"label": String(value.get("label", display_name)).left(32),
		"color": String(value.get("color", "#ffd166")).left(9),
		"minutes": clampf(float(value.get("minutes", 10.0)), 0.0, 120.0),
	}


## Whether this type is one the server announces, and how. `{}` when it is not.
##
## A function rather than a reach into `defs[id].notable`, because `notable` is a shape a mod wrote
## and this registry normalised, and those have one owner here - see engine/owned.txt.
func notable_of(type_id: int) -> Dictionary:
	if not is_valid(type_id):
		return {}
	var notable = defs[type_id].get("notable", {})
	return notable if notable is Dictionary else {}


## The id registered under this name, or **-1 if nothing is**.
##
## -1 is an answer, not an error: mods rely on it to make optional content optional. But **a -1 kept
## and later written as the u16 a block id is becomes 65535, which means UNLOADED** - the world then
## reads as absent rather than wrong, and the symptom is a player falling for ever. Keep the answer
## only after checking it, or use the `require_*` form at the API boundary.
func id_of(type_name: String) -> int:
	return ids.get(type_name, -1)


## Whether anything is registered under this id.
func is_valid(id: int) -> bool:
	return id >= 0 and id < defs.size()


## The creature table as the client receives it, trimmed to `NETWORK_FIELDS`.
func to_network() -> Array:
	var out := []
	for d in defs:
		var entry := {}
		for field in NETWORK_FIELDS:
			entry[field] = d[field]
		out.append(entry)
	return out


## Client side. Rebuilds the table from the server's copy (the engine:item entry is included).
func load_network(data) -> bool:
	if not (data is Array) or data.is_empty() or data.size() > MAX_TYPES:
		return false
	defs.clear()
	ids.clear()
	for entry in data:
		if not (entry is Dictionary) or not (entry.get("name") is String):
			return false
		var clean := {}
		for field in NETWORK_FIELDS:
			if entry.has(field):
				clean[field] = entry[field]
		if register(clean) < 0:
			return false
	return defs[ITEM].name == "engine:item"
