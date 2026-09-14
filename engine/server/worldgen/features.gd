extends RefCounted
## World generation features: things placed on the ground (trees, cacti, boulders, crystal spikes,
## huge mushrooms). A feature is data {type, ...block names} or a Callable(writer, origin, rng) from a
## GDScript mod. Features may reach past their chunk: the generator places every feature whose origin
## lies within one chunk of the chunk being generated, and the Writer keeps only the blocks inside it.
##
## Built-in types:
##   tree:     trunk, leaves, height [min, max], shape "round" | "cone" | "tall" | "flat" | "blob"
##   column:   block, height [min, max]                      (cacti, bamboo-like stalks)
##   boulder:  block, radius [min, max]
##   spike:    block, height [min, max], radius, glow_block  (crystal spires)
##   mushroom: stem, cap, height [min, max], radius, light_block (huge mushrooms)
##   patch:    block, radius, count, on                      (a scatter of plants/blocks on the surface)

const Chunk = preload("res://engine/shared/chunk.gd")

const TYPES := ["tree", "column", "boulder", "spike", "mushroom", "patch"]


## Writes blocks into one chunk from world coordinates; anything outside the chunk is ignored.
class Writer:
	var blocks: PackedByteArray
	var origin_x := 0
	var origin_z := 0
	var solid: PackedByteArray
	var replaceable: PackedByteArray  # blocks features may overwrite (air, plants, leaves)

	func get_block(x: int, y: int, z: int) -> int:
		var lx := x - origin_x
		var lz := z - origin_z
		if lx < 0 or lz < 0 or lx >= Chunk.SIZE_X or lz >= Chunk.SIZE_Z or y < 0 or y >= Chunk.SIZE_Y:
			return -1
		return blocks.decode_u16(Chunk.index(lx, y, lz) << 1)

	## Places `id` if the spot is inside this chunk and free (or `force`).
	func set_block(x: int, y: int, z: int, id: int, force := false) -> void:
		var lx := x - origin_x
		var lz := z - origin_z
		if lx < 0 or lz < 0 or lx >= Chunk.SIZE_X or lz >= Chunk.SIZE_Z or y < 1 or y >= Chunk.SIZE_Y:
			return
		var index := Chunk.index(lx, y, lz) << 1
		var current := blocks.decode_u16(index)
		if force or current == 0 or (current < replaceable.size() and replaceable[current] == 1):
			blocks.encode_u16(index, id)


## Resolves block names in a data feature to ids. Returns {} if the feature is invalid.
static func resolve(def: Dictionary, block_id: Callable) -> Dictionary:
	var type := str(def.get("type", ""))
	if not type in TYPES:
		return {}
	var d := def.duplicate(true)
	for key in ["trunk", "leaves", "block", "glow_block", "stem", "cap", "light_block"]:
		if d.has(key):
			d[key] = int(block_id.call(str(d[key])))
	if d.get("on") is Array:
		d.on = (d.on as Array).map(func(n): return int(block_id.call(str(n))))
	for key in ["height", "radius"]:
		if d.get(key) is Array and d[key].size() == 2:
			d[key] = [int(d[key][0]), int(d[key][1])]
		elif d.has(key):
			d[key] = [int(d[key]), int(d[key])]
	return d


