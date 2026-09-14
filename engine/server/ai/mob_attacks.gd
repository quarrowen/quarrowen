extends RefCounted
## Attack selection and execution for mob brains. Every attack telegraphs: a wind-up (the client
## plays a raise-and-glow animation) before it lands, so players can step out of range, block its
## line or interrupt it with a heavy hit.
##
##   melee    hits the target if it is still within reach and inside the arc in front
##   ranged   fires projectile(s), leading moving targets (better with intelligence)
##   leap     jumps at the target; damages everything near the landing spot
##   charge   dashes in a straight line; hits the first enemy in the way; stunned if it hits a wall
##   slam     area damage around the mob with knockback (more likely when several enemies are close)
##   summon   spawns allied mobs nearby (capped by max_summons)
##   custom   fires the mob_attack event; the mod decides what happens

const Pathfinder = preload("res://engine/server/ai/pathfinder.gd")

enum Event { HURT, DEATH, PICKUP, ATTACK, RESPAWN, WINDUP }


static func melee_reach(brain) -> float:
	var reach := 0.0
	for a in brain.config.attacks:
		if a.type in ["melee", "slam", "custom"]:
			reach = maxf(reach, a.range if a.type != "slam" else a.radius * 0.6)
	return reach if reach > 0.0 else 1.0


static func choose(brain, target, edge: float, seen: bool) -> Dictionary:
	var ai = brain.ai
	var e = brain.entity
	var fraction: float = brain.health_fraction()
	var best := {}
	var best_score := 0.0
	for a in brain.config.attacks:
		if brain.cooldowns.get(a.name, 0.0) > ai.time:
			continue
		if fraction > a.health_below or fraction <= a.health_above:
			continue
		var in_range: bool = edge >= a.min_range and edge <= a.range
		if a.type == "slam":
			in_range = edge <= a.radius
		if not in_range:
			continue
		if a.type in ["ranged", "leap", "charge"] and not seen:
			continue
		if a.type == "ranged" and not ai.pathfinder.line_of_sight(brain._eye(), ai.chest_of(target)):
			continue
		if a.type == "summon" and (a.entity_type < 0 or alive_summons(brain) >= a.max_summons):
			continue
		if a.type == "charge":
			var here := Pathfinder.node_of(e.body.position, brain.agent)
			var there := Pathfinder.node_of(ai.position_of(target), brain.agent)
			if not ai.pathfinder.walkable_line(here, Vector3i(there.x, here.y, there.z), brain.agent):
				continue
		var score: float = a.weight
		match a.type:
			"slam":
				score *= 1.0 + 0.8 * maxf(ai.enemies_near(brain, e.body.position, a.radius + e.def.width * 0.5).size() - 1, 0)
			"leap":
				if absf(ai.position_of(target).y - e.body.position.y) > 1.0 or edge > 3.0:
					score *= 1.6
			"charge":
				score *= 1.0 + clampf((edge - a.min_range) / 10.0, 0.0, 1.0)
			"summon":
				score *= 1.5 if alive_summons(brain) == 0 else 0.6
		# Smarter mobs pick the best option consistently; others are more erratic.
		score *= randf_range(1.0 - (1.0 - brain.config.intelligence) * 0.8, 1.0)
		if score > best_score:
			best_score = score
			best = a
	return best


static func begin(brain, a: Dictionary, target) -> void:
	var ai = brain.ai
	var e = brain.entity
	var to: Vector3 = ai.position_of(target) - e.body.position
	brain.attack = {"def": a, "target": target, "stage": "windup", "started": ai.time, "hit_at": ai.time + a.windup,
		"direction": Vector3(to.x, 0.0, to.z).normalized() if Vector2(to.x, to.z).length() > 0.01 else Vector3.FORWARD}
	brain.stop()
	ai.server.broadcast_entity_event(e, Event.WINDUP, brain.config.attacks.find(a))
	if not String(a.sound).is_empty():
		ai.server.play_sound_at(String(a.sound), e.body.position + Vector3(0, e.def.height * 0.5, 0))
	if not String(a.windup_effect).is_empty():
		ai.server.play_effect(String(a.windup_effect), e.body.position + Vector3(0, e.def.height * 0.5, 0), {"follow": e, "scale": maxf(e.def.width, 0.5)})


static func interrupt(brain) -> void:
	var a: Dictionary = brain.attack.def
	brain.cooldowns[a.name] = brain.ai.time + a.cooldown * 0.5
	brain.stun_until = brain.ai.time + 0.6
	brain.attack = {}


