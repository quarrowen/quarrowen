extends RefCounted
## The mind of one mob. Thinks a few times per second (perception, memory, threat, choosing a
## behavior) and steers every tick (path following, jumping, separation, dodging, attacks).
##
## Behaviors are chosen by utility score each think (the running one gets +0.1 so mobs don't dither):
##   idle 0.05, wander 0.1, investigate 0.4, search 0.45-0.65, engage 0.7-0.9, return_home 0.95-1.15,
##   flee 1.05, scripted 1.2; custom behaviors return their own score.
##   wander / idle     nothing better to do
##   investigate       walk to a noise or an ally's alert and look around
##   engage            chase and fight: surround (melee), keep distance and strafe (ranged), pick attacks
##   search            lost sight of the target: go where it was heading, look around, give up after `memory`
##   flee              low health (courage) or passive mobs that were hurt / approached; runs toward allies
##   return_home       beyond the leash (bosses reset)
##   scripted          a mod set a goal with Entity.set_goal
##   <custom>          behaviors mods register with register_mob_behavior
##
## Mods interact through the Entity methods (set_target, add_threat, tune, alert, perform_attack,
## set_home) and the public members below "Mod API".

const Pathfinder = preload("res://engine/server/ai/pathfinder.gd")
const MobConfig = preload("res://engine/server/ai/mob_config.gd")
const Attacks = preload("res://engine/server/ai/mob_attacks.gd")
const WorldTime = preload("res://engine/shared/world_time.gd")

const NO_NODE := Vector3i(0, -9999, 0)
const SLOW_THINK_DISTANCE := 64.0
## Mobs that have not been hurt for this long slowly recover health (fraction of max per second).
const RECOVER_AFTER := 8.0
const RECOVER_RATE := 0.015

var entity
var ai
var config: Dictionary
var agent: PackedInt32Array

# --- Mod API (read) ------------------------------------------------------------------------------
## Current enemy (a ServerPlayer or an entity) or null.
var target = null
## Name of the running behavior.
var behavior := "idle"
## Index of the boss phase reached (-1 = none).
var phase := -1
## Where the mob returns to when leashed (Vector3.INF = roams freely).
var home := Vector3.INF

# --- Internal state ------------------------------------------------------------------------------
var memory := {}  # target key -> {target, position, velocity, time, seen}
var threat := {}  # target key -> float
var stimulus := {}  # {position, time}
var attack := {}  # running attack (see mob_attacks.gd)
var cooldowns := {}  # attack name -> time it is ready again
var next_attack_time := 0.0
var recover_until := 0.0
var stun_until := 0.0
var summons: Array[int] = []
var flee_until := 0.0
var flee_from := Vector3.INF
var cornered_until := 0.0
var unreachable_since := -1.0
var last_hurt_time := -100.0
var behavior_since := 0.0
var behavior_state := {}
var scripted_goal := Vector3.INF
var phase_speed := 1.0
var custom_behaviors: Array = []

var move_goal := Vector3.INF
var move_speed := 1.0
var move_radius := 0.6
var path: Array[Vector3i] = []
var path_index := 0
var path_goal_node := NO_NODE
var path_status := 0
var path_time := -100.0
var direct := false
var look_target := Vector3.INF
var separation := Vector3.ZERO

var _think_timer := 0.0
var _last_think := 0.0
var _progress_pos := Vector3.INF
var _progress_time := 0.0
var _stuck_count := 0
var _smooth_timer := 0.0
var _dodge_ready := 0.0
var _dodged := {}
var _owns_config := false
var _strafe_sign := 1.0
var _strafe_until := 0.0
var _next_hop := 0.0
var _night_temperament := ""
var _light_check := 0.0
var _lit := false


func _init(mob, manager, resolved: Dictionary) -> void:
	entity = mob
	ai = manager
	config = resolved
	agent = Pathfinder.agent_for(entity.def.width, entity.def.height, config.step_up, config.max_drop, config.can_swim)
	_think_timer = randf() * config.think_interval
	_strafe_sign = 1.0 if randf() < 0.5 else -1.0


# --- Mod API -------------------------------------------------------------------------------------

## Changes this mob's AI settings (any MobConfig key, including attacks and phases).
func tune(values: Dictionary) -> void:
	var merged := config.duplicate(true)
	for key in values:
		if MobConfig.BASE.has(key):
			merged[key] = values[key]
	config = MobConfig.sanitize(merged, ai.resolve_entity)
	_owns_config = true
	agent = Pathfinder.agent_for(entity.def.width, entity.def.height, config.step_up, config.max_drop, config.can_swim)


