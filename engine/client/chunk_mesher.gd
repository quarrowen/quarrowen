extends RefCounted
## Builds render arrays for one chunk: flood-fill lighting and greedy merging, in Rust
## (`native/src/mesher.rs`), producing the vertex format documented in voxel_material.gd. Safe to run
## on worker threads.
##
## **There was a GDScript twin here until 2026-09-23 and it was never the same mesher.** It emitted
## one quad per visible face with approximate lighting - on the benchmark's flat terrain, 30,720 quads
## against the native 120, and a different light model. So the two builds did not draw the same world,
## which is the strongest argument against having had two.

const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const Chunk = preload("res://engine/shared/chunk.gd")

## Surface format flags for Mesh.add_surface_from_arrays (CUSTOM0 holds 4 floats per vertex).
## **Not `ARRAY_FLAG_COMPRESS_ATTRIBUTES`.** It halves vertex memory and is the obvious answer to a
## memory-bound vertex shader, and it visibly breaks this mesh: the baked light and ambient occlusion
## live in `ARRAY_COLOR`, which it quantises, and normals become octahedral. Rendered side by side,
## dirt went bright orange, grass over-saturated, pale seams appeared between blocks and the terrain
## shadows disappeared entirely. Any compression here has to leave COLOR alone. (2026-09-22)
const SURFACE_FLAGS := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT


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
		"packed_uvs": packed_uvs,
		"opaque": registry.opaque_lut,
		"render": registry.render_lut,
		"cull_same": registry.cull_same_lut,
		"liquid": registry.liquid_lut,
		"shape": registry.shape_lut,
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
	return ClassDB.class_call_static(&"NativeMesher", &"build", chunks, ctx.opaque, ctx.render,
		ctx.cull_same, ctx.liquid, ctx.emission, ctx.sway, ctx.packed_uvs, true, ctx.ambient_occlusion, ctx.shape)
