extends RefCounted
## The world `base`'s blocks make: biomes, the things that grow on them, and what is in the ground.
##
## **A world is a noun.** `base` owns blocks, liquids, flora, fauna - and biomes, which are the rule
## for *where* those go rather than a rule for how to play. Until 2026-09-23 it owned none of this:
## the biomes lived in the seven games that were deleted, so `base` alone generated nothing and a
## player spawned into empty space and fell for ever. A pack of building blocks with nowhere to build
## is not finished.
##
## **One biome per generation technique that is genuinely different**, which is the principle Phase 4
## settled on rather than a tour of every climate. Seven, and each one does something the others do
## not: rolling land with trees, land with no trees at all, land that is mostly vertical, land under
## the sea, land under snow, land that is mostly water at the surface, and the one you fall into.
##
## **This declares; it does not install.** Registering a biome is saying "a meadow is grass, oaks and
## poppies" - a fact about the world's furniture. *Turning the biome generator on*, deciding how much
## iron is in the ground and whether there are caves are rules, and they belong to a game (see
## `mods/creative/`).
##
## That distinction was learned the hard way on 2026-09-23, and it is sharper than it sounds: ore
## passes, cave carvers and generation passes attach to the **realm**, not to the generator, so they
## run even over a game that installed a world generator of its own. `base` briefly added a deepstone
## layer here and it rewrote the AI arena's flat test floor into deepstone, which then survived a
## blast that was supposed to break it. A pack of nouns that quietly edits every world built on it is
## not a pack of nouns.

## Where the sea sits. The biome heights below are written against it, so a game that turns the
## generator on wants to pass this same number - `mods/creative/` does. Chosen so `height.base` values
## read as "under water" without anybody working it out: the lookbook lost an afternoon to terrain
## generated ten blocks under an ocean, because the engine's default base is 52 and its sea was 62.
const SEA_LEVEL := 62


func setup(api) -> void:
	_features(api)
	_biomes(api)


## Trees and the rest. Registered before the biomes that name them: a biome reads its feature list at
## registration, so a feature added afterwards is a name that resolves to nothing.
func _features(api) -> void:
	api.register_feature("oak", {"type": "tree", "trunk": "base:log", "leaves": "base:leaves",
		"height": [4, 6], "radius": [2, 2]})
	api.register_feature("birch", {"type": "tree", "trunk": "base:birch_log", "leaves": "base:birch_leaves",
		"height": [5, 7], "radius": [2, 2]})
	api.register_feature("spruce", {"type": "tree", "trunk": "base:spruce_log", "leaves": "base:spruce_leaves",
		"height": [6, 9], "radius": [2, 3]})
	api.register_feature("acacia", {"type": "tree", "trunk": "base:acacia_log", "leaves": "base:acacia_leaves",
		"height": [4, 5], "radius": [3, 3]})
	# A cactus is a column rather than a tree: no canopy, and it has to stand on sand.
	api.register_feature("cactus", {"type": "column", "block": "base:cactus", "height": [2, 4]})
	api.register_feature("boulder", {"type": "boulder", "block": "base:cobblestone", "radius": [1, 2]})
	api.register_feature("gravel_patch", {"type": "patch", "block": "base:gravel", "radius": [2, 3], "count": 8})


