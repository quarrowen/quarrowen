extends RefCounted
## Blocks, items, tools, containers, stations, recipes, loot: the things a world is made of.

var api
var ids: Dictionary


func setup(mod_api, id_table: Dictionary) -> void:
	api = mod_api
	ids = id_table
	var stone := {"break": "base:stone", "place": "base:stone", "step": "base:stone_step"}
	ids.plain = api.register_block("plain", {"display_name": "Plain Block", "textures": "base:textures/stone.png",
		"sounds": stone, "hardness": 1.0, "tool": "pickaxe", "tier": 1})
	ids.lamp = api.register_block("lamp", {"display_name": "Lamp", "textures": "base:textures/glass.png",
		"sounds": stone, "hardness": 0.5, "light": 14})
	ids.crate = api.register_block("crate", {"display_name": "Crate", "textures": "base:textures/planks.png",
		"sounds": stone, "hardness": 1.5, "container": "crate"})
	ids.bench = api.register_block("bench", {"display_name": "Bench", "textures": "base:textures/planks.png",
		"sounds": stone, "hardness": 1.5, "station": "bench"})
	api.register_container("crate", {"title": "Crate",
		"groups": [{"name": "items", "count": 6}, {"name": "fuel", "count": 1, "accepts": "fuel"}],
		"progress": [{"name": "work", "label": "Work", "color": "#80ff80"}]})
	api.register_station("bench", {"workshop": {"radius": 2,
		"upgrades": [{"block": "base:glass", "title": "Bright", "grants": {"features": ["bright"]}}]}})
	ids.token = api.register_item("token", {"display_name": "Token", "icon": "base:textures/coal.png",
		"max_stack": 16})
	ids.prod = api.register_item("prod", {"display_name": "Prod", "icon": "base:textures/stick.png",
		"durability": 40, "tool": {"type": "pickaxe", "tier": 2, "speed": 5.0},
		"weapon": {"damage": 3.0, "cooldown": 0.6}})
	api.register_recipe({"base:stone": 2}, "proving:plain", 1, {"unlock": "known"})
	api.register_recipe({"proving:plain": 1, "base:stick": 1}, "proving:prod", 1, {"station": "bench"})
	api.register_process("grinding", "proving:plain", "base:sand", 1, 2.0)
	api.set_fuel("proving:token", 20.0)
	api.register_loot("crate_loot", {"pools": [
		{"rolls": 1, "guaranteed": true, "entries": [{"item": "proving:token", "count": [1, 3]}]}]})
	# A named mark on a particular item, and the tag it is allowed on.
	api.tag("prods", ["proving:prod"])
	api.register_modifier("keen", {"display_name": "Keen", "max_level": 3,
		"per_level": [{"stat": "attack_damage", "amount": 1.0}], "applies_to": ["#proving:prods"]})
	# Something that ticks, so block ticks are covered.
	api.register_block_tick("lamp", func(ctx):
		api.set_block_data(ctx.position, {"ticked": int(api.get_block_data(ctx.position).get("ticked", 0)) + 1}),
		{"interval": 5, "random": false})
