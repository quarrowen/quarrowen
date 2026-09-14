extends RefCounted
## Vanilla's world: the engine biome generator with classic biomes. Each biome's place in climate
## space (temperature, humidity, peaks) decides where it appears; trees and plants come from features.

var api


func setup(mod_api) -> void:
	api = mod_api
	api.use_biome_generator({"sea_level": 46, "snow_level": 92})
	_features()
	_biomes()
	api.add_ore_pass({"ore": "base:coal_ore", "replace": "base:stone", "veins": 12, "size": 8, "min_y": 5, "max_y": 90})
	api.add_ore_pass({"ore": "base:iron_ore", "replace": "base:stone", "veins": 7, "size": 5, "min_y": 5, "max_y": 60})


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
	api.register_biome("snowy_tundra", {"display_name": "Snowy Tundra", "climate": {"temperature": -0.65, "humidity": -0.25}, "height": {"base": 53, "variation": 3},
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
	api.register_biome("ocean", {"ocean": true, "climate": {}, "height": {"base": 34, "variation": 4},
		"surface": {"top": "base:sand", "filler": "base:sand", "underwater": "base:gravel"}})