func set_target(new_target, reason := "script") -> void:
	if new_target == null:
		target = null
		return
	var key: String = ai.key_of(new_target)
	threat[key] = maxf(float(threat.get(key, 0.0)), 5.0)
	_remember(new_target, true)
	_switch_target(new_target, reason)


func add_threat(source, amount: float) -> void:
	if source == null or not ai.is_alive(source):
		return
	var key: String = ai.key_of(source)
	threat[key] = float(threat.get(key, 0.0)) + amount
	if not memory.has(key):
		_remember(source, false)


## Makes the mob notice a position (walks there to investigate).
func alert(position: Vector3) -> void:
	stimulus = {"position": position, "time": ai.time}


func health_fraction() -> float:
	return entity.health / maxf(entity.def.health, 0.001) if entity.def.health > 0.0 else 1.0


func can_see_target() -> bool:
	return target != null and memory.get(ai.key_of(target), {}).get("seen", false)


func distance_to_target() -> float:
	return entity.body.position.distance_to(ai.position_of(target)) if target != null else INF


## Walks toward a position (pathfinding as needed). Custom behaviors call this each think.
func move_to(goal: Vector3, speed := 1.0, radius := 0.8) -> void:
	move_speed = speed
	move_radius = radius
	var pos: Vector3 = entity.body.position
	if Vector2(goal.x - pos.x, goal.z - pos.z).length() <= radius and absf(goal.y - pos.y) < 2.5:
		move_goal = goal
		path.clear()
		direct = true
		return
	move_goal = goal
	var here := Pathfinder.node_of(pos, agent)
	var goal_node := Pathfinder.node_of(goal, agent)
	var flat := Vector2(goal.x - pos.x, goal.z - pos.z).length()
	if absi(goal_node.y - here.y) == 0 and flat < 14.0 and entity.body.on_ground \
			and ai.pathfinder.walkable_line(here, goal_node, agent):
		direct = true
		path.clear()
		return
	direct = false
	var moved := Vector3(goal_node - path_goal_node).length() if path_goal_node != NO_NODE else INF
	# Repath when the goal moved noticeably relative to how far away it is (a target 30 blocks away
	# moving 2 blocks barely changes the route), or when the path is old.
	if path.is_empty() or moved > maxf(2.0, flat * 0.35) or ai.time - path_time > 5.0:
		ai.request_path(self, here, goal_node, maxf(radius - agent[0] * 0.5, 0.5))


func stop() -> void:
	move_goal = Vector3.INF
	path.clear()
	direct = false


func look_at(position: Vector3) -> void:
	look_target = position


func arrived() -> bool:
	return move_goal == Vector3.INF or entity.body.position.distance_to(move_goal) <= move_radius + 0.3


# --- Thinking ------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	if entity.dying:
		return
	_think_timer -= delta
	if _think_timer <= 0.0:
		var interval: float = config.think_interval
		if ai.nearest_player_distance(entity.body.position) > SLOW_THINK_DISTANCE:
			interval *= 4.0  # nobody around: think rarely
		_think_timer = interval * randf_range(0.85, 1.15)
		think()
	if not attack.is_empty():
		Attacks.update(self, delta)
	if config.agility > 0.0 and not ai.projectiles.is_empty():
		_dodge()
	var b = entity.body
	if move_goal == Vector3.INF and separation == Vector3.ZERO and look_target == Vector3.INF and attack.is_empty() \
			and b.on_ground and b.velocity.x == 0.0 and b.velocity.z == 0.0:
		return  # standing still with nothing to do
	_steer(delta)


func think() -> void:
	var now: float = ai.time
	_update_phase()
	if config.regen > 0.0:
		entity.heal(config.regen * config.think_interval)
	if now - last_hurt_time > RECOVER_AFTER and health_fraction() < 1.0:
		entity.heal(entity.def.health * RECOVER_RATE * config.think_interval)
	_check_light(now)
	_perceive(now)
	_choose_target(now)
	_choose_behavior(now)
	_run_behavior(now)
	separation = ai.separation_for(self)
	_last_think = now


