extends Node
## Offline tests of the engine mob AI in a flat arena (tests/mods/ai_arena):
##   godot --headless --path . res://tests/ai_test.tscn
## Runs with the native extension and, with VOXEL_NATIVE=0, with the GDScript pathfinder.

const GameServer = preload("res://engine/server/game_server.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")
const Pathfinder = preload("res://engine/server/ai/pathfinder.gd")

const DATA_DIR := "user://ai_test"
const DT := 1.0 / 60.0
const Y := 10  # standing height on the arena floor

var server
var stone := 0
var spikes := 0
var _failures := 0
var _next_peer := 100


func _ready() -> void:
	server = GameServer.new()
	add_child(server)
	# The guild mod (JavaScript) needs the native extension's JS runtime.
	var mods := ["ai_arena", "guild"] if ClassDB.class_exists(&"NativeJsRuntime") else ["ai_arena"]
	var err: Error = server.start({"mods": PackedStringArray(mods), "mod_dirs": PackedStringArray(["res://tests/mods"]),
		"world": "ai_%d" % Time.get_ticks_msec(), "data_dir": DATA_DIR, "seed": 1, "offline": true})
	if err != OK:
		_check(false, "arena server started (%s)" % error_string(err))
		return _finish()
	server.set_physics_process(false)
	server.set_gameplay({"mob_spawning": false})
	stone = server.registry.id_of("base:stone")
	spikes = server.registry.id_of("ai_arena:spikes")
	print("[ai] pathfinder: %s" % ("native" if server.world.native else "GDScript"))
	_pathfinding()
	_perception_and_chase()
	_windup_can_be_dodged()
	_surround()
	_archer_keeps_distance()
	_flee_and_threat()
	_ally_alert()
	_boss_phases()
	_giant()
	_custom_behavior_and_tuning()
	_dodging()
	if server.entities.registry.id_of("guild:goblin") > 0:
		_javascript_behavior()
	_finish()


# --- Pathfinding ---------------------------------------------------------------------------------

