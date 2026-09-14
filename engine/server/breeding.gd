extends RefCounted
## Breeding animals. A mob type with `breeding: {food: [item names], love_seconds, cooldown, grow_seconds,
## baby_scale, tempt}`:
## - follows players holding its food (tempt, default on);
## - fed by right-click while holding its food: adults fall in love (hearts) for `love_seconds`, find
##   another of their kind in love nearby, walk together and have a baby; then rest for `cooldown`;
## - babies are drawn at `baby_scale`, drop nothing, and grow up after `grow_seconds` (feeding speeds
##   that up by 10% each time).
## Timers live in entity data (saved with persistent mobs): baby, grow_left, love_left, breed_cooldown.
## Events: entity_fed {player, entity, item, cancelled}, entity_bred {parents, baby, player},
## entity_grew {entity}.

const PARTNER_RANGE := 8.0
const TEMPT_RANGE := 8.0
const MATE_DISTANCE := 1.4

var _entities
var _server


func _init(entities) -> void:
	_entities = entities
	_server = entities._server
	_entities.ai.custom_behaviors["engine:breed"] = {"score": _breed_score, "update": _breed_update, "stop": Callable()}
	_entities.ai.custom_behaviors["engine:tempt"] = {"score": _tempt_score, "update": _tempt_update, "stop": Callable()}


static func config(def: Dictionary) -> Dictionary:
	var b = def.get("breeding")
	if not (b is Dictionary):
		return {}
	var food: Array = b.get("food", []) if b.get("food") is Array else ([b.food] if b.get("food") is String else [])
	return {"food": food.map(func(f): return str(f)), "love_seconds": clampf(float(b.get("love_seconds", 30.0)), 1.0, 600.0),
		"cooldown": clampf(float(b.get("cooldown", 300.0)), 0.0, 36000.0), "grow_seconds": clampf(float(b.get("grow_seconds", 600.0)), 1.0, 360000.0),
		"baby_scale": clampf(float(b.get("baby_scale", 0.5)), 0.1, 1.0), "tempt": bool(b.get("tempt", true))}


func config_of(e) -> Dictionary:
	if not e.def.has("_breeding"):
		e.def._breeding = config(e.def)
	return e.def._breeding


func is_food(e, item: int) -> bool:
	var c := config_of(e)
	return not c.is_empty() and item > 0 and c.food.has(_server.items.name_of(item))


func is_baby(e) -> bool:
	return bool(e.data.get("baby", false))


func in_love(e) -> bool:
	return float(e.data.get("love_left", 0.0)) > 0.0


## A player right-clicked `e` holding `item`. Returns true if it was eaten.
func feed(p, e) -> bool:
	var slot: int = p.inventory.selected
	var item: int = p.inventory.selected_item()
	if not is_food(e, item) or not e.is_alive():
		return false
	var c := config_of(e)
	var baby := is_baby(e)
	if not baby and (in_love(e) or float(e.data.get("breed_cooldown", 0.0)) > 0.0):
		return false
	if _server.emit("entity_fed", {"player": p, "entity": e, "item": item, "cancelled": false}).cancelled:
		return false
	if not p.inventory.creative:
		p.inventory.counts[slot] -= 1
		if p.inventory.counts[slot] <= 0:
			p.inventory.clear_slot(slot)
		p.sync_inventory()
	if baby:
		e.data.grow_left = float(e.data.get("grow_left", c.grow_seconds)) * 0.9
		_server.play_effect("engine:sparkle", e.body.position + Vector3(0, e.def.height, 0), {"scale": 0.5})
	else:
		e.data.love_left = c.love_seconds
		e.data.fed_by = p.player_id
		_server.play_effect("engine:heal", e.body.position + Vector3(0, e.def.height, 0), {"scale": 0.8})
	_server.play_sound_at("engine:munch", e.body.position, 0.8, randf_range(0.9, 1.1))
	return true


## Once a second: babies grow, love and cooldowns run out.
func update(delta: float) -> void:
	for e in _entities.entities.values():
		if e.def.kind != "mob" or not e.def.has("breeding"):
			continue
		if is_baby(e):
			e.data.grow_left = float(e.data.get("grow_left", 0.0)) - delta
			if e.data.grow_left <= 0.0:
				e.data.erase("baby")
				e.data.erase("grow_left")
				e.set_look({"scale": 1.0})
				_server.emit("entity_grew", {"entity": e})
		if in_love(e):
			e.data.love_left = float(e.data.love_left) - delta
			if e.data.love_left <= 0.0:
				e.data.erase("love_left")
			elif randf() < 0.3:
				_server.play_effect("engine:heal", e.body.position + Vector3(0, e.def.height, 0), {"scale": 0.4})
		if float(e.data.get("breed_cooldown", 0.0)) > 0.0:
			e.data.breed_cooldown = float(e.data.breed_cooldown) - delta
			if e.data.breed_cooldown <= 0.0:
				e.data.erase("breed_cooldown")


func partner_for(e):
	var best = null
	var best_d := PARTNER_RANGE
	for other in _entities.in_radius(e.body.position, PARTNER_RANGE, e.type):
		if other == e or not other.is_alive() or not in_love(other) or is_baby(other):
			continue
		var d: float = other.body.position.distance_to(e.body.position)
		if d < best_d:
			best = other
			best_d = d
	return best


## Spawns a baby between two parents and starts their cooldowns.
func mate(a, b) -> Object:
	var c := config_of(a)
	for parent in [a, b]:
		parent.data.erase("love_left")
		parent.data.breed_cooldown = c.cooldown
	var at: Vector3 = (a.body.position + b.body.position) * 0.5
	var baby = _entities.spawn(a.type, at, {"data": {"baby": true, "grow_left": c.grow_seconds, "look": {"scale": c.baby_scale}}})
	if baby != null:
		_server.play_effect("engine:heal", at + Vector3(0, a.def.height, 0), {"scale": 1.2})
		var feeder = null
		for p in _server.players.values():
			if p.player_id == str(a.data.get("fed_by", "")):
				feeder = p
		_server.emit("entity_bred", {"parents": [a, b], "baby": baby, "player": feeder})
	return baby


func _breed_score(brain) -> float:
	var e = brain.entity
	return 0.6 if in_love(e) and not is_baby(e) and partner_for(e) != null else 0.0


func _breed_update(brain, _delta: float) -> void:
	var e = brain.entity
	var partner = partner_for(e)
	if partner == null:
		return
	brain.look_at(partner.body.position)
	if e.body.position.distance_to(partner.body.position) <= MATE_DISTANCE:
		if e.id < partner.id:  # only one of the pair makes the baby
			mate(e, partner)
		brain.stop()
	else:
		brain.move_to(partner.body.position, 1.0, MATE_DISTANCE * 0.8)


func _tempting_player(e):
	if not config_of(e).get("tempt", false):
		return null
	for p in _server.players.values():
		if not p.dead and p.state.position.distance_to(e.body.position) <= TEMPT_RANGE and is_food(e, p.inventory.selected_item()):
			return p
	return null


func _tempt_score(brain) -> float:
	return 0.5 if _tempting_player(brain.entity) != null else 0.0


func _tempt_update(brain, _delta: float) -> void:
	var p = _tempting_player(brain.entity)
	if p == null:
		return
	brain.look_at(p.get_eye_position())
	if brain.entity.body.position.distance_to(p.state.position) > 2.2:
		brain.move_to(p.state.position, 0.9, 2.0)
	else:
		brain.stop()
