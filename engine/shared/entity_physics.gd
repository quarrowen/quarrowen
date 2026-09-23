extends RefCounted
## What is left of entity movement after the Rust extension became required (2026-09-23): the body
## shape, an overlap test and a ray-vs-box test.
##
## **These are not fallbacks and never were.** `collides` is called unguarded by mob spawning and
## `segment_hits_box` by the client's reach and the server's projectile hits - eight call sites that
## run in every build. The stepping half *was* a twin of `native/src/physics.rs` and is gone; entities
## step through `world.native.step_entities` now.
##
## Projectiles are the exception worth knowing about: `entities.gd` integrates them in GDScript
## whether or not Rust is loaded, because `physics.rs` implements players and entities and not them.

const BlockShapes = preload("res://engine/shared/block_shapes.gd")


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