func _pathfinding() -> void:
	var pf: Pathfinder = server.entities.ai.pathfinder
	var normal := Pathfinder.agent_for(0.6, 1.8, 1, 3, false)
	var giant := Pathfinder.agent_for(1.2, 7.2, 2, 3, false)
	_check(giant[0] == 2 and giant[1] == 8, "giant agent occupies 2x2x8 cells")
	# A closed room with a one-block door in its south wall.
	var o := Vector3i(0, Y, 0)
	_load(o, 2)
	for i in range(-6, 7):
		for h in 3:
			for wall in [Vector3i(i, h, -6), Vector3i(i, h, 6), Vector3i(-6, h, i), Vector3i(6, h, i)]:
				_put(o + wall, stone)
	_put(o + Vector3i(0, 0, 6), 0)
	_put(o + Vector3i(0, 1, 6), 0)
	var out := pf.find_path(o, o + Vector3i(0, 0, 12), 0.5, normal)
	_check(out.status == Pathfinder.Status.FOUND and out.nodes.has(o + Vector3i(0, 0, 6)), "mob walks out through the door (%d nodes)" % out.nodes.size())
	var big := pf.find_path(o + Vector3i(-1, 0, -1), o + Vector3i(0, 0, 12), 0.5, giant, 1500)
	_check(big.status != Pathfinder.Status.FOUND, "giant does not fit through a one-block door")
	_check(not pf.line_of_sight(Vector3(o) + Vector3(0.5, 1.5, 0.5), Vector3(o) + Vector3(3.5, 1.5, 12.5)), "walls block line of sight")
	_check(pf.line_of_sight(Vector3(o) + Vector3(0.5, 1.5, 0.5), Vector3(o) + Vector3(0.5, 1.5, 5.5)), "open air does not")

	# Steps: a 1-block step up onto a 2-high platform.
	var s := Vector3i(40, Y, 0)
	_load(s, 1)
	for x in range(2, 8):
		for z in range(-2, 3):
			_put(s + Vector3i(x, 0, z), stone)
			_put(s + Vector3i(x, 1, z), stone)
	for z in range(-2, 3):
		_put(s + Vector3i(1, 0, z), stone)  # the step
	var up := pf.find_path(s, s + Vector3i(5, 2, 0), 0.5, normal)
	_check(up.status == Pathfinder.Status.FOUND and up.nodes.back().y == Y + 2, "climbs a staircase onto a platform")
	for z in range(-2, 3):
		_put(s + Vector3i(1, 0, z), 0)  # remove the step
	var no_step := pf.find_path(s + Vector3i(-2, 0, 0), s + Vector3i(5, 2, 0), 0.5, normal, 800)
	_check(no_step.status != Pathfinder.Status.FOUND, "cannot jump a 2-block wall with step_up 1")
	var tall_step := pf.find_path(s + Vector3i(-2, 0, 0), s + Vector3i(5, 2, 0), 0.5, giant, 800)
	_check(tall_step.status == Pathfinder.Status.FOUND, "a mob with step_up 2 can")

	# Cliff: jumping off a 6-high tower is too far for max_drop 3.
	var c := Vector3i(80, Y, 0)
	_load(c, 1)
	for h in 6:
		_put(c + Vector3i(0, h, 0), stone)
	var down := pf.find_path(c + Vector3i(0, 6, 0), c + Vector3i(4, 0, 0), 0.5, normal, 400)
	_check(down.status != Pathfinder.Status.FOUND, "will not jump off a 6-block cliff (max_drop 3)")
	var brave := pf.find_path(c + Vector3i(0, 6, 0), c + Vector3i(4, 0, 0), 0.5, Pathfinder.agent_for(0.6, 1.8, 1, 8, false), 400)
	_check(brave.status == Pathfinder.Status.FOUND, "a mob with max_drop 8 will")

	# Hazards: a corridor with spikes in the middle; the path detours around them.
	var h := Vector3i(120, Y, 0)
	_load(h, 1)
	for z in range(-1, 2):
		_put(h + Vector3i(4, 0, z), spikes)
	var around := pf.find_path(h, h + Vector3i(8, 0, 0), 0.5, normal)
	var stepped_on := false
	for n in around.nodes:
		if n.x == h.x + 4 and absi(n.z - h.z) <= 1:
			stepped_on = true
	_check(around.status == Pathfinder.Status.FOUND and not stepped_on, "path avoids hazard blocks")


# --- Behaviour -----------------------------------------------------------------------------------

func _perception_and_chase() -> void:
	var o := Vector3i(200, Y, 0)
	_load(o, 2)
	for x in range(-12, 13):
		for hgt in 3:
			if x != 9:
				_put(o + Vector3i(x, hgt, 5), stone)  # wall with a gap at x = 9
	var player := _player(Vector3(o) + Vector3(0.5, 0, 10.5))
	var grunt = _spawn("ai_arena:grunt", Vector3(o) + Vector3(0.5, 0, 0.5))
	_run(1.5)
	_check(grunt.get_target() == null, "does not see a player behind a wall")
	server.entities.ai.make_noise(player.state.position, 20.0, player)
	var health: float = player.health
	var hit := _run_until(func(): return player.health < health, 12.0)
	_check(hit, "heard the player, pathed through the gap and attacked (behavior %s)" % grunt.get_behavior())
	_remove(grunt, player)


func _windup_can_be_dodged() -> void:
	var o := Vector3i(300, Y, 0)
	_load(o, 2)
	var player := _player(Vector3(o) + Vector3(0.5, 0, 1.6))
	var grunt = _spawn("ai_arena:grunt", Vector3(o) + Vector3(0.5, 0, 0.5))
	grunt.set_target(player)
	_check(_run_until(func(): return not grunt.brain.attack.is_empty(), 3.0), "started an attack wind-up")
	var health: float = player.health
	player.state.position += Vector3(0, 0, 6)  # step away during the telegraph
	_run(0.6)
	_check(player.health == health, "stepping away during the wind-up dodges the hit")
	player.state.position = Vector3(o) + Vector3(0.5, 0, 1.6)
	_check(_run_until(func(): return player.health < health, 4.0), "standing still gets hit")
	_remove(grunt, player)


