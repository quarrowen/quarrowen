extends RefCounted
## Hotbar inventory of item stacks (block ids and item ids, see ItemRegistry). Authoritative on the
## server, mirrored on the client.

const SIZE := 9
const MAX_STACK := 64

var ids := PackedInt32Array()
var counts := PackedInt32Array()
var selected := 0
## Creative players place without consuming and do not collect drops.
var creative := false


func _init() -> void:
	ids.resize(SIZE)
	counts.resize(SIZE)


func selected_item() -> int:
	if ids[selected] <= 0 or (not creative and counts[selected] <= 0):
		return 0
	return ids[selected]


## The selected item if it is a block, else 0.
func selected_block() -> int:
	var id := selected_item()
	return id if id < 256 else 0


## Consumes one item from the selected slot (no-op in creative).
func consume_selected() -> void:
	if creative or counts[selected] <= 0:
		return
	counts[selected] -= 1
	if counts[selected] == 0:
		ids[selected] = 0


## Returns how many items did not fit.
func add(id: int, count: int, max_stack := MAX_STACK) -> int:
	var left := count
	for i in SIZE:
		if left <= 0:
			break
		if ids[i] == id and counts[i] < max_stack:
			var n := mini(left, max_stack - counts[i])
			counts[i] += n
			left -= n
	for i in SIZE:
		if left <= 0:
			break
		if ids[i] == 0 or counts[i] == 0:
			var n := mini(left, max_stack)
			ids[i] = id
			counts[i] = n
			left -= n
	return left


## Removes `count` items of `id` if available. Returns false (and removes nothing) otherwise.
func remove(id: int, count: int) -> bool:
	if count_of(id) < count:
		return false
	var left := count
	for i in range(SIZE - 1, -1, -1):
		if ids[i] == id and left > 0:
			var n := mini(left, counts[i])
			counts[i] -= n
			left -= n
			if counts[i] == 0:
				ids[i] = 0
	return true


func count_of(id: int) -> int:
	var total := 0
	for i in SIZE:
		if ids[i] == id:
			total += counts[i]
	return total


func set_slot(index: int, id: int, count: int) -> void:
	if index < 0 or index >= SIZE:
		return
	ids[index] = id if count > 0 else 0
	counts[index] = clampi(count, 0, 999)


func clear() -> void:
	ids.fill(0)
	counts.fill(0)


## [ids..., counts...]
func to_packed() -> PackedInt32Array:
	return ids + counts


func load_packed(data: PackedInt32Array) -> bool:
	if data.size() != SIZE * 2:
		return false
	ids = data.slice(0, SIZE)
	counts = data.slice(SIZE)
	return true
