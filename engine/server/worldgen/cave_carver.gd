extends RefCounted
## Carves caves out of generated terrain (a biome generator carver, see ModApi.add_cave_carver):
## - tunnels: long winding "spaghetti" passages where two 3D noise fields are both near zero
## - caverns: big open chambers deeper down where a slow 3D noise is high
## - ravines: deep narrow canyons along the zero line of a 2D noise, only where a mask allows
## - below `lava_level`, carved space fills with lava; in big caverns, lakes of water sit low
## Tunnels stay a few blocks under the ground except at rare entrances, and nothing is carved under
## oceans or rivers within reach of the water. Noise is sampled every 4 blocks and interpolated.
##
## options: tunnels (bool), caverns (bool), ravines (bool), lava (block name, "" = none), lava_level,
## water_level (cavern lakes), min_y, entrance_chance (0-1 share of the map with tunnel openings)

const Chunk = preload("res://engine/shared/chunk.gd")

const STEP := 4

var tunnels := true
var caverns := true
var ravines := true
var lava := 0
var lava_level := 10
var water_level := 22
var min_y := 4
var entrance_chance := 0.08

var _a := FastNoiseLite.new()
var _b := FastNoiseLite.new()
var _cavern := FastNoiseLite.new()
var _lake := FastNoiseLite.new()
var _ravine := FastNoiseLite.new()
var _ravine_mask := FastNoiseLite.new()
var _entrance := FastNoiseLite.new()
var _water := 0
var _bedrock := 0
var _liquid := PackedByteArray()


func _init(seed_value: int, block_id: Callable, registry, options := {}) -> void:
	tunnels = bool(options.get("tunnels", true))
	caverns = bool(options.get("caverns", true))
	ravines = bool(options.get("ravines", true))
	lava = maxi(int(block_id.call(str(options.get("lava", "")))), 0) if str(options.get("lava", "")) != "" else 0
	lava_level = int(options.get("lava_level", 10))
	water_level = int(options.get("water_level", 22))
	min_y = int(options.get("min_y", 4))
	entrance_chance = clampf(float(options.get("entrance_chance", 0.08)), 0.0, 1.0)
	_water = int(block_id.call("base:water"))
	_bedrock = int(block_id.call("base:bedrock"))
	_liquid = registry.liquid_lut.duplicate()
	for n in [[_a, 0.022], [_b, 0.022], [_cavern, 0.012], [_lake, 0.03], [_ravine, 0.0035], [_ravine_mask, 0.006], [_entrance, 0.01]]:
		n[0].seed = seed_value + 100 + [_a, _b, _cavern, _lake, _ravine, _ravine_mask, _entrance].find(n[0])
		n[0].noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n[0].frequency = n[1]
		n[0].fractal_type = FastNoiseLite.FRACTAL_FBM
		n[0].fractal_octaves = 2


func carve(chunk, gen, heights: PackedInt32Array) -> void:
	var blocks: PackedByteArray = chunk.blocks
	var ox: int = chunk.coord.x * Chunk.SIZE_X
	var oz: int = chunk.coord.y * Chunk.SIZE_Z
	var top := 0
	for h in heights:
		top = maxi(top, h)
	top = mini(top + 1, Chunk.SIZE_Y - 1)
	var ny := top / STEP + 2
	# Coarse grids of the 3D noise (4 blocks apart), trilinearly interpolated below.
	var grid_a := PackedFloat32Array()
	var grid_b := PackedFloat32Array()
	var grid_c := PackedFloat32Array()
	grid_a.resize(5 * 5 * ny)
	grid_b.resize(5 * 5 * ny)
	grid_c.resize(5 * 5 * ny)
	for gy in ny:
		for gz in 5:
			for gx in 5:
				var i := gx + gz * 5 + gy * 25
				var wx := ox + gx * STEP
				var wy := gy * STEP
				var wz := oz + gz * STEP
				if tunnels:
					grid_a[i] = _a.get_noise_3d(wx, wy * 1.6, wz)
					grid_b[i] = _b.get_noise_3d(wx, wy * 1.6, wz)
				if caverns:
					grid_c[i] = _cavern.get_noise_3d(wx, wy * 2.0, wz)
	# Cells (4x4x4) where no tunnel or cavern can appear are skipped: interpolated values stay between
	# the cell's corner values, so a cell can only hold a tunnel if both noises get close to zero in it.
	var possible := PackedByteArray()
	possible.resize(16 * (ny - 1))
	for cy in ny - 1:
		for cz in 4:
			for cx in 4:
				var lo_a := INF
				var hi_a := -INF
				var lo_b := INF
				var hi_b := -INF
				var max_c := -INF
				for k in 8:
					var i := (cx + (k & 1)) + (cz + ((k >> 1) & 1)) * 5 + (cy + ((k >> 2) & 1)) * 25
					lo_a = minf(lo_a, grid_a[i])
					hi_a = maxf(hi_a, grid_a[i])
					lo_b = minf(lo_b, grid_b[i])
					hi_b = maxf(hi_b, grid_b[i])
					max_c = maxf(max_c, grid_c[i])
				var near_a := 0.0 if lo_a <= 0.0 and hi_a >= 0.0 else minf(absf(lo_a), absf(hi_a))
				var near_b := 0.0 if lo_b <= 0.0 and hi_b >= 0.0 else minf(absf(lo_b), absf(hi_b))
				var tunnel_possible: bool = tunnels and near_a * near_a + near_b * near_b < 0.006
				var cavern_possible: bool = caverns and cy * STEP < 56 and max_c > 0.42
				possible[cx + cz * 4 + cy * 16] = 1 if tunnel_possible or cavern_possible else 0
	var ravine_columns := PackedInt32Array()
	ravine_columns.resize(Chunk.SIZE_X * Chunk.SIZE_Z)
	if ravines:
		for z in Chunk.SIZE_Z:
			for x in Chunk.SIZE_X:
				var wx := ox + x
				var wz := oz + z
				if heights[x + z * Chunk.SIZE_X] >= gen.sea_level and _ravine_mask.get_noise_2d(wx, wz) > 0.35:
					var r := absf(_ravine.get_noise_2d(wx, wz))
					if r < 0.02:
						ravine_columns[x + z * Chunk.SIZE_X] = int((1.0 - r / 0.02) * 34.0)
	for cy in ny - 1:
		for cz in 4:
			for cx in 4:
				var cell_possible := possible[cx + cz * 4 + cy * 16] == 1
				for z in range(cz * STEP, cz * STEP + STEP):
					for x in range(cx * STEP, cx * STEP + STEP):
						var ravine_depth := ravine_columns[x + z * Chunk.SIZE_X]
						if not cell_possible and ravine_depth == 0:
							continue
						var h := heights[x + z * Chunk.SIZE_X]
						var wet: bool = h < gen.sea_level
						for y in range(maxi(cy * STEP, min_y), mini(cy * STEP + STEP, mini(h + 1, Chunk.SIZE_Y - 1))):
							_carve_block(blocks, x, y, z, ox + x, oz + z, h, wet, ravine_depth, cell_possible, ny, grid_a, grid_b, grid_c)
	chunk.blocks = blocks


