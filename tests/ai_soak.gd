extends Node
## Mob AI soak on generated terrain: vanilla mobs around survival players at several sites (hills, forest,
## water, caves) for a few simulated minutes, measuring what players notice when AI goes wrong:
##   stuck       seconds a mob wanted to move but went nowhere
##   hops        jumps that got it nowhere (hopping against a wall)
##   flips       behavior changes per minute (dithering)
##   water       share of time spent in liquid (for mobs that cannot swim)
##   reach       hostile mobs that got within striking distance of their player, and how long it took
##   blind hits  hits landed without a line of sight (through walls, floors, doors)
##   godot --headless --path . res://tests/ai_soak.tscn -- --seconds=180 --sites=6 --seed=42
## With --check, exits 1 when a threshold in LIMITS is broken (the test suite runs a short version).

const GameServer = preload("res://engine/server/game_server.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")

var _data_dir := "user://ai_soak_%d" % OS.get_process_id()
const DT := 1.0 / 60.0
const HOSTILES := {"vanilla:zombie": 3, "vanilla:skeleton": 1, "vanilla:spider": 1, "vanilla:night_stalker": 1, "vanilla:slime": 1, "vanilla:boomshroom": 1}
const ANIMALS := {"vanilla:pig": 2, "vanilla:cow": 1, "vanilla:sheep": 1, "vanilla:chicken": 1, "vanilla:wolf": 1}
## Per mob type, over the whole run.
const LIMITS := {"stuck_share": 0.15, "futile_hops_per_min": 6.0, "flips_per_min": 20.0, "blind_hits": 0, "reach_share": 0.6}

var server
var _args := {"seconds": 180.0, "sites": 6, "seed": 42, "check": false, "move_every": 20.0}
var _stats := {}  # type name -> {...}
var _tracks := {}  # entity id -> {...}
var _next_peer := 100
var _failures := 0
var _projectiles := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"seconds": _args.seconds = float(kv[1])
			"sites": _args.sites = int(kv[1])
			"seed": _args.seed = int(kv[1])
			"check": _args.check = true
			"move-every": _args.move_every = float(kv[1])
	seed(int(_args.seed))
	server = GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(["vanilla"]), "world": "soak_%d" % Time.get_ticks_msec(), "data_dir": _data_dir,
		"seed": int(_args.seed), "offline": true})
	if err != OK:
		print("[soak] server failed to start: %s" % error_string(err))
		get_tree().quit(1)
		return
	server.set_physics_process(false)
	server.set_gameplay({"mob_spawning": false})
	server.set_world_time(0.0, 0.0)  # midnight: hostile mobs hunt
	server.add_handler("player_damage", _on_player_damage, 0)
	server.add_handler("projectile_hit", func(ev):
		var k := "shot:" + str(ev.hit)
		_projectiles[k] = int(_projectiles.get(k, 0)) + 1, 0)
	server.add_handler("mob_attack", func(ev):
		if _tracks.has(ev.entity.id):
			_stat(_tracks[ev.entity.id].type).attacks += 1, 0)
	print("[soak] %s pathfinder, seed %d, %d sites, %.0f s" % ["native" if server.world.native else "GDScript", _args.seed, _args.sites, _args.seconds])
	var sites := _pick_sites()
	var players := []
	for site: Vector3 in sites:
		var p := _player(site)
		players.append(p)
		_populate(p)
	var ticks := roundi(float(_args.seconds) / DT)
	var started := Time.get_ticks_msec()
	for i in ticks:
		if i > 0 and i % roundi(float(_args.move_every) / DT) == 0:
			for p in players:
				_relocate(p)  # players move on: mobs must re-plan
		_step()
		_observe()
	_report(Time.get_ticks_msec() - started)
	server.queue_free()
	await get_tree().process_frame
	_remove_tree(ProjectSettings.globalize_path(_data_dir))
	get_tree().quit(1 if _args.check and _failures > 0 else 0)


