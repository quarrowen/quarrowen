extends RefCounted
## Structures for the biome generator: templates (saved builds) and code-built layouts placed across
## chunks with rotation, per-biome material swaps, loot and spawner data.
##
## Template (JSON, e.g. saved with /struct save): {size: [x, y, z], palette: [block names], blocks:
## [[x, y, z, palette index, state], ...], data: {"x,y,z": {...}}} where data holds block data such as
## {"loot": "vanilla:dungeon"} for chests or {"spawner": {...}} for spawners. Palette entries that are
## "engine:air" clear terrain; cells not listed keep whatever was there.
##
## Structure (register_structure): {templates: [{template, weight}] or generator: Callable(origin,
## rng, structures) -> [{template, position, rotation}] (GDScript), spacing (region size in chunks,
## one structure at most per region), separation (chunks kept free at the region edge), salt, biomes,
## place: "surface" | "underground", y: [min, max] (underground), sink (blocks into the ground),
## foundation (block filling down to the ground under surface structures), swaps: {biome: {block:
## block}}, reach (chunks the structure may extend from its start; default from its size)}.
## Everything is computed from the world seed and the region, so every chunk agrees.

const Chunk = preload("res://engine/shared/chunk.gd")
const BlockRegistry = preload("res://engine/shared/block_registry.gd")

var world_seed := 0
var templates := {}  # name -> {size: Vector3i, blocks: Array [x, y, z, id, state], data: {Vector3i: Dictionary}}
var sets: Array[Dictionary] = []

var _block_id: Callable
var _orientation := PackedByteArray()
var _cache := {}
var _cache_order: Array = []
var _mutex := Mutex.new()


func _init(seed_value: int, block_id: Callable) -> void:
	world_seed = seed_value
	_block_id = block_id


## Parses a template dictionary (from JSON). Unknown blocks are skipped. Returns false if invalid.
func add_template(template_name: String, doc: Dictionary) -> bool:
	if not (doc.get("size") is Array) or doc.size.size() != 3 or not (doc.get("palette") is Array) or not (doc.get("blocks") is Array):
		return false
	var palette := []
	for entry in doc.palette:
		var name := str(entry)
		palette.append(0 if name == "engine:air" else int(_block_id.call(name)))
	var blocks := []
	var dropped := 0
	for b in doc.blocks:
		if b is Array and b.size() >= 4:
			var id: int = palette[int(b[3])] if int(b[3]) >= 0 and int(b[3]) < palette.size() else -1
			if id >= 0:
				blocks.append([int(b[0]), int(b[1]), int(b[2]), id, int(b[4]) if b.size() > 4 else 0])
			else:
				dropped += 1
		else:
			dropped += 1
	if dropped > 0:
		# Say so. Dropping quietly means a structure that stamps with holes in it and nothing to explain
		# them - the author sees this at pack time from mod_validator, but whoever is running a mod
		# somebody else wrote only ever gets this line. (2026-09-18)
		push_error("Structure '%s': %d of %d blocks name a palette entry that does not exist, or are malformed, and were left out" % [
			template_name, dropped, (doc.blocks as Array).size()])
	var data := {}
	if doc.get("data") is Dictionary:
		var bad_keys := 0
		for key in doc.data:
			var parts := str(key).split(",")
			if parts.size() == 3 and doc.data[key] is Dictionary:
				data[Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))] = doc.data[key]
			else:
				bad_keys += 1
		if bad_keys > 0:
			push_error("Structure '%s': %d data keys are not \"x,y,z\" with an object, and were left out" % [template_name, bad_keys])
	templates[template_name] = {"size": Vector3i(int(doc.size[0]), int(doc.size[1]), int(doc.size[2])), "blocks": blocks, "data": data}
	return true


func add_set(set_name: String, def: Dictionary) -> void:
	var s := {"name": set_name, "spacing": clampi(int(def.get("spacing", 24)), 2, 256), "separation": clampi(int(def.get("separation", 6)), 0, 255),
		"salt": str(def.get("salt", set_name)), "biomes": def.get("biomes", []) if def.get("biomes") is Array else [],
		"place": str(def.get("place", "surface")), "y": def.get("y", [12, 40]) if def.get("y") is Array else [12, 40],
		"sink": int(def.get("sink", 0)), "foundation": int(_block_id.call(str(def.foundation))) if def.has("foundation") else 0,
		"templates": [], "generator": def.get("generator", Callable()) if def.get("generator") is Callable else Callable(),
		"swaps": {}, "reach": int(def.get("reach", 0)), "chance": clampf(float(def.get("chance", 1.0)), 0.0, 1.0)}
	s.separation = mini(s.separation, s.spacing - 1)
	for t in (def.get("templates") if def.get("templates") is Array else []):
		if t is Dictionary:
			s.templates.append({"template": str(t.get("template", "")), "weight": maxf(float(t.get("weight", 1.0)), 0.0)})
	if def.get("swaps") is Dictionary:
		for biome in def.swaps:
			var map := {}
			for from in def.swaps[biome]:
				map[int(_block_id.call(str(from)))] = int(_block_id.call(str(def.swaps[biome][from])))
			s.swaps[str(biome)] = map
	sets.append(s)


