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
##   ai: "none" | "wander" | "passive" (wanders, flees when hurt) | "hostile" (chases and attacks players)
##   attack_damage, attack_range, attack_cooldown, sight_range
##   damage (projectiles: damage dealt on hit), lifetime (seconds, 0 = forever)
##   drops: [[item name or id, count], ...] on death; sounds: {hurt, death, ambient, attack}
##   persistent: saved with the chunk it is in (otherwise despawns when no player is near)
func register(def: Dictionary) -> int:
	var type_name := String(def.get("name", ""))
	if type_name.is_empty() or ids.has(type_name) or defs.size() >= MAX_TYPES:
		push_error("Invalid or duplicate entity type '%s'" % type_name)
		return -1
	var d := def.duplicate(true)
	d.name = type_name
	d.display_name = String(def.get("display_name", type_name.get_slice(":", 1).capitalize())).left(64)
	d.kind = String(def.get("kind", "mob")) if String(def.get("kind", "mob")) in KINDS else "mob"
	d.model = String(def.get("model", "")).left(256)
	d.sprite = String(def.get("sprite", "")).left(256)
	d.width = clampf(float(def.get("width", 0.6)), 0.05, 4.0)
	d.height = clampf(float(def.get("height", 1.8 if d.kind == "mob" else 0.25)), 0.05, 6.0)
	d.scale = clampf(float(def.get("scale", 1.0)), 0.05, 10.0)
	d.glow = bool(def.get("glow", false))
	d.health = maxf(float(def.get("health", 10.0 if d.kind == "mob" else 0.0)), 0.0)
	d.speed = clampf(float(def.get("speed", 2.5)), 0.0, 40.0)
	d.gravity = float(def.get("gravity", 32.0 if d.kind != "projectile" else 12.0))
	d.drag = maxf(float(def.get("drag", 0.0)), 0.0)
	d.knockback_resistance = clampf(float(def.get("knockback_resistance", 0.0)), 0.0, 1.0)
	d.ai = String(def.get("ai", "wander" if d.kind == "mob" else "none"))
	d.attack_damage = maxf(float(def.get("attack_damage", 2.0)), 0.0)
	d.attack_range = clampf(float(def.get("attack_range", 1.4)), 0.5, 8.0)
	d.attack_cooldown = clampf(float(def.get("attack_cooldown", 1.0)), 0.1, 30.0)
	d.sight_range = clampf(float(def.get("sight_range", 16.0)), 1.0, 64.0)
	d.damage = maxf(float(def.get("damage", 0.0)), 0.0)
	d.lifetime = maxf(float(def.get("lifetime", 10.0 if d.kind == "projectile" else 0.0)), 0.0)
	d.persistent = bool(def.get("persistent", false))
	d.sounds = def.get("sounds", {}) if def.get("sounds") is Dictionary else {}
	d.drops = def.get("drops", []) if def.get("drops") is Array else []
	var id := defs.size()
	d.id = id
	defs.append(d)
	ids[type_name] = id
	return id


func id_of(type_name: String) -> int:
	return ids.get(type_name, -1)


func is_valid(id: int) -> bool:
	return id >= 0 and id < defs.size()


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