# --- Setup ---------------------------------------------------------------------------------------

func _pick_sites() -> Array:
	var out := []
	var angle := 0.0
	var radius := 0.0
	while out.size() < int(_args.sites):
		var at := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		angle += 2.4
		radius += 70.0
		var spot := _surface(at.x, at.z, 3)
		if spot != Vector3.INF:
			out.append(spot)
	return out


## The standing spot on the ground at (x, z), loading chunks around it; Vector3.INF over deep water.
func _surface(x: float, z: float, load_radius := 1) -> Vector3:
	var coord := Vector2i(floori(x / 16.0), floori(z / 16.0))
	for dx in range(-load_radius, load_radius + 1):
		for dz in range(-load_radius, load_radius + 1):
			server._ensure_chunk(coord + Vector2i(dx, dz))
	var liquid: PackedByteArray = server.registry.liquid_lut
	var solid: PackedByteArray = server.registry.solid_lut
	for y in range(120, 1, -1):
		var below: int = server.world.get_block(floori(x), y - 1, floori(z))
		if liquid[below] == 1:
			return Vector3.INF
		if solid[below] == 1:
			var ground_name: String = server.registry.defs[below].name
			if ground_name.contains("leaves") or ground_name.contains("log"):
				return Vector3.INF  # tree tops are not where players stand
			return Vector3(floori(x) + 0.5, y, floori(z) + 0.5)
	return Vector3.INF


func _player(pos: Vector3) -> ServerPlayer:
	_next_peer += 1
	var p := ServerPlayer.new(server, _next_peer, "Soak%d" % _next_peer)
	p.player_id = str(_next_peer)
	p.state.position = pos
	p.state.on_ground = true
	p.set_max_health(100000.0)
	p.health = 100000.0
	server.players[_next_peer] = p
	return p


func _relocate(p: ServerPlayer) -> void:
	for attempt in 8:
		var angle := randf() * TAU
		var spot := _surface(p.state.position.x + cos(angle) * 12.0, p.state.position.z + sin(angle) * 12.0)
		if spot != Vector3.INF and absf(spot.y - p.state.position.y) < 8.0:
			p.state.position = spot
			return


func _populate(p: ServerPlayer) -> void:
	for group in [HOSTILES, ANIMALS]:
		for type_name: String in group:
			var type_id: int = server.entities.registry.id_of(type_name)
			if type_id < 0:
				continue
			for n in int(group[type_name]):
				for attempt in 12:
					var angle := randf() * TAU
					var distance := randf_range(10.0, 22.0)
					var spot := _surface(p.state.position.x + cos(angle) * distance, p.state.position.z + sin(angle) * distance)
					if spot == Vector3.INF:
						continue
					var e = server.entities.spawn(type_id, spot, {"yaw": randf() * TAU})
					if e == null:
						continue
					e.data["no_despawn"] = true
					_tracks[e.id] = {"entity": e, "player": p, "type": type_name, "hostile": HOSTILES.has(type_name), "last_pos": e.position,
						"window_pos": e.position, "window_time": 0.0, "wanted": 0.0, "was_ground": true, "hop_checks": [],
						"behavior": e.get_behavior()}
					break


# --- Simulation ----------------------------------------------------------------------------------

func _step() -> void:
	server._time += DT
	server.tick += 1
	server.entities.tick(DT)
	for p in server.players.values():
		p.hurt_timer = maxf(p.hurt_timer - DT, 0.0)
		p.health = p.max_health
		p.state.velocity = Vector3.ZERO  # scripted players do not simulate; knockback must not linger


