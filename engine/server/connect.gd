extends RefCounted
## Blocks that notice their neighbours: fences that join into a run, walls that meet at a corner, panes
## that make a window rather than four separate sheets of glass.
##
## A block declares the sixteen forms it can take - one per combination of the four sides it might join
## on to - and the engine swaps between them whenever anything beside it changes:
##
##     api.register_block("fence", {..., "connects": ["base:fence_post", "base:fence_n", ...]})
##
## The list is in bit order: north 1, east 2, south 4, west 8, so entry 5 is the one joined north and
## south. `mods/base/openings.gd` builds the list rather than writing it out.
##
## Why shapes and ids rather than a state byte: the mesher and the physics both read the shape from the
## block id alone (see BlockRegistry.SHAPE_BOXES), which keeps what a player sees and what they walk into
## the same thing by construction. The cost is sixteen ids per material, which is cheap.

const NEIGHBOURS := [Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)]

var _server
## Refreshing a block changes it, which asks for another refresh: this stops that going round for ever.
var _busy := false


func _init(server) -> void:
	_server = server


## Called when a block is placed or broken: fixes up that cell and the four around it.
func refresh_around(pos: Vector3i, into = null) -> void:
	if _busy:
		return
	_busy = true
	refresh(pos, into)
	for step in NEIGHBOURS:
		refresh(pos + step, into)
	_busy = false


## Puts the right form of a connecting block at `pos`, if what is there is one.
func refresh(pos: Vector3i, into = null) -> void:
	var in_realm = into if into != null else _server.realm
	var block: int = in_realm.world.get_block_v(pos)
	var forms := _forms(block)
	if forms.is_empty():
		return
	var mask := 0
	for i in NEIGHBOURS.size():
		if _joins(block, int(in_realm.world.get_block_v(pos + NEIGHBOURS[i]))):
			mask |= 1 << i
	var wanted: int = _server.registry.id_of(str(forms[mask]))
	if wanted > 0 and wanted != block:
		_server.set_block_authoritative(pos, wanted, true, 0, in_realm)


## Whether these two join up. A block joins its own family, and anything solid it is set against, so a
## fence meets a wall of stone without a gap.
func _joins(block: int, neighbour: int) -> bool:
	if neighbour <= 0 or neighbour == BlockRegistryUnloaded():
		return false
	var family := str(_server.registry.defs[block].get("connect_group", ""))
	var theirs := str(_server.registry.defs[neighbour].get("connect_group", ""))
	if not family.is_empty() and family == theirs:
		return true
	return _server.registry.solid_lut[neighbour] == 1 and _server.registry.shape_lut[neighbour] == 0


## The sixteen forms of a connecting block, or [] when it is not one.
func _forms(block: int) -> Array:
	if not _server.registry.is_valid(block):
		return []
	var forms = _server.registry.defs[block].get("connects")
	return forms if forms is Array and forms.size() == 16 else []


static func BlockRegistryUnloaded() -> int:
	return preload("res://engine/shared/block_registry.gd").UNLOADED
