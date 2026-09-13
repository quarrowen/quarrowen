extends RefCounted
## Mob navigation queries: A* for mobs of any size, straight-walk checks and line of sight. Uses the
## native world when the extension is loaded; otherwise runs the same rules in GDScript with a smaller
## node budget (native/src/pathfind.rs is the reference).
##
## A node is the cell holding the minimum corner of a mob's footprint. An agent is
## [width cells, height cells, step_up, max_drop, can_swim].

const NATIVE_MAX_NODES := 1500
const SCRIPT_MAX_NODES := 350
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
	if world.native:
		world.native.set_ai_tables(sight, hazard)


static func agent_for(width: float, height: float, step_up: int, max_drop: int, can_swim: bool) -> PackedInt32Array:
	return PackedInt32Array([maxi(ceili(width - 0.01), 1), maxi(ceili(height - 0.01), 1), step_up, max_drop, 1 if can_swim else 0])


static func node_of(position: Vector3, agent: PackedInt32Array) -> Vector3i:
	return Vector3i(floori(position.x - agent[0] * 0.5 + 0.5), floori(position.y + 0.05), floori(position.z - agent[0] * 0.5 + 0.5))


static func node_center(node: Vector3i, agent: PackedInt32Array) -> Vector3:
	return Vector3(node.x + agent[0] * 0.5, node.y, node.z + agent[0] * 0.5)


## {status: Status, nodes: Array[Vector3i]} from start to the end node.
func find_path(start: Vector3i, goal: Vector3i, radius: float, agent: PackedInt32Array, max_nodes := -1) -> Dictionary:
	if world.native:
		var raw: PackedVector3Array = world.native.find_path(start, goal, radius, agent, NATIVE_MAX_NODES if max_nodes < 0 else max_nodes)
		var nodes: Array[Vector3i] = []
		for i in range(1, raw.size()):
			nodes.append(Vector3i(raw[i]))
		return {"status": int(raw[0].x) if raw.size() > 0 else Status.NONE, "nodes": nodes}
	return _astar(start, goal, radius, agent, SCRIPT_MAX_NODES if max_nodes < 0 else mini(max_nodes, SCRIPT_MAX_NODES))


func walkable_line(from: Vector3i, to: Vector3i, agent: PackedInt32Array) -> bool:
	if world.native:
		return world.native.walkable_line(from, to, agent)
	return _walk_line(from, to, agent)


func standable(node: Vector3i, agent: PackedInt32Array) -> bool:
	if world.native:
		return world.native.standable(node, agent)
	return _can_stand(node.x, node.y, node.z, agent)


func line_of_sight(from: Vector3, to: Vector3) -> bool:
	if world.native:
		return world.native.line_of_sight(from, to)
	return _sight_line(from, to)


## Standable node at or near `position` (scans a few cells up and down).
func settle(position: Vector3, agent: PackedInt32Array) -> Vector3i:
	var n := node_of(position, agent)
	for dy in [0, -1, 1, -2, 2, -3, 3]:
		if standable(n + Vector3i(0, dy, 0), agent):
			return n + Vector3i(0, dy, 0)
	return Vector3i(0, -9999, 0)


# --- GDScript twin of native/src/pathfind.rs ------------------------------------------------------

func _solid(b: int) -> bool:
	return solid[b] == 1


func _box_clear(x: int, y: int, z: int, a: PackedInt32Array) -> bool:
	for dy in a[1]:
		for dz in a[0]:
			for dx in a[0]:
				var b: int = world.get_block(x + dx, y + dy, z + dz)
				if solid[b] == 1 or hazard[b] == 1:
					return false
	return true


