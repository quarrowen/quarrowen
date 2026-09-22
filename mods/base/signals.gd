extends RefCounted
## Quickdust, quickstone and the two things worth wiring up: a lever to speak and a lamp to listen.
##
## This is *content*. The engine knows only that a block may emit a level, carry one, or be told when
## the level reaching it changes (engine/server/signals.gd); every name and every rule below is ours.
## "Quick" in the old sense - alive - so a block with a level reaching it is **quickened**.
##
## Deliberately small. Gates, delays and latches are blocks somebody can write on top of this, and the
## engine will not have an opinion about them either; what the base mod owes a player is the wire, a
## way to switch it on, and something that visibly happens when they do.

var api
var ids := {}


func setup(mod_api, materials: Dictionary) -> void:
	api = mod_api
	var sounds: Dictionary = materials.stone

	# The dust first: a block cannot name a drop that does not exist yet, and the validator says so.
	api.register_item("quickdust_item", {"display_name": "Quickdust", "icon": "textures/quickdust_item.png",
		"lore": ["Ground quickstone. Lay it in a line and it carries the spark."]})

	# The ore. It glows faintly where it sits, which is the point of the whole material: a seam of it in
	# a dark cave should be something a child spots and walks towards.
	api.register_block("quickstone", {"group": "Stone", "display_name": "Quickstone", "textures": "textures/quickstone.png",
		"light": 4, "hardness": 4.5, "tier": 1, "tool": "pickaxe", "drops": "base:quickdust_item",
		"sounds": sounds})

	# The wire, in two forms: quiet, and carrying. They are the same block to a player - the second is
	# what the first looks like when something reaches it - which is why breaking either gives the dust
	# back and only the quiet one can be placed.
	for form in [["quickdust", "textures/quickdust.png", 0], ["quickdust_lit", "textures/quickdust_lit.png", 7]]:
		api.register_block(form[0], {"group": "Mechanism", "display_name": "Quickdust", "textures": form[1], "render": "plant",
			"solid": false, "replaceable": true, "light": form[2], "hardness": 0.0, "support": "solid",
			"signal_carry": true, "placeable": form[0] == "quickdust",
			"drops": "base:quickdust_item", "sounds": sounds})

	# A lever: the simplest thing that can say yes. Right-click flips it, and it emits while it is on.
	api.register_block("lever", {"group": "Mechanism", "display_name": "Lever", "textures": "textures/lever.png", "render": "plant",
		"solid": false, "interactive": true, "hardness": 0.5, "support": "solid", "drops": "base:lever",
		"sounds": sounds})

	# A lamp: the simplest thing that can listen. Lit is the same lamp with the glow turned up.
	api.register_block("quicklamp", {"group": "Light", "display_name": "Quicklamp", "textures": "textures/quicklamp.png",
		"hardness": 1.0, "drops": "base:quicklamp", "sounds": sounds})
	api.register_block("quicklamp_lit", {"group": "Light", "display_name": "Quicklamp", "textures": "textures/quicklamp_lit.png",
		"light": 14, "hardness": 1.0, "drops": "base:quicklamp", "placeable": false, "sounds": sounds})

	for block_name in ["quickstone", "quickdust", "quickdust_lit", "lever", "quicklamp", "quicklamp_lit"]:
		ids[block_name] = api.block("base:" + block_name)

	api.register_recipe({"base:quickdust_item": 1}, "base:quickdust", 1, {})
	api.register_recipe({"base:planks": 1, "base:stick": 1}, "base:lever", 1, {})
	api.register_recipe({"base:glass": 4, "base:quickdust_item": 4, "base:iron_ingot": 1}, "base:quicklamp", 1,
		{"station": "crafting_table"})

	api.on("block_interact", func(ev):
		if api.get_block(ev.position) == ids.lever:
			_flip(ev.position, ev.player))

	# The wire shows what it is carrying, and the lamp shows what reaches it. Both are the same trick:
	# swap the block for its other form. Nothing else in the engine had to learn what a lamp is.
	for form in ["quickdust", "quickdust_lit"]:
		api.register_signal(form, func(ev): _show_wire(ev))
	for form in ["quicklamp", "quicklamp_lit"]:
		api.register_signal(form, func(ev): _show_lamp(ev))


## Flipping a lever: it emits at full strength or not at all. The block does not change - it is a lever
## either way - so what it is doing is remembered in its block data.
func _flip(position: Vector3i, player) -> void:
	var data: Dictionary = api.get_block_data(position).duplicate()
	var on: bool = not bool(data.get("on", false))
	data.on = on
	api.set_block_data(position, data)
	api.set_signal(position, 15 if on else 0)
	api.play_sound("engine:click", Vector3(position) + Vector3.ONE * 0.5, 1.0, 1.2 if on else 0.8)
	if on:
		api.play_effect("engine:sparkle", Vector3(position) + Vector3(0.5, 0.6, 0.5), {"scale": 0.8, "color": "#ffd070"})
	if player != null:
		player.send_message("The quickdust wakes up." if on else "It goes quiet.")


func _show_wire(ev: Dictionary) -> void:
	var wanted: int = ids.quickdust_lit if ev.level > 0 else ids.quickdust
	if api.get_block(ev.position) != wanted:
		api.set_block(ev.position, wanted, "", true)


func _show_lamp(ev: Dictionary) -> void:
	var wanted: int = ids.quicklamp_lit if ev.level > 0 else ids.quicklamp
	if api.get_block(ev.position) == wanted:
		return
	api.set_block(ev.position, wanted, "", true)
	if ev.level > 0:
		api.play_effect("engine:sparkle", Vector3(ev.position) + Vector3(0.5, 1.0, 0.5), {"scale": 1.0, "color": "#ffe8a0"})
