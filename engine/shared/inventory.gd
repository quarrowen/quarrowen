extends RefCounted
## Player inventory: 36 slots of item stacks (block ids and item ids, see ItemRegistry). Slots 0-8 are
## the hotbar, 9-35 the main inventory. `cursor` is the stack held by the mouse while the inventory
## screen is open. Authoritative on the server, mirrored on the client.

const HOTBAR := 9
const SIZE := 36
const MAX_STACK := 64

var ids := PackedInt32Array()
var counts := PackedInt32Array()
var selected := 0
## Creative players place without consuming and do not collect drops.
var creative := false
var cursor_id := 0
var cursor_count := 0


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
	return id if id < 65536 else 0


## Consumes one item from the selected slot (no-op in creative).
func consume_selected() -> void:
	if creative or counts[selected] <= 0:
		return
	counts[selected] -= 1
	if counts[selected] == 0:
		ids[selected] = 0


## Adds to existing stacks first, then to empty slots (hotbar before the main inventory). Returns how
## many items did not fit.
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


## How many of `count` would fit (without changing anything).
func space_for(id: int, max_stack := MAX_STACK) -> int:
	var room := 0
	for i in SIZE:
		if ids[i] == id:
			room += maxi(max_stack - counts[i], 0)
		elif ids[i] == 0 or counts[i] == 0:
			room += max_stack
	return room


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
	counts[index] = clampi(count, 0, 999) if id > 0 else 0


func clear() -> void:
	ids.fill(0)
	counts.fill(0)
	cursor_id = 0
	cursor_count = 0


func is_empty() -> bool:
	for i in SIZE:
		if ids[i] > 0 and counts[i] > 0:
			return false
	return cursor_count <= 0


## Inventory screen click on `slot` with the mouse `button` (1 = left, 2 = right), Minecraft style:
## left picks up / puts down / merges / swaps whole stacks, right picks up half or puts down one.
## `shift` moves the stack between the hotbar and the main inventory. `max_stack_of` returns the
## stack limit for an item id. Returns true if anything changed.
func click(slot: int, button: int, shift: bool, max_stack_of: Callable) -> bool:
	if slot < 0 or slot >= SIZE:
		return false
	var id := ids[slot]
	var count := counts[slot] if id > 0 else 0
	if shift:
		if count <= 0:
			return false
		var limit: int = max_stack_of.call(id)
		var targets := range(HOTBAR, SIZE) if slot < HOTBAR else range(0, HOTBAR)
		var left := count
		for pass_index in 2:
			for i in targets:
				if left <= 0:
					break
				if (pass_index == 0 and ids[i] == id and counts[i] < limit) or (pass_index == 1 and (ids[i] == 0 or counts[i] == 0)):
					var n := mini(left, limit - (counts[i] if ids[i] == id else 0))
					ids[i] = id
					counts[i] = (counts[i] if pass_index == 0 else 0) + n
					left -= n
		set_slot(slot, id, left)
		return left != count
	if cursor_count <= 0:
		if count <= 0:
			return false
		var take := count if button == 1 else (count + 1) / 2
		cursor_id = id
		cursor_count = take
		set_slot(slot, id, count - take)
		return true
	var limit: int = max_stack_of.call(cursor_id)
	if count <= 0 or id == cursor_id:
		var room := limit - count
		var put := mini(cursor_count if button == 1 else 1, room)
		if put <= 0:
			return false
		set_slot(slot, cursor_id, count + put)
		cursor_count -= put
		if cursor_count <= 0:
			cursor_id = 0
		return true
	if button != 1:
		return false
	# Different item: swap the cursor with the slot.
	ids[slot] = cursor_id
	counts[slot] = cursor_count
	cursor_id = id
	cursor_count = count
	return true


## [ids..., counts..., cursor id, cursor count]
func to_packed() -> PackedInt32Array:
	var out := ids + counts
	out.append(cursor_id)
	out.append(cursor_count)
	return out


func load_packed(data: PackedInt32Array) -> bool:
	# Worlds saved before the inventory grew had only the 9 hotbar slots.
	if data.size() == HOTBAR * 2:
		clear()
		for i in HOTBAR:
			ids[i] = data[i]
			counts[i] = data[HOTBAR + i]
		return true
	if data.size() != SIZE * 2 and data.size() != SIZE * 2 + 2:
		return false
	ids = data.slice(0, SIZE)
	counts = data.slice(SIZE, SIZE * 2)
	cursor_id = data[SIZE * 2] if data.size() > SIZE * 2 else 0
	cursor_count = data[SIZE * 2 + 1] if data.size() > SIZE * 2 else 0
	return true
