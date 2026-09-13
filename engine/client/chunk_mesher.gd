extends RefCounted
## Builds render arrays for one chunk. Uses the native mesher (flood-fill lighting + greedy merging)
## when available; the GDScript fallback emits one quad per visible face with approximate lighting
## (heightmap sky light, unoccluded distance falloff for block light). Both produce the vertex format
## documented in voxel_material.gd and are safe to run on worker threads.

const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const Chunk = preload("res://engine/shared/chunk.gd")
const Native = preload("res://engine/shared/native.gd")

## Surface format flags for Mesh.add_surface_from_arrays (CUSTOM0 holds 4 floats per vertex).
const SURFACE_FLAGS := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT


class Surface:
	# Corners per face, clockwise when viewed from outside (Godot's front-face winding).
	# Face order: +X, -X, +Y, -Y, +Z, -Z.
	const CORNERS := [
		[Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)],
		[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(0, 0, 0)],
		[Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)],
		[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1)],
		[Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)],
	]
	const NORMALS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	const SHADE := [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
	const UVS := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var uv2s := PackedVector2Array()
	var custom := PackedFloat32Array()
	var indices := PackedInt32Array()

	func add_face(origin: Vector3, face: int, tile: Rect2, lower_top: bool, sky: int, block: int, flags: float) -> void:
		var n := verts.size()
		var corners: Array = CORNERS[face]
		var normal: Vector3 = NORMALS[face]
		var color := Color(sky / 15.0, block / 15.0, SHADE[face])
		for k in 4:
			var c: Vector3 = corners[k]
			if lower_top and c.y > 0.5:
				c.y = 0.88
			verts.append(origin + c)
			normals.append(normal)
			colors.append(color)
			uvs.append(UVS[k])
			uv2s.append(Vector2(flags, 0.0))
			custom.append_array([tile.position.x, tile.position.y, tile.size.x, tile.size.y])
		indices.append_array([n, n + 1, n + 2, n, n + 2, n + 3])

	func to_arrays() -> Array:
		if verts.is_empty():
			return []
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_INDEX] = indices
		return arrays


## Builds the read-only context meshing threads need from the registry and atlas.
static func make_context(registry, atlas_uv: Dictionary) -> Dictionary:
	var face_uvs: Array[Rect2] = []
	for d in registry.defs:
		for tex: String in d.textures:
			face_uvs.append(atlas_uv.get(tex, atlas_uv[""]))
	var missing: Rect2 = atlas_uv[""]
	var emissive := PackedInt32Array()
	for d in registry.defs:
		if d.light > 0:
			emissive.append(d.id)
	var packed_uvs := PackedFloat32Array()
	for uv in face_uvs:
		packed_uvs.append_array([uv.position.x, uv.position.y, uv.size.x, uv.size.y])
	# Trailing "missing" tile for ids without an entry (e.g. from a misbehaving server).
	packed_uvs.append_array([missing.position.x, missing.position.y, missing.size.x, missing.size.y])
	return {
		"native": Native.enabled(),
		"packed_uvs": packed_uvs,
		"opaque": registry.opaque_lut,
		"render": registry.render_lut,
		"cull_same": registry.cull_same_lut,
		"liquid": registry.liquid_lut,
		"emission": registry.emission_lut,
		"emissive_ids": emissive,
		"sway": registry.sway_lut,
		"ambient_occlusion": true,
		"face_uvs": face_uvs,
		"missing_uv": missing,
	}


