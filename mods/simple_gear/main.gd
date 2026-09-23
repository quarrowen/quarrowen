extends "res://engine/server/mod.gd"
## Tools, weapons, armour and charms - the verbs you hold. `base` says iron exists; this says what an
## iron pickaxe is and what it takes to make one.
##
## Split out of `base` on 2026-09-23 so the line holds: **a creative game takes `base` alone, ships
## zero recipes, and everything still exists.** Nothing in here is needed for a world to be a world.
##
## Depends on `simple_machines` because gear is made *at* something - the recipes below name the
## crafting table's station, and the Toolsmith's Bench is built at one.

const Forging = preload("forging.gd")

## Iron gear needs an anvil beside the table; iron armour also needs a Sturdy Workbench.
## Iron gear can also be forged by hand at the anvil for better quality (the "forging" minigame).
const TABLE := {"station": "crafting_table"}
const METALWORK := {"station": "crafting_table", "needs": ["metalwork"], "skill": "simple_gear:forging"}
const ARMORY := {"station": "crafting_table", "needs": ["metalwork"], "tier": 2, "time": 6.0, "skill": "simple_gear:forging"}
## [name, slot, ...] - the armour pieces every armour-bearing material gets, in the order their numbers
## are written in the materials table.
const ARMOR_PIECES := [["helmet", "head"], ["chestplate", "chest"], ["leggings", "legs"], ["boots", "feet"]]

var forging := Forging.new()


func setup(api) -> void:
	_register_tools(api)
	_register_charms(api)
	_register_hoes(api)
	forging.setup(api, {"stone": {"break": "base:stone", "place": "base:stone", "step": "base:stone_step"}})


## A material is one row in the table below and everything else follows from it, armor included: adding
## cobalt meant adding a row, which is the point. A ladder where each rung is written out by hand is a
## ladder where the fourth rung quietly disagrees with the third.
func _register_tools(api) -> void:
	var materials := [
		{"name": "wooden", "display": "Wooden", "tier": 1, "speed": 2.0, "durability": 60, "damage": 4.0, "input": "base:planks"},
		{"name": "stone", "display": "Stone", "tier": 2, "speed": 4.0, "durability": 130, "damage": 5.0, "input": "base:cobblestone"},
		{"name": "iron", "display": "Iron", "tier": 3, "speed": 6.0, "durability": 250, "damage": 6.0, "input": "base:iron_ingot",
			"armor": {"durability": 180, "points": [2.0, 6.0, 5.0, 2.0], "cost": [5, 8, 7, 4]}},
		{"name": "cobalt", "display": "Cobalt", "tier": 4, "speed": 8.5, "durability": 520, "damage": 7.0, "input": "base:cobalt_ingot",
			"armor": {"durability": 420, "points": [3.0, 8.0, 6.0, 3.0], "cost": [5, 8, 7, 4], "toughness": 1.0}},
		# Sidegrades, not rungs. Copper sits between stone and iron and is far easier to come by, so the
		# long stretch where a child has a stone pickaxe and nothing better is shorter. Gold is the
		# opposite bargain: quicker than anything until cobalt, and it breaks while you watch - which is
		# a lesson about trade-offs that costs nothing to learn.
		{"name": "copper", "display": "Copper", "tier": 2, "speed": 5.0, "durability": 180, "damage": 5.5, "input": "base:copper_ingot",
			"armor": {"durability": 140, "points": [2.0, 5.0, 4.0, 2.0], "cost": [5, 8, 7, 4]}},
		{"name": "gold", "display": "Gold", "tier": 3, "speed": 11.0, "durability": 70, "damage": 5.0, "input": "base:gold_ingot",
			"armor": {"durability": 90, "points": [2.0, 6.0, 5.0, 2.0], "cost": [5, 8, 7, 4]}},
		{"name": "sunstone", "display": "Sunstone", "tier": 5, "speed": 10.0, "durability": 900, "damage": 8.0, "input": "base:sunstone",
			"armor": {"durability": 700, "points": [3.0, 9.0, 7.0, 3.0], "cost": [5, 8, 7, 4], "toughness": 2.0}},
	]
	for m in materials:
		var station: Dictionary = METALWORK if m.tier >= 3 else TABLE
		for tool in [["pickaxe", 3, 2.0], ["axe", 3, 3.0], ["shovel", 1, 1.5]]:
			var item_name := "%s_%s" % [m.name, tool[0]]
			api.register_item(item_name, {"display_name": "%s %s" % [m.display, String(tool[0]).capitalize()], "icon": "textures/%s.png" % item_name,
				"durability": m.durability, "tool": {"type": tool[0], "tier": m.tier, "speed": m.speed},
				"weapon": {"damage": tool[2] + m.tier * 0.5, "cooldown": 0.8 if tool[0] == "axe" else 0.5}})
			api.register_recipe({m.input: tool[1], "base:stick": 2}, "simple_gear:" + item_name, 1, station)
		api.register_item("%s_sword" % m.name, {"display_name": "%s Sword" % m.display, "icon": "textures/%s_sword.png" % m.name,
			"durability": m.durability, "weapon": {"damage": m.damage, "cooldown": 0.6, "sweep": 0.3},
			"trail": {"color": "#ffffff60", "width": 0.45}})
		api.register_recipe({m.input: 2, "base:stick": 1}, "simple_gear:%s_sword" % m.name, 1, station)
		if not (m.get("armor") is Dictionary):
			continue
		var armor: Dictionary = m.armor
		for i in ARMOR_PIECES.size():
			var piece: Array = ARMOR_PIECES[i]
			var def := {"display_name": "%s %s" % [m.display, String(piece[0]).capitalize()],
				"icon": "textures/%s_%s.png" % [m.name, piece[0]], "equip_slot": piece[1],
				"durability": armor.durability, "armor": {"armor": armor.points[i]},
				"armor_texture": "textures/%s_armor.png" % m.name}
			if armor.has("toughness"):
				def.armor["toughness"] = armor.toughness
			api.register_item("%s_%s" % [m.name, piece[0]], def)
			api.register_recipe({m.input: armor.cost[i]}, "simple_gear:%s_%s" % [m.name, piece[0]], 1, ARMORY)


