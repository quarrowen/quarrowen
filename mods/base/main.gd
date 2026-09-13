extends "res://engine/server/mod.gd"
## Registers the shared block set. Other mods refer to these as "base:<name>".


func setup(api) -> void:
	api.register_block("stone", {"textures": "textures/stone.png", "drops": "base:cobblestone"})
	api.register_block("cobblestone", {"textures": "textures/cobblestone.png"})
	api.register_block("dirt", {"textures": "textures/dirt.png"})
	api.register_block("grass", {
		"textures": {"top": "textures/grass_top.png", "side": "textures/grass_side.png", "bottom": "textures/dirt.png"},
		"drops": "base:dirt",
	})
	api.register_block("snow", {
		"textures": {"top": "textures/snow.png", "side": "textures/snow_side.png", "bottom": "textures/dirt.png"},
		"drops": "base:dirt",
	})
	api.register_block("sand", {"textures": "textures/sand.png"})
	api.register_block("gravel", {"textures": "textures/gravel.png"})
	api.register_block("log", {"textures": {"all": "textures/log_side.png", "top": "textures/log_top.png", "bottom": "textures/log_top.png"}})
	api.register_block("leaves", {"textures": "textures/leaves.png", "render": "cutout", "drops": "", "sway": true})
	api.register_block("planks", {"textures": "textures/planks.png"})
	api.register_block("brick", {"textures": "textures/brick.png"})
	api.register_block("glass", {"textures": "textures/glass.png", "render": "cutout", "cull_same": true, "drops": ""})
	api.register_item("coal", {"icon": "textures/coal.png"})
	api.register_block("coal_ore", {"textures": "textures/coal_ore.png", "display_name": "Coal Ore", "drops": "base:coal"})
	api.register_block("iron_ore", {"textures": "textures/iron_ore.png", "display_name": "Iron Ore"})
	api.register_block("water", {"textures": "textures/water.png", "render": "translucent", "liquid": true})
	api.register_block("bedrock", {"textures": "textures/bedrock.png", "breakable": false, "placeable": false})

	api.register_recipe({"base:log": 1}, "base:planks", 4)
	api.register_recipe({"base:sand": 1, "base:coal": 1}, "base:glass", 2)
	api.register_recipe({"base:gravel": 2, "base:coal": 1}, "base:brick", 4)
	api.register_recipe({"base:cobblestone": 1}, "base:gravel", 1)
