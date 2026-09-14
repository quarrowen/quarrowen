extends RefCounted
## Natural spawning and despawning of mobs.
##
## Spawn rules (ModApi.add_spawn_rule): entity, category ("monster" | "animal" | "ambient" | "misc";
## default from the entity's `category` or its AI: hostile mobs are monsters, passive ones animals),
## light [min, max] (0-15 at the spawn spot: block light or daylight-scaled sky light; monsters default
## to [0, 7], animals to [9, 15]), place ("any" | "surface" | "underground"), time ("any" | "day" |
## "night"), on (block names to stand on), group [min, max] (pack size), chance (per player per second),
## max_nearby (this type within 48 blocks of a player), max_total, min_distance, max_distance, biomes
## (biome names where it may spawn; needs the biome generator).
##
## Categories cap how many of their mobs may be near each player (`caps`, changeable with
## set_spawn_caps). Monsters and ambient mobs despawn: at once beyond 96 blocks from every player, and
## now and then beyond 32. Animals stay (so farms keep their animals); so do persistent entities and any
## entity with data `no_despawn` (named, tamed, bred, ...).

const WorldTime = preload("res://engine/shared/world_time.gd")
const Chunk = preload("res://engine/shared/chunk.gd")
const EntityPhysics = preload("res://engine/shared/entity_physics.gd")

const DESPAWN_DISTANCE := 96.0
const RANDOM_DESPAWN_DISTANCE := 32.0
const RANDOM_DESPAWN_CHANCE := 1.0 / 30.0  # per second, for each far-away mob
const CAP_RADIUS := 64.0
const CATEGORIES := ["monster", "animal", "ambient", "misc"]
const DESPAWNS := {"monster": true, "ambient": true, "misc": true, "animal": false}
const DEFAULT_LIGHT := {"monster": [0, 7], "animal": [9, 15], "ambient": [0, 15], "misc": [0, 15]}

var rules: Array[Dictionary] = []
var caps := {"monster": 24, "animal": 12, "ambient": 8, "misc": 8}

var _entities
var _server


func _init(entities) -> void:
	_entities = entities
	_server = entities._server


func add_rule(def: Dictionary) -> void:
	var type_id := int(def.entity)
	var category := str(def.get("category", category_of_type(type_id)))
	if not category in CATEGORIES:
		category = "misc"
	var light: Array = def.get("light", DEFAULT_LIGHT[category]) if def.get("light") is Array and def.light.size() == 2 else DEFAULT_LIGHT[category]
	var group: Array = def.get("group", [1, 1]) if def.get("group") is Array and def.group.size() == 2 else [1, 1]
	var rule := def.duplicate()
	rule.category = category
	rule.light = [clampi(int(light[0]), 0, 15), clampi(int(light[1]), 0, 15)]
	rule.group = [clampi(int(group[0]), 1, 8), clampi(int(group[1]), 1, 8)]
	rule.place = str(def.get("place", "any")) if str(def.get("place", "any")) in ["any", "surface", "underground"] else "any"
	rules.append(rule)


func set_caps(values: Dictionary) -> void:
	for key in values:
		if str(key) in CATEGORIES:
			caps[str(key)] = clampi(int(values[key]), 0, 200)


## A mob type's category: its `category` key, else from its AI (hostile, archer and boss presets or a
## hostile temperament: monster; passive: animal).
func category_of_type(type_id: int) -> String:
	var def: Dictionary = _entities.registry.defs[type_id]
	if str(def.get("category", "")) in CATEGORIES:
		return str(def.category)
	var ai = def.get("ai")
	var preset := str(ai.get("preset", "")) if ai is Dictionary else str(ai)
	var temperament := str(ai.get("temperament", "")) if ai is Dictionary else ""
	if preset in ["hostile", "archer", "boss"] or temperament == "hostile":
		return "monster"
	if preset == "passive" or temperament == "passive":
		return "animal"
	return "misc"


func category_of(e) -> String:
	if e.data.get("category") is String:
		return e.data.category
	return category_of_type(e.type)


## Mobs of a category within CAP_RADIUS of a position.
func count_near(center: Vector3, category: String) -> int:
	var n := 0
	var r2 := CAP_RADIUS * CAP_RADIUS
	for e in _entities.entities.values():
		if e.def.kind == "mob" and e.is_alive() and e.body.position.distance_squared_to(center) <= r2 and category_of(e) == category:
			n += 1
	return n


