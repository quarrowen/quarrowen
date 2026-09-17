extends RefCounted
## Doors and windows: the two things a house needs that a pile of blocks cannot give it.
##
## **Doors** are two blocks tall and swing open. Opening one does not need shapes of its own - an open
## door is the same thin panel against the next side round - so a door is eight blocks per material
## (four facings, open and shut) and the engine's existing shape table does the rest. The top half is a
## `pair` of the bottom, the way a bed's head is a pair of its foot, so breaking either takes both.
##
## **Windows** are panes: a thin sheet down the middle of a cell, in glass or in bars. They come in two
## axes, chosen from the way the player is facing when they place one, and they let light through.
##
## Both are for building rather than for surviving, which is most of what children do with the game.

const FACINGS := ["north", "east", "south", "west"]
## Which way a door swings: the panel moves one side anticlockwise when it opens.
const SWING := {"north": "west", "east": "north", "south": "east", "west": "south"}

var api
var ids := {}


func setup(mod_api, sounds: Dictionary) -> void:
	api = mod_api
	_doors(sounds)
	_windows(sounds)
	api.on("block_interact", _on_interact)


## One set of eight blocks per material: each facing, open and shut. Only the shut north one is ever
## carried; placing it picks the facing, and opening swaps the block under both halves.
func _doors(sounds: Dictionary) -> void:
	for wood in [{"id": "door", "display": "Wooden Door", "from": "base:planks", "hardness": 1.5, "tool": "axe"}]:
		var shut := []
		var open := []
		for facing in FACINGS:
			shut.append("base:%s_%s" % [wood.id, facing])
			open.append("base:%s_%s_open" % [wood.id, facing])
		for i in FACINGS.size():
			var facing: String = FACINGS[i]
			var common := {"display_name": wood.display, "sounds": sounds.get("wood", {}), "render": "cutout",
				"hardness": wood.hardness, "tool": wood.tool, "interactive": true,
				"textures": {"all": "textures/door_lower.png", "top": "textures/door_upper.png"}}
			# Shut: the panel sits against the side it is named for, and faces the player who placed it.
			var closed := common.duplicate(true)
			closed.merge({"shape": "door_%s" % facing, "facing_blocks": shut, "drops": shut[0],
				"pair": {"block": "base:%s_%s_top" % [wood.id, facing], "direction": "up"}}, true)
			if i > 0:
				closed.placeable = false  # you always carry the north one; placing turns it to face you
			api.register_block("%s_%s" % [wood.id, facing], closed)
			var closed_top := common.duplicate(true)
			closed_top.merge({"shape": "door_%s" % facing, "placeable": false, "drops": shut[0],
				"textures": {"all": "textures/door_upper.png"},
				"pair": {"block": "base:%s_%s" % [wood.id, facing], "direction": "down"}}, true)
			api.register_block("%s_%s_top" % [wood.id, facing], closed_top)
			# Open: the same panel, against the side it swings to. Never carried, never dropped as itself.
			var swung: String = SWING[facing]
			var ajar := common.duplicate(true)
			ajar.merge({"shape": "door_%s" % swung, "placeable": false, "drops": shut[0],
				"pair": {"block": "base:%s_%s_open_top" % [wood.id, facing], "direction": "up"}}, true)
			api.register_block("%s_%s_open" % [wood.id, facing], ajar)
			var ajar_top := common.duplicate(true)
			ajar_top.merge({"shape": "door_%s" % swung, "placeable": false, "drops": shut[0],
				"textures": {"all": "textures/door_upper.png"},
				"pair": {"block": "base:%s_%s_open" % [wood.id, facing], "direction": "down"}}, true)
			api.register_block("%s_%s_open_top" % [wood.id, facing], ajar_top)
		ids.door = api.block(shut[0])
		api.register_recipe({String(wood.from): 6}, shut[0], 2, {"station": "crafting_table", "unlock": "known"})


## Panes: glass to see through, bars to see through and not climb through. Placed along whichever axis
## suits the way the player is looking, so a window lines up with the wall it is in.
func _windows(sounds: Dictionary) -> void:
	for pane in [
		{"id": "glass_pane", "display": "Glass Pane", "from": "base:glass", "texture": "textures/glass.png",
			"render": "translucent", "hardness": 0.3, "sounds": "stone", "count": 16},
		{"id": "iron_bars", "display": "Iron Bars", "from": "base:iron_ingot", "texture": "textures/iron_bars.png",
			"render": "cutout", "hardness": 3.0, "sounds": "stone", "count": 8},
	]:
		var names := ["base:%s_x" % pane.id, "base:%s_z" % pane.id]
		# facing_blocks takes one block per facing, in the engine's order (north, west, south, east): a
		# player looking north or south is standing at a wall that runs east-west, so the pane spans x.
		var by_facing := [names[1], names[0], names[1], names[0]]
		for axis in ["x", "z"]:
			var def := {"display_name": pane.display, "textures": pane.texture, "render": pane.render,
				"shape": "pane_%s" % axis, "hardness": pane.hardness, "sounds": sounds.get(pane.sounds, {}),
				"drops": names[0], "facing_blocks": by_facing}
			if axis != "x":
				def.placeable = false
			api.register_block("%s_%s" % [pane.id, axis], def)
		api.register_recipe({String(pane.from): 6}, names[0], int(pane.count), {"station": "crafting_table", "category": "blocks"})


## Right-clicking a door swings it, both halves together. A door that is opened from either half behaves
## the same, which matters because a child will click whichever one is at eye level.
func _on_interact(ev: Dictionary) -> void:
	var name: String = api.block_name(ev.block)
	if not name.begins_with("base:door_"):
		return
	ev.cancelled = true
	var bottom: Vector3i = ev.position if not name.ends_with("_top") else ev.position + Vector3i.DOWN
	var at_bottom: String = api.block_name(api.get_block(bottom))
	var swapped: String = at_bottom.replace("_open", "") if at_bottom.contains("_open") else at_bottom + "_open"
	var lower: int = api.block(swapped)
	var upper: int = api.block(swapped + "_top")
	if lower <= 0 or upper <= 0:
		return
	# Both halves move together, and neither drops: this is the same door in a different position.
	api.set_block(bottom, lower)
	api.set_block(bottom + Vector3i.UP, upper)
	api.play_sound("base:wood", Vector3(bottom) + Vector3.ONE * 0.5, 0.7, 1.1 if swapped.contains("_open") else 0.9)
