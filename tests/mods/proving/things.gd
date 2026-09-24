extends RefCounted
## Blocks, items, tools, containers, stations, recipes, loot: the things a world is made of.

var api
var ids: Dictionary


func setup(mod_api, id_table: Dictionary) -> void:
	api = mod_api
	ids = id_table
	# **No textures anywhere in this mod, on purpose.** The client draws a block with no texture as a
	# magenta checker (engine/client/texture_atlas.gd), which is both free and honest: nothing here is
	# meant to look like content. It also means this mod depends on no art, and so on no other mod.
	# `group` names the drawer this sits in in the creative palette. Here because a mod with 110
	# blocks needs it and a mod with two does not, so it would otherwise never be exercised.
	ids.rock = api.register_block("rock", {"display_name": "Rock", "hardness": 1.5, "tool": "pickaxe", "tier": 1,
		"group": "Ground"})
	ids.soil = api.register_block("soil", {"display_name": "Soil", "hardness": 0.6, "tool": "shovel"})
	ids.turf = api.register_block("turf", {"display_name": "Turf", "hardness": 0.6, "tool": "shovel"})
	ids.plain = api.register_block("plain", {"display_name": "Plain Block", "hardness": 1.0, "tool": "pickaxe", "tier": 1})
	ids.lamp = api.register_block("lamp", {"display_name": "Lamp", "hardness": 0.5, "light": 14})
	ids.crate = api.register_block("crate", {"display_name": "Crate", "hardness": 1.5, "container": "crate"})
	ids.bench = api.register_block("bench", {"display_name": "Bench", "hardness": 1.5, "station": "bench"})
	# The shapes that are not a full cube, so collision and meshing are covered.
	ids.step = api.register_block("step", {"display_name": "Step", "hardness": 1.0, "shape": "slab"})
	ids.post = api.register_block("post", {"display_name": "Post", "hardness": 1.0, "shape": "fence"})
	# A two-block thing, which had no user here: the half you carry, and the half that comes with it.
	# `placeable: false` on the far half is what keeps it out of the creative palette and out of a
	# player's hands, so this pair is also what proves the palette refuses it. (2026-09-23)
	# **Both halves of "any" and "exactly this".** `rock` and `plain` are the two members of one tag;
	# one recipe below takes either, the next insists on one of them. A machine wanting any plank and a
	# machine wanting oak are the same question. (the user, 2026-09-23)
	api.tag("rubble", ["proving:rock", "proving:plain"])
	api.register_recipe({"#proving:rubble": 2}, "proving:soil", 1, {"id": "soil_from_any_rubble"})
	api.register_recipe({"proving:rock": 4}, "proving:turf", 1, {"id": "turf_from_rock_only"})
	ids.mast = api.register_block("mast", {"display_name": "Mast", "hardness": 1.0,
		"pair": {"block": "proving:mast_top", "direction": "up"}})
	ids.mast_top = api.register_block("mast_top", {"display_name": "Mast Top", "hardness": 1.0,
		"placeable": false, "drops": "proving:mast", "pair": {"block": "proving:mast", "direction": "down"}})
	api.register_container("crate", {"title": "Crate",
		"groups": [{"name": "items", "count": 6}, {"name": "fuel", "count": 1, "accepts": "fuel"}],
		"progress": [{"name": "work", "label": "Work", "color": "#80ff80"}]})
	api.register_station("bench", {"workshop": {"radius": 2,
		"upgrades": [{"block": "proving:lamp", "title": "Bright", "grants": {"features": ["bright"]}}]}})
	# A slot of this mod's own, so equipment is not only the five the engine ships with.
	api.register_equipment_slot("charm", {"display_name": "Charm"})
	ids.token = api.register_item("token", {"display_name": "Token", "max_stack": 16})
	ids.charm = api.register_item("charm", {"display_name": "Charm", "equip_slot": "charm",
		"modifiers": [{"stat": "proving:resolve", "amount": 0.5, "op": "add"}]})
	ids.rod = api.register_item("rod", {"display_name": "Rod"})
	# Part-built tools and the minigame that grades them: three registries that had no user, which is
	# how a whole crafting style went untested. (2026-09-22)
	api.register_minigame("steady", {"title": "Hold Steady", "type": "timing", "verb": "Strike",
		"rounds": 3, "speed": 1.0, "zone": 0.25})
	api.register_part_type("head", {"display_name": "Head", "cost": 3, "station": "proving:bench"})
	api.register_part_type("handle", {"display_name": "Handle", "cost": 1, "station": "proving:bench"})
	api.register_assembly("prover", {"display_name": "Prover", "tool_type": "pickaxe", "damage": 3.0,
		"station": "proving:bench", "skill": "proving:steady",
		"slots": [{"name": "head", "part": "head", "label": "Head"},
			{"name": "grip", "part": "handle", "label": "Handle"}]})
	ids.grain = api.register_item("grain", {"display_name": "Grain", "food": {"hunger": 3, "saturation": 2.0}})
	# Food that disagrees with you. `effects` is a list of timed *stat modifiers*, not conditions -
	# food predates conditions and was never taught about them, which is worth knowing and is the sort
	# of gap this mod exists to surface. (2026-09-21)
	ids.spoiled = api.register_item("spoiled", {"display_name": "Spoiled Grain",
		"food": {"hunger": 2, "saturation": 0.5,
			"effects": [{"stat": "hunger_drain", "amount": 0.5, "seconds": 20.0,
				"message": "That was a mistake"}]}})
	# Everything an item can be made to look like: a glow, a trail, an effect when it lands.
	ids.prod = api.register_item("prod", {"display_name": "Prod",
		"glow": {"color": "#88ddff", "energy": 1.0}, "trail": {"color": "#88ddff90", "width": 0.4},
		"effects": {"hit": "proving:puff", "held": "proving:puff"},
		"durability": 40, "tool": {"type": "pickaxe", "tier": 2, "speed": 5.0},
		"weapon": {"damage": 3.0, "cooldown": 0.6}})
	api.register_recipe({"proving:rock": 2}, "proving:plain", 1, {"unlock": "known"})
	api.register_recipe({"proving:plain": 1, "proving:rod": 1}, "proving:prod", 1, {"station": "bench"})
	api.register_process("grinding", "proving:plain", "proving:rock", 1, 2.0)
	api.set_fuel("proving:token", 20.0)
	api.register_loot("crate_loot", {"pools": [
		{"rolls": 1, "guaranteed": true, "entries": [{"item": "proving:token", "count": [1, 3]}]}]})
	# The older name for the same thing. Covered because a mod written before the rename still calls it,
	# and an alias nothing exercises is an alias that can quietly stop working.
	api.register_loot_table("bench_loot", {"pools": [
		{"rolls": 1, "entries": [{"item": "proving:rod", "count": [1, 1]}]}]})
	api.tag("prods", ["proving:prod"])
	api.register_modifier("keen", {"display_name": "Keen", "max_level": 3,
		"per_level": [{"stat": "attack_damage", "amount": 1.0}], "applies_to": ["#proving:prods"]})
	# A mark that lights the world as well as changing a stat. Both halves on one mark on purpose: the
	# glow is written into the item's data beside the modifiers, and a mark that only did one of them
	# would not prove they coexist.
	api.register_modifier("kindled", {"display_name": "Kindled", "max_level": 2,
		"per_level": [{"stat": "attack_damage", "amount": 0.5}],
		"glow": {"color": "#ffcc88", "energy": 0.4, "light": 3.0}, "applies_to": ["#proving:prods"]})
	# A forge material of our own, so the parts-and-assembly capability is covered without base's.
	api.register_material("dull", {"display_name": "Dull", "item": "proving:token", "color": "#888888",
		"tier": 2, "speed": 4.0, "durability": 100, "damage": 1.0, "handle": 1.6,
		"trait": {"name": "Plain", "description": "nothing special", "speed_mult": 0.0}})
	# A source nothing could infer, so the declared half is covered too.
	api.register_source("proving:token", {"kind": "other", "from": "the keeper",
		"detail": "handed over for a favour", "chance": 0.5})
	_setup_area_tools()
	_setup_nested_inventories()
	api.register_block_tick("lamp", func(ctx):
		api.set_block_data(ctx.position, {"ticked": int(api.get_block_data(ctx.position).get("ticked", 0)) + 1}),
		{"interval": 5, "random": false})