## Deepstone is the common ingredient on purpose: charms are the second thing a cobalt pickaxe buys.
func _register_charms(api) -> void:
	api.register_equipment_slot("trinket", {"display_name": "Charm"})
	# Each takes deepstone and one thing that says what it is for, so the three recipes are told apart by
	# what a child would guess anyway: coal for the miner, a stick for the walker, cobalt for the heavy one.
	var charms := [
		["miners_charm", "Miner's Charm", "A knot of deepstone that seems to want to be swung.",
			[{"stat": "mining_speed", "amount": 0.25, "op": "multiply"}], {"base:coal": 3}],
		["wayfarers_charm", "Wayfarer's Charm", "Light on its string, and the road feels shorter.",
			[{"stat": "move_speed", "amount": 0.12, "op": "multiply"}, {"stat": "exhaustion", "amount": -0.2, "op": "multiply"}],
			{"base:stick": 2}],
		["stoneheart_charm", "Stoneheart Charm", "Heavy, warm, and it does not let go of you.",
			[{"stat": "max_health", "amount": 4.0, "op": "add"}, {"stat": "knockback_resistance", "amount": 0.15, "op": "add"}],
			{"base:cobalt_ingot": 1}],
	]
	for charm in charms:
		api.register_item(charm[0], {"display_name": charm[1], "icon": "textures/%s.png" % charm[0],
			"equip_slot": "trinket", "lore": [charm[2]], "modifiers": charm[3], "max_stack": 1})
		var recipe: Dictionary = {"base:deepstone": 2}
		recipe.merge(charm[4])
		api.register_recipe(recipe, "simple_gear:" + charm[0], 1, ARMORY)


## Basic tiered tools, swords and armor. Tiers: 1 wood, 2 stone, 3 iron, 4 cobalt (stone needs tier 1,
## iron ore tier 2, cobalt ore tier 3, and only cobalt tools bring up deepstone). Other mods can add
## tiers above or new tool types entirely.
##


## Hoes, which `base` used to own because farmland was registered beside them. The tilling itself
## stayed behind: `base` asks any held item for its tool type now, so this pack owns the hoe and `base`
## owns the soil, which is the right way round. (2026-09-23)
func _register_hoes(api) -> void:
	for m in [{"name": "wooden", "input": "base:planks", "tier": 1, "durability": 60},
			{"name": "stone", "input": "base:cobblestone", "tier": 2, "durability": 130},
			{"name": "iron", "input": "base:iron_ingot", "tier": 3, "durability": 250}]:
		api.register_item("%s_hoe" % m.name, {"display_name": "%s Hoe" % m.name.capitalize(),
			"icon": "textures/%s_hoe.png" % m.name, "durability": m.durability, "usable": true,
			"tool": {"type": "hoe", "tier": m.tier, "speed": 1.0 + m.tier}, "weapon": {"damage": 1.0, "cooldown": 0.4}})
		api.register_recipe({m.input: 2, "base:stick": 2}, "simple_gear:%s_hoe" % m.name, 1,
			METALWORK if m.name == "iron" else TABLE)