func _perceive(now: float) -> void:
	var pos: Vector3 = entity.body.position
	var eye := _eye()
	var facing := Vector3(-sin(entity.yaw), 0.0, -cos(entity.yaw))
	for enemy in ai.enemies_near(self, pos, config.sight_range):
		var key: String = ai.key_of(enemy)
		var enemy_pos: Vector3 = ai.position_of(enemy)
		var to_enemy := enemy_pos - pos
		var distance := to_enemy.length()
		var close: bool = distance < 2.5 + entity.def.width
		var known: bool = memory.has(key) and now - memory[key].time < 3.0
		var flat := Vector3(to_enemy.x, 0.0, to_enemy.z)
		var in_view: bool = config.fov >= 359.0 or flat.length() < 0.01 \
			or rad_to_deg(facing.angle_to(flat.normalized())) <= config.fov * 0.5
		if (close or known or in_view) and ai.pathfinder.line_of_sight(eye, ai.eye_of(enemy)):
			_remember(enemy, true)
			if config.temperament == "passive" and config.skittish > 0.0 and distance < config.skittish:
				flee_until = now + 3.0
				flee_from = enemy_pos
		elif memory.has(key):
			memory[key].seen = false
	for noise in ai.noises:
		if noise.time <= _last_think or config.temperament == "none":
			continue
		var reach := minf(float(noise.radius), config.hearing_range)
		if pos.distance_to(noise.position) > reach:
			continue
		if noise.source != null and ai.is_enemy(self, noise.source):
			var key: String = ai.key_of(noise.source)
			if not memory.has(key) or not memory[key].seen:
				memory[key] = {"target": noise.source, "position": noise.position, "velocity": Vector3.ZERO, "time": now, "seen": false}
		if config.temperament == "passive":
			if noise.source != null and ai.is_enemy(self, noise.source) and noise.get("violent", false):
				flee_until = now + 2.0
				flee_from = noise.position
		elif target == null:
			stimulus = {"position": noise.position, "time": now}
	for key in memory.keys():
		var m: Dictionary = memory[key]
		if now - m.time > config.memory or not ai.is_alive(m.target):
			memory.erase(key)
			threat.erase(key)
		elif not m.seen:
			threat[key] = float(threat.get(key, 0.0)) * 0.97  # grudges fade while out of sight


func _remember(enemy, seen: bool) -> void:
	memory[ai.key_of(enemy)] = {"target": enemy, "position": ai.position_of(enemy), "velocity": ai.velocity_of(enemy), "time": ai.time, "seen": seen}


func _choose_target(now: float) -> void:
	if config.temperament in ["passive", "none"]:
		target = null
		return
	var pos: Vector3 = entity.body.position
	var best = null
	var best_score := 0.0
	var pursuit: float = config.sight_range * (0.45 + 0.55 * config.aggression)
	for key in memory:
		var m: Dictionary = memory[key]
		var grudge: float = threat.get(key, 0.0)
		if config.temperament == "neutral" and grudge <= 0.0:
			continue
		var distance: float = pos.distance_to(m.position)
		if m.target != target and grudge < 1.0 and (distance > pursuit or not m.seen):
			continue
		var score := grudge + 1.5 * (1.0 - clampf(distance / (config.sight_range * 1.5), 0.0, 1.0))
		if m.target == target:
			score += 1.0  # stick with the current target unless something is clearly better
		if config.intelligence > 0.6:
			score += (1.0 - ai.health_fraction_of(m.target)) * config.intelligence  # finish off the weak
		if unreachable_since > 0.0 and m.target == target and now - unreachable_since > 6.0:
			score -= 2.5  # give up on targets it cannot get to
		if score > best_score:
			best_score = score
			best = m.target
	if best != target:
		_switch_target(best, "sight")


func _switch_target(new_target, reason: String) -> void:
	if new_target != null:
		var ev: Dictionary = ai.server.emit("mob_target", {"entity": entity, "target": new_target, "previous": target, "reason": reason, "cancelled": false})
		if ev.cancelled:
			return
	var was_idle := target == null
	target = new_target
	unreachable_since = -1.0
	if new_target != null and was_idle:
		ai.alert_allies(self, new_target, ai.position_of(new_target))


