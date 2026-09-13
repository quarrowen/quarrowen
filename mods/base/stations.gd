extends RefCounted
## Crafting table, chest and furnace, built from engine containers, stations, processing recipes,
## fuel values and scheduled block ticks.
##   crafting table: a station; tools, weapons, armor and machines need one
##   chest: 27 slots that keep their contents with the world and spill when broken
##   furnace: smelts with fuel over time, keeps working while nobody watches and catches up after
##            its chunk was unloaded; it glows while burning

const TABLE := "crafting_table"
const TICK := 0.5  # seconds between furnace updates while it works
const MAX_CATCH_UP := 3600.0

var api
var ids := {}


func setup(mod_api, sounds: Dictionary) -> void:
	api = mod_api
	ids.table = api.register_block("crafting_table", {"display_name": "Crafting Table", "station": TABLE, "sounds": sounds.wood,
		"textures": {"top": "textures/crafting_table_top.png", "side": "textures/crafting_table_side.png", "bottom": "textures/planks.png"},
		"hardness": 2.5, "tool": "axe"})
	api.register_recipe({"base:planks": 4}, "base:crafting_table")

	api.register_container("chest", {"title": "Chest", "groups": [{"name": "items", "count": 27, "columns": 9}]})
	ids.chest = api.register_block("chest", {"display_name": "Chest", "container": "chest", "sounds": sounds.wood,
		"textures": {"top": "textures/chest_top.png", "side": "textures/chest_side.png", "bottom": "textures/chest_top.png"},
		"hardness": 2.5, "tool": "axe"})
	api.register_recipe({"base:planks": 8}, "base:chest", 1, {"station": TABLE})

	api.register_container("furnace", {"title": "Furnace",
		"groups": [
			{"name": "input", "count": 1, "label": "Smelt"},
			{"name": "fuel", "count": 1, "label": "Fuel", "accepts": "fuel"},
			{"name": "output", "count": 1, "label": "Result", "take_only": true},
		],
		"progress": [{"name": "cook", "label": "Smelting", "color": "#f2f2f2"}, {"name": "burn", "label": "Fuel", "color": "#ff9a3c"}]})
	var furnace_textures := {"top": "textures/furnace_side.png", "bottom": "textures/furnace_side.png"}
	ids.furnace = api.register_block("furnace", {"display_name": "Furnace", "container": "furnace", "sounds": sounds.stone,
		"textures": furnace_textures.merged({"side": "textures/furnace_front.png"}), "hardness": 3.5, "tier": 1, "tool": "pickaxe"})
	ids.furnace_lit = api.register_block("furnace_lit", {"display_name": "Furnace", "container": "furnace", "sounds": sounds.stone,
		"textures": furnace_textures.merged({"side": "textures/furnace_front_lit.png"}), "light": 13, "drops": "base:furnace",
		"placeable": false, "hardness": 3.5, "tier": 1, "tool": "pickaxe"})
	api.register_recipe({"base:cobblestone": 8}, "base:furnace", 1, {"station": TABLE})

	api.register_item("charcoal", {"icon": "textures/charcoal.png"})
	for fuel in [["base:coal", 80.0], ["base:charcoal", 80.0], ["base:log", 15.0], ["base:planks", 15.0], ["base:crafting_table", 15.0],
			["base:chest", 15.0], ["base:stick", 5.0], ["base:sapling", 5.0], ["base:wooden_pickaxe", 10.0], ["base:wooden_axe", 10.0],
			["base:wooden_shovel", 10.0], ["base:wooden_sword", 10.0], ["base:wooden_hoe", 10.0]]:
		api.set_fuel(fuel[0], fuel[1])
	for recipe in [["base:iron_ore", "base:iron_ingot"], ["base:sand", "base:glass"], ["base:cobblestone", "base:stone"],
			["base:log", "base:charcoal"], ["base:clay", "base:brick"]]:
		if api.item(recipe[0]) > 0:
			api.register_process("smelting", recipe[0], recipe[1], 1, 10.0)

	api.on("container_changed", func(ev):
		if ev.container.type.name == "base:furnace":
			update_furnace(ev.position))
	for block_name in ["base:furnace", "base:furnace_lit"]:
		api.register_block_tick(block_name, func(ctx): update_furnace(ctx.position), {"interval": 3600.0, "catch_up": false})


## Advances a furnace by the world time since its last update: burns fuel, cooks the input, moves
## results to the output, lights or darkens the block and schedules the next update while working.
func update_furnace(pos: Vector3i) -> void:
	var c = api.get_container(pos)
	if c == null:
		return
	var s: Dictionary = c.state
	var now: float = api.get_world_clock()
	var elapsed := clampf(now - float(s.get("last", now)), 0.0, MAX_CATCH_UP)
	s.last = now
	var burn := float(s.get("burn", 0.0))
	var burn_total := maxf(float(s.get("burn_total", 1.0)), 0.001)
	var cook := float(s.get("cook", 0.0))
	while true:
		var recipe := _recipe(c)
		if burn <= 0.0:
			var fuel: Dictionary = c.get_item(c.group("fuel")[0])
			var seconds: float = api.get_fuel(fuel.item) if fuel.item > 0 else 0.0
			if recipe.is_empty() or seconds <= 0.0:
				break
			c.take(c.group("fuel")[0], 1)
			burn = seconds
			burn_total = seconds
		if elapsed <= 0.0:
			break
		var step := minf(elapsed, burn)
		if not recipe.is_empty():
			step = minf(step, float(recipe.seconds) - cook)
		burn -= step
		elapsed -= step
		if recipe.is_empty():
			cook = 0.0
		else:
			cook += step
			if cook >= float(recipe.seconds) - 0.0001:
				cook = 0.0
				c.take(c.group("input")[0], 1)
				c.add(recipe.output, recipe.count, {}, "output")
	var current := _recipe(c)
	if current.is_empty():
		cook = 0.0
	s.burn = burn
	s.burn_total = burn_total
	s.cook = cook
	c.set_progress("burn", burn / burn_total if burn > 0.0 else 0.0)
	c.set_progress("cook", cook / float(current.seconds) if not current.is_empty() else 0.0)
	var lit := burn > 0.0
	var block: int = api.get_block(pos)
	if lit != (block == ids.furnace_lit):
		api.set_block(pos, ids.furnace_lit if lit else ids.furnace, true, api.get_block_state(pos))
	if lit:
		api.schedule_block_tick(pos, TICK)


## The smelting recipe for the input if the output slot has room for its result, else {}.
func _recipe(c) -> Dictionary:
	var input: Dictionary = c.get_item(c.group("input")[0])
	if input.item <= 0:
		return {}
	var recipe: Dictionary = api.get_process("smelting", input.item)
	if recipe.is_empty():
		return {}
	var out: Dictionary = c.get_item(c.group("output")[0])
	if out.item > 0 and (out.item != recipe.output or not out.data.is_empty() or out.count + recipe.count > api.item_max_stack(recipe.output)):
		return {}
	return recipe
