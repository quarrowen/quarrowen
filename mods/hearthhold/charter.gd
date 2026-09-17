extends RefCounted
## The charter board: one block in the middle of the outpost that says what the place needs next.
##
## It is the story's spine made into something a child can walk up to and read. Chapter one's entry is
## already on it when they arrive, in the last warden's handwriting, written to somebody who never came -
## which is the whole premise delivered without a line of narration.
##
## Entries are data rather than code, so the rest of the chapters are a table. Each has a goal the engine
## can check for itself, and a line of what it means; the board shows the first one that is not done.

var api
var dwellings
var ids := {}

## The chapters, in order. `done` is asked every few seconds; the first entry that is not done is the one
## the board shows. Kept deliberately short: a child should read the board, not study it.
var entries := [
	{
		"id": "hearth",
		"title": "Firewood for the hearth",
		"hand": "Three logs should see it through the night. I will be back before dark. - W.",
		"note": "The handwriting is old. Nobody came back.",
		"done": func(): return _hearth_lit(),
	},
	{
		"id": "night",
		"title": "See the night out",
		"hand": "Keep the fire in. It is worse when it goes out.",
		"note": "Stay near the light until morning.",
		"done": func(): return _seen_a_morning(),
	},
	{
		"id": "bramble",
		"title": "Somebody saw the smoke",
		"hand": "A mark scratched into the board, and a direction. Recent.",
		"note": "Someone is out there, and they are walking this way. Go and meet them.",
		"done": func(): return _bramble_recruited(),
	},
	{
		"id": "house",
		"title": "Somewhere for her to live",
		"hand": "A bed, walls, a roof, a light, and a door. In that order, if you like.",
		"note": "Place a hearthstone where the house is to be; it will tell you what is missing.",
		"done": func(): return _bramble_home(),
	},
]


func setup(mod_api, dwellings_ref) -> void:
	api = mod_api
	dwellings = dwellings_ref
	ids.board = api.register_block("charter_board", {"display_name": "Charter Board",
		"textures": {"all": "textures/charter_board.png"}, "render": "cutout",
		"sounds": {"break": "base:wood", "place": "base:wood", "step": "base:wood_step"},
		"hardness": 1.5, "tool": "axe", "interactive": true, "orientation": 1})
	api.register_recipe({"base:planks": 4, "base:stick": 2}, "hearthhold:charter_board", 1,
		{"station": "crafting_table", "unlock": "known", "category": "blocks"})
	api.on("block_interact", func(ev):
		if ev.block == ids.board:
			ev.cancelled = true
			show(ev.player))


## What the place needs next, or that there is nothing left to do.
func current() -> Dictionary:
	for entry in entries:
		if not entry.done.call():
			return entry
	return {}


func show(player) -> void:
	var entry := current()
	var children: Array = [{"type": "label", "text": "The Charter", "size": 22, "color": "#ffd166"}]
	if entry.is_empty():
		children.append({"type": "label", "text": "Nothing outstanding. The fire is in and the valley is quieter."})
	else:
		children.append({"type": "label", "text": str(entry.title), "size": 18})
		children.append({"type": "label", "text": "\u201c%s\u201d" % str(entry.hand), "color": "#c9b896"})
		children.append({"type": "spacer", "size": 4})
		children.append({"type": "label", "text": str(entry.note), "color": "#9aa4b8"})
	# What is already done, so the board reads as a record of the place rather than a list of chores.
	var finished: Array = entries.filter(func(e): return e.done.call()).map(func(e): return str(e.title))
	if not finished.is_empty():
		children.append({"type": "spacer", "size": 6})
		children.append({"type": "label", "text": "Done: %s" % ", ".join(PackedStringArray(finished)), "size": 12, "color": "#8ce99a"})
	children.append({"type": "button", "text": "Close", "action": "close"})
	player.show_ui("hearthhold:charter", {"anchor": "center", "modal": true, "children": children})


func _hearth_lit() -> bool:
	return not api.find_block_data(api.block("hearthhold:lit_hearth")).is_empty() \
		or api.storage.get("hearth_lit", false)


func _seen_a_morning() -> bool:
	return api.storage.get("seen_morning", false)


func _bramble_recruited() -> bool:
	return api.storage.get("bramble_found", false)


func _bramble_home() -> bool:
	return api.storage.get("bramble_home", false)
