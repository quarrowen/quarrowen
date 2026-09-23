extends "res://engine/server/mod.gd"
## Registers the shared block set, material sounds, basic tools and food. Other mods refer to these
## as "base:<name>".

const Farming = preload("farming.gd")
const Beds = preload("beds.gd")
const Nature = preload("nature.gd")
const Graves = preload("graves.gd")
const Openings = preload("openings.gd")
const Colours = preload("colours.gd")
## Iron gear needs an anvil beside the table; iron armor also needs a Sturdy Workbench.
## Iron gear can also be forged by hand at the anvil for better quality (the "forging" minigame).
## [name, slot, ...] - the armor pieces every armor-bearing material gets, in the order their numbers
## are written in the materials table.

var farming := Farming.new()
var beds := Beds.new()
var nature := Nature.new()
var graves := Graves.new()
var openings := Openings.new()
var colours := Colours.new()


func setup(api) -> void:
	api.register_sound("stone", ["sounds/stone_break0.ogg", "sounds/stone_break1.ogg"])
	api.register_sound("stone_step", ["sounds/stone_step0.ogg", "sounds/stone_step1.ogg", "sounds/stone_step2.ogg"], {"volume": 0.6})
	api.register_sound("wood", ["sounds/wood_break0.ogg", "sounds/wood_break1.ogg"])
	api.register_sound("wood_step", ["sounds/wood_step0.ogg", "sounds/wood_step1.ogg", "sounds/wood_step2.ogg"], {"volume": 0.6})
	api.register_sound("dirt", ["sounds/dirt_break0.ogg", "sounds/dirt_break1.ogg"])
	api.register_sound("grass", ["sounds/grass_break0.ogg", "sounds/grass_break1.ogg"])
	api.register_sound("sand", ["sounds/sand_break0.ogg", "sounds/sand_break1.ogg"])
	api.register_sound("soft_step", ["sounds/soft_step0.ogg", "sounds/soft_step1.ogg", "sounds/soft_step2.ogg"], {"volume": 0.6})
	api.register_sound("glass", "sounds/glass_break.ogg")
	api.register_sound("eat", "sounds/eat.wav")
	var stone := {"break": "stone", "place": "stone", "step": "stone_step"}
	var wood := {"break": "wood", "place": "wood", "step": "wood_step"}
	var dirt := {"break": "dirt", "place": "dirt", "step": "soft_step"}
	var grass := {"break": "grass", "place": "grass", "step": "soft_step"}
	var sand := {"break": "sand", "place": "sand", "step": "soft_step"}

	api.register_block("stone", {"group": "Stone", "textures": "textures/stone.png", "drops": "base:cobblestone", "sounds": stone, "hardness": 1.5, "tier": 1, "tool": "pickaxe"})
	api.register_block("cobblestone", {"group": "Stone", "textures": "textures/cobblestone.png", "sounds": stone, "hardness": 2.0, "tier": 1, "tool": "pickaxe"})
	api.register_block("dirt", {"group": "Ground", "textures": "textures/dirt.png", "sounds": dirt, "hardness": 0.5, "tool": "shovel"})
	api.register_block("grass", {"group": "Ground", 
		"textures": {"top": "textures/grass_top.png", "side": "textures/grass_side.png", "bottom": "textures/dirt.png"},
		"drops": "base:dirt",
		"sounds": grass,
		"hardness": 0.6, "tool": "shovel",
	})
	api.register_block("snow", {"group": "Ground", 
		"textures": {"top": "textures/snow.png", "side": "textures/snow_side.png", "bottom": "textures/dirt.png"},
		"drops": "base:dirt",
		"sounds": grass,
		"hardness": 0.6, "tool": "shovel",
	})
	api.register_block("sand", {"group": "Ground", "textures": "textures/sand.png", "sounds": sand, "hardness": 0.5, "tool": "shovel"})
	api.register_block("gravel", {"group": "Ground", "textures": "textures/gravel.png", "sounds": sand, "hardness": 0.6, "tool": "shovel"})
	api.register_block("log", {"group": "Wood", "textures": {"all": "textures/log_side.png", "top": "textures/log_top.png", "bottom": "textures/log_top.png"}, "sounds": wood, "hardness": 2.0, "tool": "axe"})
	api.register_block("leaves", {"group": "Wood", "textures": "textures/leaves.png", "render": "cutout", "drops": "", "sway": true, "sounds": grass, "hardness": 0.2})
	api.register_block("planks", {"group": "Wood", "textures": "textures/planks.png", "sounds": wood, "hardness": 2.0, "tool": "axe"})
	api.register_block("brick", {"group": "Stone", "textures": "textures/brick.png", "sounds": stone, "hardness": 2.0, "tier": 1, "tool": "pickaxe"})
	api.register_block("glass", {"group": "Glass", "textures": "textures/glass.png", "render": "cutout", "cull_same": true, "drops": "", "hardness": 0.3,
		"sounds": {"break": "glass", "place": "stone", "step": "stone_step"}})
	api.register_item("coal", {"icon": "textures/coal.png"})
	api.register_block("coal_ore", {"group": "Ore", "textures": "textures/coal_ore.png", "display_name": "Coal Ore", "drops": "base:coal", "sounds": stone, "hardness": 3.0, "tier": 1, "tool": "pickaxe"})
	api.register_block("iron_ore", {"group": "Ore", "textures": "textures/iron_ore.png", "display_name": "Iron Ore", "sounds": stone, "hardness": 3.0, "tier": 2, "tool": "pickaxe"})
	# Copper is shallow and everywhere and a wooden pickaxe brings it up: the first metal a child meets
	# should not be gated behind the second one.
	api.register_block("copper_ore", {"group": "Ore", "textures": "textures/copper_ore.png", "display_name": "Copper Ore", "sounds": stone, "hardness": 3.0, "tier": 1, "tool": "pickaxe"})
	api.register_block("gold_ore", {"group": "Ore", "textures": "textures/gold_ore.png", "display_name": "Gold Ore", "sounds": stone, "hardness": 3.0, "tier": 2, "tool": "pickaxe"})
	# Named for what it looks like rather than where it is: a stone that holds the light, found where
	# there is none. Deep, rare, and only cobalt tools will lift it.
	api.register_block("sunstone_ore", {"group": "Ore", "textures": "textures/sunstone_ore.png", "display_name": "Sunstone Ore",
		"drops": "base:sunstone", "sounds": stone, "hardness": 5.0, "tier": 4, "tool": "pickaxe"})
	# The same metals again, set in deepstone instead of stone. Harder to break and they look different,
	# so mining *down* is a different activity from mining *along* rather than the same one lower - and
	# the wall tells a child how deep they are without reading a coordinate.
	for deep in [["coal", "Coal", "base:coal", 1], ["iron", "Iron", "", 2], ["copper", "Copper", "", 1], ["gold", "Gold", "", 2]]:
		var def := {"group": "Ore", "textures": "textures/deep_%s_ore.png" % deep[0], "display_name": "Deep %s Ore" % deep[1],
			"sounds": stone, "hardness": 4.5, "tier": int(deep[3]), "tool": "pickaxe"}
		if not String(deep[2]).is_empty():
			def["drops"] = String(deep[2])
		api.register_block("deep_%s_ore" % deep[0], def)
	api.register_block("water", {"textures": "textures/water.png", "render": "translucent", "liquid": true})
	# The thin form, for water that has spread a few blocks: a slab, so it looks shallow and a player
	# wades through it rather than swimming - shapes decide collision as well as drawing.
	api.register_block("water_shallow", {"display_name": "Water", "textures": "textures/water.png",
		"render": "translucent", "liquid": true, "shape": "slab_bottom", "placeable": false, "drops": ""})
	api.register_block("bedrock", {"group": "Stone", "textures": "textures/bedrock.png", "breakable": false, "placeable": false, "sounds": stone})

	# Food: hold use to eat (hunger points out of 20; saturation keeps you full for longer).
	api.register_item("apple", {"display_name": "Apple", "icon": "textures/apple.png", "food": {"hunger": 4, "saturation": 2.4, "color": "#d83030"}})

	# Raw materials: nouns, so they stay here. What you *make* from them is `simple_gear`'s business.
	api.register_item("stick", {"group": "Materials", "icon": "textures/stick.png"})
	api.register_item("iron_ingot", {"group": "Materials", "display_name": "Iron Ingot", "icon": "textures/iron_ingot.png"})
	api.register_item("cobalt_ingot", {"group": "Materials", "display_name": "Cobalt Ingot", "icon": "textures/cobalt_ingot.png"})
	api.register_item("copper_ingot", {"group": "Materials", "display_name": "Copper Ingot", "icon": "textures/copper_ingot.png"})
	api.register_item("gold_ingot", {"group": "Materials", "display_name": "Gold Ingot", "icon": "textures/gold_ingot.png"})
	api.register_item("sunstone", {"group": "Materials", "display_name": "Sunstone", "icon": "textures/sunstone.png"})
	_register_shapes(api, {"stone": stone, "wood": wood})
	farming.setup(api, {"dirt": dirt, "grass": grass})
	nature.setup(api, {"wood": wood, "grass": grass, "stone": stone})
	beds.setup(api, {"wood": wood})
	graves.setup(api, {"stone": stone})
	openings.setup(api, {"stone": stone, "wood": wood})
	# After the sound dicts exist; nothing else depends on the colour sets, and nothing they depend on
	# comes later.
	colours.setup(api, {"dirt": dirt, "stone": stone})


