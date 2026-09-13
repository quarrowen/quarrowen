extends RefCounted
## Player inventory: 36 backpack slots (0-8 hotbar, 9-35 main), then one slot per equipment slot the
## server defines (head, chest, legs, feet, offhand, plus any mods add). `cursor_*` is the stack held
## by the mouse while the inventory screen is open. Authoritative on the server, mirrored on the client.
##
## Every slot may carry item data: a Dictionary owned by mods and the engine (durability damage,
## custom name, lore, per-item modifiers, experience, upgrades...). Stacks merge only when their data
## is identical, so an item that levels up becomes its own stack.

const HOTBAR := 9
const SIZE := 36
const MAX_STACK := 64
## Serialized item data larger than this is refused (it is sent to clients).
const MAX_DATA_BYTES := 8192

var ids := PackedInt32Array()
var counts := PackedInt32Array()
var data: Array = []  # Dictionary per slot ({} = none)
var selected := 0
## Creative players place without consuming and do not collect drops.
var creative := false
var cursor_id := 0
var cursor_count := 0
var cursor_data := {}
## Names of the equipment slots after the backpack (index SIZE + i).
var equipment_slots: PackedStringArray = []


func _init(slot_names: PackedStringArray = PackedStringArray()) -> void:
	set_equipment_slots(slot_names)


## Total slots including equipment.
func total() -> int:
	return SIZE + equipment_slots.size()


func set_equipment_slots(slot_names: PackedStringArray) -> void:
	equipment_slots = slot_names
	ids.resize(total())
	counts.resize(total())
	data.resize(total())
	for i in data.size():
		if not (data[i] is Dictionary):
			data[i] = {}


func equipment_index(slot_name: String) -> int:
	var i := equipment_slots.find(slot_name)
	return SIZE + i if i >= 0 else -1


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
		clear_slot(selected)


## Adds to matching stacks first, then to empty slots (hotbar before the main inventory). Items with
## data only merge with stacks carrying identical data. Returns how many items did not fit.
func add(id: int, count: int, max_stack := MAX_STACK, item_data := {}) -> int:
	var left := count
	for i in SIZE:
		if left <= 0:
			break
		if ids[i] == id and counts[i] < max_stack and data[i] == item_data:
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
			data[i] = item_data.duplicate(true)
			left -= n
	return left


## How many of an item would fit (without changing anything).
func space_for(id: int, max_stack := MAX_STACK, item_data := {}) -> int:
	var room := 0
	for i in SIZE:
		if ids[i] == id and data[i] == item_data:
			room += maxi(max_stack - counts[i], 0)
		elif ids[i] == 0 or counts[i] == 0:
			room += max_stack
	return room


## Removes `count` items of `id` if available (any data). Returns false (and removes nothing) otherwise.
func remove(id: int, count: int) -> bool:
	if count_of(id) < count:
		return false
	var left := count
	# Plain stacks go first so recipes do not eat a levelled-up or renamed item.
	for with_data in [false, true]:
		for i in range(SIZE - 1, -1, -1):
			if ids[i] == id and left > 0 and data[i].is_empty() != with_data:
				var n := mini(left, counts[i])
				counts[i] -= n
				left -= n
				if counts[i] == 0:
					clear_slot(i)
	return true


func count_of(id: int) -> int:
	var total_count := 0
	for i in SIZE:
		if ids[i] == id:
			total_count += counts[i]
	return total_count


func set_slot(index: int, id: int, count: int, item_data := {}) -> void:
	if index < 0 or index >= total():
		return
	if id <= 0 or count <= 0:
		clear_slot(index)
		return
	ids[index] = id
	counts[index] = clampi(count, 0, 999)
	data[index] = item_data


func clear_slot(index: int) -> void:
	ids[index] = 0
	counts[index] = 0
	data[index] = {}


func clear() -> void:
	ids.fill(0)
	counts.fill(0)
	for i in data.size():
		data[i] = {}
	cursor_id = 0
	cursor_count = 0
	cursor_data = {}


func is_empty() -> bool:
	for i in total():
		if ids[i] > 0 and counts[i] > 0:
			return false
	return cursor_count <= 0


