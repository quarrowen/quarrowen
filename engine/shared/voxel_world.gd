extends RefCounted
## Sparse collection of loaded chunks with world-space block access.

const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const Chunk = preload("res://engine/shared/chunk.gd")
const Native = preload("res://engine/shared/native.gd")

## Vector2i -> Chunk. Read freely; mutate only through add_chunk / remove_chunk / set_block so the
## native mirror stays in sync.
var chunks := {}
## When true, everything below y = 0 is open air (skyblock-style void) instead of a solid floor.
var void_below := false:
	set(value):
		void_below = value
		if native:
			native.set_void_below(value)
## NativeVoxelWorld mirror used by native physics, or null.
var native: Object = Native.create(&"NativeVoxelWorld")


func add_chunk(chunk) -> void:
	chunks[chunk.coord] = chunk
	if native:
		native.set_chunk(chunk.coord, chunk.blocks)


func remove_chunk(coord: Vector2i) -> void:
	chunks.erase(coord)
	if native:
		native.remove_chunk(coord)


func set_lookup_tables(solid: PackedByteArray, liquid: PackedByteArray) -> void:
	if native:
		native.set_lookup_tables(solid, liquid)


static func chunk_coord_at(x: int, z: int) -> Vector2i:
	return Vector2i(x >> 4, z >> 4)


static func chunk_coord_of(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x) >> 4, floori(position.z) >> 4)


func get_block(x: int, y: int, z: int) -> int:
	if y < 0:
		return BlockRegistry.AIR if void_below else BlockRegistry.UNLOADED
	if y >= Chunk.SIZE_Y:
		return BlockRegistry.AIR
	var chunk = chunks.get(Vector2i(x >> 4, z >> 4))
	if chunk == null:
		return BlockRegistry.UNLOADED
	return chunk.blocks.decode_u16(((x & 15) + ((z & 15) << 4) + (y << 8)) << 1)


func get_block_v(p: Vector3i) -> int:
	return get_block(p.x, p.y, p.z)


## Returns false if the position is outside the world or in an unloaded chunk.
func set_block(x: int, y: int, z: int, id: int) -> bool:
	if y < 0 or y >= Chunk.SIZE_Y:
		return false
	var chunk = chunks.get(Vector2i(x >> 4, z >> 4))
	if chunk == null:
		return false
	chunk.blocks.encode_u16(((x & 15) + ((z & 15) << 4) + (y << 8)) << 1, id)
	chunk.dirty = true
	if native:
		native.set_block(x, y, z, id)
	return true


func has_chunk(coord: Vector2i) -> bool:
	return chunks.has(coord)