## `chunks`: 9 PackedByteArrays for the 3x3 neighbourhood, index (dx + 1) + (dz + 1) * 3, empty where
## not loaded. Returns [solid_arrays, translucent_arrays, models]; models is a PackedInt32Array of
## (block id, x, y, z, sky light, block light) per model block.
static func build(chunks: Array, ctx: Dictionary) -> Array:
	if ctx.native:
		return ClassDB.class_call_static(&"NativeMesher", &"build", chunks, ctx.opaque, ctx.render,
			ctx.cull_same, ctx.liquid, ctx.emission, ctx.sway, ctx.packed_uvs, true, ctx.ambient_occlusion)
	var blocks: PackedByteArray = chunks[4]
	var pos_x: PackedByteArray = chunks[5]
	var neg_x: PackedByteArray = chunks[3]
	var pos_z: PackedByteArray = chunks[7]
	var neg_z: PackedByteArray = chunks[1]
	var solid := Surface.new()
	var translucent := Surface.new()
	var models := PackedInt32Array()
	var opaque_lut: PackedByteArray = ctx.opaque
	var render_lut: PackedByteArray = ctx.render
	var cull_same_lut: PackedByteArray = ctx.cull_same
	var liquid_lut: PackedByteArray = ctx.liquid
	var face_uvs: Array[Rect2] = ctx.face_uvs
	var has_pos_x := not pos_x.is_empty()
	var has_neg_x := not neg_x.is_empty()
	var has_pos_z := not pos_z.is_empty()
	var has_neg_z := not neg_z.is_empty()
	const UNLOADED := BlockRegistry.UNLOADED
	const OPAQUE := BlockRegistry.Render.OPAQUE
	const TRANSLUCENT := BlockRegistry.Render.TRANSLUCENT
	const MODEL := BlockRegistry.Render.MODEL
	const TOP := Chunk.SIZE_Y - 1

	var empty_layer := PackedByteArray()
	empty_layer.resize(512)
	var top := TOP
	while top >= 0 and blocks.slice(top << 9, (top + 1) << 9) == empty_layer:
		top -= 1

	var light := ApproxLight.new(chunks, opaque_lut, ctx.emission, ctx.emissive_ids)
	const OFFSETS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	var neighbors := PackedInt32Array()
	neighbors.resize(6)
	for y in top + 1:
		for z in 16:
			for x in 16:
				var i := x + (z << 4) + (y << 8)
				var b := blocks.decode_u16(i << 1)
				var render := render_lut[b]
				if render == 0:
					continue
				if render == MODEL:
					var model_light := light.at(x, y, z)
					models.append_array([b, x, y, z, model_light[0], model_light[1]])
					continue
				neighbors[0] = blocks.decode_u16((i + 1) << 1) if x < 15 else (pos_x.decode_u16((i - 15) << 1) if has_pos_x else UNLOADED)
				neighbors[1] = blocks.decode_u16((i - 1) << 1) if x > 0 else (neg_x.decode_u16((i + 15) << 1) if has_neg_x else UNLOADED)
				neighbors[2] = blocks.decode_u16((i + 256) << 1) if y < TOP else 0
				neighbors[3] = blocks.decode_u16((i - 256) << 1) if y > 0 else UNLOADED
				neighbors[4] = blocks.decode_u16((i + 16) << 1) if z < 15 else (pos_z.decode_u16((i - 240) << 1) if has_pos_z else UNLOADED)
				neighbors[5] = blocks.decode_u16((i - 16) << 1) if z > 0 else (neg_z.decode_u16((i + 240) << 1) if has_neg_z else UNLOADED)
				var origin := Vector3(x, y, z)
				var uv_base := b * 6
				var flags := float(int(ctx.sway[b] != 0) | (int(liquid_lut[b] != 0) << 1) | (int(ctx.emission[b] != 0) << 2))

				if render == OPAQUE:
					for f in 6:
						if opaque_lut[neighbors[f]] == 0:
							var l := light.at(x + OFFSETS[f].x, y + OFFSETS[f].y, z + OFFSETS[f].z)
							solid.add_face(origin, f, face_uvs[uv_base + f] if uv_base + f < face_uvs.size() else ctx.missing_uv, false, l[0], l[1], flags)
				else:
					var cull_same := cull_same_lut[b] == 1
					var target := translucent if render == TRANSLUCENT else solid
					var lower := liquid_lut[b] == 1 and neighbors[2] != b
					for f in 6:
						var n := neighbors[f]
						if opaque_lut[n] == 0 and not (cull_same and n == b):
							var l := light.at(x + OFFSETS[f].x, y + OFFSETS[f].y, z + OFFSETS[f].z)
							target.add_face(origin, f, face_uvs[uv_base + f] if uv_base + f < face_uvs.size() else ctx.missing_uv, lower, l[0], l[1], flags)
	return [solid.to_arrays(), translucent.to_arrays(), models]


## Cheap lighting for the fallback mesher. Sky: full above the highest opaque block of a column,
## partial when a neighbouring column is open at that height, dark otherwise. Block light: emitter
## level minus Manhattan distance, ignoring occlusion.
class ApproxLight:
	var chunks: Array
	var opaque: PackedByteArray
	var heights := {}  # Vector2i local column -> highest opaque y (-1 = open)
	var emitters: Array = []  # [Vector3i local position, level]

	func _init(neighbourhood: Array, opaque_lut: PackedByteArray, emission: PackedByteArray, emissive_ids: PackedInt32Array) -> void:
		chunks = neighbourhood
		opaque = opaque_lut
		for cz in 3:
			for cx in 3:
				var data: PackedByteArray = chunks[cx + cz * 3]
				if data.is_empty():
					continue
				for id in emissive_ids:
					# Byte search for the low byte, confirmed at cell boundaries.
					var b := data.find(id & 255)
					while b != -1:
						if b % 2 == 0 and data.decode_u16(b) == id:
							var i := b >> 1
							var pos := Vector3i((i & 15) + (cx - 1) * 16, i >> 8, ((i >> 4) & 15) + (cz - 1) * 16)
							if absi(pos.x - 8) < 24 and absi(pos.z - 8) < 24:
								emitters.append([pos, emission[id]])
						b = data.find(id & 255, b + 1)

	func height(x: int, z: int) -> int:
		var key := Vector2i(x, z)
		if heights.has(key):
			return heights[key]
		var cx := clampi((x + 16) >> 4, 0, 2)
		var cz := clampi((z + 16) >> 4, 0, 2)
		var data: PackedByteArray = chunks[cx + cz * 3]
		var top := -1
		if not data.is_empty():
			var lx := clampi(x - (cx - 1) * 16, 0, 15)
			var lz := clampi(z - (cz - 1) * 16, 0, 15)
			for y in range(127, -1, -1):
				if opaque[data.decode_u16((lx + (lz << 4) + (y << 8)) << 1)] == 1:
					top = y
					break
		heights[key] = top
		return top

	## [sky, block] light (0-15) for a chunk-local cell.
	func at(x: int, y: int, z: int) -> PackedInt32Array:
		var sky := 15
		if y <= height(x, z):
			sky = 11 if y > mini(mini(height(x + 1, z), height(x - 1, z)), mini(height(x, z + 1), height(x, z - 1))) else 2
		var block := 0
		for e in emitters:
			var p: Vector3i = e[0]
			block = maxi(block, e[1] - (absi(p.x - x) + absi(p.y - y) + absi(p.z - z)))
		return PackedInt32Array([sky, block])