static func place(def: Dictionary, w: Writer, x: int, y: int, z: int, rng: RandomNumberGenerator) -> void:
	match def.type:
		"tree":
			_tree(def, w, x, y, z, rng)
		"column":
			var h := _range(def.get("height", [2, 3]), rng)
			for i in h:
				w.set_block(x, y + i, z, def.block)
		"boulder":
			var r := _range(def.get("radius", [1, 2]), rng)
			for dy in range(-1, r + 1):
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if dx * dx + dy * dy * 1.4 + dz * dz <= r * r + rng.randf() * 0.8:
							w.set_block(x + dx, y + dy, z + dz, def.block, true)
		"spike":
			var h := _range(def.get("height", [4, 8]), rng)
			var base_r := float(_range(def.get("radius", [1, 1]), rng))
			for i in h:
				var r := int(round(base_r * (1.0 - float(i) / h)))
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if dx * dx + dz * dz <= r * r:
							var glow: bool = def.get("glow_block", 0) > 0 and (i == h - 1 or rng.randf() < 0.12)
							w.set_block(x + dx, y + i, z + dz, def.glow_block if glow else def.block, true)
		"mushroom":
			var h := _range(def.get("height", [4, 7]), rng)
			var r := _range(def.get("radius", [2, 3]), rng)
			for i in h:
				w.set_block(x, y + i, z, def.stem)
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if absi(dx) == r and absi(dz) == r:
						continue
					var cap_y := y + h - (1 if absi(dx) == r or absi(dz) == r else 0)
					var lit: bool = def.get("light_block", 0) > 0 and rng.randf() < 0.08
					w.set_block(x + dx, cap_y, z + dz, def.light_block if lit else def.cap)
		"patch":
			var r := _range(def.get("radius", [2, 3]), rng)
			for i in int(def.get("count", 6)):
				var px := x + rng.randi_range(-r, r)
				var pz := z + rng.randi_range(-r, r)
				for py in range(y + 2, y - 3, -1):
					var below := w.get_block(px, py - 1, pz)
					if w.get_block(px, py, pz) == 0 and below > 0 and (not def.has("on") or def.on.has(below)):
						w.set_block(px, py, pz, def.block)
						break


static func _range(value, rng: RandomNumberGenerator) -> int:
	if value is Array and value.size() == 2:
		return rng.randi_range(int(value[0]), int(value[1]))
	return int(value)


static func _tree(def: Dictionary, w: Writer, x: int, y: int, z: int, rng: RandomNumberGenerator) -> void:
	var trunk_h := _range(def.get("height", [4, 6]), rng)
	var shape := str(def.get("shape", "round"))
	var top := y + trunk_h
	match shape:
		"cone":
			# Spruce: rings of leaves shrinking towards a pointed top.
			for i in range(0, trunk_h + 1):
				var ly := y + 2 + i
				var r := clampi(int(round((trunk_h + 1 - i) * 0.45)), 0, 3)
				if i % 2 == 1:
					r = maxi(r - 1, 0)
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if absi(dx) + absi(dz) <= r + (1 if r > 1 else 0):
							w.set_block(x + dx, ly, z + dz, def.leaves)
			w.set_block(x, top + 2, z, def.leaves)
			top = y + trunk_h + 1
		"flat":
			# Acacia: a leaning trunk with a wide flat crown.
			var lean := Vector2i([1, -1][rng.randi_range(0, 1)], 0) if rng.randf() < 0.5 else Vector2i(0, [1, -1][rng.randi_range(0, 1)])
			var tx := x
			var tz := z
			for i in trunk_h:
				if i == trunk_h - 2:
					tx += lean.x
					tz += lean.y
				w.set_block(tx, y + i, tz, def.trunk, true)
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					if absi(dx) + absi(dz) <= 4 and not (absi(dx) == 3 and absi(dz) == 3):
						w.set_block(tx + dx, top, tz + dz, def.leaves)
					if absi(dx) + absi(dz) <= 2:
						w.set_block(tx + dx, top + 1, tz + dz, def.leaves)
			return
		"tall":
			for ly in range(top - 3, top + 2):
				var r := 2 if ly < top else 1
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if absi(dx) == r and absi(dz) == r:
							continue
						w.set_block(x + dx, ly, z + dz, def.leaves)
		"blob":
			var r := 3
			for dy in range(-2, 3):
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if dx * dx + dy * dy * 2 + dz * dz <= r * r + rng.randf() * 2.0:
							w.set_block(x + dx, top + dy, z + dz, def.leaves)
		_:
			for ly in range(top - 2, top + 2):
				var r := 2 if ly < top else 1
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if absi(dx) == r and absi(dz) == r and (ly >= top or rng.randf() < 0.5):
							continue
						w.set_block(x + dx, ly, z + dz, def.leaves)
	for i in trunk_h:
		w.set_block(x, y + i, z, def.trunk, true)