## Inventory screen click on `slot` with the mouse `button` (1 = left, 2 = right), Minecraft style:
## left picks up / puts down / merges / swaps whole stacks, right picks up half or puts down one.
## `shift` moves the stack between the hotbar and the main inventory, or into and out of equipment.
## `max_stack_of(id)` gives stack limits; `accepts(slot_index, id)` says whether an equipment slot
## takes an item (backpack slots take anything). Returns true if anything changed.
func click(slot: int, button: int, shift: bool, max_stack_of: Callable, accepts := Callable()) -> bool:
	if slot < 0 or slot >= total():
		return false
	var id := ids[slot]
	var count := counts[slot] if id > 0 else 0
	if shift:
		return _quick_move(slot, max_stack_of, accepts)
	if cursor_count <= 0:
		if count <= 0:
			return false
		var take := count if button == 1 else (count + 1) / 2
		cursor_id = id
		cursor_count = take
		cursor_data = data[slot].duplicate(true)
		if take == count:
			clear_slot(slot)
		else:
			counts[slot] = count - take
		return true
	if slot >= SIZE and accepts.is_valid() and not accepts.call(slot, cursor_id):
		return false
	var limit: int = max_stack_of.call(cursor_id)
	if slot >= SIZE:
		limit = 1  # equipment slots hold a single item
	if count <= 0 or (id == cursor_id and data[slot] == cursor_data):
		var put := mini(cursor_count if button == 1 else 1, limit - count)
		if put <= 0:
			return false
		set_slot(slot, cursor_id, count + put, cursor_data.duplicate(true))
		cursor_count -= put
		if cursor_count <= 0:
			cursor_id = 0
			cursor_data = {}
		return true
	if button != 1 or (slot >= SIZE and cursor_count > 1):
		return false
	# Different item: swap the cursor with the slot.
	var slot_data: Dictionary = data[slot]
	set_slot(slot, cursor_id, cursor_count, cursor_data)
	cursor_id = id
	cursor_count = count
	cursor_data = slot_data
	return true


func _quick_move(slot: int, max_stack_of: Callable, accepts: Callable) -> bool:
	var id := ids[slot]
	if id <= 0 or counts[slot] <= 0:
		return false
	var item_data: Dictionary = data[slot]
	var targets: Array = []
	if slot >= SIZE:
		targets = range(HOTBAR, SIZE) + range(0, HOTBAR)  # equipment -> backpack
	else:
		if accepts.is_valid():
			for e in equipment_slots.size():
				var index := SIZE + e
				# Quick-move fills worn slots; the offhand is only filled by hand.
				if ids[index] == 0 and equipment_slots[e] != "offhand" and accepts.call(index, id) and counts[slot] == 1:
					set_slot(index, id, 1, item_data)
					clear_slot(slot)
					return true
		targets = range(HOTBAR, SIZE) if slot < HOTBAR else range(0, HOTBAR)
	var limit: int = max_stack_of.call(id)
	var left := counts[slot]
	for pass_index in 2:
		for i in targets:
			if left <= 0:
				break
			var same: bool = ids[i] == id and data[i] == item_data and counts[i] < limit
			var empty: bool = ids[i] == 0 or counts[i] == 0
			if (pass_index == 0 and same) or (pass_index == 1 and empty):
				var have := counts[i] if same else 0
				var n := mini(left, limit - have)
				set_slot(i, id, have + n, item_data.duplicate(true))
				left -= n
	var moved := left != counts[slot]
	if left <= 0:
		clear_slot(slot)
	else:
		counts[slot] = left
	return moved


## [ids..., counts..., cursor id, cursor count] for every slot including equipment.
func to_packed() -> PackedInt32Array:
	var out := ids + counts
	out.append(cursor_id)
	out.append(cursor_count)
	return out


## Item data for the network: {slot index: Dictionary} for slots that have data, cursor as -1.
func data_to_network() -> Dictionary:
	var out := {}
	for i in total():
		if not data[i].is_empty() and ids[i] > 0:
			out[i] = data[i]
	if not cursor_data.is_empty() and cursor_count > 0:
		out[-1] = cursor_data
	return out


func load_packed(packed: PackedInt32Array) -> bool:
	# Older saves: 9 hotbar slots, or 36 slots without equipment.
	if packed.size() == HOTBAR * 2:
		clear()
		for i in HOTBAR:
			ids[i] = packed[i]
			counts[i] = packed[HOTBAR + i]
		return true
	for slots in [total(), SIZE]:
		if packed.size() == slots * 2 or packed.size() == slots * 2 + 2:
			clear()
			for i in slots:
				ids[i] = packed[i]
				counts[i] = packed[slots + i]
			if packed.size() == slots * 2 + 2:
				cursor_id = packed[slots * 2]
				cursor_count = packed[slots * 2 + 1]
			return true
	return false


## Client side: applies data from data_to_network, rejecting anything malformed or oversized.
func load_network_data(network: Dictionary) -> void:
	for i in data.size():
		data[i] = {}
	cursor_data = {}
	for key in network:
		var value = network[key]
		if not (value is Dictionary) or var_to_bytes(value).size() > MAX_DATA_BYTES:
			continue
		var index := int(key)
		if index == -1:
			cursor_data = value
		elif index >= 0 and index < total():
			data[index] = value