func _observe() -> void:
	var now: float = server._time
	for id: int in _tracks.keys():
		var t: Dictionary = _tracks[id]
		var e = t.entity
		var s := _stat(t.type)
		if e.removed or e.dying:
			if not t.has("gone"):
				t.gone = true
				s.gone += 1
			continue
		var b = e.body
		var brain = e.brain
		s.samples += 1
		if b.in_liquid:
			s.liquid += 1
		# Wanting to move: a goal, not attacking, stunned or recovering.
		var busy: bool = not brain.attack.is_empty() or now < brain.stun_until or now < brain.recover_until
		var wants: bool = brain.move_goal != Vector3.INF and not busy and not brain.arrived()
		if wants:
			s.wanting += 1
			t.wanted += DT
		t.window_time += DT
		if t.window_time >= 2.0:
			var moved := Vector2(b.position.x - t.window_pos.x, b.position.z - t.window_pos.z).length()
			if t.wanted > 1.6 and moved < 0.4:
				s.stuck += t.window_time
				if not s.stuck_examples.size() >= 3:
					s.stuck_examples.append("%s at %s (%s, goal %s)" % [t.type.trim_prefix("vanilla:"), _v(b.position), brain.behavior, _v(brain.move_goal)])
			t.window_pos = b.position
			t.window_time = 0.0
			t.wanted = 0.0
		# Jumps that made no progress a second later.
		if t.was_ground and not b.on_ground and b.velocity.y > 1.0 and brain.config.hop.is_empty():
			t.hop_checks.append([now + 1.0, b.position])
			s.hops += 1
		t.was_ground = b.on_ground
		while not t.hop_checks.is_empty() and t.hop_checks[0][0] <= now:
			var check: Array = t.hop_checks.pop_front()
			if Vector2(b.position.x - check[1].x, b.position.z - check[1].z).length() < 0.5:
				s.futile_hops += 1
		if brain.behavior != t.behavior:
			s.flips += 1
			t.behavior = brain.behavior
		# Chases: the mob targets its player within 16 blocks. One succeeds when it gets within striking distance,
		# fails after 20 s without; a player relocating ends it without a verdict.
		var edge: float = server.entities.ai.edge_distance(e, t.player)
		if t.hostile:
			if t.get("caught_at", Vector3.INF) != t.player.state.position:
				t.erase("caught_at")
			if not t.has("chase_from") and not t.has("caught_at") and brain.target == t.player and edge < 16.0:
				t.chase_from = now
				t.chase_player_pos = t.player.state.position
			if t.has("chase_from"):
				if edge < (1.5 if brain.config.preferred_range.is_empty() else brain.config.preferred_range[1]):
					s.reached += 1
					s.reach_time += now - t.chase_from
					t.erase("chase_from")
					t.caught_at = t.player.state.position
				elif t.player.state.position != t.chase_player_pos or brain.target != t.player:
					t.erase("chase_from")
				elif now - t.chase_from > 20.0:
					s.chase_failures += 1
					if s.chase_examples.size() < 3:
						s.chase_examples.append("%s at %s, player at %s, %s, path %s, %d nodes" % [t.type.trim_prefix("vanilla:"), _v(b.position), _v(t.player.state.position),
							brain.behavior, ["none", "found", "partial"][brain.path_status], brain.path.size()])
					t.erase("chase_from")
		s.max_drop = maxf(s.max_drop, t.last_pos.y - b.position.y)
		t.last_pos = b.position


func _on_player_damage(ev: Dictionary) -> void:
	var mob = ev.attacker
	if mob == null or mob.get("brain") == null or not _tracks.has(mob.id):
		return
	var s := _stat(_tracks[mob.id].type)
	s.hits += 1
	var pf = server.entities.ai.pathfinder
	var p = ev.player
	var eye: Vector3 = mob.body.position + Vector3(0, mob.def.height * 0.85, 0)
	var sees: bool = pf.line_of_sight(eye, p.get_eye_position()) or pf.line_of_sight(eye, p.state.position + Vector3(0, 0.9, 0)) \
		or pf.line_of_sight(mob.body.position + Vector3(0, mob.def.height * 0.4, 0), p.state.position + Vector3(0, 0.4, 0))
	if not sees and ev.cause == "mob":
		s.blind_hits += 1
		if s.blind_examples.size() < 3:
			s.blind_examples.append("%s at %s hit player at %s" % [mob.def.name, _v(mob.body.position), _v(p.state.position)])


