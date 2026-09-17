extends RefCounted
## Vanilla's world: the engine biome generator with classic biomes. Each biome's place in climate
## space (temperature, humidity, peaks) decides where it appears; trees and plants come from features.
## Rare fantasy biomes sit at the extremes of weirdness: glowing mushroom fields and the dark shadowwood.

var api


func setup(mod_api) -> void:
	api = mod_api
	api.use_biome_generator({"sea_level": 46, "snow_level": 92})
	_blocks()
	_features()
	_biomes()
	# Caves, caverns, ravines, cave lakes and lava down deep.
	api.add_cave_carver({"tunnels": true, "caverns": true, "ravines": true, "lava": "base:lava", "lava_level": 10, "water_level": 22})
	# Ores by depth: coal high, iron in the middle, cobalt deep near the lava.
	api.add_ore_pass({"ore": "base:coal_ore", "replace": "base:stone", "veins": 14, "size": 9, "min_y": 20, "max_y": 110})
	api.add_ore_pass({"ore": "base:iron_ore", "replace": "base:stone", "veins": 9, "size": 6, "min_y": 5, "max_y": 64})
	api.add_ore_pass({"ore": "base:cobalt_ore", "replace": "base:stone", "veins": 3, "size": 4, "min_y": 4, "max_y": 24})
	# Deepstone in thick seams right at the bottom, where only a cobalt pickaxe reaches it.
	api.add_ore_pass({"ore": "base:deepstone", "replace": "base:stone", "veins": 6, "size": 14, "min_y": 1, "max_y": 14})


func _blocks() -> void:
	var soft := {"break": "base:grass", "place": "base:grass", "step": "base:soft_step"}
	var wood := {"break": "base:wood", "place": "base:wood", "step": "base:wood_step"}
	api.register_block("mycelium", {"display_name": "Sporeturf", "sounds": soft, "hardness": 0.6, "tool": "shovel", "drops": "base:dirt",
		"textures": {"all": "textures/mycelium_side.png", "top": "textures/mycelium_top.png", "bottom": "base:textures/dirt.png"}})
	api.register_block("mushroom_cap", {"display_name": "Mushroom Cap", "textures": "textures/mushroom_cap.png", "sounds": soft, "hardness": 0.3, "drops": "vanilla:red_mushroom"})
	api.register_block("mushroom_stem", {"display_name": "Mushroom Stem", "textures": "textures/mushroom_stem.png", "sounds": wood, "hardness": 0.3})
	api.register_block("glowcap", {"display_name": "Glowcap", "textures": "textures/glowcap.png", "sounds": soft, "hardness": 0.3, "light": 11,
		"drops": "vanilla:glow_mushroom"})
	api.register_block("red_mushroom", {"display_name": "Red Mushroom", "textures": "textures/red_mushroom.png", "render": "plant", "replaceable": true,
		"hardness": 0.0, "support": "solid", "sounds": soft})
	api.register_block("glow_mushroom", {"display_name": "Glow Mushroom", "textures": "textures/glow_mushroom.png", "render": "plant", "replaceable": true,
		"hardness": 0.0, "support": "solid", "light": 6, "sounds": soft})
	api.register_block("shadow_log", {"display_name": "Shadowwood Log", "sounds": wood, "hardness": 2.0, "tool": "axe",
		"textures": {"all": "textures/shadow_log_side.png", "top": "textures/shadow_log_top.png", "bottom": "textures/shadow_log_top.png"}})
	api.register_block("shadow_leaves", {"display_name": "Shadowwood Leaves", "textures": "textures/shadow_leaves.png", "render": "cutout",
		"drops": "", "sway": true, "sounds": soft, "hardness": 0.2})
	api.register_recipe({"vanilla:shadow_log": 1}, "base:planks", 4, {"unlock": "known", "id": "planks_from_shadow"})
	api.set_fuel("vanilla:shadow_log", 15.0)  # wood burns, whatever it grew from
	api.register_process("smelting", "vanilla:shadow_log", "base:charcoal", 1, 10.0)
	api.register_block("gloomgrass", {"display_name": "Gloomgrass", "sounds": soft, "hardness": 0.6, "tool": "shovel", "drops": "base:dirt",
		"textures": {"all": "textures/gloomgrass_side.png", "top": "textures/gloomgrass_top.png", "bottom": "base:textures/dirt.png"}})
	# Biome waters: glowing pools in the mushroom fields, murky water in the shadowwood.
	api.register_block("glowing_water", {"display_name": "Glowing Water", "textures": "textures/glowing_water.png", "render": "translucent", "liquid": true, "light": 9})
	api.register_block("gloom_water", {"display_name": "Gloom Water", "textures": "textures/gloom_water.png", "render": "translucent", "liquid": true})
	api.register_block("shadow_pod", {"display_name": "Shadow Pod", "textures": "textures/shadow_pod.png", "render": "plant", "solid": false,
		"hardness": 0.1, "light": 9, "sounds": soft, "drops": ""})
	api.register_block("nightbloom", {"display_name": "Nightbloom", "textures": "textures/nightbloom.png", "render": "plant", "replaceable": true,
		"hardness": 0.0, "support": "solid", "light": 4, "sway": true, "sounds": soft})


