extends RefCounted
## Movement for non-player entities (mobs, dropped items, projectiles): gravity, drag and
## axis-separated AABB-vs-voxel collision like PlayerPhysics, but with per-entity sizes. Runs only on
## the server; clients interpolate the replicated positions.

const BlockShapes = preload("res://engine/shared/block_shapes.gd")

const MAX_SUBSTEP := 0.45
const SKIN := 0.001
const EDGE := 0.0001


class Body:
	## Feet position (bottom center of the AABB).
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var half_width := 0.3
	var height := 1.8
	var on_ground := false
	## Set when horizontal movement was blocked this step (used by AI to jump over steps).
	var blocked := false
	var in_liquid := false


## Integrates one step. `gravity` in blocks/s^2, `drag` per second applied to horizontal velocity
## when airborne (ground friction comes from the caller steering velocity).
static func step(b: Body, world, solid: PackedByteArray, liquid: PackedByteArray, dt: float, gravity: float,
		drag := 0.0, shapes := PackedByteArray()) -> void:
	if collides(b.position, b.half_width, b.height, world, solid, shapes):
		b.position.y += 0.25  # pushed out when terrain changed around the body
		b.velocity = Vector3.ZERO
		b.on_ground = false
		return
	var feet_block: int = world.get_block(floori(b.position.x), floori(b.position.y + minf(0.4, b.height * 0.5)), floori(b.position.z))
	b.in_liquid = feet_block < liquid.size() and liquid[feet_block] == 1
	if b.in_liquid:
		b.velocity.y = move_toward(b.velocity.y, -1.5, 12.0 * dt)
		b.velocity.x *= maxf(0.0, 1.0 - 3.0 * dt)
		b.velocity.z *= maxf(0.0, 1.0 - 3.0 * dt)
	else:
		b.velocity.y = maxf(b.velocity.y - gravity * dt, -60.0)
		if drag > 0.0 and not b.on_ground:
			b.velocity.x *= maxf(0.0, 1.0 - drag * dt)
			b.velocity.z *= maxf(0.0, 1.0 - drag * dt)
	var motion := b.velocity * dt
	var largest := maxf(absf(motion.x), maxf(absf(motion.y), absf(motion.z)))
	var steps := maxi(1, ceili(largest / MAX_SUBSTEP))
	var part := motion / steps
	b.on_ground = false
	b.blocked = false
	for i in steps:
		if _move_axis(b, 1, part.y, world, solid, shapes):
			if part.y < 0.0:
				b.on_ground = true
			b.velocity.y = 0.0
			part.y = 0.0
		if _move_axis(b, 0, part.x, world, solid, shapes):
			b.velocity.x = 0.0
			part.x = 0.0
			b.blocked = true
		if _move_axis(b, 2, part.z, world, solid, shapes):
			b.velocity.z = 0.0
			part.z = 0.0
			b.blocked = true


static func _move_axis(b: Body, axis: int, delta: float, world, solid: PackedByteArray, shapes := PackedByteArray()) -> bool:
	var swept := BlockShapes.sweep(b.position, b.half_width, b.height, axis, delta, world, solid, shapes)
	b.position[axis] += swept.delta
	return swept.hit


static func collides(p: Vector3, half_width: float, height: float, world, solid: PackedByteArray,
		shapes := PackedByteArray()) -> bool:
	return BlockShapes.overlaps(p, half_width, height, world, solid, shapes)


## Distance along the segment `from` + `dir` * t (t in [0, max_t]) where it enters the box, or -1.
static func segment_hits_box(from: Vector3, dir: Vector3, max_t: float, box_min: Vector3, box_max: Vector3) -> float:
	var t_enter := 0.0
	var t_exit := max_t
	for axis in 3:
		if absf(dir[axis]) < 0.000001:
			if from[axis] < box_min[axis] or from[axis] > box_max[axis]:
				return -1.0
			continue
		var t1 := (box_min[axis] - from[axis]) / dir[axis]
		var t2 := (box_max[axis] - from[axis]) / dir[axis]
		t_enter = maxf(t_enter, minf(t1, t2))
		t_exit = minf(t_exit, maxf(t1, t2))
		if t_enter > t_exit:
			return -1.0
	return t_enter
