extends RefCounted
## Tameable mobs. A mob type with `taming: {items: [item names], chance, follow_distance,
## teleport_distance}`:
## - right-click it holding one of `items` to try taming it (each try uses one item; `chance` per try);
## - a tamed mob belongs to that player: it follows them (teleporting to catch up when far behind),
##   never attacks them, fights whatever hurts its owner or whatever its owner attacks, and does not
##   despawn;
## - its owner right-clicks it (with anything but its taming or breeding food) to make it sit or stand.
## Data: owner (player id), owner_name, sitting. Events: entity_tamed {player, entity},
## entity_sit {player, entity, sitting}.

const DEFEND_RANGE := 16.0

var _entities
var _server


func _init(entities) -> void:
	_entities = entities
	_server = entities._server
	_entities.ai.custom_behaviors["engine:sit"] = {"score": _sit_score, "update": _sit_update, "stop": Callable()}
	_entities.ai.custom_behaviors["engine:follow_owner"] = {"score": _follow_score, "update": _follow_update, "stop": Callable()}


static func config(def: Dictionary) -> Dictionary:
	var t = def.get("taming")
	if not (t is Dictionary):
		return {}
	var items: Array = t.get("items", []) if t.get("items") is Array else ([t.items] if t.get("items") is String else [])
	return {"items": items.map(func(i): return str(i)), "chance": clampf(float(t.get("chance", 0.33)), 0.0, 1.0),
		"follow_distance": clampf(float(t.get("follow_distance", 3.0)), 1.0, 32.0),
		"teleport_distance": clampf(float(t.get("teleport_distance", 16.0)), 4.0, 128.0)}


func config_of(e) -> Dictionary:
	if not e.def.has("_taming"):
		e.def._taming = config(e.def)
	return e.def._taming


func owner_id(e) -> String:
	return str(e.data.get("owner", ""))


func is_tamed(e) -> bool:
	return not owner_id(e).is_empty()


func owner_of(e):
	var id := owner_id(e)
	if id.is_empty():
		return null
	for p in _server.players.values():
		if p.player_id == id:
			return p
	return null


## Right-click by a player. Returns true if it was handled (a taming try or sit toggle).
func interact(p, e) -> bool:
	var c := config_of(e)
	if c.is_empty() or not e.is_alive():
		return false
	var item: int = p.inventory.selected_item()
	var item_name: String = _server.items.name_of(item) if item > 0 else ""
	if not is_tamed(e):
		if not c.items.has(item_name):
			return false
		if not p.inventory.creative:
			p.inventory.counts[p.inventory.selected] -= 1
			if p.inventory.counts[p.inventory.selected] <= 0:
				p.inventory.clear_slot(p.inventory.selected)
			p.sync_inventory()
		if randf() < c.chance:
			tame(e, p)
		else:
			_server.play_effect("engine:smoke", e.body.position + Vector3(0, e.def.height, 0), {"scale": 0.5})
		return true
	if owner_id(e) != p.player_id or c.items.has(item_name) or _entities.breeding.is_food(e, item):
		return false
	set_sitting(e, not bool(e.data.get("sitting", false)), p)
	return true


func tame(e, p) -> void:
	e.data.owner = p.player_id
	e.data.owner_name = p.name
	e.data.no_despawn = true
	e.data.erase("sitting")
	if e.brain != null:
		e.brain.memory.erase(_entities.ai.key_of(p))
		e.brain.threat.erase(_entities.ai.key_of(p))
		if e.brain.target == p:
			e.brain.set_target(null)
	_server.play_effect("engine:heal", e.body.position + Vector3(0, e.def.height, 0), {"scale": 1.2})
	_server.emit("entity_tamed", {"player": p, "entity": e})


func set_sitting(e, sitting: bool, p = null) -> void:
	if sitting:
		e.data.sitting = true
		if e.brain != null:
			e.brain.stop()
			e.brain.set_target(null)
	else:
		e.data.erase("sitting")
	e.set_look({"pose": "sit" if sitting else ""})
	_server.emit("entity_sit", {"player": p, "entity": e, "sitting": sitting})


## Tamed mobs near a player that are ready to fight for them.
func defenders_of(p) -> Array:
	var out := []
	for e in _entities.in_radius(p.state.position, DEFEND_RANGE):
		if e.brain != null and e.is_alive() and owner_id(e) == p.player_id and not e.data.get("sitting", false):
			out.append(e)
	return out


## Someone hurt `p`: their tamed mobs turn on the attacker.
func owner_hurt(p, attacker) -> void:
	if attacker == null or attacker == p:
		return
	for e in defenders_of(p):
		if attacker != e and not (attacker.get("data") != null and str(attacker.data.get("owner", "")) == p.player_id):
			e.brain.add_threat(attacker, 6.0)


## `p` attacked `target`: their tamed mobs join in.
func owner_attacked(p, target) -> void:
	if target == null or (target.get("data") != null and str(target.data.get("owner", "")) == p.player_id):
		return
	for e in defenders_of(p):
		if target != e:
			e.brain.add_threat(target, 4.0)


## Whether `e` must never treat `other` as an enemy (its owner).
func protects(e, other) -> bool:
	return other != null and other.get("player_id") != null and is_tamed(e) and owner_id(e) == other.player_id


## Once a second: tamed mobs that fell far behind catch up with their owner.
func update() -> void:
	for e in _entities.entities.values():
		if e.brain == null or not is_tamed(e) or e.data.get("sitting", false) or not e.is_alive():
			continue
		var p = owner_of(e)
		if p == null or p.dead or not p.state.on_ground:
			continue
		if e.body.position.distance_to(p.state.position) > config_of(e).get("teleport_distance", 16.0):
			var spot := _near(p.state.position)
			if spot != Vector3.INF:
				e.body.position = spot
				e.body.velocity = Vector3.ZERO
				e.brain.stop()
				e.dirty = true


func _near(center: Vector3) -> Vector3:
	var world = _server.world
	var solid: PackedByteArray = _server.registry.solid_lut
	for offset in [Vector3i(2, 0, 0), Vector3i(-2, 0, 0), Vector3i(0, 0, 2), Vector3i(0, 0, -2), Vector3i(1, 0, 1), Vector3i(-1, 0, -1)]:
		var feet: Vector3i = Vector3i(floori(center.x), floori(center.y), floori(center.z)) + offset
		if solid[world.get_block_v(feet)] == 0 and solid[world.get_block_v(feet + Vector3i.UP)] == 0 and solid[world.get_block_v(feet + Vector3i.DOWN)] == 1:
			return Vector3(feet) + Vector3(0.5, 0.0, 0.5)
	return Vector3.INF


func _sit_score(brain) -> float:
	return 1.3 if brain.entity.data.get("sitting", false) else 0.0


func _sit_update(brain, _delta: float) -> void:
	brain.stop()


func _follow_score(brain) -> float:
	var e = brain.entity
	if not is_tamed(e) or e.data.get("sitting", false) or brain.target != null:
		return 0.0
	var p = owner_of(e)
	if p == null or p.dead:
		return 0.0
	var d: float = e.body.position.distance_to(p.state.position)
	return 0.55 if d > config_of(e).follow_distance * 2.0 or (brain.behavior == "engine:follow_owner" and d > config_of(e).follow_distance) else 0.0


func _follow_update(brain, _delta: float) -> void:
	var p = owner_of(brain.entity)
	if p != null:
		brain.move_to(p.state.position, 1.2, config_of(brain.entity).follow_distance)
