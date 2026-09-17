extends RefCounted
## The Hearthstone: the block that turns building into the thing the game counts.
##
## A house is not worked out from invisible rules about enclosed space - a child would never guess those,
## and "why is it not working" is the worst sentence a game can produce. You place a Hearthstone and it
## tells you, in a list with ticks, exactly what is still missing:
##
##     ✓ A bed within 6 blocks        ✗ A light
##     ✓ Walls around the bed          ✓ A roof over the bed
##     ✓ A door to come in by
##
## Every requirement is a thing a child can point at, and the list teaches the parts of a house by naming
## them. Once they all tick, somebody can live here.

const RADIUS := 6
const ROOF_HEIGHT := 8
## How bright a lamp or torch has to make it. Deliberately *block* light and not daylight: a house has to
## be lit at night, which is the whole point, and counting the sun would pass every open field at noon.
const MIN_LIGHT := 8

var api
var ids := {}


func setup(mod_api, sounds: Dictionary) -> void:
	api = mod_api
	ids.hearthstone = api.register_block("hearthstone", {"display_name": "Hearthstone",
		"textures": {"top": "textures/hearthstone_top.png", "side": "textures/hearthstone_side.png",
			"bottom": "textures/hearthstone_side.png"},
		"sounds": sounds.get("stone", {}), "hardness": 2.0, "tool": "pickaxe", "interactive": true,
		"light": 4})
	api.register_recipe({"base:cobblestone": 4, "base:torch": 1}, "hearthhold:hearthstone", 1,
		{"station": "crafting_table", "unlock": "known", "category": "blocks"})
	api.on("block_interact", func(ev):
		if ev.block == ids.hearthstone:
			ev.cancelled = true  # the panel is the interaction
			show_panel(ev.player, ev.position))
	# Marked with block data so the settlers can find every hearthstone in the world without searching it.
	api.on("block_placed", func(ev):
		if ev.block == ids.hearthstone and api.get_block_data(ev.position).is_empty():
			api.set_block_data(ev.position, {"hearthstone": true}))


## What a home needs, and how to tell whether this one has it. Each returns {ok, label, hint}.
##
func survey(pos: Vector3i) -> Array:
	var bed := _find_near(pos, func(p): return _is_bed(api.get_block(p)))
	var door := _find_near(pos, func(p): return _is_door(api.get_block(p)))
	var lit: bool = int(api.get_light_levels(pos + Vector3i.UP).get("block", 0)) >= MIN_LIGHT
	var roofed: bool = bed != Vector3i.MAX and _has_roof(bed)
	var walled: int = _walls_around(bed) if bed != Vector3i.MAX else 0
	return [
		{"ok": bed != Vector3i.MAX, "label": "A bed to sleep in", "hint": "Any bed, within %d blocks." % RADIUS},
		{"ok": walled >= 3, "label": "Walls around the bed", "hint": "Solid blocks on at least three sides of it (%d so far)." % walled},
		{"ok": roofed, "label": "A roof over the bed", "hint": "Something solid above where they sleep."},
		{"ok": lit, "label": "A light for the night", "hint": "A torch or a lamp by the hearthstone - the sun does not count."},
		{"ok": door != Vector3i.MAX, "label": "A door to come in by", "hint": "A wooden door in the wall, within %d blocks." % RADIUS},
	]


## True when everything is ticked and a settler could move in.
func is_home(pos: Vector3i) -> bool:
	return survey(pos).all(func(item): return item.ok)


## The list a player sees, ticking as they build. Deliberately a checklist and not a yes/no, so that
## "it does not work" is never the answer - it always says which part is missing.
func show_panel(player, pos: Vector3i) -> void:
	var items := survey(pos)
	var done: int = items.filter(func(item): return item.ok).size()
	var children: Array = [{"type": "label", "text": "Hearthstone", "size": 22, "color": "#ffd166"}]
	for item in items:
		children.append({"type": "label", "text": "%s  %s" % ["✓" if item.ok else "✗", item.label],
			"color": "#8ce99a" if item.ok else "#ffa8a8"})
		if not item.ok:
			children.append({"type": "label", "text": "     %s" % item.hint, "size": 12, "color": "#9aa4b8"})
	children.append({"type": "spacer", "size": 6})
	children.append({"type": "label", "text": _verdict(done, items.size())})
	children.append({"type": "button", "text": "Close", "action": "close"})
	player.show_ui("hearthhold:hearthstone", {"anchor": "center", "modal": true, "children": children})


func _verdict(done: int, total: int) -> String:
	if done == total:
		return "Somebody could live here."
	if done == total - 1:
		return "Nearly. One thing left."
	return "%d of %d. Keep going." % [done, total]


## The nearest block within RADIUS that `test` accepts, or Vector3i.MAX. Searched in rings so the answer
## is the closest one, which is what a player would point at.
func _find_near(pos: Vector3i, test: Callable) -> Vector3i:
	for r in range(1, RADIUS + 1):
		for x in range(-r, r + 1):
			for y in range(-3, 4):
				for z in range(-r, r + 1):
					if maxi(absi(x), absi(z)) != r:
						continue  # only the shell of this ring; the inside was searched already
					var at := pos + Vector3i(x, y, z)
					if test.call(at):
						return at
	return Vector3i.MAX


func _has_roof(bed: Vector3i) -> bool:
	for y in range(1, ROOF_HEIGHT + 1):
		if api.is_solid(api.get_block(bed + Vector3i(0, y, 0))):
			return true
	return false


## How many of the four sides around the bed are walled, somewhere in the two blocks above the floor.
func _walls_around(bed: Vector3i) -> int:
	var sides := 0
	for dir: Vector3i in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		for step in range(1, 4):
			var at: Vector3i = bed + dir * step
			if api.is_solid(api.get_block(at)) or api.is_solid(api.get_block(at + Vector3i.UP)):
				sides += 1
				break
	return sides


func _is_bed(block: int) -> bool:
	return block > 0 and api.block_name(block).contains("bed")


func _is_door(block: int) -> bool:
	return block > 0 and api.block_name(block).contains("door")