func _surround() -> void:
	var o := Vector3i(400, Y, 0)
	_load(o, 2)
	var player := _player(Vector3(o) + Vector3(0.5, 0, 0.5))
	player.max_health = 1000.0
	player.health = 1000.0
	var grunts := []
	for i in 4:
		var g = _spawn("ai_arena:grunt", Vector3(o) + Vector3(-1.5 + i, 0, -7.5))
		g.set_target(player)
		grunts.append(g)
	_run(6.0)
	var angles := []
	for g in grunts:
		var d: Vector3 = g.position - player.state.position
		angles.append(fposmod(atan2(d.z, d.x), TAU))
	angles.sort()
	var largest_gap := 0.0
	for i in angles.size():
		var next: float = angles[(i + 1) % angles.size()] + (TAU if i == angles.size() - 1 else 0.0)
		largest_gap = maxf(largest_gap, next - angles[i])
	_check(largest_gap < deg_to_rad(200), "4 attackers spread around the target (largest gap %d deg)" % roundi(rad_to_deg(largest_gap)))
	_check(player.health < 1000.0, "and hit it")
	for g in grunts:
		g.remove()
	server.players.erase(player.peer_id)


func _archer_keeps_distance() -> void:
	var o := Vector3i(500, Y, 0)
	_load(o, 2)
	var player := _player(Vector3(o) + Vector3(0.5, 0, 3.5))
	player.max_health = 1000.0
	player.health = 1000.0
	var archer = _spawn("ai_arena:archer", Vector3(o) + Vector3(0.5, 0, 0.5))
	archer.set_target(player)
	_run(3.0)
	var distance: float = archer.position.distance_to(player.state.position)
	_check(distance > 5.5, "archer backed away to shooting range (%.1f blocks)" % distance)
	_check(_run_until(func(): return player.health < 1000.0, 5.0), "archer shot the player")
	_remove(archer, player)


func _flee_and_threat() -> void:
	var o := Vector3i(600, Y, 0)
	_load(o, 2)
	var a := _player(Vector3(o) + Vector3(0.5, 0, 2.5))
	var b := _player(Vector3(o) + Vector3(6.5, 0, 0.5))
	var coward = _spawn("ai_arena:coward", Vector3(o) + Vector3(0.5, 0, 0.5))
	coward.set_target(a)
	_run(0.5)
	server.entities.damage(coward, 8.0, "attack", b)
	_run(0.6)
	_check(coward.get_target() == b, "switches target to whoever hurt it most")
	coward.hurt_timer = 0.0
	server.entities.damage(coward, 6.0, "attack", b)
	var start_distance: float = coward.position.distance_to(b.state.position)
	_run(2.5)
	_check(coward.get_behavior() in ["flee", "wander", "idle"] and coward.position.distance_to(b.state.position) > start_distance + 2.0,
		"flees at low health and stays away (%s, %.1f -> %.1f)" % [coward.get_behavior(), start_distance, coward.position.distance_to(b.state.position)])
	coward.remove()
	server.players.erase(a.peer_id)
	server.players.erase(b.peer_id)


func _ally_alert() -> void:
	var o := Vector3i(700, Y, 0)
	_load(o, 2)
	for x in range(-8, 9):
		for hgt in 3:
			_put(o + Vector3i(x, hgt, -3), stone)
	var player := _player(Vector3(o) + Vector3(0.5, 0, 6.5))
	player.max_health = 1000.0
	player.health = 1000.0
	var lookout = _spawn("ai_arena:grunt", Vector3(o) + Vector3(0.5, 0, 0.5))
	var hidden = _spawn("ai_arena:grunt", Vector3(o) + Vector3(0.5, 0, -6.5))  # behind the wall
	lookout.yaw = PI  # facing +Z, toward the player
	_run(1.0)
	_check(lookout.get_target() == player, "lookout spotted the player")
	_check(hidden.brain.memory.has("p%d" % player.peer_id), "ally behind the wall was alerted")
	_remove(lookout, player)
	hidden.remove()


