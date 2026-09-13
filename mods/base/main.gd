extends "res://engine/server/mod.gd"
## Registers the shared block set, material sounds, basic tools and food. Other mods refer to these
## as "base:<name>".

const APPLE_HEAL := 4.0


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

	var apple: int = api.register_item("apple", {"display_name": "Apple", "icon": "textures/apple.png", "usable": true})

	api.register_recipe({"base:log": 1}, "base:planks", 4)
	api.register_recipe({"base:sand": 1, "base:coal": 1}, "base:glass", 2)
	api.register_recipe({"base:gravel": 2, "base:coal": 1}, "base:brick", 4)
	api.register_recipe({"base:cobblestone": 1}, "base:gravel", 1)
	_register_tools(api)

	api.on("item_use", func(ev):
		if ev.item == apple:
			_eat(api, ev.player, apple))


## Basic tiered tools, swords and iron armor. Tiers: 1 wood, 2 stone, 3 iron (stone needs tier 1,
## iron ore tier 2). Other mods can add tiers above or new tool types entirely.
func _register_tools(api) -> void:
	api.register_item("stick", {"icon": "textures/stick.png"})
	api.register_item("iron_ingot", {"display_name": "Iron Ingot", "icon": "textures/iron_ingot.png"})
	api.register_recipe({"base:iron_ore": 1, "base:coal": 1}, "base:iron_ingot", 1)
	api.register_recipe({"base:planks": 2}, "base:stick", 4)
	var materials := [
		{"name": "wooden", "display": "Wooden", "tier": 1, "speed": 2.0, "durability": 60, "damage": 4.0, "input": "base:planks"},
		{"name": "stone", "display": "Stone", "tier": 2, "speed": 4.0, "durability": 130, "damage": 5.0, "input": "base:cobblestone"},
		{"name": "iron", "display": "Iron", "tier": 3, "speed": 6.0, "durability": 250, "damage": 6.0, "input": "base:iron_ingot"},
	]
	for m in materials:
		for tool in [["pickaxe", 3, 2.0], ["axe", 3, 3.0], ["shovel", 1, 1.5]]:
			var item_name := "%s_%s" % [m.name, tool[0]]
			api.register_item(item_name, {"display_name": "%s %s" % [m.display, String(tool[0]).capitalize()], "icon": "textures/%s.png" % item_name,
				"durability": m.durability, "tool": {"type": tool[0], "tier": m.tier, "speed": m.speed},
				"weapon": {"damage": tool[2] + m.tier * 0.5, "cooldown": 0.8 if tool[0] == "axe" else 0.5}})
			api.register_recipe({m.input: tool[1], "base:stick": 2}, "base:" + item_name)
		api.register_item("%s_sword" % m.name, {"display_name": "%s Sword" % m.display, "icon": "textures/%s_sword.png" % m.name,
			"durability": m.durability, "weapon": {"damage": m.damage, "cooldown": 0.6, "sweep": 0.3}})
		api.register_recipe({m.input: 2, "base:stick": 1}, "base:%s_sword" % m.name)
	var pieces := [["helmet", "head", 2.0, 5], ["chestplate", "chest", 6.0, 8], ["leggings", "legs", 5.0, 7], ["boots", "feet", 2.0, 4]]
	for piece in pieces:
		api.register_item("iron_%s" % piece[0], {"display_name": "Iron %s" % String(piece[0]).capitalize(), "icon": "textures/iron_%s.png" % piece[0],
			"equip_slot": piece[1], "durability": 180, "armor": {"armor": piece[2]}, "armor_texture": "textures/iron_armor.png"})
		api.register_recipe({"base:iron_ingot": piece[3]}, "base:iron_%s" % piece[0])


func _eat(api, player, item: int) -> void:
	if player.health >= player.max_health:
		player.show_title("", "You are not hungry", 1.0)
	elif player.is_creative() or player.take(item, 1):
		player.heal(APPLE_HEAL)
		api.play_sound("eat", player.get_eye_position())