func _features() -> void:
	api.register_feature("oak", {"type": "tree", "trunk": "base:log", "leaves": "base:leaves", "height": [4, 6], "shape": "round"})
	api.register_feature("big_oak", {"type": "tree", "trunk": "base:log", "leaves": "base:leaves", "height": [6, 8], "shape": "blob"})
	api.register_feature("birch", {"type": "tree", "trunk": "base:birch_log", "leaves": "base:birch_leaves", "height": [5, 7], "shape": "tall"})
	api.register_feature("spruce", {"type": "tree", "trunk": "base:spruce_log", "leaves": "base:spruce_leaves", "height": [6, 9], "shape": "cone"})
	api.register_feature("acacia", {"type": "tree", "trunk": "base:acacia_log", "leaves": "base:acacia_leaves", "height": [4, 6], "shape": "flat"})
	api.register_feature("swamp_oak", {"type": "tree", "trunk": "base:log", "leaves": "base:leaves", "height": [4, 5], "shape": "blob"})
	api.register_feature("cactus", {"type": "column", "block": "base:cactus", "height": [1, 3]})
	api.register_feature("boulder", {"type": "boulder", "block": "base:cobblestone", "radius": [1, 2]})
	api.register_feature("flowers", {"type": "patch", "block": "base:poppy", "radius": [2, 3], "count": 6, "on": ["base:grass"]})
	api.register_feature("huge_mushroom", {"type": "mushroom", "stem": "vanilla:mushroom_stem", "cap": "vanilla:mushroom_cap", "height": [4, 7], "radius": [2, 3]})
	api.register_feature("huge_glowcap", {"type": "mushroom", "stem": "vanilla:mushroom_stem", "cap": "vanilla:glowcap", "light_block": "vanilla:glowcap", "height": [5, 8], "radius": [2, 3]})
	api.register_feature("shadow_tree", {"type": "tree", "trunk": "vanilla:shadow_log", "leaves": "vanilla:shadow_leaves", "height": [7, 10], "shape": "blob",
		"fruit": "vanilla:shadow_pod", "fruit_chance": 0.35})
	api.register_feature("dandelions", {"type": "patch", "block": "base:dandelion", "radius": [2, 3], "count": 6, "on": ["base:grass"]})


