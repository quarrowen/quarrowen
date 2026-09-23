extends RefCounted
## Mob navigation queries: A* for mobs of any size, straight-walk checks and line of sight. Uses the
## native world when the extension is loaded; otherwise runs the same rules in GDScript with a smaller
## node budget (native/src/pathfind.rs is the reference).
##
## A node is the cell holding the minimum corner of a mob's footprint. An agent is
## [width cells, height cells, step_up, max_drop, can_swim].

## How far a single path search may look before giving up.
const NATIVE_MAX_NODES := 1500
const DIAGONAL := 1.41421356
const STEP_UP_COST := 0.6
const DROP_COST := 0.35
const SWIM_COST := 2.5
const EDGE_COST := 0.6
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const UNLOADED := 65535

enum Status { NONE, FOUND, PARTIAL }

var world
var solid := PackedByteArray()
var liquid := PackedByteArray()
var hazard := PackedByteArray()
var sight := PackedByteArray()


func _init(voxel_world) -> void:
	world = voxel_world


## `sight_blockers`: 1 for blocks that stop line of sight; `hazards`: 1 for blocks mobs avoid.
func set_tables(solid_lut: PackedByteArray, liquid_lut: PackedByteArray, sight_blockers: PackedByteArray, hazards: PackedByteArray) -> void:
	solid = solid_lut
	liquid = liquid_lut
	sight = sight_blockers
	hazard = hazards
	world.native.set_ai_tables(sight, hazard)


static func agent_for(width: float, height: float, step_up: int, max_drop: int, can_swim: bool) -> PackedInt32Array:
	return PackedInt32Array([maxi(ceili(width - 0.01), 1), maxi(ceili(height - 0.01), 1), step_up, max_drop, 1 if can_swim else 0])


static func node_of(position: Vector3, agent: PackedInt32Array) -> Vector3i:
	return Vector3i(floori(position.x - agent[0] * 0.5 + 0.5), floori(position.y + 0.05), floori(position.z - agent[0] * 0.5 + 0.5))


static func node_center(node: Vector3i, agent: PackedInt32Array) -> Vector3:
	return Vector3(node.x + agent[0] * 0.5, node.y, node.z + agent[0] * 0.5)


## {status: Status, nodes: Array[Vector3i]} from start to the end node.
func find_path(start: Vector3i, goal: Vector3i, radius: float, agent: PackedInt32Array, max_nodes := -1) -> Dictionary:
	var raw: PackedVector3Array = world.native.find_path(start, goal, radius, agent, NATIVE_MAX_NODES if max_nodes < 0 else max_nodes)
	var nodes: Array[Vector3i] = []
	for i in range(1, raw.size()):
		nodes.append(Vector3i(raw[i]))
	return {"status": int(raw[0].x) if raw.size() > 0 else Status.NONE, "nodes": nodes}


func walkable_line(from: Vector3i, to: Vector3i, agent: PackedInt32Array) -> bool:
	return world.native.walkable_line(from, to, agent)


func standable(node: Vector3i, agent: PackedInt32Array) -> bool:
	return world.native.standable(node, agent)


func line_of_sight(from: Vector3, to: Vector3) -> bool:
	return world.native.line_of_sight(from, to)


## Standable node at or near `position` (scans a few cells up and down).
func settle(position: Vector3, agent: PackedInt32Array) -> Vector3i:
	var n := node_of(position, agent)
	for dy in [0, -1, 1, -2, 2, -3, 3]:
		if standable(n + Vector3i(0, dy, 0), agent):
			return n + Vector3i(0, dy, 0)
	return Vector3i(0, -9999, 0)