func _carve_block(blocks: PackedByteArray, x: int, y: int, z: int, wx: int, wz: int, h: int, wet: bool, ravine_depth: int,
		cell_possible: bool, ny: int, grid_a: PackedFloat32Array, grid_b: PackedFloat32Array, grid_c: PackedFloat32Array) -> void:
	var index := Chunk.index(x, y, z) << 1
	var current := blocks.decode_u16(index)
	if current == 0 or current == _bedrock or current < _liquid.size() and _liquid[current] == 1:
		return
	var depth := h - y
	var carve := false
	if ravine_depth > 0 and depth < ravine_depth:
		var width := 0.02 * (1.0 - float(depth) / ravine_depth * 0.7)
		carve = absf(_ravine.get_noise_2d(wx, wz)) < width
	if not carve and cell_possible and (depth >= 4 or _entrance.get_noise_2d(wx, wz) > 1.0 - entrance_chance * 2.5) and not (wet and depth < 8):
		var fx := float(x) / STEP
		var fy := float(y) / STEP
		var fz := float(z) / STEP
		if tunnels:
			var na := _sample(grid_a, fx, fy, fz, ny)
			var nb := _sample(grid_b, fx, fy, fz, ny)
			carve = na * na + nb * nb < 0.006
		if not carve and caverns and y < 56 and depth >= 10:
			carve = _sample(grid_c, fx, fy, fz, ny) > 0.42 + 0.15 * clampf((y - 12.0) / 40.0, 0.0, 1.0)
	if not carve:
		return
	# Don't open into the sea or drain a lake above.
	if y + 1 < Chunk.SIZE_Y:
		var above := blocks.decode_u16(Chunk.index(x, y + 1, z) << 1)
		if above < _liquid.size() and _liquid[above] == 1:
			return
	if lava > 0 and y <= lava_level:
		blocks.encode_u16(index, lava)
	elif y <= water_level and depth >= 12 and _lake.get_noise_3d(wx, y * 3.0, wz) > 0.35:
		blocks.encode_u16(index, _water)
	else:
		blocks.encode_u16(index, 0)


func _sample(grid: PackedFloat32Array, fx: float, fy: float, fz: float, ny: int) -> float:
	var x0 := mini(int(fx), 3)
	var y0 := mini(int(fy), ny - 2)
	var z0 := mini(int(fz), 3)
	var tx := fx - x0
	var ty := fy - y0
	var tz := fz - z0
	var c000 := grid[x0 + z0 * 5 + y0 * 25]
	var c100 := grid[x0 + 1 + z0 * 5 + y0 * 25]
	var c010 := grid[x0 + z0 * 5 + (y0 + 1) * 25]
	var c110 := grid[x0 + 1 + z0 * 5 + (y0 + 1) * 25]
	var c001 := grid[x0 + (z0 + 1) * 5 + y0 * 25]
	var c101 := grid[x0 + 1 + (z0 + 1) * 5 + y0 * 25]
	var c011 := grid[x0 + (z0 + 1) * 5 + (y0 + 1) * 25]
	var c111 := grid[x0 + 1 + (z0 + 1) * 5 + (y0 + 1) * 25]
	var x00 := lerpf(c000, c100, tx)
	var x10 := lerpf(c010, c110, tx)
	var x01 := lerpf(c001, c101, tx)
	var x11 := lerpf(c011, c111, tx)
	return lerpf(lerpf(x00, x10, ty), lerpf(x01, x11, ty), tz)
