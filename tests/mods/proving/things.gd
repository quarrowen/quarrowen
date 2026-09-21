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
	ids.rock = api.register_block("rock", {"display_name": "Rock", "hardness": 1.5, "tool": "pickaxe", "tier": 1})
	ids.soil = api.register_block("soil", {"display_name": "Soil", "hardness": 0.6, "tool": "shovel"})
	ids.turf = api.register_block("turf", {"display_name": "Turf", "hardness": 0.6, "tool": "shovel"})
	ids.plain = api.register_block("plain", {"display_name": "Plain Block", "hardness": 1.0, "tool": "pickaxe", "tier": 1})
	ids.lamp = api.register_block("lamp", {"display_name": "Lamp", "hardness": 0.5, "light": 14})
	ids.crate = api.register_block("crate", {"display_name": "Crate", "hardness": 1.5, "container": "crate"})
	ids.bench = api.register_block("bench", {"display_name": "Bench", "hardness": 1.5, "station": "bench"})
	# The shapes that are not a full cube, so collision and meshing are covered.
	ids.step = api.register_block("step", {"display_name": "Step", "hardness": 1.0, "shape": "slab"})
	ids.post = api.register_block("post", {"display_name": "Post", "hardness": 1.0, "shape": "fence"})
	api.register_container("crate", {"title": "Crate",
		"groups": [{"name": "items", "count": 6}, {"name": "fuel", "count": 1, "accepts": "fuel"}],
		"progress": [{"name": "work", "label": "Work", "color": "#80ff80"}]})
	api.register_station("bench", {"workshop": {"radius": 2,
		"upgrades": [{"block": "proving:lamp", "title": "Bright", "grants": {"features": ["bright"]}}]}})
	ids.token = api.register_item("token", {"display_name": "Token", "max_stack": 16})
	ids.rod = api.register_item("rod", {"display_name": "Rod"})
	ids.grain = api.register_item("grain", {"display_name": "Grain", "food": {"hunger": 3, "saturation": 2.0}})
	ids.prod = api.register_item("prod", {"display_name": "Prod",
		"durability": 40, "tool": {"type": "pickaxe", "tier": 2, "speed": 5.0},
		"weapon": {"damage": 3.0, "cooldown": 0.6}})
	api.register_recipe({"proving:rock": 2}, "proving:plain", 1, {"unlock": "known"})
	api.register_recipe({"proving:plain": 1, "proving:rod": 1}, "proving:prod", 1, {"station": "bench"})
	api.register_process("grinding", "proving:plain", "proving:rock", 1, 2.0)
	api.set_fuel("proving:token", 20.0)
	api.register_loot("crate_loot", {"pools": [
		{"rolls": 1, "guaranteed": true, "entries": [{"item": "proving:token", "count": [1, 3]}]}]})
	api.tag("prods", ["proving:prod"])
	api.register_modifier("keen", {"display_name": "Keen", "max_level": 3,
		"per_level": [{"stat": "attack_damage", "amount": 1.0}], "applies_to": ["#proving:prods"]})
	api.register_block_tick("lamp", func(ctx):
		api.set_block_data(ctx.position, {"ticked": int(api.get_block_data(ctx.position).get("ticked", 0)) + 1}),
		{"interval": 5, "random": false})
