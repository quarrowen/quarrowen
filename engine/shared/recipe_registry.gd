extends RefCounted
## Crafting recipes and their categories, sent to clients so the crafting screen can show the recipe
## book, what you are missing and what an item is used for. The server stays the authority on crafting.
##
## Recipe: {id ("mod:name"), inputs: {item id: count}, output, count, station ("" = anywhere), tier
## (minimum station tier), needs ([station features, e.g. "metalwork"]), category, time (seconds crafted in
## the station's queue, 0 = instant), project (built together: players contribute ingredients over time),
## unlock (how players learn it when discovery is on: "known" from the start, "pickup" when they first
## hold an ingredient, "blueprint" from a blueprint item, "experiment" at the crafting grid, "secret"
## hidden until taught), hint (text shown while undiscovered), pattern (optional arrangement for the
## experimentation grid: rows of item ids, 0 = empty, e.g. [[coal], [stick]])}
## Categories group the recipe book; recipes without one get a category from their output (tools,
## weapons, armor, food, blocks, materials).

const MAX_RECIPES := 8192
const UNLOCKS := ["known", "pickup", "blueprint", "experiment", "secret"]
const DEFAULT_CATEGORIES := [
	{"name": "tools", "display_name": "Tools"},
	{"name": "weapons", "display_name": "Weapons"},
	{"name": "armor", "display_name": "Armor"},
	{"name": "blocks", "display_name": "Building"},
	{"name": "food", "display_name": "Food"},
	{"name": "materials", "display_name": "Materials"},
	{"name": "parts", "display_name": "Parts"},
	{"name": "misc", "display_name": "Other"},
]

var recipes: Array[Dictionary] = []
var categories: Array[Dictionary] = []
var _ids := {}  # recipe id -> index
## While a mod reloads: its recipes re-registered by id replace themselves at the same index (indices
## stay valid everywhere); those it no longer registers are marked `removed` at end_reload.
var _reloading_owner := ""
var _reloaded := {}


func _init() -> void:
	for c in DEFAULT_CATEGORIES:
		register_category(c)


## Declares a tab for the crafting screen, or joins one that already exists. False only when the name
## is unusable.
##
## **Category names are a shared namespace on purpose**, and are the one registry key that is not
## namespaced per mod. They have to be: the engine owns `tools`, `weapons`, `blocks` and the rest from
## `_init`, recipes name a category as a plain string, and a mod qualified to `mymod:tools` could never
## put anything in the engine's Tools tab - it would only ever make a second tab with the same label.
##
## **Joining counts as succeeding.** This used to return false when the name was taken, which a mod
## author could not tell apart from "you passed an empty name" - while the recipes went into the tab
## anyway, which is what they asked for. First registration still wins the *label*, so a mod whose
## display_name is dropped is told at the API boundary rather than left to wonder. (2026-09-22)
func register_category(def: Dictionary) -> bool:
	var cat_name := str(def.get("name", "")).left(32)
	if cat_name.is_empty():
		return false
	if has_category(cat_name):
		return true
	categories.append({"name": cat_name, "display_name": str(def.get("display_name", cat_name.capitalize())).left(32),
		"icon": int(def.get("icon", 0))})
	return true


## Whether a tab of this name is already declared, by the engine or by a mod that loaded earlier.
func has_category(cat_name: String) -> bool:
	return categories.any(func(c): return c.name == cat_name)