func _boss_phases() -> void:
	var o := Vector3i(800, Y, 0)
	_load(o, 2)
	var near := _player(Vector3(o) + Vector3(2.5, 0, 0.5))
	var far := _player(Vector3(o) + Vector3(12.5, 0, 0.5))
	var boss = _spawn("ai_arena:boss", Vector3(o) + Vector3(0.5, 0, 0.5))
	var phases := []
	server.add_handler("mob_phase", func(ev): phases.append(ev.phase), 0)
	boss.set_target(near)
	_check(_run_until(func(): return near.health < 20.0, 4.0), "boss slam hit the adjacent player")
	_check(far.health == 20.0, "players outside the slam radius are unharmed")
	boss.hurt_timer = 0.0
	boss.damage(60.0, near, "attack")
	_run(1.0)
	_check(phases == [0], "boss entered phase two below half health (%s)" % str(phases))
	near.health = 20.0
	var summoned := _run_until(func(): return server.entities.in_radius(boss.position, 8.0, server.entities.registry.id_of("ai_arena:grunt")).size() > 0, 6.0)
	_check(summoned, "phase two unlocked summoning")
	for e in server.entities.in_radius(boss.position, 16.0):
		e.remove()
	server.players.erase(near.peer_id)
	server.players.erase(far.peer_id)


func _giant() -> void:
	var o := Vector3i(900, Y, 0)
	_load(o, 2)
	var player := _player(Vector3(o) + Vector3(0.5, 0, 14.5))
	player.max_health = 1000.0
	player.health = 1000.0
	for x in range(-6, 7):
		for hgt in 2:
			if absi(x) > 1:
				_put(o + Vector3i(x, hgt, 7), stone)  # wall with a 3-wide opening
	var giant = _spawn("ai_arena:giant", Vector3(o) + Vector3(1.0, 0, 1.0))
	giant.set_target(player)
	var arrived := _run_until(func(): return giant.position.distance_to(player.state.position) < 5.0, 14.0)
	_check(arrived, "giant (2 wide, 8 tall) navigated through a wide opening (%.1f blocks away)" % giant.position.distance_to(player.state.position))
	_check(_run_until(func(): return player.health < 1000.0, 4.0), "giant stomped the player")
	_remove(giant, player)


func _custom_behavior_and_tuning() -> void:
	var o := Vector3i(1000, Y, 0)
	_load(o, 2)
	var player := _player(Vector3(o) + Vector3(-9.5, 0, 0.5))  # mobs with nobody nearby despawn
	var guard = _spawn("ai_arena:guard", Vector3(o) + Vector3(0.5, 0, 0.5))
	guard.data["patrol_to"] = Vector3(o) + Vector3(6.5, 0, 6.5)
	_run(0.6)
	_check(guard.get_behavior() == "ai_arena:patrol", "custom behavior won the utility vote (%s)" % guard.get_behavior())
	_check(_run_until(func(): return not guard.data.has("patrol_to"), 6.0), "custom behavior walked to its patrol point")
	player.state.position = guard.position + Vector3(1.5, 0, 0)
	_run(1.0)
	_check(guard.get_target() == null, "neutral mob ignores players until provoked")
	server.entities.damage(guard, 2.0, "attack", player)
	_run(0.6)
	_check(guard.get_target() == player, "provoked neutral mob fights back")
	var grunt = _spawn("ai_arena:grunt", Vector3(o) + Vector3(3.5, 0, 0.5))
	grunt.tune({"temperament": "passive"})
	grunt.yaw = PI * 0.5
	_run(1.0)
	_check(grunt.get_target() == null, "tune() changes a single mob's temperament")
	guard.remove()
	grunt.remove()
	server.players.erase(player.peer_id)


