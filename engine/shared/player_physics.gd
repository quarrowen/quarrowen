extends RefCounted
## Deterministic player movement shared by the server (authoritative) and the client (prediction).
## Uses axis-separated AABB-vs-voxel collision rather than Godot physics so both sides produce
## identical results from identical inputs. Tunables come from the server's mods via `Rules`.

const DT := 1.0 / 60.0
const HALF_WIDTH := 0.3
const HEIGHT := 1.8
const EYE_HEIGHT := 1.62

const MAX_SUBSTEP := 0.45
const SKIN := 0.001
const EDGE := 0.0001

## Encoded size of one PlayerInput in bytes.
const INPUT_SIZE := 15


class Rules:
	const TUNABLES := ["walk_speed", "sprint_speed", "gravity", "jump_velocity", "terminal_velocity",
		"ground_accel", "air_accel", "swim_speed", "sink_speed"]

	var walk_speed := 4.3
	var sprint_speed := 5.6
	var gravity := 32.0
	var jump_velocity := 9.0
	var terminal_velocity := 60.0
	var ground_accel := 60.0
	var air_accel := 12.0
	var swim_speed := 3.0
	var sink_speed := 2.0
	var void_below := false
	## TUNABLES packed in order for the native step.
	var packed := PackedFloat32Array([4.3, 5.6, 32.0, 9.0, 60.0, 60.0, 12.0, 3.0, 2.0])
	## Supplied by the block registry, not sent separately.
	var solid_lut := PackedByteArray()
	var liquid_lut := PackedByteArray()

	func to_dict() -> Dictionary:
		var d := {"void_below": void_below}
		for key in TUNABLES:
			d[key] = get(key)
		return d

	func apply_dict(d: Dictionary) -> void:
		for key in TUNABLES:
			if d.has(key) and (d[key] is float or d[key] is int):
				set(key, clampf(float(d[key]), 0.0, 500.0))
		if d.has("void_below"):
			void_below = bool(d.void_below)
		packed = PackedFloat32Array(TUNABLES.map(func(key): return get(key)))


class State:
	## Feet position (bottom center of the AABB).
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var on_ground := false


class PlayerInput:
	var seq := 0
	## x = strafe right, y = forward. Quantized to 1/127 on the wire.
	var move := Vector2.ZERO
	var yaw := 0.0
	var pitch := 0.0
	var jump := false
	var sprint := false

	func write(buf: StreamPeerBuffer) -> void:
		buf.put_u32(seq)
		buf.put_8(clampi(roundi(move.x * 127.0), -127, 127))
		buf.put_8(clampi(roundi(move.y * 127.0), -127, 127))
		buf.put_float(yaw)
		buf.put_float(pitch)
		buf.put_u8(int(jump) | (int(sprint) << 1))

	static func read(buf: StreamPeerBuffer) -> PlayerInput:
		var input := PlayerInput.new()
		input.seq = buf.get_u32()
		input.move = Vector2(buf.get_8() / 127.0, buf.get_8() / 127.0)
		input.yaw = buf.get_float()
		input.pitch = buf.get_float()
		var flags := buf.get_u8()
		input.jump = (flags & 1) != 0
		input.sprint = (flags & 2) != 0
		return input


static func eye_position(state: State) -> Vector3:
	return state.position + Vector3(0.0, EYE_HEIGHT, 0.0)


static func look_direction(yaw: float, pitch: float) -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


