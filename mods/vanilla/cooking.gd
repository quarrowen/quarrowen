extends RefCounted
## What goes in the pot. The pot itself, the bowls and the stirring minigame are base's (mods/base/
## cooking.gd); these are the meals vanilla's own animals, mushrooms and flowers make.
##
## Every dish does something a player can feel for a while, so cooking is worth the trouble: the engine
## already applies `effects` from food as timed modifiers on any of its stats (engine/server/hunger.gd),
## and stirring well makes a meal Masterwork, which glows, carries the cook's name and fills more.
##
## Each one also uses something that previously had no use at all - eggs, mushrooms, nightbloom - so a
## child who picks up an odd thing now has somewhere to try it.

const POT := "cooking_pot"
const SKILL := "base:cooking"


func setup(api) -> void:
	# Mushroom Stew: the first real meal, from two mushrooms and a bowl.
	api.register_item("mushroom_stew", {"display_name": "Mushroom Stew", "icon": "textures/mushroom_stew.png",
		"food": {"hunger": 7, "saturation": 7.2, "color": "#c89a58", "remainder": "base:bowl",
			"effects": [{"stat": "exhaustion", "amount": -0.25, "op": "multiply", "seconds": 180,
				"message": "That will keep you going"}]}})
	api.register_recipe({"vanilla:red_mushroom": 2, "base:bowl": 1}, "vanilla:mushroom_stew", 1,
		{"station": POT, "skill": SKILL, "time": 5.0, "category": "food", "unlock": "known"})

	# Beef Stew: heavy food that makes you harder to knock about.
	api.register_item("beef_stew", {"display_name": "Beef Stew", "icon": "textures/beef_stew.png",
		"food": {"hunger": 10, "saturation": 12.0, "color": "#8c5228", "remainder": "base:bowl", "heal": 2.0,
			"effects": [{"stat": "knockback_resistance", "amount": 0.35, "seconds": 150, "message": "You feel solid"}]}})
	api.register_recipe({"vanilla:raw_beef": 1, "base:wheat": 1, "base:bowl": 1}, "vanilla:beef_stew", 1,
		{"station": POT, "skill": SKILL, "time": 8.0, "category": "food"})

	# Glowcap Soup: made from the mushroom that grows in the dark, and it lets you see further.
	api.register_item("glowcap_soup", {"display_name": "Glowcap Soup", "icon": "textures/glowcap_soup.png",
		"food": {"hunger": 6, "saturation": 6.0, "color": "#6fc08c", "remainder": "base:bowl",
			"effects": [{"stat": "reach", "amount": 1.5, "seconds": 120, "message": "Everything looks closer"}]}})
	api.register_recipe({"vanilla:glow_mushroom": 2, "vanilla:milk_bucket": 1, "base:bowl": 1}, "vanilla:glowcap_soup", 1,
		{"station": POT, "skill": SKILL, "time": 7.0, "category": "food"})

	# Honey Cake: what eggs are for. Worth the walk to a beehive of wheat and sugar-sweet nightbloom.
	api.register_item("honey_cake", {"display_name": "Honey Cake", "icon": "textures/honey_cake.png",
		"food": {"hunger": 9, "saturation": 10.0, "color": "#f0d070", "heal": 3.0,
			"effects": [{"stat": "move_speed", "amount": 0.18, "op": "multiply", "seconds": 150, "message": "Sugar! You feel fast"}]}})
	api.register_recipe({"vanilla:egg": 2, "base:wheat": 3, "vanilla:nightbloom": 1}, "vanilla:honey_cake", 1,
		{"station": POT, "skill": SKILL, "time": 10.0, "category": "food"})

	# Hearty Feast: the celebration dish, and the one worth cooking together before something difficult.
	api.register_item("hearty_feast", {"display_name": "Hearty Feast", "icon": "textures/hearty_feast.png",
		"food": {"hunger": 14, "saturation": 18.0, "color": "#d8b070", "remainder": "base:bowl", "heal": 6.0,
			"effects": [
				{"stat": "max_health", "amount": 4.0, "seconds": 240, "message": "A feast! You feel mighty"},
				{"stat": "attack_damage", "amount": 0.15, "op": "multiply", "seconds": 240},
			]}})
	api.register_recipe({"vanilla:steak": 1, "vanilla:cooked_chicken": 1, "base:bread": 1, "base:bowl": 1},
		"vanilla:hearty_feast", 1, {"station": POT, "skill": SKILL, "time": 14.0, "category": "food"})

	# Something to find out for yourself: the pot takes rotten flesh and gives back something edible.
	api.register_item("clean_broth", {"display_name": "Clean Broth", "icon": "textures/beef_stew.png",
		"food": {"hunger": 5, "saturation": 4.0, "color": "#a8b070", "remainder": "base:bowl"}})
	api.register_recipe({"vanilla:rotten_flesh": 2, "vanilla:milk_bucket": 1, "base:bowl": 1}, "vanilla:clean_broth", 1,
		{"station": POT, "skill": SKILL, "time": 6.0, "category": "food", "unlock": "experiment",
			"hint": "Even the worst meat is worth something boiled with milk."})