func _dodging() -> void:
	var o := Vector3i(1100, Y, 0)
	_load(o, 2)
	var player := _player(Vector3(o) + Vector3(0.5, 0, 10.5))
	var archer = _spawn("ai_arena:archer", Vector3(o) + Vector3(0.5, 0, 0.5))
	archer.tune({"agility": 1.0, "intelligence": 1.0, "attacks": []})
	_run(0.5)
	var before: Vector3 = archer.position
	var bolt: int = server.entities.registry.id_of("ai_arena:bolt")
	server.entities.spawn(bolt, player.get_eye_position() - Vector3(0, 0.6, 0), {"velocity": (archer.position + Vector3(0, 1, 0) - player.get_eye_position()).normalized() * 20.0, "owner": player})
	_run(0.8)
	var sidestep := Vector2(archer.position.x - before.x, archer.position.z - before.z).length()
	_check(sidestep > 0.5 and archer.health == archer.max_health, "agile mob sidestepped an incoming projectile (moved %.1f)" % sidestep)
	_remove(archer, player)


func _javascript_behavior() -> void:
	var o := Vector3i(1200, Y, 0)
	_load(o, 2)
	var player := _player(Vector3(o) + Vector3(-30.5, 0, 0.5))  # far enough not to scare it
	var goblin = _spawn("guild:goblin", Vector3(o) + Vector3(0.5, 0, 0.5))
	var coin: int = server.items.id_of("guild:gold_coin")
	var dropped = server.entities.drop_item(coin, 1, Vector3(o) + Vector3(6.5, 0.5, 4.5), Vector3.ZERO)
	var grabbed := _run_until(func(): return dropped.removed, 8.0)
	_check(grabbed and goblin.data.get("guild", {}).get("loot", 0) == 1, "JavaScript mob behavior sent the goblin to grab a coin (%s)" % goblin.get_behavior())
	player.state.position = goblin.position + Vector3(3, 0, 0)
	var start: float = goblin.position.distance_to(player.state.position)
	_run(2.0)
	_check(goblin.position.distance_to(player.state.position) > start + 2.0, "skittish goblin runs from a nearby player")
	_remove(goblin, player)


# --- Helpers -------------------------------------------------------------------------------------

func _load(center: Vector3i, radius: int) -> void:
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			server._ensure_chunk(Vector2i(floori(center.x / 16.0) + x, floori(center.z / 16.0) + z))


func _put(pos: Vector3i, id: int) -> void:
	server.set_block_authoritative(pos, id)


func _player(pos: Vector3) -> ServerPlayer:
	_next_peer += 1
	var p := ServerPlayer.new(server, _next_peer, "P%d" % _next_peer)
	p.player_id = str(_next_peer)
	p.state.position = pos
	p.state.on_ground = true
	server.players[_next_peer] = p
	return p


func _spawn(type_name: String, pos: Vector3):
	return server.entities.spawn(server.entities.registry.id_of(type_name), pos, {"yaw": 0.0})


func _remove(mob, player) -> void:
	mob.remove()
	server.players.erase(player.peer_id)


func _run(seconds: float) -> void:
	for i in roundi(seconds / DT):
		_step()


func _run_until(condition: Callable, timeout: float) -> bool:
	for i in roundi(timeout / DT):
		_step()
		if condition.call():
			return true
	return false


func _step() -> void:
	server._time += DT
	server.tick += 1
	server.entities.tick(DT)
	for p in server.players.values():
		p.hurt_timer = maxf(p.hurt_timer - DT, 0.0)


func _check(ok: bool, what: String) -> void:
	print("[ai] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _finish() -> void:
	if server:
		server.queue_free()
	await get_tree().process_frame
	_remove_tree(ProjectSettings.globalize_path(DATA_DIR))
	print("[ai] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
