extends RefCounted
## Engine mob AI: owns every mob brain and the shared services they use: the pathfinder (with a
## per-tick request budget), noises, ally alerts, surround slots around shared targets, a spatial
## grid for neighbour queries, projectile awareness and boss health bars.

const MobBrain = preload("res://engine/server/ai/mob_brain.gd")
const MobConfig = preload("res://engine/server/ai/mob_config.gd")
const Pathfinder = preload("res://engine/server/ai/pathfinder.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")

## How many path searches one tick may run. Eight, because the search is in Rust; the GDScript
## twin could only afford two, and it is gone. (2026-09-23)
const PATHS_PER_TICK := 8
const GRID_CELL := 8.0
## Ticks between rebuilding the neighbour grid and engagement groups (mobs move < 1 block meanwhile).
const GRID_INTERVAL := 4
const NOISE_LIFETIME := 1.0
const BOSS_BAR_INTERVAL := 0.5

var server
var entities
var pathfinder: Pathfinder
var time := 0.0
## name -> {score: Callable(brain) -> float, update: Callable(brain, delta), stop: Callable(brain)}
var custom_behaviors := {}
var noises: Array = []  # {position, radius, source, time, violent}
var brains := {}  # entity id -> MobBrain
var projectiles: Array = []

var _configs := {}  # entity type id -> resolved config
## True once any mob hunts other mobs (enemy_groups); otherwise mob-vs-mob checks are skipped.
var _mob_rivalries := false
var _boss_sent := {}  # entity id -> last health shown
var _grid := {}  # Vector2i -> Array[MobBrain]
var _path_queue: Array = []  # [brain, from, goal, radius]
var _queued := {}  # brain -> index marker
var _engaged := {}  # target key -> Array[MobBrain]
var _boss_timer := 0.0
var _boss_viewers := {}  # entity id -> {peer_id: true}
var _ticks := 0


func _init(game_server, entity_system) -> void:
	server = game_server
	entities = entity_system
	pathfinder = Pathfinder.new(entity_system.realm.world if entity_system.realm != null else server.world)


func update_tables() -> void:
	var r = server.registry
	pathfinder.set_tables(r.solid_lut, r.liquid_lut, r.opaque_lut, r.hazard_lut)


func resolve_entity(type_name: String) -> int:
	return entities.registry.id_of(type_name)


func config_for(type_id: int) -> Dictionary:
	if not _configs.has(type_id):
		var def: Dictionary = entities.registry.defs[type_id]
		_configs[type_id] = MobConfig.resolve(def.get("ai", "wander"), def, resolve_entity)
		if def.get("breeding") is Dictionary:
			# Animals that breed follow their food and seek partners (engine/server/breeding.gd).
			for behavior in ["engine:breed", "engine:tempt"]:
				if not _configs[type_id].behaviors.has(behavior):
					_configs[type_id].behaviors.append(behavior)
		if def.get("taming") is Dictionary:
			# Tameable mobs sit and follow their owner (engine/server/taming.gd).
			for behavior in ["engine:sit", "engine:follow_owner"]:
				if not _configs[type_id].behaviors.has(behavior):
					_configs[type_id].behaviors.append(behavior)
		if not _configs[type_id].enemy_groups.is_empty():
			_mob_rivalries = true
	return _configs[type_id]


func attach(e) -> MobBrain:
	var brain := MobBrain.new(e, self, config_for(e.type))
	if not brain.config.enemy_groups.is_empty():
		_mob_rivalries = true
	brains[e.id] = brain
	# Visible to neighbour queries (alerts, separation) right away, not only after the next rebuild.
	var cell := Vector2i(floori(e.body.position.x / GRID_CELL), floori(e.body.position.z / GRID_CELL))
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append(brain)
	return brain


func detach(e) -> void:
	var brain = brains.get(e.id)
	brains.erase(e.id)
	for cell in _grid:
		_grid[cell].erase(brain)
	if _boss_viewers.has(e.id):
		for peer_id in _boss_viewers[e.id]:
			var p = server.players.get(peer_id)
			if p != null and server._started:
				p.hide_ui("engine:boss_%d" % e.id)
		_boss_viewers.erase(e.id)
	_boss_sent.erase(e.id)


func tick(delta: float) -> void:
	time = server._time
	_ticks += 1
	if _ticks % GRID_INTERVAL == 1 or GRID_INTERVAL == 1:
		_rebuild_grid()
	projectiles = entities.projectiles
	_process_paths()
	for brain: MobBrain in brains.values():
		if brain.entity.is_alive():
			brain.tick(delta)
	var fresh := []
	for noise in noises:
		if time - noise.time < NOISE_LIFETIME:
			fresh.append(noise)
	noises = fresh
	_boss_timer += delta
	if _boss_timer >= BOSS_BAR_INTERVAL:
		_boss_timer = 0.0
		_update_boss_bars()