## Daylight temperament and fear of light (checked every half second).
func _check_light(now: float) -> void:
	if config.day_temperament.is_empty() and config.fear_light <= 0:
		return
	if now - _light_check < 0.5:
		return
	_light_check = now
	var server = ai.server
	var cell := Vector3i(floori(entity.body.position.x), floori(entity.body.position.y + 0.5), floori(entity.body.position.z))
	var daylight: float = WorldTime.daylight(server.get_time_of_day())
	var light: int = server.block_ticks.light_at(cell, daylight)
	if not config.day_temperament.is_empty():
		if _night_temperament.is_empty():
			_night_temperament = config.temperament
		var wanted: String = config.day_temperament if daylight > 0.6 and light >= 12 else _night_temperament
		if wanted != config.temperament:
			tune({"temperament": wanted})
	if config.fear_light > 0:
		_lit = light >= config.fear_light or _torch_near(3.0 + config.fear_light * 0.4) != null


## A player within `radius` holding a light-giving block (a torch), or null.
func _torch_near(radius: float):
	for p in ai.server.players.values():
		if p.dead or p.state.position.distance_to(entity.body.position) > radius:
			continue
		var held: int = p.inventory.selected_item()
		if held > 0 and held < 65536 and ai.server.registry.is_valid(held) and int(ai.server.registry.defs[held].light) >= 10:
			return p
	return null


## Heads for the darkest nearby spot, away from any torch-bearer.
func _avoid_light(now: float) -> void:
	if now < behavior_state.get("until", 0.0) and not arrived():
		return
	var server = ai.server
	var daylight: float = WorldTime.daylight(server.get_time_of_day())
	var pos: Vector3 = entity.body.position
	var bearer = _torch_near(12.0)
	var best := pos
	var best_score := INF
	for i in 8:
		var dir := Vector3.RIGHT.rotated(Vector3.UP, i * TAU / 8.0)
		var spot := pos + dir * 7.0
		var score := float(server.block_ticks.light_at(Vector3i(floori(spot.x), floori(spot.y + 0.5), floori(spot.z)), daylight))
		if bearer != null:
			score -= spot.distance_to(bearer.state.position) * 0.8
		if score < best_score:
			best_score = score
			best = spot
	behavior_state.until = now + 1.5
	move_to(best, 1.3, 1.0)


func _choose_behavior(now: float) -> void:
	var scores := {"idle": 0.05}
	if _lit:
		scores.avoid_light = 1.1
	if config.wander_radius > 0.0 and config.wander_speed > 0.0:
		scores.wander = 0.1
	if not stimulus.is_empty() and now - stimulus.time < config.memory and target == null and config.temperament in ["hostile", "neutral"]:
		scores.investigate = 0.4
	if target != null:
		var m: Dictionary = memory.get(ai.key_of(target), {})
		if not m.is_empty():
			if m.seen or now - m.time < 1.0:
				scores.engage = 0.7 + 0.2 * config.aggression
			else:
				scores.search = 0.45 + 0.2 * (1.0 - (now - m.time) / config.memory)
	var fraction := health_fraction()
	var badly_hurt: bool = config.courage < 1.0 and fraction < (1.0 - config.courage) * 0.5 and now > cornered_until
	if config.temperament == "passive" and now < flee_until:
		scores.flee = 1.05
	elif badly_hurt and _threat_nearby():
		scores.flee = 1.05
	if badly_hurt:
		# Keep away until recovered instead of wandering back into the fight.
		scores.erase("engage")
		scores.erase("search")
		scores.erase("investigate")
	if home != Vector3.INF and config.leash > 0.0:
		var away: float = entity.body.position.distance_to(home)
		if away > config.leash or (behavior == "return_home" and away > 3.0):
			scores.return_home = 0.95 if away < config.leash * 1.5 else 1.15
	if scripted_goal != Vector3.INF:
		scores.scripted = 1.2
	for behavior_name in config.behaviors:
		var custom: Dictionary = ai.custom_behaviors.get(behavior_name, {})
		if not custom.is_empty() and custom.score.is_valid():
			scores[behavior_name] = float(custom.score.call(self))
	if scores.has(behavior):
		scores[behavior] += 0.1
	var best := "idle"
	for key in scores:
		if scores[key] > scores[best]:
			best = key
	if best != behavior:
		_end_behavior(behavior)
		behavior = best
		behavior_since = now
		behavior_state = {}


func _end_behavior(old: String) -> void:
	var custom: Dictionary = ai.custom_behaviors.get(old, {})
	if not custom.is_empty() and custom.get("stop", Callable()).is_valid():
		custom.stop.call(self)
	if old == "engage" or old == "flee":
		stop()


func _threat_nearby() -> bool:
	for key in memory:
		if ai.time - memory[key].time < 3.0 and memory[key].position.distance_to(entity.body.position) < config.sight_range:
			return true
	return false


