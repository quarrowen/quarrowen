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

	api.register_block("stone", {"textures": "textures/stone.png", "drops": "base:cobblestone", "sounds": stone})
	api.register_block("cobblestone", {"textures": "textures/cobblestone.png", "sounds": stone})
	api.register_block("dirt", {"textures": "textures/dirt.png", "sounds": dirt})
	api.register_block("grass", {
		"textures": {"top": "textures/grass_top.png", "side": "textures/grass_side.png", "bottom": "textures/dirt.png"},
		"drops": "base:dirt",
		"sounds": grass,
	})
	api.register_block("snow", {
		"textures": {"top": "textures/snow.png", "side": "textures/snow_side.png", "bottom": "textures/dirt.png"},
		"drops": "base:dirt",
		"sounds": grass,
	})
	api.register_block("sand", {"textures": "textures/sand.png", "sounds": sand})
	api.register_block("gravel", {"textures": "textures/gravel.png", "sounds": sand})
	api.register_block("log", {"textures": {"all": "textures/log_side.png", "top": "textures/log_top.png", "bottom": "textures/log_top.png"}, "sounds": wood})
	api.register_block("leaves", {"textures": "textures/leaves.png", "render": "cutout", "drops": "", "sway": true, "sounds": grass})
	api.register_block("planks", {"textures": "textures/planks.png", "sounds": wood})
	api.register_block("brick", {"textures": "textures/brick.png", "sounds": stone})
	api.register_block("glass", {"textures": "textures/glass.png", "render": "cutout", "cull_same": true, "drops": "",
		"sounds": {"break": "glass", "place": "stone", "step": "stone_step"}})
	api.register_item("coal", {"icon": "textures/coal.png"})
	api.register_block("coal_ore", {"textures": "textures/coal_ore.png", "display_name": "Coal Ore", "drops": "base:coal", "sounds": stone})
	api.register_block("iron_ore", {"textures": "textures/iron_ore.png", "display_name": "Iron Ore", "sounds": stone})
	api.register_block("water", {"textures": "textures/water.png", "render": "translucent", "liquid": true})
	api.register_block("bedrock", {"textures": "textures/bedrock.png", "breakable": false, "placeable": false, "sounds": stone})

	api.register_item("wooden_sword", {"display_name": "Wooden Sword", "icon": "textures/wooden_sword.png", "max_stack": 1, "attack_damage": 4})
	api.register_item("stone_sword", {"display_name": "Stone Sword", "icon": "textures/stone_sword.png", "max_stack": 1, "attack_damage": 5})
	var apple: int = api.register_item("apple", {"display_name": "Apple", "icon": "textures/apple.png", "usable": true})

	api.register_recipe({"base:log": 1}, "base:planks", 4)
	api.register_recipe({"base:sand": 1, "base:coal": 1}, "base:glass", 2)
	api.register_recipe({"base:gravel": 2, "base:coal": 1}, "base:brick", 4)
	api.register_recipe({"base:cobblestone": 1}, "base:gravel", 1)
	api.register_recipe({"base:planks": 2, "base:log": 1}, "base:wooden_sword")
	api.register_recipe({"base:cobblestone": 2, "base:log": 1}, "base:stone_sword")

	api.on("item_use", func(ev):
		if ev.item == apple:
			_eat(api, ev.player, apple))


func _eat(api, player, item: int) -> void:
	if player.health >= player.max_health:
		player.show_title("", "You are not hungry", 1.0)
	elif player.is_creative() or player.take(item, 1):
		player.heal(APPLE_HEAL)
		api.play_sound("eat", player.get_eye_position())