func _rebuild_grid() -> void:
	_grid.clear()
	_engaged.clear()
	for brain: MobBrain in brains.values():
		var p: Vector3 = brain.entity.body.position
		var cell := Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL))
		if not _grid.has(cell):
			_grid[cell] = []
		_grid[cell].append(brain)
		if brain.behavior == "engage" and brain.target != null and brain.config.preferred_range.is_empty():
			var key := key_of(brain.target)
			if not _engaged.has(key):
				_engaged[key] = []
			_engaged[key].append(brain)


func brains_near(center: Vector3, radius: float) -> Array:
	var out := []
	var r2 := radius * radius
	for x in range(floori((center.x - radius) / GRID_CELL), floori((center.x + radius) / GRID_CELL) + 1):
		for z in range(floori((center.z - radius) / GRID_CELL), floori((center.z + radius) / GRID_CELL) + 1):
			for brain in _grid.get(Vector2i(x, z), []):
				if brain.entity.body.position.distance_squared_to(center) <= r2:
					out.append(brain)
	return out


# --- Pathfinding budget --------------------------------------------------------------------------

func request_path(brain: MobBrain, from: Vector3i, goal: Vector3i, radius: float) -> void:
	if _queued.has(brain):
		var entry: Array = _queued[brain]
		entry[1] = from
		entry[2] = goal
		entry[3] = radius
		return
	var entry := [brain, from, goal, radius]
	_queued[brain] = entry
	_path_queue.append(entry)


func _process_paths() -> void:
	var budget := PATHS_PER_TICK
	while budget > 0 and not _path_queue.is_empty():
		var entry: Array = _path_queue.pop_front()
		var brain: MobBrain = entry[0]
		_queued.erase(brain)
		if not brain.entity.is_alive():
			continue
		brain.on_path(pathfinder.find_path(entry[1], entry[2], entry[3], brain.agent), entry[2])
		budget -= 1


# --- Targets: players and entities ---------------------------------------------------------------

func key_of(t) -> String:
	return "p%d" % t.peer_id if t.get("peer_id") != null else "e%d" % t.id


func is_alive(t) -> bool:
	if t == null:
		return false
	if t.get("peer_id") != null:
		return not t.dead and server.players.get(t.peer_id) == t
	return t.is_alive()


func position_of(t) -> Vector3:
	return t.state.position if t.get("peer_id") != null else t.body.position


func velocity_of(t) -> Vector3:
	return t.state.velocity if t.get("peer_id") != null else t.body.velocity


func eye_of(t) -> Vector3:
	return t.get_eye_position() if t.get("peer_id") != null else t.body.position + Vector3(0, t.def.height * 0.85, 0)


func chest_of(t) -> Vector3:
	return position_of(t) + Vector3(0, (PlayerPhysics.HEIGHT if t.get("peer_id") != null else t.def.height) * 0.6, 0)


func half_width_of(t) -> float:
	return PlayerPhysics.HALF_WIDTH if t.get("peer_id") != null else t.def.width * 0.5


func aabb_of(t) -> AABB:
	if t.get("peer_id") != null:
		return AABB(t.state.position - Vector3(PlayerPhysics.HALF_WIDTH, 0, PlayerPhysics.HALF_WIDTH),
			Vector3(PlayerPhysics.HALF_WIDTH * 2.0, PlayerPhysics.HEIGHT, PlayerPhysics.HALF_WIDTH * 2.0))
	return t.aabb()


func health_fraction_of(t) -> float:
	if t.get("peer_id") != null:
		return t.health / maxf(t.max_health, 1.0)
	return t.health / maxf(t.def.health, 1.0) if t.def.health > 0.0 else 1.0


## Horizontal gap between the mob's box and the target's box (0 when touching), plus any height gap.
func edge_distance(e, t) -> float:
	var a: AABB = e.aabb()
	var b: AABB = aabb_of(t)
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dz := maxf(maxf(a.position.z - b.end.z, b.position.z - a.end.z), 0.0)
	var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	return sqrt(dx * dx + dz * dz) + dy


func is_enemy(brain: MobBrain, other) -> bool:
	if other == null or other == brain.entity:
		return false
	if entities.taming.protects(brain.entity, other):
		return false  # never its owner
	if float(brain.threat.get(key_of(other), 0.0)) > 0.0:
		return true  # anything it holds a grudge against (tamed mobs defending their owner)
	if other.get("peer_id") != null:
		return brain.config.temperament != "none" and not other.inventory.creative
	var other_brain = brains.get(other.id)
	if other_brain == null:
		return false
	if allied(brain, other_brain):
		return false
	return brain.config.enemy_groups.has(other_brain.config.group) or other_brain.config.enemy_groups.has(brain.config.group)


func allied(a: MobBrain, b: MobBrain) -> bool:
	var group_a: String = a.config.group if not a.config.group.is_empty() else a.entity.def.name
	var group_b: String = b.config.group if not b.config.group.is_empty() else b.entity.def.name
	return group_a == group_b