func _run_behavior(now: float) -> void:
	match behavior:
		"idle":
			stop()
			look_target = Vector3.INF
		"wander":
			_wander(now)
		"investigate":
			_look_around_at(stimulus.position, 0.75, now, func(): stimulus = {})
		"search":
			var m: Dictionary = memory.get(ai.key_of(target), {})
			if m.is_empty():
				return
			var elapsed := clampf(now - m.time, 0.0, 2.0)
			var predicted: Vector3 = m.position + m.velocity * elapsed * config.intelligence
			_look_around_at(predicted, config.chase_speed * 0.8, now, func(): pass)
		"engage":
			_engage(now)
		"flee":
			_flee(now)
		"return_home":
			memory.clear()
			threat.clear()
			target = null
			if config.reset_on_leash:
				entity.heal(entity.def.health * 0.1)
			move_to(home, 1.0, 1.5)
		"avoid_light":
			_avoid_light(now)
		"scripted":
			move_to(scripted_goal, 1.0, 0.6)
			if arrived():
				scripted_goal = Vector3.INF
		_:
			var custom: Dictionary = ai.custom_behaviors.get(behavior, {})
			if not custom.is_empty() and custom.update.is_valid():
				custom.update.call(self, config.think_interval)


func _wander(now: float) -> void:
	look_target = Vector3.INF
	if now < behavior_state.get("until", 0.0) and not arrived():
		return
	if now < behavior_state.get("until", 0.0):
		return
	if randf() < 0.4:
		stop()
		behavior_state.until = now + randf_range(2.0, 5.0)
		return
	var center: Vector3 = home if home != Vector3.INF else entity.body.position
	var angle := randf() * TAU
	var distance := randf_range(3.0, maxf(config.wander_radius, 3.0))
	var spot: Vector3i = ai.pathfinder.settle(center + Vector3(cos(angle), 0.0, sin(angle)) * distance, agent)
	if spot != NO_NODE:
		move_to(Pathfinder.node_center(spot, agent), config.wander_speed, 0.8)
	behavior_state.until = now + randf_range(4.0, 8.0)


## Walks to `where`, then looks around for a few seconds before calling `done`.
func _look_around_at(where: Vector3, speed: float, now: float, done: Callable) -> void:
	if not behavior_state.has("arrived"):
		move_to(where, speed, 1.5)
		look_target = Vector3.INF
		if entity.body.position.distance_to(where) < 2.0 or (path_status == Pathfinder.Status.PARTIAL and arrived()):
			behavior_state.arrived = now
		return
	stop()
	if now - behavior_state.get("glance", 0.0) > 0.9:
		behavior_state.glance = now
		look_target = entity.body.position + Vector3(randf_range(-6, 6), 1.5, randf_range(-6, 6))
	if now - behavior_state.arrived > 3.0:
		done.call()


func _engage(now: float) -> void:
	var key: String = ai.key_of(target)
	var m: Dictionary = memory[key]
	var pos: Vector3 = entity.body.position
	var target_pos: Vector3 = ai.position_of(target) if m.seen else m.position
	look_target = ai.eye_of(target) if m.seen else m.position + Vector3(0, 1.5, 0)
	if not attack.is_empty():
		return
	var edge: float = ai.edge_distance(entity, target)
	if now >= next_attack_time and now >= recover_until:
		var chosen := Attacks.choose(self, target, edge, m.seen)
		if not chosen.is_empty():
			Attacks.begin(self, chosen, target)
			return
	var flat := Vector2(target_pos.x - pos.x, target_pos.z - pos.z)
	var distance := flat.length()
	var my_half: float = entity.def.width * 0.5
	var their_half: float = ai.half_width_of(target)
	if not config.preferred_range.is_empty():
		_engage_ranged(now, target_pos, distance, m)
		return
	var reach := Attacks.melee_reach(self)
	var goal := target_pos
	if config.intelligence >= 0.5 and m.seen:
		# Intercept: aim where the target is going, not where it is.
		var lead: float = clampf(distance / maxf(entity.def.speed * config.chase_speed, 0.1), 0.0, 0.8) * config.intelligence
		goal = target_pos + Vector3(m.velocity.x, 0.0, m.velocity.z) * lead
	var stop_at := my_half + their_half + reach * 0.7
	var slot: Vector3 = ai.surround_slot(self, target, stop_at) if config.intelligence >= 0.35 else Vector3.INF
	var cooling := now < next_attack_time
	if cooling and config.aggression < 0.75 and config.intelligence >= 0.5 and edge < reach + 1.5:
		# Recharging: circle at a short distance instead of hugging the target.
		var around := Vector3(pos.x - target_pos.x, 0.0, pos.z - target_pos.z).normalized()
		if around == Vector3.ZERO:
			around = Vector3.RIGHT
		var tangent := Vector3(-around.z, 0.0, around.x) * _strafe_sign
		if now > _strafe_until:
			_strafe_until = now + randf_range(1.0, 2.0)
			_strafe_sign = -_strafe_sign if randf() < 0.4 else _strafe_sign
		move_to(target_pos + (around * (stop_at + 1.2) + tangent * 1.5), 0.7, 0.4)
	elif slot != Vector3.INF and distance < 10.0:
		move_to(slot, config.chase_speed, 0.35)
	else:
		move_to(goal, config.chase_speed, stop_at)
	# Track whether the target can be reached at all (e.g. it pillared up out of reach).
	if path_status == Pathfinder.Status.PARTIAL and arrived() and edge > reach + 1.0:
		if unreachable_since < 0.0:
			unreachable_since = now
	elif edge <= reach + 1.0:
		unreachable_since = -1.0


