extends RefCounted
## A 16 x 128 x 16 column of blocks. Cell index = x + z * 16 + y * 256; `blocks` stores one
## little-endian u16 block id per cell (read with blocks.decode_u16(index << 1), write with
## blocks.encode_u16(index << 1, id)).
## `states` holds an optional per-block state byte (e.g. facing) for the few blocks that use one.

const SIZE_X := 16
const SIZE_Y := 128
const SIZE_Z := 16
const VOLUME := SIZE_X * SIZE_Y * SIZE_Z
const BYTES := VOLUME * 2

var coord: Vector2i
var blocks: PackedByteArray
## Sparse block states: local index -> state (1..255). Missing means 0.
var states := {}
## Server only: modified since last save.
var dirty := false


func _init(chunk_coord: Vector2i, data: PackedByteArray = PackedByteArray()) -> void:
	coord = chunk_coord
	if data.size() == BYTES:
		blocks = data
	else:
		blocks = PackedByteArray()
		blocks.resize(BYTES)


static func index(x: int, y: int, z: int) -> int:
	return x + (z << 4) + (y << 8)


## True if any cell holds `id`. Uses a native byte search, then confirms the id at cell boundaries.
static func contains(blocks: PackedByteArray, id: int) -> bool:
	var low := id & 255
	var i := blocks.find(low)
	while i != -1:
		if i % 2 == 0 and blocks.decode_u16(i) == id:
			return true
		i = blocks.find(low, i + 1)
	return false


func encode() -> PackedByteArray:
	return blocks.compress(FileAccess.COMPRESSION_ZSTD)


## [index, state, index, state, ...] for the network.
func encode_states() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in states:
		out.append(i)
		out.append(states[i])
	return out


func load_states(pairs: PackedInt32Array) -> void:
	states.clear()
	for k in range(0, pairs.size() - 1, 2):
		if pairs[k] >= 0 and pairs[k] < VOLUME and pairs[k + 1] > 0:
			states[pairs[k]] = pairs[k + 1] & 255


## Returns an empty array if the payload is malformed.
static func decode_blocks(payload: PackedByteArray) -> PackedByteArray:
	var data := payload.decompress(BYTES, FileAccess.COMPRESSION_ZSTD)
	return data if data.size() == BYTES else PackedByteArray()