static func update(brain, _delta: float) -> void:
	if brain.attack.is_empty():
		return
	var ai = brain.ai
	var state: Dictionary = brain.attack
	var e = brain.entity
	var target = state.target
	match state.stage:
		"windup":
			if not ai.is_alive(target):
				_finish(brain)
				return
			# Keep turning toward the target during most of the wind-up, then commit.
			if ai.time < state.hit_at - state.def.windup * 0.35 and state.def.type != "charge":
				var to: Vector3 = ai.position_of(target) - e.body.position
				if Vector2(to.x, to.z).length() > 0.01:
					state.direction = Vector3(to.x, 0.0, to.z).normalized()
			e.yaw = atan2(-state.direction.x, -state.direction.z)
			if ai.time >= state.hit_at:
				_execute(brain)
		"charging":
			var speed: float = state.def.speed * brain.phase_speed
			e.body.velocity.x = state.direction.x * speed
			e.body.velocity.z = state.direction.z * speed
			e.wake()
			var box: AABB = e.aabb().grow(0.3)
			for enemy in ai.enemies_near(brain, e.body.position, e.def.width + 2.0):
				if state.hits.has(ai.key_of(enemy)) or not box.intersects(ai.aabb_of(enemy)):
					continue
				state.hits[ai.key_of(enemy)] = true
				_hit(brain, enemy, state.def.damage, state.direction, state.def.knockback * 1.6)
			if e.body.blocked and ai.time - state.started > 0.15:
				brain.stun_until = ai.time + 1.5  # ran into a wall
				_finish(brain)
			elif ai.time > state.ends or not state.hits.is_empty():
				_finish(brain)
		"leaping":
			if e.body.on_ground and ai.time - state.started > 0.2:
				var center: Vector3 = e.body.position
				for enemy in ai.enemies_near(brain, center, state.def.radius + e.def.width * 0.5):
					_hit(brain, enemy, state.def.damage, ai.position_of(enemy) - center, state.def.knockback)
				ai.make_noise(center, 12.0, e)
				_finish(brain)
			elif ai.time - state.started > 3.0:
				_finish(brain)


static func _execute(brain) -> void:
	var ai = brain.ai
	var e = brain.entity
	var state: Dictionary = brain.attack
	var a: Dictionary = state.def
	var target = state.target
	var ev: Dictionary = ai.server.emit("mob_attack", {"entity": e, "attack": {"name": a.name, "type": a.type, "damage": a.damage},
		"target": target, "cancelled": false})
	if ev.cancelled:
		_finish(brain)
		return
	ai.server.broadcast_entity_event(e, Event.ATTACK, brain.config.attacks.find(a))
	if not String(a.effect).is_empty():
		# Melee and ranged effects play at the mob's front, area attacks at its feet, scaled to its size.
		var front: Vector3 = e.body.position + Vector3(-sin(e.yaw), 0.0, -cos(e.yaw)) * (e.def.width * 0.5 + 0.4) + Vector3(0, e.def.height * 0.5, 0)
		var at_feet: bool = a.type in ["slam", "summon"]
		ai.server.play_effect(String(a.effect), e.body.position if at_feet else front,
			{"scale": maxf(float(a.radius) / 3.0, 0.5) if at_feet else maxf(e.def.width, 0.5), "direction": Vector3(-sin(e.yaw), 0.3, -cos(e.yaw))})
	match a.type:
		"melee":
			var edge: float = ai.edge_distance(e, target)
			var to: Vector3 = ai.position_of(target) - e.body.position
			var facing := Vector3(-sin(e.yaw), 0.0, -cos(e.yaw))
			var flat := Vector3(to.x, 0.0, to.z)
			var in_arc: bool = flat.length() < e.def.width or rad_to_deg(facing.angle_to(flat.normalized())) <= a.arc * 0.5
			if ai.is_alive(target) and edge <= a.range + 0.35 and in_arc:
				_hit(brain, target, a.damage, flat, a.knockback)
		"ranged":
			_fire(brain, a, target)
		"slam":
			var center: Vector3 = e.body.position
			for enemy in ai.enemies_near(brain, center, a.radius + e.def.width * 0.5):
				var offset: Vector3 = ai.position_of(enemy) - center
				var falloff := 1.0 - 0.5 * clampf(offset.length() / (a.radius + e.def.width * 0.5), 0.0, 1.0)
				_hit(brain, enemy, a.damage * falloff, offset, a.knockback)
			ai.make_noise(center, 16.0, e)
		"leap":
			var to: Vector3 = ai.position_of(target) - e.body.position
			var flight := clampf(Vector2(to.x, to.z).length() / 10.0, 0.45, 1.0)
			e.body.velocity = Vector3(to.x / flight, 0.5 * e.def.gravity * flight + to.y / flight, to.z / flight)
			e.wake()
			state.stage = "leaping"
			state.started = ai.time
			return
		"charge":
			state.stage = "charging"
			state.started = ai.time
			state.ends = ai.time + a.duration
			state.hits = {}
			return
		"summon":
			_summon(brain, a, target)
		"explode":
			# Blows up if the target is still close when the fuse runs out; otherwise it fizzles.
			if ai.is_alive(target) and ai.edge_distance(e, target) <= a.range + float(a.get("fuse_escape", 2.5)):
				var at: Vector3 = e.body.position + Vector3(0, e.def.height * 0.5, 0)
				_finish(brain)
				e.remove()
				ai.server.explosions.explode(at, float(a.get("power", 3.0)), {"source": e})
				return
	_finish(brain)