## Adds a recipe. `items` (an ItemRegistry) picks a category when none is given. Returns its index.
func add(def: Dictionary, items = null) -> int:
	if recipes.size() >= MAX_RECIPES:
		return -1
	var inputs := {}
	var given = def.get("inputs", {})
	for key in (given if given is Dictionary else {}):
		if int(key) > 0 and int(given[key]) > 0:
			inputs[int(key)] = int(given[key])
	var output := int(def.get("output", 0))
	if inputs.is_empty() or output <= 0:
		return -1
	var recipe_id := str(def.get("id", ""))
	var replace_at := -1
	if not _reloading_owner.is_empty() and _ids.has(recipe_id) and recipes[_ids[recipe_id]].get("owner", "") == _reloading_owner:
		replace_at = _ids[recipe_id]
	elif recipe_id.is_empty() or _ids.has(recipe_id):
		recipe_id = "recipe:%d" % recipes.size()
	var category := str(def.get("category", ""))
	if category.is_empty() or not categories.any(func(c): return c.name == category):
		category = guess_category(output, items)
	var r := {"id": recipe_id, "inputs": inputs, "output": output, "count": clampi(int(def.get("count", 1)), 1, 999),
		"station": str(def.get("station", "")).left(64), "category": category, "tier": clampi(int(def.get("tier", 0)), 0, 99),
		"needs": (def.get("needs") as Array).map(func(f): return str(f).left(32)).slice(0, 8) if def.get("needs") is Array else [],
		"time": clampf(float(def.get("time", 0.0)) if def.get("time") is float or def.get("time") is int else 0.0, 0.0, 3600.0),
		"project": bool(def.get("project", false)),
		"unlock": str(def.get("unlock", "pickup")) if str(def.get("unlock", "pickup")) in UNLOCKS else "pickup",
		"hint": str(def.get("hint", "")).left(160),
		"skill": str(def.get("skill", "")).left(64),
		"pattern": _clean_pattern(def.get("pattern")),
		"output_data": def.get("output_data", {}) if def.get("output_data") is Dictionary else {},
		"owner": str(def.get("owner", "")), "removed": bool(def.get("removed", false))}
	if replace_at >= 0:
		recipes[replace_at] = r
		_reloaded[recipe_id] = true
		return replace_at
	if not _reloading_owner.is_empty():
		_reloaded[recipe_id] = true
	_ids[recipe_id] = recipes.size()
	recipes.append(r)
	return recipes.size() - 1


static func _clean_pattern(value) -> Array:
	var rows := []
	for row in (value if value is Array else []).slice(0, 3):
		if row is Array:
			rows.append((row as Array).slice(0, 3).map(func(v): return int(v) if v is int or v is float else 0))
	return rows


## Starts watching one mod's recipes so `end_reload` can tell which have gone.
##
## Reloading cannot simply drop the owner's recipes and re-add them: a recipe is referred to by index
## elsewhere, so they are marked removed instead and the indices stay put.
func begin_reload(owner: String) -> void:
	_reloading_owner = owner
	_reloaded = {}


## Marks the owner's recipes that were not registered again as removed. Returns how many changed.
func end_reload() -> int:
	var removed := 0
	for r in recipes:
		if r.get("owner", "") == _reloading_owner and not _reloaded.has(r.id) and not r.get("removed", false):
			r.removed = true
			removed += 1
	_reloading_owner = ""
	_reloaded = {}
	return removed


## Forgets every recipe (clients rebuild the book from a content update).
func clear() -> void:
	recipes.clear()
	_ids.clear()


## Where a recipe sits in `recipes`, or -1. The index is what everything else refers to a recipe by,
## because it survives a reload while the array position of a rebuilt list would not.
func index_of(recipe_id: String) -> int:
	return _ids.get(recipe_id, -1)


## Recipes whose output is `item`.
func producing(item: int) -> Array:
	return range(recipes.size()).filter(func(i): return recipes[i].output == item)


## Recipes that use `item` as an ingredient.
func using(item: int) -> Array:
	return range(recipes.size()).filter(func(i): return recipes[i].inputs.has(item))


## Which crafting tab a recipe belongs in when the mod did not say: worked out from what it makes -
## blocks, armor, tools, weapons, food, else materials.
static func guess_category(output: int, items) -> String:
	if items == null:
		return "misc"
	var def: Dictionary = items.get_def(output)
	if output < items.FIRST_ITEM:
		return "blocks"
	if not def.get("armor", {}).is_empty() or not str(def.get("equip_slot", "")).is_empty():
		return "armor"
	if not def.get("tool", {}).is_empty():
		return "tools"
	if not def.get("weapon", {}).is_empty():
		return "weapons"
	if def.get("usable", false) and def.get("food", null) != null:
		return "food"
	return "materials"


## The recipe book as the client receives it.
func to_network() -> Dictionary:
	return {"recipes": recipes.duplicate(true), "categories": categories.duplicate(true)}


## Rebuilds the book on the client. False when the data is not the shape we expect.
func load_network(data) -> bool:
	if not (data is Dictionary):
		return true
	if data.get("categories") is Array:
		for c in data.categories:
			if c is Dictionary:
				register_category(c)
	if data.get("recipes") is Array:
		for r in data.recipes.slice(0, MAX_RECIPES):
			if r is Dictionary:
				add(r)
	return true