func _can_stand(x: int, y: int, z: int, a: PackedInt32Array) -> bool:
	if not _box_clear(x, y, z, a):
		return false
	var supported := false
	for dz in a[0]:
		for dx in a[0]:
			var below: int = world.get_block(x + dx, y - 1, z + dz)
			if hazard[below] == 1:
				return false
			if solid[below] == 1 and below != UNLOADED:
				supported = true
			if a[4] != 0 and liquid[world.get_block(x + dx, y, z + dz)] == 1:
				supported = true
	if not supported:
		return false
	if a[4] == 0:
		for dz in a[0]:
			for dx in a[0]:
				if liquid[world.get_block(x + dx, y, z + dz)] == 1:
					return false
	return true


func _in_liquid(x: int, y: int, z: int, a: PackedInt32Array) -> bool:
	for dz in a[0]:
		for dx in a[0]:
			if liquid[world.get_block(x + dx, y, z + dz)] == 1:
				return true
	return false


func _column_has_floor(x: int, y: int, z: int, a: PackedInt32Array) -> bool:
	for dz in a[0]:
		for dx in a[0]:
			var b: int = world.get_block(x + dx, y, z + dz)
			if (solid[b] == 1 and b != UNLOADED) or liquid[b] == 1:
				return true
	return false


func _near_edge(x: int, y: int, z: int, a: PackedInt32Array) -> bool:
	for i in 4:
		var nx: int = x + DIRS[i].x
		var nz: int = z + DIRS[i].y
		if not _box_clear(nx, y, nz, a):
			continue
		var depth := 0
		while depth <= a[3] and not _column_has_floor(nx, y - 1 - depth, nz, a):
			depth += 1
		if depth > a[3]:
			return true
	return false


func _neighbours(n: Vector3i, a: PackedInt32Array) -> Array:
	var out := []
	for i in DIRS.size():
		var d: Vector2i = DIRS[i]
		var nx := n.x + d.x
		var nz := n.z + d.y
		var diagonal := i >= 4
		var base := DIAGONAL if diagonal else 1.0
		if diagonal and not (_box_clear(n.x + d.x, n.y, n.z, a) and _box_clear(n.x, n.y, n.z + d.y, a)):
			continue
		if _can_stand(nx, n.y, nz, a):
			out.append([Vector3i(nx, n.y, nz), base])
			continue
		if _box_clear(nx, n.y, nz, a):
			for k in range(1, a[3] + 1):
				if not _box_clear(nx, n.y - k, nz, a):
					break
				if _can_stand(nx, n.y - k, nz, a):
					out.append([Vector3i(nx, n.y - k, nz), base + DROP_COST * k])
					break
			continue
		if diagonal:
			continue
		for k in range(1, a[2] + 1):
			if not _box_clear(n.x, n.y + k, n.z, a):
				break
			if _can_stand(nx, n.y + k, nz, a):
				out.append([Vector3i(nx, n.y + k, nz), base + STEP_UP_COST * k])
				break
	return out


func _heuristic(n: Vector3i, goal: Vector3i) -> float:
	var dx := absf(n.x - goal.x)
	var dz := absf(n.z - goal.z)
	return maxf(dx, dz) + (DIAGONAL - 1.0) * minf(dx, dz) + absf(n.y - goal.y) * 0.5


