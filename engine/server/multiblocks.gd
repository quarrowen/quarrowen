extends RefCounted
## Noticing a shape somebody built, and treating it as one machine.
##
## A mod describes the shape as layers of characters, bottom layer first, which is the way anybody
## would draw it on paper:
##
##     api.register_multiblock("forge", {
##         "layers": [["BBB", "BBB", "BBB"],
##                    ["B B", " C ", "B B"]],
##         "key": {"B": "base:brick", "C": "base:furnace"},
##         "controller": "C"})
##
## A space means "do not care". A key may name a **tag** with `#`, so "any log" works and a mod that
## adds a tree joins in. The controller is the cell the machine's data lives on - where the player
## right-clicks, where the inventory hangs.
##
## **The engine does not remember which machines are built.** It answers "is there one here, now?"
## - cheap, because a pattern is a handful of cells - and tells a mod when the answer changes near a
## block that was placed or broken. Remembering would mean saving it, and a saved fact that can be
## worked out from the blocks is a fact that can disagree with them. What the *machine* holds - its
## inventory, its progress - is block data on the controller, which the mod already owns.

const VoxelWorld = preload("res://engine/shared/voxel_world.gd")

## Cells one pattern may have. A shape bigger than this is a building, not a machine.
const MAX_CELLS := 512

var server
var realm

## Name -> {name, owner, cells: [{offset, spec}], controller: Vector3i, size}
var patterns := {}
## "<controller>|<pattern>" -> true for the ones known to be standing. Keyed by **both**, because two
## patterns can share a controller - which is exactly what an upgrade is, swapping a machine's walls
## for better ones - and keying by position alone made the two changes cancel out and fire nothing.
## (2026-09-20)
var _standing := {}


func _init(game_server, in_realm) -> void:
	server = game_server
	realm = in_realm


## def: layers (bottom first, each a list of rows of characters), key (character -> block name or
## "#tag"), controller (which character is the controller; default the first key that matches one cell).
func register(pattern_name: String, def: Dictionary, owner := "engine") -> bool:
	var layers = def.get("layers")
	var key = def.get("key")
	if not (layers is Array) or not (key is Dictionary) or (layers as Array).is_empty():
		push_error("Multiblock '%s' needs layers and a key" % pattern_name)
		return false
	var cells := []
	var controller_char := String(def.get("controller", ""))
	var controller := Vector3i.ZERO
	var found_controller := false
	for y in (layers as Array).size():
		var rows = layers[y]
		if not (rows is Array):
			continue
		for z in (rows as Array).size():
			var row := String(rows[z])
			for x in row.length():
				var ch := row[x]
				if ch == " ":
					continue  # do not care what is here
				if not key.has(ch):
					push_error("Multiblock '%s' uses '%s', which its key does not name" % [pattern_name, ch])
					return false
				var offset := Vector3i(x, y, z)
				cells.append({"offset": offset, "spec": String(key[ch])})
				if ch == controller_char:
					controller = offset
					found_controller = true
	if cells.is_empty() or cells.size() > MAX_CELLS:
		push_error("Multiblock '%s' has %d cells" % [pattern_name, cells.size()])
		return false
	if not found_controller and not controller_char.is_empty():
		push_error("Multiblock '%s' has no '%s' in its layers" % [pattern_name, controller_char])
		return false
	patterns[pattern_name] = {"name": pattern_name, "owner": owner, "cells": cells, "controller": controller}
	return true


## Whether the block at a position satisfies a pattern cell: a block name, or "#tag" for any member.
func _matches(spec: String, block: int) -> bool:
	if spec.begins_with("#"):
		return server.tags.has(spec.substr(1), server.registry.defs[block].name if server.registry.is_valid(block) else "")
	return server.registry.is_valid(block) and server.registry.defs[block].name == spec


## Is a machine of this pattern standing with its controller here? Worked out now rather than looked up.
func at(controller_pos: Vector3i, pattern_name := "") -> Dictionary:
	for name: String in (patterns.keys() if pattern_name.is_empty() else [pattern_name]):
		var pattern: Dictionary = patterns.get(name, {})
		if pattern.is_empty():
			continue
		var origin: Vector3i = controller_pos - pattern.controller
		if _standing_at(pattern, origin):
			_standing[_mark(controller_pos, name)] = true
			return {"name": name, "controller": controller_pos, "origin": origin,
				"cells": (pattern.cells as Array).map(func(c: Dictionary) -> Vector3i: return origin + c.offset)}
		_standing.erase(_mark(controller_pos, name))
	return {}


static func _mark(controller_pos: Vector3i, pattern_name: String) -> String:
	return "%d,%d,%d|%s" % [controller_pos.x, controller_pos.y, controller_pos.z, pattern_name]


func _standing_at(pattern: Dictionary, origin: Vector3i) -> bool:
	for cell: Dictionary in pattern.cells:
		if not _matches(String(cell.spec), realm.world.get_block_v(origin + cell.offset)):
			return false
	return true


## A block was placed or broken: a machine near it may have just been finished, or just been spoiled.
##
## Every pattern is tried with this block as each of its cells in turn, which is why a pattern is
## capped: the work is cells squared, and a machine is a handful of blocks.
func block_changed(pos: Vector3i, _old: int, _block: int) -> void:
	var seen := {}
	for name: String in patterns:
		var pattern: Dictionary = patterns[name]
		for cell: Dictionary in pattern.cells:
			var origin: Vector3i = pos - cell.offset
			var controller_pos: Vector3i = origin + pattern.controller
			var mark := _mark(controller_pos, name)
			if seen.has(mark):
				continue
			seen[mark] = true
			var was: bool = _standing.has(mark)
			var now := _standing_at(pattern, origin)
			if now == was:
				continue
			if now:
				_standing[mark] = true
				server.emit("multiblock_formed", {"realm": realm.id, "name": name, "controller": controller_pos,
					"origin": origin, "cells": (pattern.cells as Array).map(func(c: Dictionary) -> Vector3i: return origin + c.offset)})
			else:
				_standing.erase(mark)
				server.emit("multiblock_broken", {"realm": realm.id, "name": name, "controller": controller_pos,
					"origin": origin, "position": pos})
