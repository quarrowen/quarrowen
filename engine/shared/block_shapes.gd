extends RefCounted
## Collision against blocks that do not fill their cell (slabs, stairs, fences).
##
## A block's shape (BlockRegistry.Shape) is a list of boxes in block space, and the same list decides
## what is drawn, so what you see is what you walk into. Everything here works on a box (feet position,
## half width, height) so players and other entities share it; native/src/physics.rs is the twin used
## when the extension is loaded, and the two must stay in step.

const BlockRegistry = preload("res://engine/shared/block_registry.gd")

const EDGE := 0.0001
const SKIN := 0.001
## How far a walker is lifted onto a low block (a slab or the first step of a stairs) without jumping.
const STEP_HEIGHT := 0.55


## The boxes a block fills, or the whole cell when it has no shape of its own.
static func boxes_of(block: int, shapes: PackedByteArray) -> Array:
	var shape: int = shapes[block] if block < shapes.size() else BlockRegistry.Shape.FULL
	return BlockRegistry.SHAPE_BOXES.get(shape, BlockRegistry.SHAPE_BOXES[BlockRegistry.Shape.FULL])


## True when the box at `position` overlaps any solid block.
static func overlaps(position: Vector3, half_width: float, height: float, world, solid: PackedByteArray,
		shapes: PackedByteArray) -> bool:
	var x0 := floori(position.x - half_width)
	var x1 := floori(position.x + half_width - EDGE)
	var y0 := floori(position.y)
	var y1 := floori(position.y + height - EDGE)
	var z0 := floori(position.z - half_width)
	var z1 := floori(position.z + half_width - EDGE)
	# Shapes can stand taller than their own cell (a fence), so the cell below counts too.
	for y in range(y0 - 1, y1 + 1):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var block: int = world.get_block(x, y, z)
				if solid[block] == 0:
					continue
				for box in boxes_of(block, shapes):
					if _overlaps_box(position, half_width, height, x, y, z, box):
						return true
	return false


## Moves the box along one axis as far as the blocks allow. Returns the distance actually travelled;
## `hit` is true when something stopped it short.
static func sweep(position: Vector3, half_width: float, height: float, axis: int, delta: float, world,
		solid: PackedByteArray, shapes: PackedByteArray) -> Dictionary:
	if delta == 0.0:
		return {"delta": 0.0, "hit": false}
	var target := position
	target[axis] += delta
	var low := Vector3(minf(position.x, target.x), minf(position.y, target.y), minf(position.z, target.z))
	var high := Vector3(maxf(position.x, target.x), maxf(position.y, target.y), maxf(position.z, target.z))
	var x0 := floori(low.x - half_width)
	var x1 := floori(high.x + half_width - EDGE)
	var y0 := floori(low.y) - 1  # a fence in the cell below still blocks
	var y1 := floori(high.y + height - EDGE)
	var z0 := floori(low.z - half_width)
	var z1 := floori(high.z + half_width - EDGE)
	var limit := delta
	var hit := false
	for y in range(y0, y1 + 1):
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var block: int = world.get_block(x, y, z)
				if solid[block] == 0:
					continue
				var cell := Vector3(x, y, z)
				for box in boxes_of(block, shapes):
					var box_min := cell + Vector3(box[0], box[1], box[2])
					var box_max := cell + Vector3(box[3], box[4], box[5])
					if not _crosses(position, half_width, height, axis, box_min, box_max):
						continue
					var lo: float = position[axis] - (0.0 if axis == 1 else half_width)
					var hi: float = lo + (height if axis == 1 else half_width * 2.0)
					var allowed := limit
					if delta > 0.0 and box_min[axis] >= hi - EDGE:
						allowed = maxf(box_min[axis] - hi - SKIN, 0.0)
					elif delta < 0.0 and box_max[axis] <= lo + EDGE:
						allowed = minf(box_max[axis] - lo + SKIN, 0.0)
					else:
						continue  # not in the way of this move (beside it, or already overlapping)
					if absf(allowed) < absf(limit):
						limit = allowed
						hit = true
	return {"delta": limit, "hit": hit}


## Whether the box overlaps a block's box on the two axes it is not moving along.
static func _crosses(position: Vector3, half_width: float, height: float, axis: int, box_min: Vector3, box_max: Vector3) -> bool:
	for other in 3:
		if other == axis:
			continue
		var lo: float = position[other] - (0.0 if other == 1 else half_width)
		var hi: float = lo + (height if other == 1 else half_width * 2.0)
		if hi - EDGE <= box_min[other] or lo + EDGE >= box_max[other]:
			return false
	return true


static func _overlaps_box(position: Vector3, half_width: float, height: float, x: int, y: int, z: int, box: Array) -> bool:
	var box_min := Vector3(x + box[0], y + box[1], z + box[2])
	var box_max := Vector3(x + box[3], y + box[4], z + box[5])
	return position.x - half_width + EDGE < box_max.x and position.x + half_width - EDGE > box_min.x \
		and position.y + EDGE < box_max.y and position.y + height - EDGE > box_min.y \
		and position.z - half_width + EDGE < box_max.z and position.z + half_width - EDGE > box_min.z


## The highest surface under the box within `reach`, or -INF: where a step up would put the feet.
static func step_target(position: Vector3, half_width: float, height: float, direction: Vector3, world,
		solid: PackedByteArray, shapes: PackedByteArray, reach := STEP_HEIGHT) -> float:
	var ahead := position + Vector3(direction.x, 0.0, direction.z).normalized() * (half_width + 0.15)
	var best := -INF
	for x in range(floori(ahead.x - half_width), floori(ahead.x + half_width - EDGE) + 1):
		for z in range(floori(ahead.z - half_width), floori(ahead.z + half_width - EDGE) + 1):
			for y in range(floori(position.y), floori(position.y + reach) + 1):
				var block: int = world.get_block(x, y, z)
				if solid[block] == 0:
					continue
				for box in boxes_of(block, shapes):
					var top: float = y + box[4]
					if top > position.y + EDGE and top <= position.y + reach:
						best = maxf(best, top)
	if best == -INF:
		return -INF
	# Only worth it when the box fits where it would land.
	return best if not overlaps(Vector3(ahead.x, best + SKIN, ahead.z), half_width, height, world, solid, shapes) else -INF
