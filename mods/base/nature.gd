extends RefCounted
## Blocks for biomes: birch, spruce and acacia trees (their logs make ordinary planks), cacti, sandstone,
## dead bushes and ferns. The vanilla game places them with the engine biome generator.


## The woods that grow in other biomes. They behave exactly like oak, including burning and charring
## (see stations.gd, which registers the fuels once charcoal exists).
const WOODS := ["birch", "spruce", "acacia"]


func setup(api, sounds: Dictionary) -> void:
	for wood in WOODS:
		api.register_block("%s_log" % wood, {"group": "Wood", "display_name": "%s Log" % wood.capitalize(), "sounds": sounds.wood, "hardness": 2.0, "tool": "axe",
			"textures": {"all": "textures/%s_log_side.png" % wood, "top": "textures/%s_log_top.png" % wood, "bottom": "textures/%s_log_top.png" % wood}})
		api.register_block("%s_leaves" % wood, {"group": "Wood", "display_name": "%s Leaves" % wood.capitalize(), "textures": "textures/%s_leaves.png" % wood,
			"render": "cutout", "drops": "", "sway": true, "sounds": sounds.grass, "hardness": 0.2})
		api.register_recipe({"base:%s_log" % wood: 1}, "base:planks", 4, {"unlock": "known", "id": "planks_from_%s" % wood})
	# **`base` says which of its blocks are logs; it does not say that logs burn.** That a log is fuel
	# is a rule and belongs to whatever pack wants it - `simple_machines` reads this tag. Before the
	# split, `simple_machines` preloaded this file for its `WOODS` constant, which is one mod reaching
	# into another's folder: it works until somebody moves a file, and it makes the pack impossible to
	# use without this exact layout. A tag is the supported way to ask. (2026-09-23)
	var logs := ["base:log"]
	for wood in WOODS:
		logs.append("base:%s_log" % wood)
	api.tag("logs", logs)
	api.register_block("cactus", {"group": "Nature", "display_name": "Cactus", "sounds": sounds.grass, "hardness": 0.4, "hazard": true, "support": ["base:sand", "base:cactus"],
		"textures": {"all": "textures/cactus_side.png", "top": "textures/cactus_top.png", "bottom": "textures/cactus_top.png"}, "render": "cutout"})
	api.register_block("sandstone", {"group": "Stone", "display_name": "Sandstone", "sounds": sounds.stone, "hardness": 0.8, "tier": 1, "tool": "pickaxe",
		"textures": {"all": "textures/sandstone_side.png", "top": "textures/sandstone_top.png", "bottom": "textures/sandstone_top.png"}})
	api.register_recipe({"base:sand": 4}, "base:sandstone", 1, {"category": "blocks"})
	api.register_block("dead_bush", {"group": "Nature", "display_name": "Dry Shrub", "textures": "textures/dead_bush.png", "render": "plant", "replaceable": true,
		"hardness": 0.0, "drops": "base:stick", "support": ["base:sand"], "sounds": sounds.grass})
	# Lava: fills the deepest caves; glows and burns.
	api.register_block("lava", {"display_name": "Lava", "textures": "textures/lava.png", "liquid": true, "light": 15, "hazard": true,
		"breakable": false, "placeable": false, "contact_damage": {"amount": 4.0, "interval": 0.5, "cause": "lava"}})
	# The black glass, where lava meets water. Hard enough to be a proper errand rather than a detour,
	# and the reason a bucket is worth carrying down a cave: it is the only way to make any.
	api.register_block("blackglass", {"group": "Glass", "display_name": "Blackglass", "textures": "textures/blackglass.png",
		"sounds": sounds.stone, "hardness": 22.0, "tier": 3, "tool": "pickaxe", "drops": "base:blackglass"})

	# Liquids that go somewhere. Water spreads seven blocks and falls; lava creeps three and is slow,
	# which is most of what makes it frightening rather than merely hot.
	api.register_liquid("water", {"range": 7, "falls": true, "speed": 0.22,
		"shallow": "base:water_shallow", "shallow_from": 4})
	api.register_liquid("lava", {"range": 3, "falls": true, "speed": 0.9})
	api.register_liquid_meeting("water", "lava", "base:blackglass")

	# Cobalt: a deep ore (below y 24) for later tool tiers; smelts into ingots.
	api.register_block("cobalt_ore", {"group": "Ore", "display_name": "Cobalt Ore", "textures": "textures/cobalt_ore.png", "sounds": sounds.stone, "hardness": 4.5,
		"tier": 3, "tool": "pickaxe"})
	# The ingot itself is registered with the tools it belongs to (main.gd _register_tools), because the
	# cobalt recipes are written there and a recipe cannot name an item that does not exist yet.
	# Deepstone: the floor of the world, and the reason cobalt tools are worth making. Nothing below tier 4
	# brings it up, so the ladder has a rung at the top that is about reaching somewhere rather than about
	# mining the same stone slightly faster.
	api.register_block("deepstone", {"group": "Stone", "display_name": "Deepstone", "textures": "textures/deepstone.png", "sounds": sounds.stone,
		"hardness": 6.0, "tier": 4, "tool": "pickaxe"})
	# Mob spawners (placed by structures; set what they spawn in block data, see engine/server/spawners.gd).
	api.register_block("spawner", {"group": "Special", "display_name": "Monster Nest", "textures": "textures/spawner.png", "render": "cutout", "spawner": true,
		"hardness": 5.0, "tier": 1, "tool": "pickaxe", "drops": "", "sounds": sounds.stone})
	# Portals take players to another server in this server's network (engine/server/transfers.gd): stand in
	# one. Admins set where it goes with /portal <server> [arrival] while standing next to it.
	api.register_block("portal", {"group": "Special", "display_name": "Portal", "textures": "textures/portal.png", "render": "translucent", "solid": false,
		"light": 11, "portal": true, "hardness": 2.0, "drops": "", "sounds": sounds.stone})
	api.register_block("fern", {"group": "Nature", "display_name": "Fern", "textures": "textures/fern.png", "render": "plant", "replaceable": true, "sway": true,
		"hardness": 0.0, "drops": "", "support": "solid", "sounds": sounds.grass})