## Area tools: all three built-in shapes, a shape of our own, and the preview.
##
## Commands rather than an item, because a test can run a command and cannot swing a pick. What the
## capability is actually for is a tool - "mine the whole vein", "flatten this" - and the shape of the
## API is the same either way: choose cells, show them, change them. (2026-09-21)
func _setup_area_tools() -> void:
	# A shape of our own, to prove a mod can add one. A vertical column, which none of the built-in
	# three describes: box needs two corners, sphere is a ball, vein follows one block kind.
	api.register_area_rule("column", func(ctx):
		var at: Vector3i = ctx.get("position", Vector3i.ZERO)
		var height: int = clampi(int(ctx.get("height", 4)), 1, 32)
		var out: Array = []
		for dy in height:
			out.append(at + Vector3i(0, dy, 0))
		return out)
	api.register_command("dig", "Mine the vein you are looking at", func(player, _args):
		var hit: Dictionary = api.raycast(player.get_eye_position(), api.look_direction(player), 6.0)
		if not bool(hit.get("hit", false)):
			player.send_message("Look at a block first.")
			return
		var at: Vector3i = hit.position
		var cells: Array = api.area_cells("vein", {"position": at, "player": player, "max": 64})
		var done: Dictionary = api.area_edit(player, cells, {"block": 0})
		player.send_message("Mined %d of %d." % [done.changed, cells.size()]))
	api.register_command("box", "Fill a 3x3x3 box with rock", func(player, _args):
		var at: Vector3i = Vector3i(player.position) + Vector3i(0, 1, 0)
		var cells: Array = api.area_cells("box", {"from": at - Vector3i(1, 0, 1), "to": at + Vector3i(1, 2, 1)})
		api.show_area(player, cells, {"seconds": 3.0})
		var done: Dictionary = api.area_edit(player, cells, {"block": api.require_block("proving:rock")})
		player.send_message("Placed %d." % done.changed))


## Inventories inside things: a bag you carry, and a store that is the same wherever you open it.
##
## Two halves of one capability, because both are containers whose contents do not live at a position
## - which is the whole reason the addressing had to stop being one. (2026-09-21)
func _setup_nested_inventories() -> void:
	api.register_container("satchel", {"title": "Satchel", "slots": 9})
	api.register_container("vault", {"title": "Vault", "slots": 18})
	ids.satchel = api.register_item("satchel", {"display_name": "Satchel", "max_stack": 1,
		"usable": true, "container": "proving:satchel"})
	# One vault for everybody, so a test can put something in as one player and take it out as another.
	api.shared_store("vault", "vault")
	api.register_command("satchel", "Open the satchel you are holding", func(player, _args):
		if not api.open_bag(player, player.selected_slot):
			player.send_message("Hold a satchel first."))
	api.register_command("vault", "Open the shared vault", func(player, _args):
		api.open_shared(player, "vault"))
