extends RefCounted
## The engine's biome world generator. Games and add-on mods register biomes (ModApi.register_biome)
## and features (ModApi.register_feature); a game turns the generator on with ModApi.use_biome_generator.
##
## Climate: four smooth noise fields pick biomes everywhere: temperature, humidity, weirdness (a biome
## with a weirdness value only appears where the noise goes past it: rare fantasy biomes) and peaks. Continentalness decides land and ocean.
## Each biome says where it sits in that climate space; every column blends the heights of nearby
## biomes (so borders are smooth) and takes blocks, plants and features from the closest one.
##
## Biome def:
##   climate: {temperature, humidity, weirdness, peaks} (-1..1, defaults 0), ocean: bool
##   height: {base, variation (hills), peaks (extra mountain height)}
##   surface: {top, filler, depth, underwater, beach, stone, water (the biome's lakes and seas)}
##   features: [{feature: name, per_chunk: float}]    trees, cacti, boulders...
##   plants: [{block, chance, on: [blocks]}]          per surface column
##   ores, spawn tags and anything else are free for mods
## Runs on worker threads: definitions are frozen once the world starts generating.

const Chunk = preload("res://engine/shared/chunk.gd")
const Features = preload("res://engine/server/worldgen/features.gd")

var sea_level := 46
var snow_level := 92
var world_seed := 0
var biomes: Array[Dictionary] = []
var biome_ids := {}  # name -> index
var features := {}  # name -> resolved def or Callable
## Carvers and other passes: objects with carve(chunk, generator) run after terrain, before features.
var carvers: Array = []

var _block_id: Callable
var _registry
var _snow := 0
var _bedrock := 0
var _stone := 0
var _water := 0
var _replaceable := PackedByteArray()
var _solid := PackedByteArray()
var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _peaks := FastNoiseLite.new()
var _temperature := FastNoiseLite.new()
var _humidity := FastNoiseLite.new()
var _weirdness := FastNoiseLite.new()


func _init(seed_value: int, block_id: Callable, registry, options := {}) -> void:
	world_seed = seed_value
	_block_id = block_id
	sea_level = int(options.get("sea_level", 46))
	snow_level = int(options.get("snow_level", 92))
	_registry = registry
	_configure(_continent, seed_value, 0.0025, 4)
	_configure(_hills, seed_value + 1, 0.02, 3)
	_configure(_peaks, seed_value + 2, 0.004, 5)
	_configure(_temperature, seed_value + 10, 0.0011, 3)
	_configure(_humidity, seed_value + 11, 0.0014, 3)
	_configure(_weirdness, seed_value + 12, 0.0018, 2)


static func _configure(noise: FastNoiseLite, seed_value: int, frequency: float, octaves: int) -> void:
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves


## Called once every mod has registered its blocks: snapshots block tables for the worker threads.
func freeze() -> void:
	_bedrock = int(_block_id.call("base:bedrock"))
	_stone = int(_block_id.call("base:stone"))
	_water = int(_block_id.call("base:water"))
	_snow = int(_block_id.call("base:snow"))
	_solid = _registry.solid_lut.duplicate()
	_replaceable.resize(_registry.defs.size())
	for i in _registry.defs.size():
		var d: Dictionary = _registry.defs[i]
		_replaceable[i] = 1 if d.replaceable or String(d.name).ends_with("leaves") or d.render == 5 else 0


func add_biome(biome_name: String, def: Dictionary) -> void:
	var climate: Dictionary = def.get("climate", {}) if def.get("climate") is Dictionary else {}
	var height: Dictionary = def.get("height", {}) if def.get("height") is Dictionary else {}
	var surface: Dictionary = def.get("surface", {}) if def.get("surface") is Dictionary else {}
	var b := {
		"name": biome_name, "display_name": str(def.get("display_name", biome_name.get_slice(":", 1).capitalize())),
		"ocean": bool(def.get("ocean", false)),
		"t": float(climate.get("temperature", 0.0)), "h": float(climate.get("humidity", 0.0)),
		"w": float(climate.get("weirdness", 0.0)), "p": float(climate.get("peaks", 0.0)),
		"base": float(height.get("base", 52.0)), "variation": float(height.get("variation", 4.0)), "peak_height": float(height.get("peaks", 0.0)),
		"top": int(_block_id.call(str(surface.get("top", "base:grass")))),
		"filler": int(_block_id.call(str(surface.get("filler", "base:dirt")))),
		"depth": clampi(int(surface.get("depth", 3)), 0, 12),
		"underwater": int(_block_id.call(str(surface.get("underwater", "base:gravel")))),
		"beach": int(_block_id.call(str(surface.get("beach", "base:sand")))) if str(surface.get("beach", "base:sand")) != "" else 0,
		"stone": int(_block_id.call(str(surface.get("stone", "base:stone")))),
		"water": maxi(int(_block_id.call(str(surface.get("water", "base:water")))), 0),
		"features": [], "plants": [], "def": def,
	}
	for f in (def.get("features") if def.get("features") is Array else []):
		if f is Dictionary:
			b.features.append({"feature": str(f.get("feature", "")), "per_chunk": clampf(float(f.get("per_chunk", 1.0)), 0.0, 64.0)})
	for plant in (def.get("plants") if def.get("plants") is Array else []):
		if plant is Dictionary:
			b.plants.append({"block": int(_block_id.call(str(plant.get("block", "")))), "chance": clampf(float(plant.get("chance", 0.05)), 0.0, 1.0),
				"on": (plant.get("on", []) as Array).map(func(n): return int(_block_id.call(str(n)))) if plant.get("on") is Array else []})
	biome_ids[biome_name] = biomes.size()
	biomes.append(b)


