extends RefCounted
## One world inside the server: its blocks, its terrain, its creatures and its folder on disk.
##
## A server used to be one world, with the blocks, the generator, the entities and the save directory
## sitting directly on GameServer. Dimensions are the reason that stops working - the Emberdeep is not
## somewhere you travel *to*, it is somewhere that exists at the same time as everywhere else, with its
## own terrain, its own creatures wandering about in it, and its own chunks on disk.
##
## So the per-world half of the server lives here and the server keeps several. What stays on the server
## is everything that is true of the whole server rather than of one place in it: the registries, the
## mods, the players, the recipes, the loot tables.
##
## **Why not one coordinate space with the realms far apart**, which would have been a much smaller
## change: Godot's Vector3 is 32-bit, and at the distances that would need - a million blocks or more,
## so nobody can walk from one realm into another - a position is only accurate to an eighth of a block.
## Everything would judder. Measured before it was ruled out. (2026-09-19)

const VoxelWorld = preload("res://engine/shared/voxel_world.gd")
const Entities = preload("res://engine/server/entities.gd")

## What a mod called it ("overworld", "mymod:emberdeep"). The overworld's name is "" for the world a
## server has always had, so a save written before realms existed is still where it was.
var id := ""
var display_name := ""

var world := VoxelWorld.new()
var seed_value := 0
var entities
## Set once the mods have run: the terrain this realm is made of. Realms differ mostly by this.
var generator = null
var generation_passes: Array = []

## Blocks that differ from freshly generated terrain, and which chunks still need writing.
var block_data := {}  # Vector2i chunk -> {Vector3i: Dictionary}
var save_dirty := {}  # Vector2i chunk -> true
## Where this realm's chunks live. The overworld keeps the folder it always had; every other realm gets
## one of its own beside it, so an old save is still a valid new save.
var save_dir := ""

var _server


func _init(game_server, realm_id: String, realm_name := "") -> void:
	_server = game_server
	id = realm_id
	display_name = realm_name if not realm_name.is_empty() else realm_id


## Built after the realm is in place rather than inside _init, because the creatures reach back through
## the server for the world they are standing in - and during _init the server does not yet know this
## realm exists, so it would hand them somebody else's.
func attach() -> void:
	entities = Entities.new(_server, self)


## Whether this is the world a server has always had. Kept as a question rather than a comparison
## scattered about, because "" meaning the overworld is a compatibility decision and not an obvious one.
func is_overworld() -> bool:
	return id.is_empty()


## `<save dir>/chunks/x_z.json` for the overworld, `<save dir>/realms/<id>/chunks/x_z.json` for the rest.
func chunk_path(coord: Vector2i) -> String:
	return "%s/chunks/%d_%d.json" % [save_dir, coord.x, coord.y]
