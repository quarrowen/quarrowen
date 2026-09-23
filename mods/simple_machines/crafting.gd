extends RefCounted
## The everyday recipes: what `base`'s materials turn into at a crafting table, or in your hands.
##
## These lived in `base` beside the blocks they make, which read as natural and was the whole problem:
## **a recipe is a rule, and `base` owns nouns.** The test of the line is that a creative game takes
## `base` alone and ships zero recipes while everything still exists - so every one of these moved out
## on 2026-09-23, and `base` now registers none.
##
## Naming another pack's blocks is not a smell here; it is what a pack is for. The dependency runs one
## way (`simple_machines` -> `base`) and never back.


func setup(api) -> void:
	# Wood, asked of the tag rather than of a list. A mod that adds a tree and tags its log gets planks
	# for nothing - which is the same reason the furnace asks this question about fuel.
	for log_name: String in api.tagged("base:logs"):
		api.register_recipe({log_name: 1}, "base:planks", 4,
			{"unlock": "known", "id": "planks_from_" + log_name.get_slice(":", 1)})
	api.register_recipe({"base:planks": 2}, "base:stick", 4, {"unlock": "known"})

	api.register_recipe({"base:gravel": 2, "base:coal": 1}, "base:brick", 4)
	api.register_recipe({"base:cobblestone": 1}, "base:gravel", 1)
	api.register_recipe({"base:sand": 4}, "base:sandstone", 1, {"category": "blocks"})
	api.register_recipe({"base:planks": 4, "base:stick": 2}, "base:fence", 3, TABLE)
	api.register_recipe({"base:planks": 3, "base:hay_bale": 1}, "base:bed", 1,
		{"station": "crafting_table", "category": "blocks"})

	# Food and drink. The pot and its meals are next door in cooking.gd; these are the hand-made ones.
	api.register_recipe({"base:wheat": 3}, "base:bread", 1, {"category": "food"})
	api.register_recipe({"base:glass": 3}, "base:glass_bottle", 3, {"category": "materials"})
	api.register_recipe({"base:apple": 2, "base:glass_bottle": 1}, "base:apple_juice", 1, {"category": "food"})
	api.register_recipe({}, "base:hay_bale", 1, {"pattern": ["WWW", "WWW", "WWW"], "key": {"W": "base:wheat"},
		"unlock": "experiment", "category": "blocks"})
	api.register_recipe({"base:hay_bale": 1}, "base:wheat", 9, {"id": "wheat_from_hay"})

	# Shapes. `base` registers the blocks - a slab is a thing that exists - and cutting one out of a
	# full block is a rule, so it lives here. Named rather than derived: three materials that have not
	# changed since they were written, and a loop over a table in another mod's source is exactly the
	# cross-mod reach that cost us a morning today.
	for material in [{"id": "stone", "from": "base:stone"}, {"id": "cobblestone", "from": "base:cobblestone"},
			{"id": "planks", "from": "base:planks"}]:
		var slab := "base:%s_slab" % material.id
		api.register_recipe({String(material.from): 3}, slab, 6, TABLE)
		api.register_recipe({slab: 2}, String(material.from), 1, TABLE)
		api.register_recipe({String(material.from): 6}, "base:%s_stairs_north" % material.id, 4, TABLE)

	# Doors and panes: one item each, whichever way it ends up facing when you place it.
	api.register_recipe({"base:planks": 6}, "base:door_north", 2, {"station": "crafting_table", "unlock": "known"})
	api.register_recipe({"base:glass": 6}, "base:glass_pane_x", 16, {"station": "crafting_table", "category": "blocks"})
	api.register_recipe({"base:iron_ingot": 6}, "base:iron_bars_x", 8, {"station": "crafting_table", "category": "blocks"})


const TABLE := {"station": "crafting_table"}