func run() -> void:
	if rules.is_empty() or not _server.gameplay.get("mob_spawning", true) or _server.players.is_empty():
		return
	var daylight: float = WorldTime.daylight(_server.get_time_of_day())
	for rule in rules:
		var time := str(rule.get("time", "any"))
		if time == "night" and daylight > 0.45 or time == "day" and daylight < 0.6:
			continue
		var type_id := int(rule.entity)
		var total := 0
		for e in _entities.entities.values():
			if e.type == type_id:
				total += 1
		if total >= int(rule.get("max_total", 40)):
			continue
		for p in _server.players.values():
			if p.dead or randf() > float(rule.get("chance", 0.3)):
				continue
			if count_near(p.state.position, rule.category) >= int(caps.get(rule.category, 8)):
				continue
			if _entities.in_radius(p.state.position, 48.0, type_id).size() >= int(rule.get("max_nearby", 4)):
				continue
			var pos := find_spot(p.state.position, rule, daylight)
			if pos == Vector3.INF:
				continue
			var pack := randi_range(int(rule.group[0]), int(rule.group[1]))
			for i in pack:
				var at := pos if i == 0 else find_spot(pos, rule, daylight, 1.0, 4.0)
				if at == Vector3.INF:
					continue
				var ev: Dictionary = _server.emit("entity_natural_spawn", {"type": _entities.registry.defs[type_id].name, "position": at,
					"category": rule.category, "cancelled": false})
				if not ev.cancelled:
					_entities.spawn(type_id, at)


## A spot for a rule's mob around `center` (surface or caves), or Vector3.INF.
func find_spot(center: Vector3, rule: Dictionary, daylight: float, min_distance := -1.0, max_distance := -1.0) -> Vector3:
	var world = _server.world
	var solid: PackedByteArray = _server.registry.solid_lut
	var liquid: PackedByteArray = _server.registry.liquid_lut
	var allowed: Array = rule.get("on", [])
	var def: Dictionary = _entities.registry.defs[int(rule.entity)]
	var near := float(rule.get("min_distance", 24.0)) if min_distance < 0.0 else min_distance
	var far := float(rule.get("max_distance", 44.0)) if max_distance < 0.0 else max_distance
	for attempt in 6:
		var angle := randf() * TAU
		var dist := randf_range(near, far)
		var x := floori(center.x + cos(angle) * dist)
		var z := floori(center.z + sin(angle) * dist)
		if not world.has_chunk(Vector2i(floori(x / 16.0), floori(z / 16.0))):
			continue
		# Start at a random height near the player and look up and down for a place to stand, so caves
		# get mobs as well as the surface.
		var start := clampi(floori(center.y) + randi_range(-16, 16), 2, Chunk.SIZE_Y - 3)
		for step in 25:
			var y := start + ((step >> 1) if step % 2 == 0 else -((step + 1) >> 1))
			if y < 2 or y > Chunk.SIZE_Y - 3:
				continue
			var ground: int = world.get_block(x, y - 1, z)
			if ground == 65535 or solid[ground] == 0 or liquid[ground] == 1:
				continue
			if solid[world.get_block(x, y, z)] == 1 or liquid[world.get_block(x, y, z)] == 1 or solid[world.get_block(x, y + 1, z)] == 1:
				continue
			if not allowed.is_empty() and not allowed.has(ground):
				break
			if not rule.get("biomes", []).is_empty() and _server.biome_generator != null \
					and not rule.biomes.has(_server.biome_generator.biome_at(x, z)):
				break
			var cell := Vector3i(x, y, z)
			var open_sky: bool = _server.block_ticks._column_height(x, z) < y
			if rule.place == "surface" and not open_sky or rule.place == "underground" and open_sky:
				break
			var light: int = _server.block_ticks.light_at(cell, daylight)
			if light < int(rule.light[0]) or light > int(rule.light[1]):
				break
			var pos := Vector3(x + 0.5, y, z + 0.5)
			if not EntityPhysics.collides(pos, def.width * 0.5, def.height, world, solid):
				return pos
			break
	return Vector3.INF


## Removes mobs nobody is near (run once a second).
func despawn() -> void:
	for e in _entities.entities.values():
		if e.def.persistent or e.def.kind != "mob" or e.data.get("no_despawn", false) or not DESPAWNS.get(category_of(e), true):
			continue
		var nearest := INF
		for p in _server.players.values():
			nearest = minf(nearest, p.state.position.distance_to(e.body.position))
		if nearest > DESPAWN_DISTANCE or (nearest > RANDOM_DESPAWN_DISTANCE and randf() < RANDOM_DESPAWN_CHANCE):
			_entities.remove(e)


## {category: {near, cap}} around a player, for the /mobs command.
func summary(center: Vector3) -> Dictionary:
	var out := {}
	for category in CATEGORIES:
		out[category] = {"near": count_near(center, category), "cap": caps[category]}
	return out
