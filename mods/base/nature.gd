extends RefCounted
## Blocks for biomes: birch, spruce and acacia trees (their logs make ordinary planks), cacti, sandstone,
## dead bushes and ferns. The vanilla game places them with the engine biome generator.


func setup(api, sounds: Dictionary) -> void:
	for wood in ["birch", "spruce", "acacia"]:
		api.register_block("%s_log" % wood, {"display_name": "%s Log" % wood.capitalize(), "sounds": sounds.wood, "hardness": 2.0, "tool": "axe",
			"textures": {"all": "textures/%s_log_side.png" % wood, "top": "textures/%s_log_top.png" % wood, "bottom": "textures/%s_log_top.png" % wood}})
		api.register_block("%s_leaves" % wood, {"display_name": "%s Leaves" % wood.capitalize(), "textures": "textures/%s_leaves.png" % wood,
			"render": "cutout", "drops": "", "sway": true, "sounds": sounds.grass, "hardness": 0.2})
		api.register_recipe({"base:%s_log" % wood: 1}, "base:planks", 4, {"unlock": "known", "id": "planks_from_%s" % wood})
	api.register_block("cactus", {"display_name": "Cactus", "sounds": sounds.grass, "hardness": 0.4, "hazard": true, "support": ["base:sand", "base:cactus"],
		"textures": {"all": "textures/cactus_side.png", "top": "textures/cactus_top.png", "bottom": "textures/cactus_top.png"}, "render": "cutout"})
	api.register_block("sandstone", {"display_name": "Sandstone", "sounds": sounds.stone, "hardness": 0.8, "tier": 1, "tool": "pickaxe",
		"textures": {"all": "textures/sandstone_side.png", "top": "textures/sandstone_top.png", "bottom": "textures/sandstone_top.png"}})
	api.register_recipe({"base:sand": 4}, "base:sandstone", 1, {"category": "blocks"})
	api.register_block("dead_bush", {"display_name": "Dead Bush", "textures": "textures/dead_bush.png", "render": "plant", "replaceable": true,
		"hardness": 0.0, "drops": "base:stick", "support": ["base:sand"], "sounds": sounds.grass})
	api.register_block("fern", {"display_name": "Fern", "textures": "textures/fern.png", "render": "plant", "replaceable": true, "sway": true,
		"hardness": 0.0, "drops": "", "support": "solid", "sounds": sounds.grass})