func _astar(start_node: Vector3i, goal: Vector3i, radius: float, a: PackedInt32Array, max_nodes: int) -> Dictionary:
	var start := Vector3i(0, -9999, 0)
	for dy in [0, -1, 1, -2, 2, -3]:
		if _can_stand(start_node.x, start_node.y + dy, start_node.z, a):
			start = start_node + Vector3i(0, dy, 0)
			break
	var empty: Array[Vector3i] = []
	if start.y == -9999:
		return {"status": Status.NONE, "nodes": empty}
	var came := {start: [start, 0.0]}
	var open := [[_heuristic(start, goal), 0.0, start]]  # binary heap of [f, g, node]
	var best := start
	var best_h := _heuristic(start, goal)
	var expanded := 0
	while not open.is_empty():
		var top: Array = _heap_pop(open)
		var g: float = top[1]
		var node: Vector3i = top[2]
		if came[node][1] < g:
			continue
		if Vector2(node.x - goal.x, node.z - goal.z).length() <= radius and absi(node.y - goal.y) <= 2:
			return {"status": Status.FOUND, "nodes": _unwind(came, node)}
		expanded += 1
		if expanded > max_nodes:
			break
		var edge := EDGE_COST if _near_edge(node.x, node.y, node.z, a) else 0.0
		for entry in _neighbours(node, a):
			var next: Vector3i = entry[0]
			var swim := SWIM_COST if a[4] != 0 and _in_liquid(next.x, next.y, next.z, a) else 0.0
			var tentative: float = g + entry[1] + swim + edge
			if not came.has(next) or tentative < came[next][1]:
				came[next] = [node, tentative]
				var h := _heuristic(next, goal)
				if h < best_h:
					best_h = h
					best = next
				_heap_push(open, [tentative + h, tentative, next])
	if best == start:
		var only: Array[Vector3i] = [start]
		return {"status": Status.NONE, "nodes": only}
	return {"status": Status.PARTIAL, "nodes": _unwind(came, best)}


func _unwind(came: Dictionary, end: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [end]
	var current := end
	while came.has(current) and came[current][0] != current:
		current = came[current][0]
		path.append(current)
	path.reverse()
	return path


static func _heap_push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if not _less(heap[i], heap[parent]):
			break
		var tmp = heap[i]
		heap[i] = heap[parent]
		heap[parent] = tmp
		i = parent


static func _heap_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var smallest := i
		if l < heap.size() and _less(heap[l], heap[smallest]):
			smallest = l
		if r < heap.size() and _less(heap[r], heap[smallest]):
			smallest = r
		if smallest == i:
			break
		var tmp = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest
	return top


static func _less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] > b[1])


func _walk_line(from: Vector3i, to: Vector3i, a: PackedInt32Array) -> bool:
	if from.y != to.y:
		return false
	var dx := float(to.x - from.x)
	var dz := float(to.z - from.z)
	var steps := ceili(maxf(absf(dx), absf(dz)) * 3.0)
	if steps == 0:
		return true
	var half := 0.5 * a[0] - 0.05
	for i in steps + 1:
		var t := float(i) / steps
		var cx := from.x + 0.5 * a[0] + dx * t
		var cz := from.z + 0.5 * a[0] + dz * t
		var supported := false
		for z in range(floori(cz - half), floori(cz + half) + 1):
			for x in range(floori(cx - half), floori(cx + half) + 1):
				for dy in a[1]:
					var b: int = world.get_block(x, from.y + dy, z)
					if solid[b] == 1 or hazard[b] == 1:
						return false
				var below: int = world.get_block(x, from.y - 1, z)
				if hazard[below] == 1:
					return false
				if solid[below] == 1 and below != UNLOADED:
					supported = true
		if not supported:
			return false
	return true


func _sight_line(from: Vector3, to: Vector3) -> bool:
	var d := to - from
	var length := d.length()
	if length < 0.0001:
		return true
	var dir := d / length
	var cell := Vector3i(floori(from.x), floori(from.y), floori(from.z))
	var target := Vector3i(floori(to.x), floori(to.y), floori(to.z))
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for i in 3:
		if dir[i] > 0.0:
			t_max[i] = (floorf(from[i]) + 1.0 - from[i]) / dir[i]
			t_delta[i] = 1.0 / dir[i]
		elif dir[i] < 0.0:
			t_max[i] = (from[i] - floorf(from[i])) / -dir[i]
			t_delta[i] = -1.0 / dir[i]
	for guard in 512:
		if cell == target:
			return true
		var axis := 0 if t_max.x < t_max.y and t_max.x < t_max.z else (1 if t_max.y < t_max.z else 2)
		if t_max[axis] > length:
			return true
		cell[axis] += step[axis]
		t_max[axis] += t_delta[axis]
		if cell != target and sight[world.get_block(cell.x, cell.y, cell.z)] == 1:
			return false
	return false
