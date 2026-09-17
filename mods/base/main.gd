extends "res://engine/server/mod.gd"
## Registers the shared block set, material sounds, basic tools and food. Other mods refer to these
## as "base:<name>".

const Farming = preload("farming.gd")
const Stations = preload("stations.gd")
const Forging = preload("forging.gd")
const Beds = preload("beds.gd")
const Nature = preload("nature.gd")
const Guide = preload("guide.gd")
const Graves = preload("graves.gd")
const Cooking = preload("cooking.gd")
const Openings = preload("openings.gd")
const TABLE := {"station": "crafting_table"}
## Iron gear needs an anvil beside the table; iron armor also needs a Sturdy Workbench.
## Iron gear can also be forged by hand at the anvil for better quality (the "forging" minigame).
const METALWORK := {"station": "crafting_table", "needs": ["metalwork"], "skill": "base:forging"}
const ARMORY := {"station": "crafting_table", "needs": ["metalwork"], "tier": 2, "time": 6.0, "skill": "base:forging"}
## [name, slot, ...] - the armor pieces every armor-bearing material gets, in the order their numbers
## are written in the materials table.
const ARMOR_PIECES := [["helmet", "head"], ["chestplate", "chest"], ["leggings", "legs"], ["boots", "feet"]]

var farming := Farming.new()
var stations := Stations.new()
var forging := Forging.new()
var beds := Beds.new()
var nature := Nature.new()
var guide := Guide.new()
var graves := Graves.new()
var cooking := Cooking.new()
var openings := Openings.new()


func setup(api) -> void:
	api.register_sound("stone", ["sounds/stone_break0.wav", "sounds/stone_break1.wav"])
	api.register_sound("stone_step", ["sounds/stone_step0.wav", "sounds/stone_step1.wav", "sounds/stone_step2.wav"], {"volume": 0.6})
	api.register_sound("wood", ["sounds/wood_break0.wav", "sounds/wood_break1.wav"])
	api.register_sound("wood_step", ["sounds/wood_step0.wav", "sounds/wood_step1.wav", "sounds/wood_step2.wav"], {"volume": 0.6})
	api.register_sound("dirt", ["sounds/dirt_break0.wav", "sounds/dirt_break1.wav"])
	api.register_sound("grass", ["sounds/grass_break0.wav", "sounds/grass_break1.wav"])
	api.register_sound("sand", ["sounds/sand_break0.wav", "sounds/sand_break1.wav"])
	api.register_sound("soft_step", ["sounds/soft_step0.wav", "sounds/soft_step1.wav", "sounds/soft_step2.wav"], {"volume": 0.6})
	api.register_sound("glass", "sounds/glass_break.wav")
	api.register_sound("eat", "sounds/eat.wav")
	var stone := {"break": "stone", "place": "stone", "step": "stone_step"}
	var wood := {"break": "wood", "place": "wood", "step": "wood_step"}
	var dirt := {"break": "dirt", "place": "dirt", "step": "soft_step"}
	var grass := {"break": "grass", "place": "grass", "step": "soft_step"}
	var sand := {"break": "sand", "place": "sand", "step": "soft_step"}

	api.register_block("stone", {"textures": "textures/stone.png", "drops": "base:cobblestone", "sounds": stone, "hardness": 1.5, "tier": 1, "tool": "pickaxe"})
	api.register_block("cobblestone", {"textures": "textures/cobblestone.png", "sounds": stone, "hardness": 2.0, "tier": 1, "tool": "pickaxe"})
	api.register_block("dirt", {"textures": "textures/dirt.png", "sounds": dirt, "hardness": 0.5, "tool": "shovel"})
	api.register_block("grass", {
		"textures": {"top": "textures/grass_top.png", "side": "textures/grass_side.png", "bottom": "textures/dirt.png"},
		"drops": "base:dirt",
		"sounds": grass,
		"hardness": 0.6, "tool": "shovel",
	})
	api.register_block("snow", {
		"textures": {"top": "textures/snow.png", "side": "textures/snow_side.png", "bottom": "textures/dirt.png"},
		"drops": "base:dirt",
		"sounds": grass,
		"hardness": 0.6, "tool": "shovel",
	})
	api.register_block("sand", {"textures": "textures/sand.png", "sounds": sand, "hardness": 0.5, "tool": "shovel"})
	api.register_block("gravel", {"textures": "textures/gravel.png", "sounds": sand, "hardness": 0.6, "tool": "shovel"})
	api.register_block("log", {"textures": {"all": "textures/log_side.png", "top": "textures/log_top.png", "bottom": "textures/log_top.png"}, "sounds": wood, "hardness": 2.0, "tool": "axe"})
	api.register_block("leaves", {"textures": "textures/leaves.png", "render": "cutout", "drops": "", "sway": true, "sounds": grass, "hardness": 0.2})
	api.register_block("planks", {"textures": "textures/planks.png", "sounds": wood, "hardness": 2.0, "tool": "axe"})
	api.register_block("brick", {"textures": "textures/brick.png", "sounds": stone, "hardness": 2.0, "tier": 1, "tool": "pickaxe"})
	api.register_block("glass", {"textures": "textures/glass.png", "render": "cutout", "cull_same": true, "drops": "", "hardness": 0.3,
		"sounds": {"break": "glass", "place": "stone", "step": "stone_step"}})
	api.register_item("coal", {"icon": "textures/coal.png"})
	api.register_block("coal_ore", {"textures": "textures/coal_ore.png", "display_name": "Coal Ore", "drops": "base:coal", "sounds": stone, "hardness": 3.0, "tier": 1, "tool": "pickaxe"})
	api.register_block("iron_ore", {"textures": "textures/iron_ore.png", "display_name": "Iron Ore", "sounds": stone, "hardness": 3.0, "tier": 2, "tool": "pickaxe"})
	api.register_block("water", {"textures": "textures/water.png", "render": "translucent", "liquid": true})
	api.register_block("bedrock", {"textures": "textures/bedrock.png", "breakable": false, "placeable": false, "sounds": stone})

	# Food: hold use to eat (hunger points out of 20; saturation keeps you full for longer).
	api.register_item("apple", {"display_name": "Apple", "icon": "textures/apple.png", "food": {"hunger": 4, "saturation": 2.4, "color": "#d83030"}})

	api.register_recipe({"base:log": 1}, "base:planks", 4, {"unlock": "known"})
	api.register_recipe({"base:gravel": 2, "base:coal": 1}, "base:brick", 4)
	api.register_recipe({"base:cobblestone": 1}, "base:gravel", 1)
	_register_tools(api)
	_register_shapes(api, {"stone": stone, "wood": wood})
	farming.setup(api, {"dirt": dirt, "grass": grass})
	nature.setup(api, {"wood": wood, "grass": grass, "stone": stone})
	_register_charms(api)  # after nature: the charms are made of deepstone, which nature registers
	stations.setup(api, {"wood": wood, "stone": stone})
	forging.setup(api, {"stone": stone})
	beds.setup(api, {"wood": wood})
	graves.setup(api, {"stone": stone})
	cooking.setup(api, {"stone": stone, "wood": wood})
	openings.setup(api, {"stone": stone, "wood": wood})
	guide.setup(api)


