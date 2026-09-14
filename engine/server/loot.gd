extends RefCounted
## Loot tables: {rolls: [min, max], entries: [{item, count: [min, max], weight, data}]}. A container
## whose block data has `loot: "<table>"` (structure chests) is filled the first time it is opened, from
## the data's `structure_seed` so the same chest always holds the same loot.

var tables := {}

var _server


func _init(game_server) -> void:
	_server = game_server


func register(table_name: String, def: Dictionary) -> void:
	var entries := []
	for e in (def.get("entries") if def.get("entries") is Array else []):
		if e is Dictionary and _server.items.id_of(str(e.get("item", ""))) > 0:
			var count: Array = e.get("count", [1, 1]) if e.get("count") is Array and e.count.size() == 2 else [int(e.get("count", 1)), int(e.get("count", 1))]
			entries.append({"item": str(e.item), "count": [int(count[0]), int(count[1])], "weight": maxf(float(e.get("weight", 1.0)), 0.0),
				"data": e.get("data", {}) if e.get("data") is Dictionary else {}})
	var rolls: Array = def.get("rolls", [2, 4]) if def.get("rolls") is Array and def.rolls.size() == 2 else [2, 4]
	tables[table_name] = {"rolls": [int(rolls[0]), int(rolls[1])], "entries": entries}


## [[item id, count, data], ...] for a table.
func roll(table_name: String, seed_value: int) -> Array:
	var t: Dictionary = tables.get(table_name, {})
	if t.is_empty() or t.entries.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var total := 0.0
	for e in t.entries:
		total += e.weight
	var out := []
	for i in rng.randi_range(t.rolls[0], t.rolls[1]):
		var pick := rng.randf() * total
		for e in t.entries:
			pick -= e.weight
			if pick <= 0.0:
				out.append([_server.items.id_of(e.item), rng.randi_range(e.count[0], e.count[1]), e.data.duplicate(true)])
				break
	return out


## Fills a container view from its `loot` data (once).
func fill(container) -> void:
	var store: Dictionary = container._store if container.get("_store") != null else {}
	var table := str(store.get("loot", ""))
	if table.is_empty():
		return
	var seed_value := int(store.get("structure_seed", randi()))
	store.erase("loot")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1
	for stack in roll(table, seed_value):
		# Scatter the loot over random empty slots.
		for attempt in 12:
			var slot := rng.randi_range(0, container.size() - 1)
			if int(container.get_item(slot).item) == 0:
				container.set_item(slot, stack[0], stack[1], stack[2])
				break
	_server.emit("loot_generated", {"position": container.position, "table": table})