func _biomes(api) -> void:
	# The ordinary one: rolling, green, wooded. Most of the world, and the one a child starts in.
	api.register_biome("meadow", {
		"climate": {"temperature": 0.5, "humidity": 0.5},
		"height": {"base": 68.0, "variation": 6.0, "peaks": 10.0},
		"surface": {"top": "base:grass", "filler": "base:dirt", "beach": "base:sand",
			"underwater": "base:gravel", "stone": "base:stone", "water": "base:water"},
		"features": [{"feature": "oak", "per_chunk": 0.5}, {"feature": "birch", "per_chunk": 0.25},
			{"feature": "boulder", "per_chunk": 0.15}],
		"plants": [{"block": "base:tall_grass", "chance": 0.24, "on": ["base:grass"]},
			{"block": "base:poppy", "chance": 0.03, "on": ["base:grass"]},
			{"block": "base:dandelion", "chance": 0.03, "on": ["base:grass"]}],
	})
	# Trees close enough together to get lost in, which is a different technique from "a few trees":
	# the per-chunk counts are what make a forest rather than the block list.
	api.register_biome("forest", {
		"climate": {"temperature": 0.4, "humidity": 0.75},
		"height": {"base": 70.0, "variation": 5.0, "peaks": 8.0},
		"surface": {"top": "base:grass", "filler": "base:dirt", "beach": "base:sand",
			"underwater": "base:gravel", "stone": "base:stone", "water": "base:water"},
		"features": [{"feature": "spruce", "per_chunk": 2.2}, {"feature": "oak", "per_chunk": 1.1},
			{"feature": "boulder", "per_chunk": 0.2}],
		"plants": [{"block": "base:fern", "chance": 0.18, "on": ["base:grass"]},
			{"block": "base:tall_grass", "chance": 0.14, "on": ["base:grass"]}],
	})
	# No trees, sand all the way down, and the only plant is the one that does not want water.
	api.register_biome("desert", {
		"climate": {"temperature": 0.95, "humidity": 0.05},
		"height": {"base": 66.0, "variation": 4.0, "peaks": 6.0},
		"surface": {"top": "base:sand", "filler": "base:sand", "beach": "base:sand",
			"underwater": "base:sand", "stone": "base:sandstone", "water": "base:water"},
		"features": [{"feature": "cactus", "per_chunk": 0.5}, {"feature": "acacia", "per_chunk": 0.12}],
		"plants": [{"block": "base:dead_bush", "chance": 0.06, "on": ["base:sand"]}],
	})
	# Mostly vertical. `peaks` does the work here, not `variation` - the difference between hilly and
	# mountainous is which of those two is large.
	api.register_biome("peaks", {
		"climate": {"temperature": 0.2, "humidity": 0.3},
		"height": {"base": 80.0, "variation": 10.0, "peaks": 46.0},
		"surface": {"top": "base:grass", "filler": "base:dirt", "beach": "base:gravel",
			"underwater": "base:gravel", "stone": "base:stone", "water": "base:water"},
		"features": [{"feature": "spruce", "per_chunk": 0.3}, {"feature": "boulder", "per_chunk": 0.6}],
		"plants": [{"block": "base:tall_grass", "chance": 0.05, "on": ["base:grass"]}],
	})
	# Above the snow line the generator caps it with snow; this is the biome that lives up there.
	api.register_biome("tundra", {
		"climate": {"temperature": 0.02, "humidity": 0.4},
		"height": {"base": 72.0, "variation": 6.0, "peaks": 14.0},
		"surface": {"top": "base:snow", "filler": "base:dirt", "beach": "base:snow",
			"underwater": "base:gravel", "stone": "base:stone", "water": "base:water"},
		"features": [{"feature": "spruce", "per_chunk": 0.35}],
		"plants": [{"block": "base:dead_bush", "chance": 0.02, "on": ["base:snow"]}],
	})
	# Land that sits just under the waterline, so the surface is water with ground showing through.
	api.register_biome("marsh", {
		"climate": {"temperature": 0.6, "humidity": 0.95},
		"height": {"base": 61.0, "variation": 2.0, "peaks": 3.0},
		"surface": {"top": "base:grass", "filler": "base:dirt", "beach": "base:sand",
			"underwater": "base:dirt", "stone": "base:stone", "water": "base:water"},
		"features": [{"feature": "oak", "per_chunk": 0.4}, {"feature": "gravel_patch", "per_chunk": 0.3}],
		"plants": [{"block": "base:tall_grass", "chance": 0.3, "on": ["base:grass"]},
			{"block": "base:fern", "chance": 0.12, "on": ["base:grass"]}],
	})
	# The sea itself. `ocean: true` is what tells the generator this is meant to be under water rather
	# than a biome that happens to have drowned.
	api.register_biome("ocean", {
		"climate": {"temperature": 0.5, "humidity": 0.6},
		"ocean": true,
		"height": {"base": 40.0, "variation": 6.0, "peaks": 4.0},
		"surface": {"top": "base:gravel", "filler": "base:dirt", "beach": "base:sand",
			"underwater": "base:sand", "stone": "base:stone", "water": "base:water"},
		"features": [],
		"plants": [],
	})