func _engage_ranged(now: float, target_pos: Vector3, distance: float, m: Dictionary) -> void:
	var low: float = config.preferred_range[0]
	var high: float = config.preferred_range[1]
	var pos: Vector3 = entity.body.position
	var away := Vector3(pos.x - target_pos.x, 0.0, pos.z - target_pos.z)
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	if not m.seen or distance > high:
		move_to(target_pos, config.chase_speed, low)
		return
	if distance < low:
		# Kite: back off, preferring directions with room to stand.
		for angle in [0.0, 0.6, -0.6, 1.2, -1.2]:
			var dir := away.rotated(Vector3.UP, angle)
			var spot: Vector3i = ai.pathfinder.settle(pos + dir * (low - distance + 3.0), agent)
			if spot != NO_NODE and Vector3(Pathfinder.node_center(spot, agent)).distance_to(target_pos) > distance:
				move_to(Pathfinder.node_center(spot, agent), config.chase_speed, 0.6)
				return
		cornered_until = now + 2.0  # nowhere to go
	if now > _strafe_until:
		_strafe_until = now + randf_range(1.0, 2.5) * (1.6 - config.intelligence)
		if randf() < 0.5:
			_strafe_sign = -_strafe_sign
	var tangent := Vector3(-away.z, 0.0, away.x) * _strafe_sign
	var spot: Vector3i = ai.pathfinder.settle(pos + tangent * 2.5, agent)
	if spot != NO_NODE:
		move_to(Pathfinder.node_center(spot, agent), 0.8, 0.4)
	else:
		_strafe_sign = -_strafe_sign


func _flee(now: float) -> void:
	var pos: Vector3 = entity.body.position
	var danger := flee_from
	var nearest := INF
	for key in memory:
		var d: float = memory[key].position.distance_to(pos)
		if now - memory[key].time < 4.0 and d < nearest:
			nearest = d
			danger = memory[key].position
	look_target = Vector3.INF
	if danger == Vector3.INF:
		stop()
		return
	var away := Vector3(pos.x - danger.x, 0.0, pos.z - danger.z)
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
	var ally = ai.nearest_ally(self, 24.0)
	if ally != null and ally.entity.body.position.distance_to(danger) > pos.distance_to(danger):
		away = (away + (ally.entity.body.position - pos).normalized() * 0.7).normalized()  # run toward friends
	for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6]:
		var spot: Vector3i = ai.pathfinder.settle(pos + away.rotated(Vector3.UP, angle) * 9.0, agent)
		if spot != NO_NODE:
			move_to(Pathfinder.node_center(spot, agent), config.chase_speed * 1.15, 1.0)
			return
	if nearest < 2.0 + entity.def.width and config.temperament != "passive":
		cornered_until = now + 4.0  # trapped: fight back


func on_hurt(attacker, amount: float) -> void:
	var now: float = ai.time
	last_hurt_time = now
	if attacker != null and ai.is_alive(attacker) and ai.is_enemy(self, attacker):
		var key: String = ai.key_of(attacker)
		threat[key] = float(threat.get(key, 0.0)) + amount * 2.0 + 1.0
		_remember(attacker, true)
		if config.temperament == "passive":
			flee_until = now + 5.0
			flee_from = ai.position_of(attacker)
			ai.alert_allies(self, attacker, ai.position_of(attacker))
		elif target == null:
			ai.alert_allies(self, attacker, ai.position_of(attacker))
	# A heavy hit staggers a mob out of its wind-up (bosses shrug it off).
	if not attack.is_empty() and attack.stage == "windup" and config.boss.is_empty() and amount >= entity.def.health * 0.2:
		Attacks.interrupt(self)


