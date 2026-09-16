extends RefCounted
## The experimentation grid: players arrange items they hold in a 3x3 grid and try them. A matching
## recipe (by ingredient counts, and by arrangement for recipes with a `pattern`) is discovered if it
## unlocks by experimenting or picking up; otherwise the closest recipe gives a hint.

const SIZE := 3
const COOLDOWN := 0.4

var _server
var _last := {}  # peer id -> time of the last experiment


func _init(game_server) -> void:
	_server = game_server


## `grid`: 9 item ids (0 = empty), row by row. Returns {status: "discovered" | "known" | "blueprint" |
## "close" | "nothing" | "invalid", recipe (index or -1), hint}.
func experiment(p, grid: Array) -> Dictionary:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(p.peer_id, -10.0)) < COOLDOWN:
		return {"status": "invalid", "recipe": -1, "hint": "Slow down..."}
	_last[p.peer_id] = now
	var cells := _cells(grid)
	var counts := _counts(cells)
	if counts.is_empty():
		return {"status": "nothing", "recipe": -1, "hint": "Put some items in the grid."}
	for id: int in counts:
		if not p.inventory.creative and p.inventory.count_of(id) < counts[id]:
			return {"status": "invalid", "recipe": -1, "hint": "You need to hold the items you experiment with."}
	var best := -1
	var best_score := 0.0
	var best_hint := ""
	for index in _server.recipes.recipes.size():
		var r: Dictionary = _server.recipes.recipes[index]
		if r.get("removed", false) or r.get("project", false) or not _server._at_station(p, r):
			continue
		var shaped_ok: bool = r.pattern.is_empty() or _shape_matches(cells, r.pattern)
		if counts == _int_keys(r.inputs):
			if not shaped_ok:
				return _close(p, index, "So close! These belong together, but not arranged like this.")
			if _server.knows_recipe(p, r.id):
				return {"status": "known", "recipe": index, "hint": "You know this one: %s." % _server.items.display_name(r.output)}
			if r.unlock in ["experiment", "pickup"]:
				_server.learn_recipe(p, r.id, "experiment")
				_server.play_sound_to(p, "engine:discover")
				_server.emit("recipe_experimented", {"player": p, "recipe": r.id})
				return {"status": "discovered", "recipe": index, "hint": "Discovered: %s!" % _server.items.display_name(r.output)}
			if r.unlock == "blueprint":
				return {"status": "blueprint", "recipe": -1, "hint": "These could make something, but you would need its plans."}
			continue  # secret recipes give nothing away
		if r.unlock == "secret" and not _server.knows_recipe(p, r.id):
			continue
		var scored: Dictionary = _similarity(counts, _int_keys(r.inputs))
		if scored.score > best_score:
			best = index
			best_score = scored.score
			best_hint = scored.hint
	if best >= 0 and best_score >= 0.5:
		return _close(p, best, best_hint, counts)
	return {"status": "nothing", "recipe": -1, "hint": "Nothing happens."}


## A near miss. Bookshelves at the station name what is missing or extra.
func _close(p, index: int, hint: String, have := {}) -> Dictionary:
	var r: Dictionary = _server.recipes.recipes[index]
	var hints := int(p.crafting_station.get("hints", 0))
	if hints >= 2 and hint.begins_with("Something is missing"):
		# Name something they have not put in. Naming the first ingredient regardless was a coin flip:
		# a player holding coal and missing the stick was told "the books mention Coal".
		for id: int in r.inputs:
			if int(have.get(id, 0)) >= int(r.inputs[id]):
				continue
			hint += " The books mention %s." % _server.items.display_name(id)
			break
	return {"status": "close", "recipe": -1, "hint": hint}


## {score 0-1, hint} comparing the grid's ingredients with a recipe's.
static func _similarity(have: Dictionary, need: Dictionary) -> Dictionary:
	var shared := 0
	var union := {}
	for id in have:
		union[id] = true
	for id in need:
		union[id] = true
		if have.has(id):
			shared += 1
	var score := float(shared) / maxf(union.size(), 1)
	var missing := need.keys().filter(func(id): return not have.has(id)).size()
	var extra := have.keys().filter(func(id): return not need.has(id)).size()
	var hint := "Nothing happens."
	if missing == 0 and extra == 0:
		hint = "The ingredients feel right, but the amounts are off."
		score = 0.95
	elif missing > 0 and extra == 0:
		hint = "Something is missing."
	elif missing == 0 and extra > 0:
		hint = "Something here doesn't belong."
	else:
		hint = "Some of these belong together."
	return {"score": score, "hint": hint}


static func _cells(grid: Array) -> Array:
	var cells := []
	for i in SIZE * SIZE:
		cells.append(int(grid[i]) if i < grid.size() and (grid[i] is int or grid[i] is float) and int(grid[i]) > 0 else 0)
	return cells


static func _counts(cells: Array) -> Dictionary:
	var counts := {}
	for id in cells:
		if id > 0:
			counts[id] = int(counts.get(id, 0)) + 1
	return counts


static func _int_keys(d: Dictionary) -> Dictionary:
	var out := {}
	for key in d:
		out[int(key)] = int(d[key])
	return out


## Whether the grid holds the pattern anywhere (shifted), mirrored or not.
static func _shape_matches(cells: Array, pattern: Array) -> bool:
	var rows := pattern.size()
	var cols := 0
	for row in pattern:
		cols = maxi(cols, row.size())
	for mirror in [false, true]:
		for oy in range(0, SIZE - rows + 1):
			for ox in range(0, SIZE - cols + 1):
				var ok := true
				for y in SIZE:
					for x in SIZE:
						var want := 0
						var py := y - oy
						var px := x - ox
						if py >= 0 and py < rows and px >= 0 and px < cols:
							var row: Array = pattern[py]
							var col := (cols - 1 - px) if mirror else px
							want = int(row[col]) if col < row.size() else 0
						if cells[y * SIZE + x] != want:
							ok = false
							break
					if not ok:
						break
				if ok:
					return true
	return false