## Rotates a local template position (y unchanged) inside a template of `size`.
static func rotate(p: Vector3i, size: Vector3i, rotation: int) -> Vector3i:
	match rotation & 3:
		1:
			return Vector3i(size.z - 1 - p.z, p.y, p.x)
		2:
			return Vector3i(size.x - 1 - p.x, p.y, size.z - 1 - p.z)
		3:
			return Vector3i(p.z, p.y, size.x - 1 - p.x)
	return p


static func rotated_size(size: Vector3i, rotation: int) -> Vector3i:
	return Vector3i(size.z, size.y, size.x) if rotation & 1 == 1 else size


## The structure a region holds, or {} (cached; safe to call from worker threads).
func start_for(s: Dictionary, region: Vector2i, gen) -> Dictionary:
	var key := "%s|%d|%d" % [s.name, region.x, region.y]
	_mutex.lock()
	var cached = _cache.get(key)
	_mutex.unlock()
	if cached != null:
		return cached
	var result := _compute_start(s, region, gen)
	_mutex.lock()
	_cache[key] = result
	_cache_order.append(key)
	if _cache_order.size() > 512:
		_cache.erase(_cache_order.pop_front())
	_mutex.unlock()
	return result


func _compute_start(s: Dictionary, region: Vector2i, gen) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, s.salt, region.x, region.y])
	if rng.randf() > s.chance:
		return {}
	var chunk: Vector2i = region * s.spacing + Vector2i(rng.randi_range(0, s.spacing - 1 - s.separation), rng.randi_range(0, s.spacing - 1 - s.separation))
	var x: int = chunk.x * Chunk.SIZE_X + rng.randi_range(2, 13)
	var z: int = chunk.y * Chunk.SIZE_Z + rng.randi_range(2, 13)
	var column: Dictionary = gen.column(x, z)
	var biome: String = gen.biomes[column.biome].name
	if not s.biomes.is_empty() and not s.biomes.has(biome):
		return {}
	var y: int
	if s.place == "underground":
		y = rng.randi_range(int(s.y[0]), mini(int(s.y[1]), int(column.height) - 12))
		if y < 4:
			return {}
	else:
		if int(column.height) < gen.sea_level:
			return {}  # no surface structures under water
		y = int(column.height) + 1 - s.sink
	var origin := Vector3i(x, y, z)
	var pieces := []
	if s.generator.is_valid():
		pieces = s.generator.call(origin, rng, self)
	else:
		var template := _pick(s.templates, rng)
		if template.is_empty() or not templates.has(template):
			return {}
		var rotation := rng.randi_range(0, 3)
		var size: Vector3i = rotated_size(templates[template].size, rotation)
		pieces = [{"template": template, "position": origin - Vector3i(size.x / 2, 0, size.z / 2), "rotation": rotation}]
	var lo := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var hi := -lo
	var valid := []
	for piece in pieces:
		if not (piece is Dictionary) or not templates.has(str(piece.get("template", ""))):
			continue
		var t: Dictionary = templates[piece.template]
		var rotation: int = int(piece.get("rotation", 0)) & 3
		var pos: Vector3i = piece.position
		var size := rotated_size(t.size, rotation)
		valid.append({"template": piece.template, "position": pos, "rotation": rotation, "size": size})
		lo = Vector3i(mini(lo.x, pos.x), mini(lo.y, pos.y), mini(lo.z, pos.z))
		hi = Vector3i(maxi(hi.x, pos.x + size.x), maxi(hi.y, pos.y + size.y), maxi(hi.z, pos.z + size.z))
	if valid.is_empty():
		return {}
	return {"name": s.name, "origin": origin, "biome": biome, "pieces": valid, "lo": lo, "hi": hi, "seed": rng.randi()}