func receive_alert(enemy, position: Vector3) -> void:
	var now: float = ai.time
	match config.temperament:
		"passive":
			flee_until = now + 4.0
			flee_from = position
		"hostile", "neutral":
			var key: String = ai.key_of(enemy)
			if not memory.has(key):
				memory[key] = {"target": enemy, "position": position, "velocity": Vector3.ZERO, "time": now, "seen": false}
			threat[key] = maxf(float(threat.get(key, 0.0)), 1.0)
			if target == null:
				stimulus = {"position": position, "time": now}


func _update_phase() -> void:
	var fraction := health_fraction()
	for i in config.phases.size():
		if i > phase and fraction <= config.phases[i].health_below:
			_enter_phase(i)


func _enter_phase(index: int) -> void:
	if not _owns_config:
		config = config.duplicate(true)
		_owns_config = true
	var p: Dictionary = config.phases[index]
	phase = index
	if p.has("attacks"):
		config.attacks = p.attacks.duplicate(true)
	if p.has("add_attacks"):
		config.attacks.append_array(p.add_attacks.duplicate(true))
	for key in ["aggression", "intelligence", "courage", "agility", "attack_interval", "chase_speed"]:
		if p.has(key):
			config[key] = float(p[key])
	phase_speed *= clampf(float(p.get("speed_multiplier", 1.0)), 0.1, 5.0)
	var ev: Dictionary = ai.server.emit("mob_phase", {"entity": entity, "phase": index, "message": String(p.get("message", ""))})
	if not String(ev.message).is_empty():
		ai.announce(self, String(ev.message))


# --- Movement ------------------------------------------------------------------------------------

func _steer(delta: float) -> void:
	var now: float = ai.time
	var b = entity.body
	var desired := Vector3.ZERO
	var speed: float = entity.def.speed * move_speed * phase_speed
	var busy: bool = now < stun_until or now < recover_until or (not attack.is_empty() and attack.stage == "windup")
	var controlled: bool = not attack.is_empty() and attack.stage in ["charging", "leaping"]
	if controlled:
		return  # the attack drives velocity
	if not busy and move_goal != Vector3.INF:
		var pos: Vector3 = b.position
		var point := move_goal
		if not direct and not path.is_empty():
			while path_index < path.size():
				var waypoint := Pathfinder.node_center(path[path_index], agent)
				if Vector2(waypoint.x - pos.x, waypoint.z - pos.z).length() < 0.35 + 0.2 * agent[0] and absf(waypoint.y - pos.y) < 1.1:
					path_index += 1
				else:
					break
			_smooth_timer -= delta
			if _smooth_timer <= 0.0 and path_index + 1 < path.size() and b.on_ground:
				_smooth_timer = 0.2
				if path[path_index + 1].y == Pathfinder.node_of(pos, agent).y \
						and ai.pathfinder.walkable_line(Pathfinder.node_of(pos, agent), path[path_index + 1], agent):
					path_index += 1  # string-pull: skip waypoints we can walk straight past
			if path_index < path.size():
				point = Pathfinder.node_center(path[path_index], agent)
		var to := point - pos
		var flat := Vector3(to.x, 0.0, to.z)
		var remaining := pos.distance_to(move_goal)
		if remaining > move_radius or (not direct and path_index < path.size()):
			if flat.length() > 0.05:
				desired = flat.normalized() * speed
			if b.on_ground and ((to.y > 0.4 and flat.length() < 1.2 + agent[0] * 0.5) or (b.blocked and flat.length() > 0.2)):
				var rise := clampf(ceilf(to.y) if to.y > 0.4 else 1.0, 1.0, maxf(float(config.step_up), 1.0))
				b.velocity.y = sqrt(2.0 * entity.def.gravity * (rise + 0.35))
			_check_progress(now, pos)
	if separation != Vector3.ZERO:
		desired += separation * maxf(speed, entity.def.speed * 0.6) * 0.6
	if config.climb and b.blocked and desired != Vector3.ZERO:
		b.velocity.y = maxf(b.velocity.y, 3.2)  # up the wall
	if not config.hop.is_empty() and not b.in_liquid:
		# Hoppers stand still on the ground and move only in jumps.
		if b.on_ground:
			if desired != Vector3.ZERO and now >= _next_hop:
				_next_hop = now + float(config.hop.interval) * randf_range(0.8, 1.2)
				b.velocity = Vector3(desired.x, sqrt(2.0 * entity.def.gravity * float(config.hop.height)), desired.z)
				entity.wake()
			elif b.velocity.y <= 0.0:
				b.velocity.x = 0.0
				b.velocity.z = 0.0
		if desired.length() > 0.1:
			entity.yaw = lerp_angle(entity.yaw, atan2(-desired.x, -desired.z), minf(1.0, 10.0 * delta))
		return
	var accel := 30.0 if b.on_ground else 8.0
	if b.in_liquid:
		accel = 12.0
		if desired != Vector3.ZERO:
			b.velocity.y = maxf(b.velocity.y, 2.0)
	var horizontal := Vector2(b.velocity.x, b.velocity.z).move_toward(Vector2(desired.x, desired.z), accel * delta)
	if desired == Vector3.ZERO and not b.on_ground:
		horizontal = Vector2(b.velocity.x, b.velocity.z)  # keep momentum (knockback) in the air
	b.velocity.x = horizontal.x
	b.velocity.z = horizontal.y
	if horizontal.length() > 0.01 or desired != Vector3.ZERO:
		entity.wake()
	var face := look_target
	if face == Vector3.INF and desired.length() > 0.1:
		face = b.position + desired
	if face != Vector3.INF:
		var d: Vector3 = face - b.position
		if Vector2(d.x, d.z).length() > 0.05:
			entity.yaw = lerp_angle(entity.yaw, atan2(-d.x, -d.z), minf(1.0, 10.0 * delta))