func add_feature(feature_name: String, def) -> void:
	if def is Callable:
		features[feature_name] = def
	elif def is Dictionary:
		var resolved := Features.resolve(def, _block_id)
		if not resolved.is_empty():
			features[feature_name] = resolved


# --- Climate and height ---------------------------------------------------------------------------

## {t, h, w, p, c} at a column.
func climate(x: int, z: int) -> Dictionary:
	return {"t": _temperature.get_noise_2d(x, z) * 1.6, "h": _humidity.get_noise_2d(x, z) * 1.6, "w": _weirdness.get_noise_2d(x, z) * 1.8,
		"p": clampf((_peaks.get_noise_2d(x, z) - 0.1) * 2.2, -1.0, 1.0), "c": _continent.get_noise_2d(x, z)}


## Blend weights {biome index: weight} for a climate, normalized. Weights are relative to the closest
## biome, so every column has a clear winner and borders blend over a short distance.
func weights(c: Dictionary) -> Dictionary:
	var ocean: bool = float(c.c) < -0.22
	var peaks := maxf(float(c.p), 0.0)
	var distances := {}
	var nearest := INF
	for i in biomes.size():
		var b: Dictionary = biomes[i]
		if b.ocean != ocean:
			continue
		# Weird biomes only appear where weirdness passes their value (same sign); the rest ignore it.
		if b.w != 0.0 and (signf(c.w) != signf(b.w) or absf(c.w) < absf(b.w)):
			continue
		var d: float = (c.t - b.t) ** 2 + (c.h - b.h) ** 2 + 2.0 * (peaks - b.p) ** 2 - (0.3 if b.w != 0.0 else 0.0)
		distances[i] = d
		nearest = minf(nearest, d)
	if distances.is_empty():
		return {}
	var out := {}
	var total := 0.0
	for i: int in distances:
		var weight := exp(-(float(distances[i]) - nearest) / 0.035)
		if weight > 0.01:
			out[i] = weight
			total += weight
	for i in out:
		out[i] /= total
	return out


## {biome (index), height} for a column.
func column(x: int, z: int) -> Dictionary:
	var c := climate(x, z)
	var w := weights(c)
	if w.is_empty():
		return {"biome": 0, "height": sea_level}
	var hills := _hills.get_noise_2d(x, z)
	var peak := maxf(_peaks.get_noise_2d(x, z) - 0.15, 0.0) / 0.85
	var h := 0.0
	var best := 0
	var best_w := -1.0
	for i: int in w:
		var b: Dictionary = biomes[i]
		h += w[i] * (b.base + b.variation * hills + b.peak_height * pow(peak, 1.3))
		if w[i] > best_w:
			best_w = w[i]
			best = i
	# Coasts: land sinks towards the sea as continentalness falls.
	var coast := clampf((float(c.c) + 0.22) / 0.12, 0.0, 1.0)
	if not biomes[best].ocean:
		h = lerpf(float(sea_level - 2), h, coast) if coast < 1.0 else h
	else:
		h = lerpf(float(sea_level - 2), h, clampf((-0.22 - float(c.c)) / 0.15, 0.0, 1.0))  # shelving coast
	return {"biome": best, "height": clampi(int(h), 2, Chunk.SIZE_Y - 16)}


func surface_height(x: int, z: int) -> int:
	return int(column(x, z).height)


func biome_at(x: int, z: int) -> String:
	return biomes[int(column(x, z).biome)].name if not biomes.is_empty() else ""


# --- Generation -----------------------------------------------------------------------------------

