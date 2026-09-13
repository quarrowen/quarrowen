extends RefCounted
## Voxel grid traversal (Amanatides & Woo).

const BlockRegistry = preload("res://engine/shared/block_registry.gd")


## `targetable` is BlockRegistry.targetable_lut. Returns {hit, position, normal, block}.
static func cast(world, targetable: PackedByteArray, origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var dir := direction.normalized()
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_delta := Vector3(
		absf(1.0 / dir.x) if dir.x != 0.0 else INF,
		absf(1.0 / dir.y) if dir.y != 0.0 else INF,
		absf(1.0 / dir.z) if dir.z != 0.0 else INF)
	var t_max := Vector3(
		_initial_t(origin.x, dir.x),
		_initial_t(origin.y, dir.y),
		_initial_t(origin.z, dir.z))
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_distance:
		var block: int = world.get_block(cell.x, cell.y, cell.z)
		if block == BlockRegistry.UNLOADED:
			break
		if targetable[block] == 1:
			return {"hit": true, "position": cell, "normal": normal, "block": block}
		if t_max.x < t_max.y and t_max.x < t_max.z:
			cell.x += step.x
			t = t_max.x
			t_max.x += t_delta.x
			normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			cell.y += step.y
			t = t_max.y
			t_max.y += t_delta.y
			normal = Vector3i(0, -step.y, 0)
		else:
			cell.z += step.z
			t = t_max.z
			t_max.z += t_delta.z
			normal = Vector3i(0, 0, -step.z)
	return {"hit": false}


static func _initial_t(origin: float, dir: float) -> float:
	if dir > 0.0:
		return (floorf(origin) + 1.0 - origin) / dir
	if dir < 0.0:
		return (origin - floorf(origin)) / -dir
	return INF
