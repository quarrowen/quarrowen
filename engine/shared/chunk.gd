extends RefCounted
## A 16 x 128 x 16 column of blocks. Index = x + z * 16 + y * 256.
## `states` holds an optional per-block state byte (e.g. facing) for the few blocks that use one.

const SIZE_X := 16
const SIZE_Y := 128
const SIZE_Z := 16
const VOLUME := SIZE_X * SIZE_Y * SIZE_Z

var coord: Vector2i
var blocks: PackedByteArray
## Sparse block states: local index -> state (1..255). Missing means 0.
var states := {}
## Server only: modified since last save.
var dirty := false


func _init(chunk_coord: Vector2i, data: PackedByteArray = PackedByteArray()) -> void:
	coord = chunk_coord
	if data.size() == VOLUME:
		blocks = data
	else:
		blocks = PackedByteArray()
		blocks.resize(VOLUME)


static func index(x: int, y: int, z: int) -> int:
	return x + (z << 4) + (y << 8)


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
	var data := payload.decompress(VOLUME, FileAccess.COMPRESSION_ZSTD)
	return data if data.size() == VOLUME else PackedByteArray()
