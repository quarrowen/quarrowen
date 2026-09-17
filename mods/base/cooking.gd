extends RefCounted
## The cooking pot: a station where several things go in and a meal comes out.
##
## It is a *station*, not a container like the furnace, because a meal is several ingredients rather than
## one thing melted. That means the recipe book already knows how to show it, recipes can be discovered
## the usual way, two players can cook together at the same pot, and stirring it by hand runs the quality
## minigame - so a child can serve Masterwork Mushroom Stew ★★★ with their name on it, which the engine
## already makes more filling (see engine/server/hunger.gd).
##
## base puts the pot and the bowls here; what goes in them belongs to whichever game is running
## (mods/vanilla/cooking.gd has the stews).

const STATION := "cooking_pot"

var api


func setup(mod_api, sounds: Dictionary) -> void:
	api = mod_api
	# Stirring: hold the spoon moving at the right pace. Too fast and it splashes, too slow and it catches.
	api.register_minigame("cooking", {"title": "Stir the pot", "type": "hold", "verb": "Stir",
		"duration": 7.0, "zone": 0.22, "speed": 0.7})
	api.register_block("cooking_pot", {"display_name": "Cooking Pot", "station": STATION, "sounds": sounds.get("stone", {}),
		"hardness": 3.0, "tier": 1, "tool": "pickaxe",
		"textures": {"top": "textures/cooking_pot_top.png", "side": "textures/cooking_pot_side.png",
			"bottom": "textures/furnace_side.png"}})
	api.register_recipe({"base:cobblestone": 5, "base:iron_ingot": 1}, "base:cooking_pot", 1, {"station": "crafting_table"})

	# Bowls: what a stew is served in, and they come back when you have eaten.
	api.register_item("bowl", {"display_name": "Bowl", "icon": "textures/bowl.png"})
	api.register_recipe({"base:planks": 3}, "base:bowl", 4, {"station": "crafting_table", "unlock": "known"})

	# One dish base can make on its own: everything else needs a game's own ingredients.
	api.register_item("apple_pie", {"display_name": "Apple Pie", "icon": "textures/apple_pie.png",
		"food": {"hunger": 8, "saturation": 9.0, "color": "#e8b45a", "heal": 2.0,
			"effects": [{"stat": "move_speed", "amount": 0.12, "op": "multiply", "seconds": 120, "message": "Warm and full - you feel quick"}]}})
	api.register_recipe({"base:apple": 2, "base:wheat": 2, "base:bowl": 1}, "base:apple_pie", 1,
		{"station": STATION, "skill": "base:cooking", "time": 6.0, "category": "food"})