func _check_progress(now: float, pos: Vector3) -> void:
	if _progress_pos == Vector3.INF or now - _progress_time > 1.0:
		if _progress_pos != Vector3.INF and pos.distance_to(_progress_pos) < 0.3:
			_stuck_count += 1
			path.clear()
			path_time = -100.0
			path_goal_node = NO_NODE
			if _stuck_count >= 3:
				_stuck_count = 0
				entity.body.velocity += Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU) * 3.0  # wiggle free
		else:
			_stuck_count = 0
		_progress_pos = pos
		_progress_time = now


func on_path(result: Dictionary, goal_node: Vector3i) -> void:
	path = result.nodes
	path_status = result.status
	path_index = 1 if path.size() > 1 else 0
	path_goal_node = goal_node
	path_time = ai.time
	direct = false


## Sidesteps projectiles fired by enemies that are about to hit.
func _dodge() -> void:
	if config.agility <= 0.0 or ai.time < _dodge_ready or ai.projectiles.is_empty():
		return
	var b = entity.body
	var center: Vector3 = b.position + Vector3(0, entity.def.height * 0.5, 0)
	for projectile in ai.projectiles:
		if _dodged.has(projectile.id) or projectile.owner == null or not ai.is_enemy(self, projectile.owner):
			continue
		var velocity: Vector3 = projectile.body.velocity
		var speed_sq := velocity.length_squared()
		if speed_sq < 1.0:
			continue
		var rel: Vector3 = center - projectile.body.position
		var t := rel.dot(velocity) / speed_sq
		if t < 0.0 or t > 0.7:
			continue
		var closest: Vector3 = projectile.body.position + velocity * t
		var miss := Vector2(closest.x - center.x, closest.z - center.z).length()
		if miss > entity.def.width * 0.5 + 0.8 or absf(closest.y - center.y) > entity.def.height * 0.6:
			continue
		_dodged[projectile.id] = true
		if randf() > config.agility * (0.5 + 0.5 * config.intelligence):
			continue
		var side := Vector3(-velocity.z, 0.0, velocity.x).normalized()
		if side.dot(Vector3(center.x - closest.x, 0.0, center.z - closest.z)) < 0.0:
			side = -side
		b.velocity += side * 7.0 + (Vector3(0, 3.5, 0) if b.on_ground else Vector3.ZERO)
		entity.wake()
		_dodge_ready = ai.time + 1.0
		return
	if _dodged.size() > 64:
		_dodged.clear()


func _eye() -> Vector3:
	return entity.body.position + Vector3(0, entity.def.height * 0.85, 0)
