extends RefCounted
## Seeded noise terrain: continents, hills, mountains with snow caps, beaches, ores and trees.

const Chunk = preload("res://engine/shared/chunk.gd")

const SEA_LEVEL := 46
const SNOW_LEVEL := 92

var world_seed: int
var b := {}  # block short name -> id
var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _mountains := FastNoiseLite.new()
var _forest := FastNoiseLite.new()


func _init(api) -> void:
	world_seed = api.world_seed
	for block_name in ["stone", "dirt", "grass", "sand", "gravel", "snow", "water", "bedrock", "log", "leaves", "coal_ore", "iron_ore"]:
		b[block_name] = api.block("base:" + block_name)
	_configure(_continent, world_seed, 0.0025, 4)
	_configure(_hills, world_seed + 1, 0.02, 3)
	_configure(_mountains, world_seed + 2, 0.004, 5)
	_configure(_forest, world_seed + 3, 0.01, 2)


static func _configure(noise: FastNoiseLite, seed_value: int, frequency: float, octaves: int) -> void:
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves


func surface_height(wx: int, wz: int) -> int:
	var h := 50.0 + _continent.get_noise_2d(wx, wz) * 14.0 + _hills.get_noise_2d(wx, wz) * 4.0
	var m := _mountains.get_noise_2d(wx, wz)
	if m > 0.15:
		h += pow((m - 0.15) / 0.85, 1.3) * 90.0
	return clampi(int(h), 2, Chunk.SIZE_Y - 16)


func generate(chunk) -> void:
	var blocks: PackedByteArray = chunk.blocks
	var coord: Vector2i = chunk.coord
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, coord.x, coord.y])
	var ox := coord.x * Chunk.SIZE_X
	var oz := coord.y * Chunk.SIZE_Z
	var heights := PackedInt32Array()
	heights.resize(Chunk.SIZE_X * Chunk.SIZE_Z)

	for z in Chunk.SIZE_Z:
		for x in Chunk.SIZE_X:
			var h := surface_height(ox + x, oz + z)
			heights[x + z * Chunk.SIZE_X] = h
			var beach := h <= SEA_LEVEL + 1
			var rocky := h >= SNOW_LEVEL - 14
			for y in range(0, maxi(h, SEA_LEVEL) + 1):
				var id: int
				if y == 0 or (y <= 2 and rng.randf() < 0.5):
					id = b.bedrock
				elif y > h:
					id = b.water
				elif y == h:
					if h < SEA_LEVEL - 4:
						id = b.gravel
					elif beach:
						id = b.sand
					elif h >= SNOW_LEVEL:
						id = b.snow
					elif rocky:
						id = b.stone
					else:
						id = b.grass
				elif y >= h - 3:
					id = b.sand if beach else (b.stone if rocky else b.dirt)
				else:
					id = b.stone
				blocks[Chunk.index(x, y, z)] = id

	_place_ores(blocks, heights, rng, b.coal_ore, 12, 8)
	_place_ores(blocks, heights, rng, b.iron_ore, 7, 5)

	var density := (_forest.get_noise_2d(ox + 8, oz + 8) + 1.0) * 0.5
	for i in int(density * density * 7.0):
		var tx := rng.randi_range(2, 13)
		var tz := rng.randi_range(2, 13)
		var th := heights[tx + tz * Chunk.SIZE_X]
		if blocks[Chunk.index(tx, th, tz)] == b.grass and th + 9 < Chunk.SIZE_Y:
			_place_tree(blocks, tx, th + 1, tz, rng)

	chunk.blocks = blocks


func _place_ores(blocks: PackedByteArray, heights: PackedInt32Array, rng: RandomNumberGenerator,
		ore: int, veins: int, vein_size: int) -> void:
	for i in veins:
		var x := rng.randi_range(0, 15)
		var z := rng.randi_range(0, 15)
		var max_y := heights[x + z * Chunk.SIZE_X] - 5
		if max_y <= 4:
			continue
		var y := rng.randi_range(3, max_y)
		for n in rng.randi_range(2, vein_size):
			if x >= 0 and x < 16 and z >= 0 and z < 16 and y > 0 and y < Chunk.SIZE_Y:
				var idx := Chunk.index(x, y, z)
				if blocks[idx] == b.stone:
					blocks[idx] = ore
			match rng.randi_range(0, 5):
				0: x += 1
				1: x -= 1
				2: y += 1
				3: y -= 1
				4: z += 1
				_: z -= 1


## Trees stay inside the chunk (x/z in 2..13) so generation never touches neighbours.
func _place_tree(blocks: PackedByteArray, x: int, y: int, z: int, rng: RandomNumberGenerator) -> void:
	var trunk := rng.randi_range(4, 6)
	var top := y + trunk
	for ly in range(top - 2, top + 2):
		var r := 2 if ly < top else 1
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) == r and absi(dz) == r and (ly >= top or rng.randf() < 0.5):
					continue
				var idx := Chunk.index(x + dx, ly, z + dz)
				if blocks[idx] == 0:
					blocks[idx] = b.leaves
	for dy in trunk:
		blocks[Chunk.index(x, y + dy, z)] = b.log