## A charm slot, and three things to put in it.
##
## Armor is the only thing that changes what a character is good at, and armor is a straight line: more
## of it is better. A charm is a choice instead - you may have one, so wearing the miner's charm means
## not wearing the traveller's. That is where the interesting decisions live, and it is where mods should
## put effects that are not "more armor".
##
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
		api.register_recipe(recipe, "base:" + charm[0], 1, ARMORY)


## Basic tiered tools, swords and armor. Tiers: 1 wood, 2 stone, 3 iron, 4 cobalt (stone needs tier 1,
## iron ore tier 2, cobalt ore tier 3, and only cobalt tools bring up deepstone). Other mods can add
## tiers above or new tool types entirely.
##
## A material is one row in the table below and everything else follows from it, armor included: adding
## cobalt meant adding a row, which is the point. A ladder where each rung is written out by hand is a
## ladder where the fourth rung quietly disagrees with the third.
func _register_tools(api) -> void:
	api.register_item("stick", {"icon": "textures/stick.png"})
	api.register_item("iron_ingot", {"display_name": "Iron Ingot", "icon": "textures/iron_ingot.png"})
	api.register_item("cobalt_ingot", {"display_name": "Cobalt Ingot", "icon": "textures/cobalt_ingot.png"})
	api.register_recipe({"base:planks": 2}, "base:stick", 4, {"unlock": "known"})
	var materials := [
		{"name": "wooden", "display": "Wooden", "tier": 1, "speed": 2.0, "durability": 60, "damage": 4.0, "input": "base:planks"},
		{"name": "stone", "display": "Stone", "tier": 2, "speed": 4.0, "durability": 130, "damage": 5.0, "input": "base:cobblestone"},
		{"name": "iron", "display": "Iron", "tier": 3, "speed": 6.0, "durability": 250, "damage": 6.0, "input": "base:iron_ingot",
			"armor": {"durability": 180, "points": [2.0, 6.0, 5.0, 2.0], "cost": [5, 8, 7, 4]}},
		{"name": "cobalt", "display": "Cobalt", "tier": 4, "speed": 8.5, "durability": 520, "damage": 7.0, "input": "base:cobalt_ingot",
			"armor": {"durability": 420, "points": [3.0, 8.0, 6.0, 3.0], "cost": [5, 8, 7, 4], "toughness": 1.0}},
	]
	for m in materials:
		var station: Dictionary = METALWORK if m.tier >= 3 else TABLE
		for tool in [["pickaxe", 3, 2.0], ["axe", 3, 3.0], ["shovel", 1, 1.5]]:
			var item_name := "%s_%s" % [m.name, tool[0]]
			api.register_item(item_name, {"display_name": "%s %s" % [m.display, String(tool[0]).capitalize()], "icon": "textures/%s.png" % item_name,
				"durability": m.durability, "tool": {"type": tool[0], "tier": m.tier, "speed": m.speed},
				"weapon": {"damage": tool[2] + m.tier * 0.5, "cooldown": 0.8 if tool[0] == "axe" else 0.5}})
			api.register_recipe({m.input: tool[1], "base:stick": 2}, "base:" + item_name, 1, station)
		api.register_item("%s_sword" % m.name, {"display_name": "%s Sword" % m.display, "icon": "textures/%s_sword.png" % m.name,
			"durability": m.durability, "weapon": {"damage": m.damage, "cooldown": 0.6, "sweep": 0.3},
			"trail": {"color": "#ffffff60", "width": 0.45}})
		api.register_recipe({m.input: 2, "base:stick": 1}, "base:%s_sword" % m.name, 1, station)
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
			api.register_recipe({m.input: armor.cost[i]}, "base:%s_%s" % [m.name, piece[0]], 1, ARMORY)


