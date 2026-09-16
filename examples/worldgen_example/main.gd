extends "res://engine/server/mod.gd"
## Shaping the world. Three levels, smallest first - most mods only ever want the first.
##
##   1. an ore pass: scatter a block through stone, in whatever game is running
##   2. a feature: something placed on the surface (a tree, a boulder, a patch)
##   3. a biome: your own stretch of world, with its own blocks and features
##
## World generation is decided once, when a chunk is first made, so these all run at load and a quick
## reload skips them (the engine handles that; /reload full applies changes to new chunks).
##
## Try it: godot --path . -- --host=vanilla,worldgen_example --dev

var api


func setup(mod_api) -> void:
	api = mod_api
	_an_ore()
	_a_feature()
	_a_biome()


## 1. An ore pass runs after whatever generator the game uses, so an add-on can put its ore in any world
## without knowing how that world is made. Here: coal, but only deep down and rarer than usual.
func _an_ore() -> void:
	api.add_ore_pass({
		"ore": "base:coal_ore",
		"replace": "base:stone",
		"veins": 2,      # tries per chunk
		"size": 5,       # blocks in a vein
		"min_y": 4,
		"max_y": 28,
		"chance": 0.5,   # of each vein actually appearing
	})


## 2. A feature is a thing placed on the surface. The engine has types for the usual shapes (tree,
## column, boulder, patch, mushroom) so most features are data, not code.
func _a_feature() -> void:
	api.register_feature("stone_cairn", {"type": "boulder", "block": "base:cobblestone", "radius": [1, 2]})


## 3. A biome, with the blocks it is made of and the features scattered over it. `temperature` and
## `humidity` decide where it lands on the world's climate map; `weight` how much of the map it gets.
func _a_biome() -> void:
	api.register_biome("quarry", {
		"display_name": "Old Quarry",
		"temperature": [0.35, 0.7],
		"humidity": [0.0, 0.35],
		"weight": 0.4,
		"surface": "base:gravel",
		"filler": "base:stone",
		"height": [64, 74],
		# A name without a ":" is this mod's own. Another mod's feature would be "vanilla:boulder", but
		# then this mod would have to depend on vanilla - an example is better off standing alone.
		"features": [
			{"feature": "stone_cairn", "chance": 0.25},
		],
	})