static func step(s: State, input: PlayerInput, world, rules: Rules) -> void:
	if world.native:
		var out: PackedFloat32Array = world.native.step_player(s.position, s.velocity, s.on_ground, input.move,
			input.yaw, int(input.jump) | (int(input.sprint) << 1), rules.packed)
		s.position = Vector3(out[0], out[1], out[2])
		s.velocity = Vector3(out[3], out[4], out[5])
		s.on_ground = out[6] > 0.5
		return
	var solid := rules.solid_lut
	if _collides(s.position, world, solid):
		# Stuck inside a block (e.g. terrain changed around us): push upward until free.
		s.position.y += 0.25
		s.velocity = Vector3.ZERO
		s.on_ground = false
		return

	var move := input.move
	if move.length_squared() > 1.0:
		move = move.normalized()
	var forward := Vector3(-sin(input.yaw), 0.0, -cos(input.yaw))
	var right := Vector3(cos(input.yaw), 0.0, -sin(input.yaw))
	var wish := right * move.x + forward * move.y
	var in_liquid := rules.liquid_lut[world.get_block(floori(s.position.x), floori(s.position.y + 0.4), floori(s.position.z))] == 1

	var speed := rules.sprint_speed if input.sprint and move.y > 0.0 else rules.walk_speed
	if in_liquid:
		speed *= 0.5
	var accel := rules.ground_accel if s.on_ground or in_liquid else rules.air_accel
	var horizontal := Vector2(s.velocity.x, s.velocity.z).move_toward(Vector2(wish.x, wish.z) * speed, accel * DT)
	s.velocity.x = horizontal.x
	s.velocity.z = horizontal.y

	if in_liquid:
		var target_vy := rules.swim_speed if input.jump else -rules.sink_speed
		s.velocity.y = move_toward(s.velocity.y, target_vy, 20.0 * DT)
	else:
		if input.jump and s.on_ground:
			s.velocity.y = rules.jump_velocity
		s.velocity.y = maxf(s.velocity.y - rules.gravity * DT, -rules.terminal_velocity)

	var motion := s.velocity * DT
	var largest := maxf(absf(motion.x), maxf(absf(motion.y), absf(motion.z)))
	var steps := maxi(1, ceili(largest / MAX_SUBSTEP))
	var part := motion / steps
	s.on_ground = false
	for i in steps:
		if _move_axis(s, 1, part.y, world, solid):
			if part.y < 0.0:
				s.on_ground = true
			s.velocity.y = 0.0
			part.y = 0.0
		if _move_axis(s, 0, part.x, world, solid):
			s.velocity.x = 0.0
			part.x = 0.0
		if _move_axis(s, 2, part.z, world, solid):
			s.velocity.z = 0.0
			part.z = 0.0


## Moves along one axis; on collision snaps flush against the blocking voxel. Returns true on collision.
static func _move_axis(s: State, axis: int, delta: float, world, solid: PackedByteArray) -> bool:
	if delta == 0.0:
		return false
	var p := s.position
	p[axis] += delta
	if not _collides(p, world, solid):
		s.position = p
		return false
	if axis == 1:
		if delta > 0.0:
			p.y = floorf(p.y + HEIGHT) - HEIGHT - SKIN
		else:
			p.y = floorf(p.y) + 1.0
	else:
		if delta > 0.0:
			p[axis] = floorf(p[axis] + HALF_WIDTH) - HALF_WIDTH - SKIN
		else:
			p[axis] = floorf(p[axis] - HALF_WIDTH) + 1.0 + HALF_WIDTH + SKIN
	# Only accept the snap if it lies between the start and the target and is free.
	if (p[axis] - s.position[axis]) * delta >= 0.0 and not _collides(p, world, solid):
		s.position = p
	return true


static func _collides(p: Vector3, world, solid: PackedByteArray) -> bool:
	var x0 := floori(p.x - HALF_WIDTH)
	var x1 := floori(p.x + HALF_WIDTH - EDGE)
	var y0 := floori(p.y)
	var y1 := floori(p.y + HEIGHT - EDGE)
	var z0 := floori(p.z - HALF_WIDTH)
	var z1 := floori(p.z + HALF_WIDTH - EDGE)
	for y in range(y0, y1 + 1):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				if solid[world.get_block(x, y, z)] == 1:
					return true
	return false


## True if a player standing at feet position `p` overlaps the unit block at `block`.
static func overlaps_block(p: Vector3, block: Vector3i) -> bool:
	return (p.x - HALF_WIDTH < block.x + 1 and p.x + HALF_WIDTH > block.x
		and p.y < block.y + 1 and p.y + HEIGHT > block.y
		and p.z - HALF_WIDTH < block.z + 1 and p.z + HALF_WIDTH > block.z)
