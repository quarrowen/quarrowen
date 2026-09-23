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


static func _overlaps_box(position: Vector3, half_width: float, height: float, x: int, y: int, z: int, box: Array) -> bool:
	var box_min := Vector3(x + box[0], y + box[1], z + box[2])
	var box_max := Vector3(x + box[3], y + box[4], z + box[5])
	return position.x - half_width + EDGE < box_max.x and position.x + half_width - EDGE > box_min.x \
		and position.y + EDGE < box_max.y and position.y + height - EDGE > box_min.y \
		and position.z - half_width + EDGE < box_max.z and position.z + half_width - EDGE > box_min.z


