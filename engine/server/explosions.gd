extends RefCounted
## Explosions: `explode(center, power, options)`.
##
## Blocks: rays go out from the center losing strength with distance and with each block's blast
## resistance (`blast_resistance` in the block definition; default from hardness; unbreakable blocks and
## liquids stop the blast). Blocks the rays get through are destroyed and drop their items with a chance
## of 1 / power. Mob explosions only break blocks when the `mob_griefing` rule is on; any explosion can
## pass `break_blocks: false`.
## Players and entities within 2 x power blocks take damage and knockback that fall off with distance
## and cover (armor protects against "explosion"), then the `explosion` effect and sound play.
## options: source (the entity or player responsible), break_blocks (bool), drop_chance (0-1),
## damage (multiplier), effect, sound.
## Event: explosion {position, power, source, blocks: [Vector3i], cancelled}; mods may change blocks.

const VoxelRaycast = preload("res://engine/shared/voxel_raycast.gd")
const BlockRegistry = preload("res://engine/shared/block_registry.gd")

const RAYS := 400
const STEP := 0.4
const MAX_POWER := 12.0

var _server
var _directions := PackedVector3Array()


func _init(game_server) -> void:
	_server = game_server
	# Evenly spread ray directions (a Fibonacci sphere).
	var golden := PI * (3.0 - sqrt(5.0))
	for i in RAYS:
		var y := 1.0 - (i + 0.5) / RAYS * 2.0
		var r := sqrt(1.0 - y * y)
		_directions.append(Vector3(cos(golden * i) * r, y, sin(golden * i) * r))


func blast_resistance(block: int) -> float:
	var def: Dictionary = _server.registry.defs[block]
	if def.has("blast_resistance"):
		return float(def.blast_resistance)
	if not def.breakable or def.liquid:
		return 1000.0
	return float(def.get("hardness", 0.5)) * 1.2


## options.realm: the world it goes off in (a Realm, or null for the overworld). An explosion is a
## thing that happens in a place, and a position alone no longer says where.
func explode(center: Vector3, power: float, options := {}) -> Dictionary:
	power = clampf(power, 0.1, MAX_POWER)
	var into = options.get("realm")
	if into == null:
		into = _server.realm
	var source = options.get("source")
	var from_mob: bool = source != null and source.get("brain") != null
	var break_blocks: bool = bool(options.get("break_blocks", true)) and (not from_mob or bool(_server.gameplay.get("mob_griefing", true)))
	var blocks := []
	if break_blocks:
		var seen := {}
		var world = into.world
		for dir in _directions:
			var strength := power * randf_range(0.7, 1.3)
			var pos := center
			while strength > 0.0:
				var cell := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
				var block: int = world.get_block_v(cell)
				if block == BlockRegistry.UNLOADED:
					break
				if block != BlockRegistry.AIR:
					strength -= (blast_resistance(block) + 0.3) * 0.3
					if strength > 0.0 and not seen.has(cell) and blast_resistance(block) < 1000.0:
						seen[cell] = true
						blocks.append(cell)
				strength -= STEP * 0.75
				pos += dir * STEP
	var ev: Dictionary = _server.emit("explosion", {"position": center, "power": power, "source": source, "blocks": blocks, "cancelled": false})
	if ev.cancelled:
		return ev
	var drop_chance := float(options.get("drop_chance", 1.0 / power))
	for cell in (ev.blocks if ev.blocks is Array else []):
		var block: int = into.world.get_block_v(cell)
		if block == BlockRegistry.AIR or block == BlockRegistry.UNLOADED:
			continue
		# The ordinary path rather than reaching past it into _apply_block: that bypassed
		# block_destroyed entirely, so a blast was the one way to remove a block that nothing could
		# observe. Silent, because fifty break sounds under one explosion is a noise. (2026-09-21)
		_server.break_block(cell, randf() < drop_chance, into, false)
	_hurt_around(center, power, source, float(options.get("damage", 1.0)), into)
	_server.play_effect(str(options.get("effect", "engine:explosion")), center, {"scale": clampf(power / 3.0, 0.4, 3.0)})
	_server.play_sound_at(str(options.get("sound", "engine:explosion")), center, 1.0, randf_range(0.85, 1.05))
	into.entities.ai.make_noise(center, 16.0 + power * 4.0, source, true)
	return ev


## Damage and knockback for players and entities in range: falls off with distance and with how much
## of the target the blast can see.
func _hurt_around(center: Vector3, power: float, source, multiplier: float, into = null) -> void:
	var radius := power * 2.0
	var solid: PackedByteArray = _server.registry.solid_lut
	if into == null:
		into = _server.realm
	for p in _server.players.values():
		# Only people standing in the world it went off in: a blast in the Emberdeep must not hurt
		# somebody at the same coordinates in the overworld.
		if p.dead or _server.realm_of(p) != into:
			continue
		var impact := _impact(center, p.state.position, 1.8, radius, solid, into)
		if impact > 0.0:
			var damage := ((impact * impact + impact) * 0.5 * 7.0 * power + 1.0) * multiplier * 0.5
			_server.damage_player(p, damage, "explosion", source if source != p else null, p.state.position - center, true, 10.0 * impact)
	for e in into.entities.in_radius(center, radius + 1.0):
		if e == source or not e.is_alive():
			continue
		var impact := _impact(center, e.body.position, e.def.height, radius, solid, into)
		if impact <= 0.0:
			continue
		if e.def.kind == "mob":
			into.entities.damage(e, ((impact * impact + impact) * 0.5 * 7.0 * power + 1.0) * multiplier * 0.5, "explosion", source, e.body.position - center)
		var push: Vector3 = (e.body.position + Vector3(0, e.def.height * 0.5, 0) - center).normalized() * 10.0 * impact
		e.body.velocity += push + Vector3(0, 3.0 * impact, 0)
		e.wake()


func _impact(center: Vector3, feet: Vector3, height: float, radius: float, solid: PackedByteArray, into = null) -> float:
	var distance := center.distance_to(feet + Vector3(0, height * 0.5, 0))
	if distance >= radius:
		return 0.0
	var visible := 0
	for t in [0.1, 0.5, 0.9]:
		var point := feet + Vector3(0, height * t, 0)
		var ray: Dictionary = VoxelRaycast.cast((into if into != null else _server.realm).world, solid, center, point - center, center.distance_to(point))
		if not ray.hit or Vector3(ray.position).distance_to(point) < 1.0:
			visible += 1
	return (1.0 - distance / radius) * visible / 3.0