func generate(chunk) -> void:
	var blocks: PackedByteArray = chunk.blocks
	var coord: Vector2i = chunk.coord
	var ox := coord.x * Chunk.SIZE_X
	var oz := coord.y * Chunk.SIZE_Z
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, coord.x, coord.y])
	var heights := PackedInt32Array()
	heights.resize(Chunk.SIZE_X * Chunk.SIZE_Z)
	var column_biomes := PackedInt32Array()
	column_biomes.resize(Chunk.SIZE_X * Chunk.SIZE_Z)
	for z in Chunk.SIZE_Z:
		for x in Chunk.SIZE_X:
			var col := column(ox + x, oz + z)
			var h: int = col.height
			var b: Dictionary = biomes[col.biome]
			heights[x + z * Chunk.SIZE_X] = h
			column_biomes[x + z * Chunk.SIZE_X] = col.biome
			var beach: bool = h <= sea_level + 1 and h >= sea_level - 3 and b.beach > 0 and not b.ocean
			var high: bool = h >= snow_level
			var rocky: bool = h >= snow_level - 14
			for y in range(0, maxi(h, sea_level) + 1):
				var id: int
				if y == 0 or (y <= 2 and rng.randf() < 0.5):
					id = _bedrock
				elif y > h:
					id = b.water if b.water > 0 else _water
				elif y == h:
					if h < sea_level - 1:
						id = b.underwater
					elif beach:
						id = b.beach
					elif high:
						id = _snow
					elif rocky and b.peak_height > 0.0:
						id = b.stone
					else:
						id = b.top
				elif y >= h - b.depth:
					id = b.beach if beach else (b.stone if rocky and b.peak_height > 0.0 else b.filler)
				else:
					id = b.stone
				blocks.encode_u16(Chunk.index(x, y, z) << 1, id)
	chunk.blocks = blocks
	for carver in carvers:
		carver.carve(chunk, self, heights)
	blocks = chunk.blocks
	# Features from this chunk and its neighbours (they may reach across the border).
	var writer := Features.Writer.new()
	writer.blocks = blocks
	writer.origin_x = ox
	writer.origin_z = oz
	writer.solid = _solid
	writer.replaceable = _replaceable
	for ncz in range(-1, 2):
		for ncx in range(-1, 2):
			_place_features(writer, coord + Vector2i(ncx, ncz), ncx == 0 and ncz == 0, heights, column_biomes)
	blocks = writer.blocks
	# Plants on open surface columns.
	for z in Chunk.SIZE_Z:
		for x in Chunk.SIZE_X:
			var h := heights[x + z * Chunk.SIZE_X]
			if h + 1 >= Chunk.SIZE_Y or h < sea_level:
				continue
			var b: Dictionary = biomes[column_biomes[x + z * Chunk.SIZE_X]]
			if b.plants.is_empty() or blocks.decode_u16(Chunk.index(x, h + 1, z) << 1) != 0:
				continue
			var ground := blocks.decode_u16(Chunk.index(x, h, z) << 1)
			var roll := rng.randf()
			for plant in b.plants:
				if roll < plant.chance:
					if plant.on.is_empty() or plant.on.has(ground):
						blocks.encode_u16(Chunk.index(x, h + 1, z) << 1, plant.block)
					break
				roll -= plant.chance
	chunk.blocks = blocks


## Places a chunk's features. Positions and randomness depend only on that chunk, so every chunk the
## features overlap draws them the same way.
func _place_features(writer, feature_chunk: Vector2i, local: bool, heights: PackedInt32Array, column_biomes: PackedInt32Array) -> void:
	var fox := feature_chunk.x * Chunk.SIZE_X
	var foz := feature_chunk.y * Chunk.SIZE_Z
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, "features", feature_chunk.x, feature_chunk.y])
	var center := column(fox + 8, foz + 8)
	var b: Dictionary = biomes[center.biome]
	for entry in b.features:
		var feature = features.get(entry.feature)
		var count := int(entry.per_chunk)
		if rng.randf() < entry.per_chunk - count:
			count += 1
		for i in count:
			var lx := rng.randi_range(0, Chunk.SIZE_X - 1)
			var lz := rng.randi_range(0, Chunk.SIZE_Z - 1)
			var instance_seed := rng.randi()
			if feature == null:
				continue
			var wx := fox + lx
			var wz := foz + lz
			var h: int
			var biome: int
			if local:
				h = heights[lx + lz * Chunk.SIZE_X]
				biome = column_biomes[lx + lz * Chunk.SIZE_X]
			else:
				var col := column(wx, wz)
				h = col.height
				biome = col.biome
			if biome != center.biome or h < sea_level or h >= snow_level:
				continue
			if local:
				var ground: int = writer.get_block(wx, h, wz)
				if ground <= 0 or _solid[ground] == 0 or writer.get_block(wx, h + 1, wz) != 0:
					continue  # carved away or already occupied
			var feature_rng := RandomNumberGenerator.new()
			feature_rng.seed = instance_seed
			if feature is Callable:
				feature.call(writer, Vector3i(wx, h + 1, wz), feature_rng)
			else:
				Features.place(feature, writer, wx, h + 1, wz, feature_rng)
