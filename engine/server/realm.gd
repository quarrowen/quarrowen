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
const BlockTicks = preload("res://engine/server/block_ticks.gd")
const Signals = preload("res://engine/server/signals.gd")
const Liquids = preload("res://engine/server/liquids.gd")
const Multiblocks = preload("res://engine/server/multiblocks.gd")
const Chunk = preload("res://engine/shared/chunk.gd")

## What a mod called it ("overworld", "mymod:emberdeep"). The overworld's name is "" for the world a
## server has always had, so a save written before realms existed is still where it was.
var id := ""
var display_name := ""

## An instance's realm: made on demand, thrown away when it empties. Never written to disk, so a
## dungeon run leaves no folder behind and a crash mid-run leaves nothing to clean up. (2026-09-21)
var ephemeral := false

var world := VoxelWorld.new()
var seed_value := 0
var entities: Entities
## Set once the mods have run: the terrain this realm is made of. Realms differ mostly by this, and it
## is what a chunk job is handed. A mod supplies it with set_world_generator, or asks for the engine's
## biome generator, which is then usually - but not always - the same object.
var generator = null
## The engine biome generator, if this realm uses one. **Not** the same field as `generator`: a game can
## use its own world generator and still want biomes for spawning and for "what biome am I in", which
## is why conflating the two broke chunk generation for the games that do. (2026-09-19)
var biome_generator = null
var generation_passes: Array = []

## Blocks that change over time in this realm, and the light it is lit by. One per realm rather than
## one per server, because everything in it is indexed by chunk coordinate and every realm has a
## chunk (0, 0) - a single table would have the Emberdeep's furnaces and the overworld's sharing a key.
var block_ticks: BlockTicks
## Levels spreading from block to block in this realm (see engine/server/signals.gd). Per realm for
## the same reason as everything else here: a position alone does not say which world.
var signals: Signals
## Liquids flowing in this realm (see engine/server/liquids.gd).
var liquids: Liquids
## Machines assembled out of blocks (see engine/server/multiblocks.gd).
var multiblocks: Multiblocks

## Blocks that differ from freshly generated terrain, and which chunks still need writing.
var block_data := {}  # Vector2i chunk -> {Vector3i: Dictionary}
var save_dirty := {}  # Vector2i chunk -> true
## Delta persistence: what each chunk's terrain was when generated, and how it differs now.
var deltas := {}  # Vector2i chunk -> {local index: block id}
var generated := {}  # Vector2i chunk -> PackedByteArray as generated (kept while the chunk has edits)
## Chunks waiting to be serialized, and chunks being loaded or generated on a worker thread. Both are
## per realm for the same reason as block_ticks: the coordinate alone does not say which world.
var save_queue := {}  # Vector2i chunk -> true
var chunk_jobs := {}  # Vector2i chunk -> job Dictionary
## Chunks whose saved file lists persistent creatures; resaved so ones that walked away are dropped.
var entity_chunks := {}  # Vector2i chunk -> true
## Where this realm's chunks live. The overworld keeps the folder it always had; every other realm gets
## one of its own beside it, so an old save is still a valid new save.
var save_dir := ""

## Chunks close enough to somebody to be run. Everything else that is loaded is still there - a player
## can still see it, it is still saved - it simply does not tick. Empty means the realm is asleep: its
## clock keeps running and nothing in it does, which is what makes it cheap for a mod to register five
## realms nobody is standing in. (2026-09-19, and see docs/roadmap.md "How much of the world is running")
var simulated := {}  # Vector2i chunk -> true

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
	block_ticks = BlockTicks.new(_server, self)
	signals = Signals.new(_server, self)
	liquids = Liquids.new(_server, self)
	multiblocks = Multiblocks.new(_server, self)
	# Shared with every other realm: what a block type *does* is true everywhere, and only where each
	# block happens to be differs. A realm added after a mod registered would otherwise be inert.
	block_ticks.handlers = _server.block_tick_handlers
	signals.handlers = _server.signal_handlers
	liquids.kinds = _server.liquid_kinds
	liquids.meetings = _server.liquid_meetings
	multiblocks.patterns = _server.multiblock_patterns


## Whether anything in this realm should be run this tick. A claim on a chunk (keeping a machine going
## after its owner leaves) will wake a realm too, which is why this asks about the simulated set rather
## than counting players.
func is_awake() -> bool:
	return not simulated.is_empty()


## Whether this is the world a server has always had. Kept as a question rather than a comparison
## scattered about, because "" meaning the overworld is a compatibility decision and not an obvious one.
func is_overworld() -> bool:
	return id.is_empty()


## The block state (its rotation, its stage, whatever the block means by it) at a position in *this*
## world. On the realm rather than the server because a position alone does not say which world.
func block_state(pos: Vector3i) -> int:
	var chunk = world.chunks.get(VoxelWorld.chunk_coord_at(pos.x, pos.z))
	if chunk == null or pos.y < 0 or pos.y >= Chunk.SIZE_Y:
		return 0
	return chunk.states.get(Chunk.index(pos.x & 15, pos.y, pos.z & 15), 0)


## Decides where this realm keeps its chunks, under the world's folder, and makes the folder.
##
## The overworld keeps `<world>/chunks`, which is the folder every save already has; every other realm
## gets `<world>/realms/<id>/chunks` beside it. That is the whole of why the overworld's id is "": a
## world written before realms existed is still a valid world afterwards, with no migration.
func set_storage(world_dir: String) -> void:
	save_dir = world_dir if is_overworld() else world_dir.path_join("realms").path_join(id.validate_filename())
	DirAccess.make_dir_recursive_absolute(save_dir + "/chunks")


## `<save dir>/chunks/x_z.json`.
func chunk_path(coord: Vector2i) -> String:
	return "%s/chunks/%d_%d.json" % [save_dir, coord.x, coord.y]
