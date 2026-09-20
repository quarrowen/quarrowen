extends RefCounted
## Blocks that leave the grid, move as one thing, and set back down again: a platform on a track, a
## drawbridge swinging open, a whole contraption somebody built and started.
##
## **This is the one capability that fights the engine's shape.** A voxel world is a grid, and
## everything else here assumes a block is at whole-number coordinates. An assembly is not: it has a
## position of its own, it is somewhere between two cells most of the time, and a player standing on it
## has to be carried along rather than left behind.
##
## How it is kept honest:
##
## - **Lifting takes the blocks out of the world.** They are held here with everything they had - their
##   state and their block data - and the cells they came from become air. There is no moment where a
##   block is in two places, because that is where this sort of thing goes wrong.
## - **Setting down is refused rather than forced.** If something is in the way where it would land,
##   the assembly stays up and says so. Dropping it anyway would destroy whatever was there, and this
##   engine does not get to delete what somebody built.
## - **Whoever is standing on it is carried.** That is most of what a moving platform is for, and it is
##   the difference between a lift and a piece of scenery.
##
## What a mod decides: what may be lifted, what moves it, how fast, and when it stops. The engine moves
## a set of blocks and knows nothing about tracks, pistons or drawbridges.

const VoxelWorld = preload("res://engine/shared/voxel_world.gd")
const Chunk = preload("res://engine/shared/chunk.gd")

## Blocks one assembly may hold. A contraption larger than this is a building, and dragging a building
## about is how a server stops responding.
const MAX_CELLS := 512
## How far above an assembly a player still counts as standing on it.
const CARRY_HEIGHT := 1.2

var server

## id -> {realm, origin (Vector3i the cells are relative to), offset (Vector3), cells, riders}
var assemblies := {}
var _next_id := 1
## Why the last lift or settle was refused, in words a player can be shown.
var problem := ""


func _init(game_server) -> void:
	server = game_server


## Takes a set of world positions out of the world and holds them as one moving thing. Returns the
## assembly id, or 0 with the reason in `problem`.
func lift(realm_id: String, positions: Array, options := {}) -> int:
	problem = ""
	var realm = server.realms.get(realm_id)
	if realm == null:
		problem = "There is no such world."
		return 0
	if positions.is_empty() or positions.size() > MAX_CELLS:
		problem = "That is %d blocks; an assembly may hold %d." % [positions.size(), MAX_CELLS]
		return 0
	var origin: Vector3i = positions[0]
	var cells := []
	for at in positions:
		var pos: Vector3i = at
		var block: int = realm.world.get_block_v(pos)
		if block == 0 or block == 255:
			continue  # air and unloaded are not part of anything
		cells.append({"offset": pos - origin, "block": block, "state": realm.block_state(pos),
			"data": server.get_block_data(pos, realm).duplicate(true)})
	if cells.is_empty():
		problem = "There is nothing there to move."
		return 0
	# Out of the world before anything else happens: a block in two places at once is where this sort
	# of thing goes wrong, so there is no moment when one is.
	for cell: Dictionary in cells:
		server.set_block_authoritative(origin + cell.offset, 0, false, 0, realm)
	var id := _next_id
	_next_id += 1
	assemblies[id] = {"realm": realm_id, "origin": origin, "offset": Vector3.ZERO, "cells": cells,
		"name": String(options.get("name", "assembly")), "owner": String(options.get("owner", "engine"))}
	server.emit("assembly_lifted", {"id": id, "realm": realm_id, "origin": origin, "cells": cells.size()})
	server.tell_assembly(id)
	return id


## Moves it, and carries whoever is standing on it. `by` is in blocks and may be fractional - that is
## the whole point of being off the grid.
func move(id: int, by: Vector3) -> bool:
	var assembly: Dictionary = assemblies.get(id, {})
	if assembly.is_empty():
		return false
	# Who is standing on it is worked out *before* it moves. Afterwards they are no longer above it,
	# which is how the first version managed to leave everybody behind. (2026-09-20)
	var riders := _riders(assembly)
	assembly.offset += by
	for p in riders:
		# Carried rather than pushed: their own movement still works, they simply start each step from
		# where the floor has got to.
		p.teleport(p.state.position + by)
	server.tell_assembly_moved(id)
	return true


## Puts it back into the world at wherever it has got to, and stops being an assembly.
##
## Refused if anything solid is in the way. Forcing it would mean deleting whatever was there, and an
## engine that destroys what somebody built because a machine arrived is not one to build with.
func settle(id: int) -> bool:
	problem = ""
	var assembly: Dictionary = assemblies.get(id, {})
	if assembly.is_empty():
		return false
	var realm = server.realms.get(assembly.realm)
	if realm == null:
		return false
	var drift: Vector3 = assembly.offset
	var landing: Vector3i = assembly.origin + Vector3i((drift + Vector3(0.5, 0.5, 0.5)).floor())
	for cell: Dictionary in assembly.cells:
		var at: Vector3i = landing + cell.offset
		var there: int = realm.world.get_block_v(at)
		if at.y < 0 or at.y >= Chunk.SIZE_Y:
			problem = "There is no room there."
			return false
		if there != 0 and there != 255 and server.registry.solid_lut[there] == 1:
			problem = "Something is in the way."
			return false
	for cell: Dictionary in assembly.cells:
		var at: Vector3i = landing + cell.offset
		server.set_block_authoritative(at, int(cell.block), true, int(cell.state), realm)
		if not (cell.data as Dictionary).is_empty():
			server.set_block_data(at, (cell.data as Dictionary).duplicate(true), realm)
	assemblies.erase(id)
	server.emit("assembly_settled", {"id": id, "realm": assembly.realm, "origin": landing})
	server.tell_assembly_gone(id)
	return true


## Puts an assembly back exactly where it was lifted from, for a mod that wants to give up cleanly.
func cancel(id: int) -> bool:
	var assembly: Dictionary = assemblies.get(id, {})
	if assembly.is_empty():
		return false
	assembly.offset = Vector3.ZERO
	return settle(id)


func info(id: int) -> Dictionary:
	var assembly: Dictionary = assemblies.get(id, {})
	if assembly.is_empty():
		return {}
	return {"id": id, "realm": assembly.realm, "origin": assembly.origin, "offset": assembly.offset,
		"cells": (assembly.cells as Array).size(), "name": assembly.name}


## Everyone standing on it: inside its footprint, and within a stride of its top.
func _riders(assembly: Dictionary) -> Array:
	var out := []
	var base: Vector3 = Vector3(assembly.origin) + assembly.offset
	for p in server.players.values():
		if server.realm_of(p).id != assembly.realm or p.dead:
			continue
		var local: Vector3 = p.state.position - base
		for cell: Dictionary in assembly.cells:
			var c: Vector3i = cell.offset
			if local.x >= float(c.x) - 0.4 and local.x <= float(c.x) + 1.4 \
					and local.z >= float(c.z) - 0.4 and local.z <= float(c.z) + 1.4 \
					and local.y >= float(c.y) and local.y <= float(c.y) + CARRY_HEIGHT:
				out.append(p)
				break
	return out