## Blocks that do not fill their cell: slabs (half a block, walked onto without jumping), stairs (four
## facings, one item that places the one facing you) and a fence (a post you cannot jump over).
func _register_shapes(api, sounds: Dictionary) -> void:
	# In the order BlockRegistry.facing_from_yaw gives: the variant that climbs away from the player.
	var facings := ["north", "west", "south", "east"]
	for material in [
		{"id": "stone", "from": "base:stone", "display": "Stone", "sound": "stone", "hardness": 1.5, "tool": "pickaxe", "tier": 1},
		{"id": "cobblestone", "from": "base:cobblestone", "display": "Cobblestone", "sound": "stone", "hardness": 2.0, "tool": "pickaxe", "tier": 1},
		{"id": "planks", "from": "base:planks", "display": "Wooden", "sound": "wood", "hardness": 1.2, "tool": "axe", "tier": 0},
	]:
		var textures = api.block_textures(String(material.from))
		var common := {"textures": textures, "sounds": sounds.get(String(material.sound), {}),
			"hardness": float(material.hardness), "tool": String(material.tool), "tier": int(material.tier)}
		# One slab in the hand, two in the world: which half it fills follows where you aimed, so a slab
		# can be a ceiling as well as a step. You never carry the top one, and it drops the bottom one.
		var slab_name := "%s_slab" % material.id
		var slab := common.duplicate(true)
		slab.merge({"display_name": "%s Slab" % material.display, "shape": "slab",
			"top_block": "base:%s_slab_top" % material.id, "full_block": String(material.from)}, true)
		api.register_block(slab_name, slab)
		var slab_top := common.duplicate(true)
		slab_top.merge({"display_name": "%s Slab" % material.display, "shape": "slab_top",
			"placeable": false, "drops": "base:" + slab_name, "full_block": String(material.from)}, true)
		api.register_block("%s_slab_top" % material.id, slab_top)
		api.register_recipe({String(material.from): 3}, "base:" + slab_name, 6, {"station": "crafting_table"})
		api.register_recipe({"base:" + slab_name: 2}, String(material.from), 1, {"station": "crafting_table"})

		var variant_names := []
		for facing in facings:
			variant_names.append("base:%s_stairs_%s" % [material.id, facing])
		for i in facings.size():
			var stairs := common.duplicate(true)
			stairs.merge({"display_name": "%s Stairs" % material.display, "shape": "stairs_%s" % facings[i],
				"facing_blocks": variant_names, "drops": variant_names[0]}, true)
			if i > 0:
				stairs.placeable = false  # you always carry the north one; placing turns it to face you
			api.register_block("%s_stairs_%s" % [material.id, facings[i]], stairs)
		api.register_recipe({String(material.from): 6}, variant_names[0], 4, {"station": "crafting_table"})

	# A fence joins up with whatever is beside it: sixteen forms, one per combination of the four sides,
	# swapped by the engine when anything next to it changes (engine/server/connect.gd). Only the lone
	# post is ever carried, and every form drops that one.
	var sides := ["n", "e", "s", "w"]
	var forms := []
	for mask in 16:
		var suffix := ""
		for bit in 4:
			if mask & (1 << bit):
				suffix += sides[bit]
		forms.append("base:fence" if suffix.is_empty() else "base:fence_%s" % suffix)
	for mask in 16:
		var fence := {"display_name": "Fence", "textures": api.block_textures("base:planks"),
			"sounds": sounds.get("wood", {}), "hardness": 1.2, "tool": "axe", "render": "cutout",
			"connect_group": "fence", "connects": forms, "drops": "base:fence",
			"shape": "fence_%s" % (forms[mask].get_slice("_", 1) if mask > 0 else "post")}
		if mask > 0:
			fence.placeable = false  # placing the post is enough; it joins up by itself
		api.register_block(forms[mask].get_slice(":", 1), fence)
	api.register_recipe({"base:planks": 4, "base:stick": 2}, "base:fence", 3, {"station": "crafting_table"})
