extends RefCounted
## Tools built from parts at the Tool Forge, using the engine's materials, part types and assemblies:
## make heads, handles and bindings from any material, then assemble a pickaxe, axe, shovel or sword
## whose stats and look come from its parts. The fixed wooden, stone and iron tools stay for the early
## game. Other mods add materials (vanilla bone, Guild gold, Arcana mana crystals).

const STATION := "tool_forge"

var api


func setup(mod_api, sounds: Dictionary) -> void:
	api = mod_api
	api.register_block("tool_forge", {"display_name": "Tool Forge", "station": STATION, "sounds": sounds.stone, "hardness": 4.0, "tier": 1,
		"tool": "pickaxe", "textures": {"top": "textures/anvil_top.png", "side": "textures/tool_rack.png", "bottom": "textures/cobblestone.png"}})
	api.register_recipe({"base:cobblestone": 4, "base:iron_ingot": 2, "base:planks": 4}, "base:tool_forge", 1, {"station": "crafting_table"})

	for part in [["pickaxe_head", "Pickaxe Head", 3], ["axe_head", "Axe Head", 3], ["shovel_head", "Shovel Head", 1],
			["sword_blade", "Sword Blade", 2], ["tool_handle", "Tool Handle", 1], ["binding", "Binding", 1],
			["sword_grip", "Sword Grip", 1], ["guard", "Guard", 1]]:
		api.register_part_type(part[0], {"display_name": part[1], "sprite": "textures/parts/%s.png" % part[0], "cost": part[2], "station": STATION})

	api.register_material("wood", {"display_name": "Wooden", "item": "base:planks", "color": "#a07a48", "tier": 1, "speed": 2.0,
		"durability": 60, "damage": 0.0, "handle": 1.0,
		"trait": {"name": "Light", "description": "attacks 10% faster", "modifiers": [{"stat": "attack_cooldown", "amount": -0.1, "op": "multiply"}]}})
	api.register_material("stone", {"display_name": "Stone", "item": "base:cobblestone", "color": "#8e8e92", "tier": 2, "speed": 4.0,
		"durability": 130, "damage": 1.0, "handle": 0.8,
		"trait": {"name": "Sturdy", "description": "+15% durability", "durability_mult": 0.15}})
	api.register_material("iron", {"display_name": "Iron", "item": "base:iron_ingot", "color": "#dcdce2", "tier": 3, "speed": 6.0,
		"durability": 250, "damage": 2.0, "handle": 1.2,
		"trait": {"name": "Balanced", "description": "+10% mining speed", "speed_mult": 0.1}})

	var tool_slots := func(head: String) -> Array:
		return [{"name": "head", "part": head, "label": "Head"}, {"name": "handle", "part": "tool_handle", "label": "Handle"},
			{"name": "binding", "part": "binding", "label": "Binding"}]
	api.register_assembly("forged_pickaxe", {"display_name": "Pickaxe", "icon": "textures/iron_pickaxe.png", "slots": tool_slots.call("pickaxe_head"),
		"tool_type": "pickaxe", "damage": 2.0, "cooldown": 0.55, "station": STATION})
	api.register_assembly("forged_axe", {"display_name": "Axe", "icon": "textures/iron_axe.png", "slots": tool_slots.call("axe_head"),
		"tool_type": "axe", "damage": 3.0, "cooldown": 0.8, "station": STATION})
	api.register_assembly("forged_shovel", {"display_name": "Shovel", "icon": "textures/iron_shovel.png", "slots": tool_slots.call("shovel_head"),
		"tool_type": "shovel", "damage": 1.5, "cooldown": 0.5, "station": STATION})
	api.register_assembly("forged_sword", {"display_name": "Sword", "icon": "textures/iron_sword.png", "station": STATION,
		"slots": [{"name": "blade", "part": "sword_blade", "label": "Blade"}, {"name": "grip", "part": "sword_grip", "label": "Grip"},
			{"name": "guard", "part": "guard", "label": "Guard"}],
		"damage": 4.0, "cooldown": 0.6, "sweep": 0.3})