func _biomes() -> void:
	var grassy := [{"block": "base:tall_grass", "chance": 0.12, "on": ["base:grass"]}, {"block": "base:poppy", "chance": 0.006, "on": ["base:grass"]},
		{"block": "base:dandelion", "chance": 0.006, "on": ["base:grass"]}]
	api.register_biome("plains", {"climate": {"temperature": 0.2, "humidity": -0.35}, "height": {"base": 51, "variation": 3},
		"features": [{"feature": "oak", "per_chunk": 0.15}, {"feature": "dandelions", "per_chunk": 0.2}],
		"plants": [{"block": "base:tall_grass", "chance": 0.22, "on": ["base:grass"]}, {"block": "base:dandelion", "chance": 0.01, "on": ["base:grass"]}]})
	api.register_biome("forest", {"climate": {"temperature": 0.25, "humidity": 0.35}, "height": {"base": 53, "variation": 6},
		"features": [{"feature": "oak", "per_chunk": 5.0}, {"feature": "big_oak", "per_chunk": 0.6}, {"feature": "birch", "per_chunk": 1.0}], "plants": grassy})
	api.register_biome("birch_forest", {"display_name": "Birch Flower Forest", "climate": {"temperature": -0.05, "humidity": 0.05},
		"height": {"base": 53, "variation": 5},
		"features": [{"feature": "birch", "per_chunk": 4.5}, {"feature": "flowers", "per_chunk": 0.8}, {"feature": "dandelions", "per_chunk": 0.6}],
		"plants": [{"block": "base:tall_grass", "chance": 0.1, "on": ["base:grass"]}, {"block": "base:poppy", "chance": 0.03, "on": ["base:grass"]},
			{"block": "base:dandelion", "chance": 0.03, "on": ["base:grass"]}]})
	api.register_biome("taiga", {"climate": {"temperature": -0.4, "humidity": 0.3}, "height": {"base": 55, "variation": 6},
		"features": [{"feature": "spruce", "per_chunk": 5.0}, {"feature": "boulder", "per_chunk": 0.15}],
		"plants": [{"block": "base:fern", "chance": 0.1, "on": ["base:grass"]}, {"block": "base:tall_grass", "chance": 0.05, "on": ["base:grass"]}],
		"spawn_tags": ["wolves"]})
	api.register_biome("snowy_tundra", {"display_name": "Frozen Steppe", "climate": {"temperature": -0.65, "humidity": -0.25}, "height": {"base": 53, "variation": 3},
		"surface": {"top": "base:snow", "filler": "base:dirt", "beach": "base:snow"}, "features": [{"feature": "spruce", "per_chunk": 0.25}]})
	api.register_biome("desert", {"climate": {"temperature": 0.6, "humidity": -0.5}, "height": {"base": 52, "variation": 4},
		"surface": {"top": "base:sand", "filler": "base:sandstone", "depth": 4, "underwater": "base:sand"},
		"features": [{"feature": "cactus", "per_chunk": 1.2}],
		"plants": [{"block": "base:dead_bush", "chance": 0.01, "on": ["base:sand"]}]})
	api.register_biome("swamp", {"climate": {"temperature": 0.4, "humidity": 0.62}, "height": {"base": 45.2, "variation": 2.5},
		"surface": {"underwater": "base:dirt", "beach": ""},
		"features": [{"feature": "swamp_oak", "per_chunk": 2.0}],
		"plants": [{"block": "base:fern", "chance": 0.08, "on": ["base:grass"]}, {"block": "base:tall_grass", "chance": 0.1, "on": ["base:grass"]}]})
	api.register_biome("savanna", {"climate": {"temperature": 0.55, "humidity": -0.05}, "height": {"base": 54, "variation": 3},
		"features": [{"feature": "acacia", "per_chunk": 0.8}],
		"plants": [{"block": "base:tall_grass", "chance": 0.3, "on": ["base:grass"]}]})
	api.register_biome("mountains", {"climate": {"temperature": -0.1, "humidity": 0.0, "peaks": 0.85}, "height": {"base": 60, "variation": 8, "peaks": 80},
		"features": [{"feature": "spruce", "per_chunk": 0.6}, {"feature": "boulder", "per_chunk": 0.3}],
		"plants": [{"block": "base:tall_grass", "chance": 0.05, "on": ["base:grass"]}]})
	# Fantasy biomes: rare, at the far ends of weirdness.
	api.register_biome("mushroom_fields", {"display_name": "Glowcap Flats", "climate": {"temperature": 0.3, "humidity": 0.55, "weirdness": 0.8},
		"height": {"base": 50, "variation": 5}, "surface": {"top": "vanilla:mycelium", "beach": "vanilla:mycelium", "water": "vanilla:glowing_water"},
		"features": [{"feature": "huge_mushroom", "per_chunk": 1.2}, {"feature": "huge_glowcap", "per_chunk": 0.8}],
		"plants": [{"block": "vanilla:red_mushroom", "chance": 0.04, "on": ["vanilla:mycelium"]}, {"block": "vanilla:glow_mushroom", "chance": 0.05, "on": ["vanilla:mycelium"]}]})
	api.register_biome("shadowwood", {"display_name": "Shadowwood", "climate": {"temperature": -0.15, "humidity": 0.45, "weirdness": -0.8},
		"height": {"base": 54, "variation": 6}, "surface": {"top": "vanilla:gloomgrass", "beach": "", "water": "vanilla:gloom_water"},
		"features": [{"feature": "shadow_tree", "per_chunk": 6.0}],
		"plants": [{"block": "base:fern", "chance": 0.1, "on": ["vanilla:gloomgrass"]}, {"block": "vanilla:nightbloom", "chance": 0.03, "on": ["vanilla:gloomgrass"]}]})
	api.register_biome("ocean", {"ocean": true, "climate": {}, "height": {"base": 34, "variation": 4},
		"surface": {"top": "base:sand", "filler": "base:sand", "underwater": "base:gravel"}})