func _pick(list: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for t in list:
		total += t.weight
	var roll := rng.randf() * total
	for t in list:
		roll -= t.weight
		if roll <= 0.0:
			return t.template
	return list.back().template if not list.is_empty() else ""


## Writes every structure piece that overlaps this chunk. `data` collects block data {Vector3i: dict}.
func place_in_chunk(chunk, gen, writer, data: Dictionary) -> void:
	if sets.is_empty():
		return
	var coord: Vector2i = chunk.coord
	var chunk_lo := Vector3i(coord.x * Chunk.SIZE_X, 0, coord.y * Chunk.SIZE_Z)
	var chunk_hi := chunk_lo + Vector3i(Chunk.SIZE_X, Chunk.SIZE_Y, Chunk.SIZE_Z)
	for s in sets:
		var reach: int = s.reach if s.reach > 0 else 2
		var r0 := Vector2i(floori(float(coord.x - reach) / s.spacing), floori(float(coord.y - reach) / s.spacing))
		var r1 := Vector2i(floori(float(coord.x + reach) / s.spacing), floori(float(coord.y + reach) / s.spacing))
		for rz in range(r0.y, r1.y + 1):
			for rx in range(r0.x, r1.x + 1):
				var start := start_for(s, Vector2i(rx, rz), gen)
				if start.is_empty():
					continue
				if start.hi.x <= chunk_lo.x or start.lo.x >= chunk_hi.x or start.hi.z <= chunk_lo.z or start.lo.z >= chunk_hi.z:
					continue
				var swaps: Dictionary = s.swaps.get(start.biome, {})
				for piece in start.pieces:
					_write_piece(s, start, piece, writer, data, swaps, chunk_lo, chunk_hi, gen)


func _write_piece(s: Dictionary, start: Dictionary, piece: Dictionary, writer, data: Dictionary, swaps: Dictionary,
		chunk_lo: Vector3i, chunk_hi: Vector3i, gen) -> void:
	var t: Dictionary = templates[piece.template]
	var pos: Vector3i = piece.position
	var size: Vector3i = piece.size
	if pos.x + size.x <= chunk_lo.x or pos.x >= chunk_hi.x or pos.z + size.z <= chunk_lo.z or pos.z >= chunk_hi.z:
		return
	for b in t.blocks:
		var p: Vector3i = pos + rotate(Vector3i(b[0], b[1], b[2]), t.size, piece.rotation)
		if p.x < chunk_lo.x or p.x >= chunk_hi.x or p.z < chunk_lo.z or p.z >= chunk_hi.z:
			continue
		var id: int = swaps.get(b[3], b[3])
		writer.set_block(p.x, p.y, p.z, id, true)
		if b[4] != 0 or id != 0:
			writer.set_state(p.x, p.y, p.z, _rotate_state(id, b[4], piece.rotation))
	# Surface structures stand on a foundation reaching down to the ground.
	if s.foundation > 0 and s.place == "surface" and pos.y == start.origin.y:
		for lx in size.x:
			for lz in size.z:
				var wx := pos.x + lx
				var wz := pos.z + lz
				if wx < chunk_lo.x or wx >= chunk_hi.x or wz < chunk_lo.z or wz >= chunk_hi.z:
					continue
				for y in range(pos.y - 1, maxi(pos.y - 12, 1), -1):
					var current: int = writer.get_block(wx, y, wz)
					if current > 0 and writer.solid[current] == 1:
						break
					writer.set_block(wx, y, wz, swaps.get(s.foundation, s.foundation), true)
	for local: Vector3i in t.data:
		var p: Vector3i = pos + rotate(local, t.size, piece.rotation)
		if p.x < chunk_lo.x or p.x >= chunk_hi.x or p.z < chunk_lo.z or p.z >= chunk_hi.z:
			continue
		var entry: Dictionary = t.data[local].duplicate(true)
		entry.structure_seed = hash([start.seed, p.x, p.y, p.z])
		data[p] = entry


func _rotate_state(id: int, state: int, rotation: int) -> int:
	if rotation == 0 or not _is_oriented(id):
		return state
	var facing := ((state & 3) + rotation) & 3
	return facing | (state & ~3)


func _is_oriented(id: int) -> bool:
	return id < _orientation.size() and _orientation[id] == 1


func freeze(registry) -> void:
	_orientation.resize(registry.defs.size())
	for i in registry.defs.size():
		_orientation[i] = 1 if int(registry.defs[i].get("orientation", 0)) == 1 else 0


## A template dictionary (JSON-ready) from a region of a world. `keep_air`: leave air cells out (the
## structure then keeps the terrain there). Block data in the region (chest contents, spawner settings)
## goes into `data`.
static func capture(server, lo: Vector3i, hi: Vector3i, keep_air := false) -> Dictionary:
	var a := Vector3i(mini(lo.x, hi.x), mini(lo.y, hi.y), mini(lo.z, hi.z))
	var b := Vector3i(maxi(lo.x, hi.x), maxi(lo.y, hi.y), maxi(lo.z, hi.z))
	var palette := []
	var index := {}
	var blocks := []
	var data := {}
	for y in range(a.y, b.y + 1):
		for z in range(a.z, b.z + 1):
			for x in range(a.x, b.x + 1):
				var pos := Vector3i(x, y, z)
				var id: int = server.get_block_loaded(pos)
				if id == BlockRegistry.UNLOADED or (id == 0 and keep_air):
					continue
				var name: String = "engine:air" if id == 0 else server.registry.defs[id].name
				if not index.has(name):
					index[name] = palette.size()
					palette.append(name)
				var local := pos - a
				var state: int = server.get_block_state(pos)
				blocks.append([local.x, local.y, local.z, index[name], state] if state != 0 else [local.x, local.y, local.z, index[name]])
				var block_data: Dictionary = server.get_block_data(pos)
				if not block_data.is_empty():
					data["%d,%d,%d" % [local.x, local.y, local.z]] = block_data.duplicate(true)
	return {"size": [b.x - a.x + 1, b.y - a.y + 1, b.z - a.z + 1], "palette": palette, "blocks": blocks, "data": data}