## Enemies (survival players and mobs of enemy groups) within `radius`.
func enemies_near(brain: MobBrain, center: Vector3, radius: float) -> Array:
	var out := []
	if brain.config.temperament != "none":
		var r2 := radius * radius
		for p in server.players.values():
			if not p.dead and not p.inventory.creative and p.state.position.distance_squared_to(center) <= r2:
				out.append(p)
	if _mob_rivalries:
		for other: MobBrain in brains_near(center, radius):
			if other != brain and other.entity.is_alive() and is_enemy(brain, other.entity):
				out.append(other.entity)
	return out


func nearest_player_distance(center: Vector3) -> float:
	var best := INF
	for p in server.players.values():
		best = minf(best, p.state.position.distance_to(center))
	return best


# --- Coordination --------------------------------------------------------------------------------

func alert_allies(brain: MobBrain, enemy, position: Vector3) -> void:
	if brain.config.alert_radius <= 0.0:
		return
	for other: MobBrain in brains_near(brain.entity.body.position, brain.config.alert_radius):
		if other != brain and allied(brain, other) and other.target == null:
			other.receive_alert(enemy, position)


func nearest_ally(brain: MobBrain, radius: float) -> MobBrain:
	var best: MobBrain = null
	var best_d := INF
	for other: MobBrain in brains_near(brain.entity.body.position, radius):
		if other == brain or not allied(brain, other) or other.behavior == "flee":
			continue
		var d: float = other.entity.body.position.distance_to(brain.entity.body.position)
		if d < best_d:
			best_d = d
			best = other
	return best


## Melee mobs fighting the same target spread around it instead of piling up on one side.
## Returns this brain's slot position, or Vector3.INF when it is the only attacker.
func surround_slot(brain: MobBrain, t, ring: float) -> Vector3:
	var group: Array = _engaged.get(key_of(t), [])
	if group.size() < 2 or not group.has(brain):
		return Vector3.INF
	var center := position_of(t)
	var bearings := []
	for other: MobBrain in group:
		var d: Vector3 = other.entity.body.position - center
		bearings.append([atan2(d.z, d.x), other])
	bearings.sort_custom(func(a, b): return a[0] < b[0])
	var base: float = bearings[0][0]
	for i in bearings.size():
		if bearings[i][1] == brain:
			var angle := base + TAU * i / bearings.size()
			return center + Vector3(cos(angle), 0.0, sin(angle)) * ring
	return Vector3.INF


func separation_for(brain: MobBrain) -> Vector3:
	var push := Vector3.ZERO
	var me: Vector3 = brain.entity.body.position
	var my_half: float = brain.entity.def.width * 0.5
	for other: MobBrain in brains_near(me, my_half + 2.5):
		if other == brain:
			continue
		var d: Vector3 = Vector3(me.x - other.entity.body.position.x, 0.0, me.z - other.entity.body.position.z)
		var min_d: float = my_half + other.entity.def.width * 0.5 + 0.35
		var length := d.length()
		if length < min_d:
			push += (d / maxf(length, 0.01) if length > 0.01 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)) * (1.0 - length / min_d)
	return push.limit_length(1.0)


func make_noise(position: Vector3, radius: float, source = null, violent := false) -> void:
	noises.append({"position": position, "radius": radius, "source": source, "time": time, "violent": violent})


func announce(brain: MobBrain, message: String) -> void:
	if not server._started:
		return
	var reach := float(brain.config.boss.get("bar_range", 48.0))
	for p in server.players.values():
		if p.state.position.distance_to(brain.entity.body.position) <= reach:
			p.show_title("", message, 3.0)


func _update_boss_bars() -> void:
	if not server._started:
		return
	for brain: MobBrain in brains.values():
		if brain.config.boss.is_empty():
			continue
		var e = brain.entity
		var viewers: Dictionary = _boss_viewers.get(e.id, {})
		var reach := float(brain.config.boss.get("bar_range", 48.0))
		var title := String(brain.config.boss.get("name", e.def.display_name))
		var changed: bool = _boss_sent.get(e.id, -1.0) != e.health
		_boss_sent[e.id] = e.health
		for p in server.players.values():
			var near: bool = e.is_alive() and p.state.position.distance_to(e.body.position) <= reach
			if near:
				if viewers.has(p.peer_id) and not changed:
					continue
				viewers[p.peer_id] = true
				p.show_ui("engine:boss_%d" % e.id, {"anchor": "center_top", "children": [
					{"type": "label", "text": title, "size": 20, "color": "#ff6b6b"},
					{"type": "progress", "value": e.health, "max": e.def.health, "color": "#e5484d", "width": 360},
				]})
			elif viewers.erase(p.peer_id):
				p.hide_ui("engine:boss_%d" % e.id)
		_boss_viewers[e.id] = viewers