static func _finish(brain) -> void:
	var ai = brain.ai
	if brain.attack.is_empty():
		return
	var a: Dictionary = brain.attack.def
	brain.cooldowns[a.name] = ai.time + a.cooldown
	brain.next_attack_time = ai.time + brain.config.attack_interval * (1.4 - 0.8 * brain.config.aggression)
	brain.recover_until = ai.time + a.recovery
	brain.attack = {}


static func _hit(brain, victim, damage: float, direction: Vector3, knockback: float) -> void:
	var ai = brain.ai
	if victim.get("peer_id") != null:
		ai.server.damage_player(victim, damage, "mob", brain.entity, direction, false, knockback)
	else:
		ai.entities.damage(victim, damage, "mob", brain.entity, direction)


static func _fire(brain, a: Dictionary, target) -> void:
	var ai = brain.ai
	var e = brain.entity
	if a.projectile_type < 0:
		return
	var from: Vector3 = brain._eye()
	var aim: Vector3 = ai.chest_of(target)
	var speed: float = a.projectile_speed
	var gravity: float = ai.entities.registry.defs[a.projectile_type].gravity
	var flight := from.distance_to(aim) / maxf(speed, 0.1)
	aim += ai.velocity_of(target) * flight * brain.config.intelligence  # lead moving targets
	flight = from.distance_to(aim) / maxf(speed, 0.1)
	for i in a.count:
		var velocity := (aim - from) / maxf(flight, 0.01)
		velocity.y += 0.5 * gravity * flight  # arc over the distance
		var spread := deg_to_rad(a.spread * (1.6 - brain.config.intelligence) + 3.0 * i)
		velocity = velocity.rotated(Vector3.UP, randf_range(-spread, spread)).rotated(velocity.cross(Vector3.UP).normalized() if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT, randf_range(-spread, spread) * 0.5)
		var start: Vector3 = from + velocity.normalized() * (e.def.width * 0.5 + 0.35)
		ai.entities.spawn(a.projectile_type, start, {"velocity": velocity, "owner": e, "yaw": atan2(-velocity.x, -velocity.z)})


static func _summon(brain, a: Dictionary, target) -> void:
	var ai = brain.ai
	var e = brain.entity
	var def: Dictionary = ai.entities.registry.defs[a.entity_type]
	var agent := Pathfinder.agent_for(def.width, def.height, 1, 3, false)
	var spawned := 0
	for attempt in a.count * 4:
		if spawned >= a.count or alive_summons(brain) >= a.max_summons:
			break
		var angle := randf() * TAU
		var spot: Vector3i = ai.pathfinder.settle(e.body.position + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(e.def.width + 1.5, e.def.width + 4.0), agent)
		if spot.y == -9999:
			continue
		var minion = ai.entities.spawn(a.entity_type, Pathfinder.node_center(spot, agent), {"yaw": angle})
		if minion == null:
			continue
		spawned += 1
		brain.summons.append(minion.id)
		if minion.brain != null and ai.is_alive(target):
			minion.brain.set_target(target, "summoned")


static func alive_summons(brain) -> int:
	var alive: Array[int] = []
	for id in brain.summons:
		var minion = brain.ai.entities.entities.get(id)
		if minion != null and minion.is_alive():
			alive.append(id)
	brain.summons = alive
	return alive.size()
