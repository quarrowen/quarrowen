extends RefCounted
## Somewhere on the ground that does something to whoever stands in it, for a while: a pool of fire
## left after a boss lands, a cloud of gas from a cracked pipe, the warmth of a campfire, a healing
## circle in the middle of a village.
##
## **Called a field because the other two words are taken.** `plots` is ground with an owner and
## `claims` is ground kept awake; a third meaning for "area" in one engine is how somebody ends up
## reading the wrong file at midnight.
##
##     api.register_field("fire_pool", {"display_name": "Fire", "radius": 3.0, "seconds": 10.0,
##         "tick": {"seconds": 1.0, "damage": 2.0, "cause": "fire"},
##         "condition": {"condition": "vanilla:burning", "seconds": 4.0},
##         "effect": "engine:flame"})
##
##     api.place_field("fire_pool", position, {"seconds": 20.0, "owner": mob})
##
## **A field is always visible.** An invisible thing on the floor that hurts a child is not a hazard,
## it is a trick, so placing one starts a running effect and letting it go stops that effect. A mod may
## choose which effect; it may not choose none.
##
## **It does not tick per frame.** Each field keeps its own next-tick time and only then looks for who
## is standing in it, so a world with forty campfires costs forty radius searches a second between them
## rather than forty a frame.
##
## What stays the mod's: what fields exist, what puts them there, what they mean. The engine knows a
## circle, a clock, and what to do to whoever is inside.

const MobAttacks = preload("res://engine/server/ai/mob_attacks.gd")
const MobConfig = preload("res://engine/server/ai/mob_config.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")

## Enough for a busy fight and a village of campfires; few enough that nothing can carpet a world in
## them and make every tick a thousand radius searches.
const MAX_FIELDS := 256
const MAX_RADIUS := 32.0
## Who a field touches. Deliberately not "enemies": that would mean the engine learning about sides.
const AFFECTS := ["everyone", "players", "creatures"]

var server

## Name -> {name, display_name, radius, seconds, tick, condition, effect, affects, except_owner, owner}
var kinds := {}
## id -> {id, kind, realm, position, radius, expires, next_tick, level, owner, handle}
var fields := {}
var _next_id := 1


func _init(game_server) -> void:
	server = game_server


func register(field_name: String, def: Dictionary, owner := "engine") -> bool:
	if field_name.is_empty() or kinds.has(field_name):
		push_error("Invalid or duplicate field '%s'" % field_name)
		return false
	var tick := {}
	var source = def.get("tick")
	if source is Dictionary:
		tick = {"seconds": maxf(float(source.get("seconds", 1.0)), 0.1),
			"damage": maxf(float(source.get("damage", 0.0)), 0.0),
			"heal": maxf(float(source.get("heal", 0.0)), 0.0),
			"cause": String(source.get("cause", field_name.get_slice(":", 1)))}
	# The same reader the AI uses for an attack's condition, rather than a second one that would drift
	# from it: a field and a bite leave the same kind of thing behind.
	var condition := MobConfig.condition_of(def.get("condition"))
	if tick.is_empty() and condition.is_empty():
		push_error("Field '%s' does nothing to anybody standing in it" % field_name)
		return false
	var effect := String(def.get("effect", "engine:sparkle"))
	var affects := String(def.get("affects", "everyone"))
	kinds[field_name] = {"name": field_name, "owner": owner,
		"display_name": String(def.get("display_name", field_name.get_slice(":", 1).capitalize())),
		"radius": clampf(float(def.get("radius", 3.0)), 0.5, MAX_RADIUS),
		"seconds": maxf(float(def.get("seconds", 10.0)), 0.0),
		"tick": tick, "condition": condition, "effect": effect,
		"affects": affects if AFFECTS.has(affects) else "everyone",
		# Whoever left it behind usually should not stand in their own fire.
		"except_owner": bool(def.get("except_owner", true))}
	return true


## Puts one down. `options`: seconds, radius, level (multiplies damage, heal and the condition's
## level), owner (a player or a creature), realm.
func place(field_name: String, position: Vector3, options := {}) -> int:
	var kind: Dictionary = kinds.get(field_name, {})
	if kind.is_empty() or fields.size() >= MAX_FIELDS:
		return 0
	var seconds := maxf(float(options.get("seconds", kind.seconds)), 0.0)
	var radius := clampf(float(options.get("radius", kind.radius)), 0.5, MAX_RADIUS)
	var realm_id := String(options.get("realm", ""))
	var id := _next_id
	_next_id += 1
	var now: float = server._time
	fields[id] = {"id": id, "kind": field_name, "realm": realm_id, "position": position, "radius": radius,
		"expires": now + seconds if seconds > 0.0 else 0.0,
		"next_tick": now + float(kind.tick.get("seconds", 1.0)),
		"level": clampi(int(options.get("level", 1)), 1, 10),
		"owner": options.get("owner"),
		"handle": server.start_effect(String(kind.effect), position, {"scale": radius}, realm_id)}
	server.emit("field_placed", {"field": id, "kind": field_name, "position": position, "realm": realm_id})
	return id


