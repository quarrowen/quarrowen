extends RefCounted
## What the rare night creatures' curios turn into: gear that is *interesting* rather than better.
##
## **Sidegrades, not a fifth rung** (the user, 2026-09-23). The ladder in `main.gd` already says this
## is how the pack thinks - copper shortens the dull stretch after stone, gold is blistering and
## shatters while you watch - so a curio makes one good piece with one real drawback, and a player who
## never fights a rare creature reaches the same places by mining, just slower.
##
## **One curio makes one piece.** A Wisp drops a single Emberheart, so nothing here costs two of them:
## a set would mean farming a creature that is meant to be met a handful of times.
##
## Here rather than in a game, because this pack owns *what a thing is* - `base` says an Emberheart
## exists, this says what you can make of one, and a game decides whether any of it matters. What the
## Moonpearl charm actually *does* is a rule and lives in `mods/firstlight/`: the engine has no
## night-vision stat, so the effect is a condition a game gives and takes away. (2026-09-24)

## Built where iron gear is built: at the crafting table with an anvil beside it. These are not
## beginner items and the station says so without a word of text.
const METALWORK := {"station": "crafting_table", "needs": ["metalwork"]}


func setup(api) -> void:
	# **A pick that never wears out, and is otherwise an iron pick.** `durability: 0` is the engine's
	# "never" (see ItemRegistry). The trade is deliberate and is the whole point of a sidegrade: it
	# will not mine cobalt, it will not mine faster, and you will still want a cobalt pickaxe - but you
	# will never again lose one halfway down a shaft.
	api.register_item("emberheart_pick", {"group": "Tools", "display_name": "Emberheart Pick",
		"icon": "textures/emberheart_pick.png", "max_stack": 1, "durability": 0,
		"tool": {"type": "pickaxe", "tier": 3, "speed": 6.0},
		"weapon": {"damage": 5.0, "cooldown": 0.6},
		"glow": {"color": "#ffb45a", "energy": 0.5}})
	api.register_recipe({"base:emberheart": 1, "base:iron_ingot": 3, "base:stick": 2},
		"simple_gear:emberheart_pick", 1, METALWORK)

	# **Armour that shrugs off knockback and is heavy to move in.** A Barrow Warden barely moves when
	# hit, and this is that, worn: the knockback resistance is what makes a fight with something that
	# throws you around survivable, and the move speed is what you pay. Stands in for an iron
	# chestplate rather than beating one - the armour points are the same.
	api.register_item("warden_plate", {"group": "Armour", "display_name": "Warden Plate",
		"icon": "textures/warden_plate.png", "max_stack": 1, "durability": 400,
		"equip_slot": "chest", "armor_texture": "textures/warden_armor.png",
		"armor": {"armor": 6.0, "toughness": 2.0, "knockback_resistance": 0.8},
		"modifiers": [{"stat": "move_speed", "amount": 0.9, "op": "multiply"}]})
	api.register_recipe({"base:warden_core": 1, "base:iron_ingot": 5}, "simple_gear:warden_plate", 1, METALWORK)

	# **The charm does nothing on its own, on purpose.** Worn, it is a bead on a cord; a game decides
	# what the night does with it. `firstlight` gives a condition while it is dark that makes monsters
	# notice you later, which is the thing the engine has no stat for and an event can do.
	api.register_item("moonpearl_charm", {"group": "Curios", "display_name": "Moonpearl Charm",
		"icon": "textures/moonpearl_charm.png", "max_stack": 1, "equip_slot": "trinket",
		"lore": "Cold to hold. The dark seems to mind you less."})
	api.register_recipe({"base:moonpearl": 1, "base:cloth_white": 2}, "simple_gear:moonpearl_charm", 1,
		{"station": "crafting_table"})
