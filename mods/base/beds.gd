extends RefCounted
## Beds: a two-block piece (foot placed where you click, head behind it). Right-click one to set your
## respawn point, and at night to sleep through it (see engine/server/sleep.gd). Straw beds for now;
## wool beds in colors can follow when sheep arrive.


func setup(api, sounds: Dictionary) -> void:
	var common := {"orientation": "horizontal", "bed": true, "hardness": 0.6, "tool": "axe", "sounds": sounds.wood,
		"drops": "base:bed", "textures": "textures/bed_icon.png"}
	var foot := common.duplicate()
	foot.merge({"display_name": "Bed", "model": "models/bed_foot.glb", "pair": {"block": "base:bed_head", "direction": "back"}})
	api.register_block("bed", foot)
	var head := common.duplicate()
	head.merge({"display_name": "Bed", "model": "models/bed_head.glb", "placeable": false, "pair": {"block": "base:bed", "direction": "front"}})
	api.register_block("bed_head", head)
	api.register_recipe({"base:planks": 3, "base:hay_bale": 1}, "base:bed", 1, {"station": "crafting_table", "category": "blocks"})