func clear(id: int) -> bool:
	var field: Dictionary = fields.get(id, {})
	if field.is_empty():
		return false
	if int(field.handle) > 0:
		server.stop_effect(int(field.handle))
	fields.erase(id)
	server.emit("field_cleared", {"field": id, "kind": field.kind})
	return true


## Every field a point is inside, for a mod that wants to ask rather than be told.
func at(position: Vector3, realm_id := "") -> Array:
	var out := []
	for id: int in fields:
		var field: Dictionary = fields[id]
		if String(field.realm) == realm_id and position.distance_to(field.position) <= float(field.radius):
			out.append(info(id))
	return out


func info(id: int) -> Dictionary:
	var field: Dictionary = fields.get(id, {})
	if field.is_empty():
		return {}
	return {"id": id, "kind": String(field.kind), "realm": String(field.realm), "position": field.position,
		"radius": float(field.radius), "level": int(field.level),
		"seconds": maxf(float(field.expires) - server._time, 0.0) if float(field.expires) > 0.0 else -1.0}


func tick(_delta: float) -> void:
	if fields.is_empty():
		return
	var now: float = server._time
	for id: int in (fields.keys() as Array):
		var field: Dictionary = fields[id]
		if float(field.expires) > 0.0 and now >= float(field.expires):
			clear(id)
			continue
		if now < float(field.next_tick):
			continue
		var kind: Dictionary = kinds.get(String(field.kind), {})
		if kind.is_empty():
			clear(id)  # the mod that owned it is gone
			continue
		field.next_tick = now + float(kind.tick.get("seconds", 1.0))
		for target in _inside(field, kind):
			_apply(field, kind, target)


## Who is standing in it. Players are walked directly because there are never many; creatures go
## through the entity index, which is what it is for.
func _inside(field: Dictionary, kind: Dictionary) -> Array:
	var out := []
	var affects := String(kind.affects)
	var radius := float(field.radius)
	if affects != "creatures":
		for p in server.players.values():
			if String(p.realm_id) == String(field.realm) and p.state.position.distance_to(field.position) <= radius:
				out.append(p)
	if affects != "players":
		var realm = server.realms.get(String(field.realm), server.realm)
		for e in realm.entities.in_radius(field.position, radius, -1):
			if e.def.get("kind", "mob") == "mob":
				out.append(e)
	if bool(kind.except_owner) and field.owner != null:
		out = out.filter(func(t): return t != field.owner)
	return out


func _apply(field: Dictionary, kind: Dictionary, target) -> void:
	var level := int(field.level)
	var tick: Dictionary = kind.tick
	if not tick.is_empty():
		if float(tick.heal) > 0.0:
			target.heal(float(tick.heal) * level)
		if float(tick.damage) > 0.0:
			var amount := float(tick.damage) * level
			if target.get_script() == ServerPlayer:
				# Past the hurt cooldown, as conditions are: a fire that respected it would skip most
				# of its own ticks and standing in it would be nearly safe.
				server.damage_player(target, amount, String(tick.cause), null, Vector3.ZERO, true)
			else:
				target.hurt_timer = 0.0
				target.damage(amount, String(tick.cause))
	if not (kind.condition as Dictionary).is_empty():
		var condition: Dictionary = (kind.condition as Dictionary).duplicate()
		condition["level"] = int(condition.get("level", 1)) * level
		MobAttacks.apply_condition(server, target, condition)


## Fields are saved: a village campfire that went out because somebody restarted the server would be a
## puzzle rather than a feature. Written as how long is *left*, since server time restarts with it.
func to_saved() -> Array:
	var out := []
	for id: int in fields:
		var field: Dictionary = fields[id]
		out.append({"kind": field.kind, "realm": field.realm, "radius": field.radius, "level": field.level,
			"position": [field.position.x, field.position.y, field.position.z],
			"left": maxf(float(field.expires) - server._time, 0.0) if float(field.expires) > 0.0 else 0.0})
	return out


func load_saved(list) -> void:
	for id: int in (fields.keys() as Array):
		clear(id)
	if not (list is Array):
		return
	for entry in list:
		if not (entry is Dictionary) or not (entry.get("position") is Array) or (entry.position as Array).size() != 3:
			continue
		var at_pos := Vector3(float(entry.position[0]), float(entry.position[1]), float(entry.position[2]))
		# One that had run out is simply not put back, rather than arriving already expired.
		if float(entry.get("left", 0.0)) <= 0.0 and float(entry.get("left", 0.0)) != 0.0:
			continue
		place(String(entry.get("kind", "")), at_pos, {"seconds": float(entry.get("left", 0.0)),
			"radius": float(entry.get("radius", 3.0)), "level": int(entry.get("level", 1)),
			"realm": String(entry.get("realm", ""))})