## A charm slot, and three things to put in it.
##
## Armor is the only thing that changes what a character is good at, and armor is a straight line: more
## of it is better. A charm is a choice instead - you may have one, so wearing the miner's charm means
## not wearing the traveller's. That is where the interesting decisions live, and it is where mods should
## put effects that are not "more armor".
##
## Blocks that do not fill their cell: slabs (half a block, walked onto without jumping), stairs (four
## facings, one item that places the one facing you) and a fence (a post you cannot jump over).
func _register_shapes(api, sounds: Dictionary) -> void:
	# In the order BlockRegistry.facing_from_yaw gives: the variant that climbs away from the player.
	var facings := ["north", "west", "south", "east"]
	for material in [
		{"id": "stone", "from": "base:stone", "display": "Stone", "sound": "stone", "hardness": 1.5, "tool": "pickaxe", "tier": 1, "group": "Stone"},
		{"id": "cobblestone", "from": "base:cobblestone", "display": "Cobblestone", "sound": "stone", "hardness": 2.0, "tool": "pickaxe", "tier": 1, "group": "Stone"},
		{"id": "planks", "from": "base:planks", "display": "Wooden", "sound": "wood", "hardness": 1.2, "tool": "axe", "tier": 0, "group": "Wood"},
	]:
		var textures = api.block_textures(String(material.from))
		# A slab of stone belongs in the same drawer as the stone, not in a drawer of slabs: a builder
		# reaching for a material wants its shapes beside it.
		var common := {"textures": textures, "sounds": sounds.get(String(material.sound), {}),
			"hardness": float(material.hardness), "tool": String(material.tool), "tier": int(material.tier),
			"group": String(material.group)}
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
		var fence := {"group": "Wood", "display_name": "Fence", "textures": api.block_textures("base:planks"),
			"sounds": sounds.get("wood", {}), "hardness": 1.2, "tool": "axe", "render": "cutout",
			"connect_group": "fence", "connects": forms, "drops": "base:fence",
			"shape": "fence_%s" % (forms[mask].get_slice("_", 1) if mask > 0 else "post")}
		if mask > 0:
			fence.placeable = false  # placing the post is enough; it joins up by itself
		api.register_block(forms[mask].get_slice(":", 1), fence)