func _stat(type_name: String) -> Dictionary:
	if not _stats.has(type_name):
		_stats[type_name] = {"count": 0, "samples": 0, "wanting": 0, "stuck": 0.0, "hops": 0, "futile_hops": 0, "flips": 0, "liquid": 0,
			"reached": 0, "reach_time": 0.0, "chase_failures": 0, "chase_examples": [], "hits": 0, "attacks": 0, "blind_hits": 0, "gone": 0, "max_drop": 0.0, "stuck_examples": [], "blind_examples": []}
	return _stats[type_name]


# --- Report --------------------------------------------------------------------------------------

func _report(wall_msec: int) -> void:
	for t in _tracks.values():
		_stat(t.type).count += 1
	print("[soak] simulated %.0f s in %.1f s" % [_args.seconds, wall_msec / 1000.0])
	print("[soak] %-14s %5s %7s %9s %8s %6s %9s %7s %6s %6s" % ["type", "mobs", "stuck%", "hops/min", "flips/m", "water%", "reached", "attacks", "hits", "blind"])
	var minutes := float(_args.seconds) / 60.0
	for type_name: String in _stats:
		var s: Dictionary = _stats[type_name]
		var mob_minutes := maxf(s.samples * DT / 60.0, 0.001)
		var stuck_share: float = s.stuck / maxf(s.samples * DT, 0.001)
		var hostile := HOSTILES.has(type_name)
		var reached := "%d/%d %.0fs" % [s.reached, s.reached + s.chase_failures, s.reach_time / maxf(s.reached, 1)] if hostile else "-"
		print("[soak] %-14s %5d %6.1f%% %9.1f %8.1f %5.1f%% %9s %7d %6d %6d" % [type_name.trim_prefix("vanilla:"), s.count, stuck_share * 100.0,
			s.futile_hops / mob_minutes, s.flips / mob_minutes, 100.0 * s.liquid / maxf(s.samples, 1), reached, s.attacks, s.hits, s.blind_hits])
		for line in s.chase_examples:
			print("[soak]     chase failed: %s" % line)
		if type_name == "vanilla:skeleton":
			_limit(s.hits > 0, "skeletons never hit a player (%d shots)" % s.attacks)
		for line in s.stuck_examples:
			print("[soak]     stuck: %s" % line)
		for line in s.blind_examples:
			print("[soak]     blind hit: %s" % line)
		_limit(stuck_share <= LIMITS.stuck_share, "%s stuck %.0f%% of the time" % [type_name, stuck_share * 100.0])
		_limit(s.futile_hops / mob_minutes <= LIMITS.futile_hops_per_min, "%s hops in place %.1f times a minute" % [type_name, s.futile_hops / mob_minutes])
		_limit(s.flips / mob_minutes <= LIMITS.flips_per_min, "%s changes its mind %.1f times a minute" % [type_name, s.flips / mob_minutes])
		_limit(s.blind_hits <= LIMITS.blind_hits, "%s hit players it could not see %d times" % [type_name, s.blind_hits])
		if hostile and s.reached + s.chase_failures > 0:
			_limit(float(s.reached) / (s.reached + s.chase_failures) >= LIMITS.reach_share, "%s caught its player in %d of %d chases" % [type_name, s.reached, s.reached + s.chase_failures])
	print("[soak] projectile hits: %s" % _projectiles)
	print("[soak] %s" % ("within limits" if _failures == 0 else "%d limits broken" % _failures))


func _limit(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("[soak] LIMIT %s" % what)


static func _v(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z] if v != Vector3.INF else "none"


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
