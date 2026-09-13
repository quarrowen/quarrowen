extends RefCounted
## Loads block models (glTF binary assets downloaded from the server) into single ArrayMeshes that
## can be drawn with MultiMesh. Reads the CPU-side glTF state directly, so it also works headless.

const MAX_VERTICES := 65536


## Returns null if the bytes are not a usable model.
static func load_mesh(bytes: PackedByteArray) -> ArrayMesh:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if bytes.is_empty() or doc.append_from_buffer(bytes, "", state) != OK:
		return null
	var nodes := state.get_nodes()
	var meshes := state.get_meshes()
	var out := ArrayMesh.new()
	var vertex_count := 0
	for i in nodes.size():
		var node: GLTFNode = nodes[i]
		if node.mesh < 0 or node.mesh >= meshes.size():
			continue
		var xform := _global_transform(nodes, i)
		var importer: ImporterMesh = meshes[node.mesh].mesh
		for s in importer.get_surface_count():
			var arrays := importer.get_surface_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			vertex_count += verts.size()
			if vertex_count > MAX_VERTICES:
				push_warning("[models] Model exceeds %d vertices; truncated" % MAX_VERTICES)
				return out
			for v in verts.size():
				verts[v] = xform * verts[v]
			arrays[Mesh.ARRAY_VERTEX] = verts
			if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array:
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var basis := xform.basis.inverse().transposed()
				for n in normals.size():
					normals[n] = (basis * normals[n]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TANGENT] = null
			out.add_surface_from_arrays(importer.get_surface_primitive_type(s), arrays)
			out.surface_set_material(out.get_surface_count() - 1, _prepare_material(importer.get_surface_material(s)))
	return out if out.get_surface_count() > 0 else null


## For animated entities: one entry per glTF node with a mesh, {name, mesh, transform}, where the
## transform is the node's global transform (its pivot) and the mesh stays in node space so the part
## can rotate around its pivot. Returns [] if the bytes are not a usable model.
static func load_parts(bytes: PackedByteArray) -> Array:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if bytes.is_empty() or doc.append_from_buffer(bytes, "", state) != OK:
		return []
	var nodes := state.get_nodes()
	var meshes := state.get_meshes()
	var parts := []
	var vertex_count := 0
	for i in nodes.size():
		var node: GLTFNode = nodes[i]
		if node.mesh < 0 or node.mesh >= meshes.size():
			continue
		var importer: ImporterMesh = meshes[node.mesh].mesh
		var mesh := ArrayMesh.new()
		for s in importer.get_surface_count():
			var arrays := importer.get_surface_arrays(s)
			vertex_count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if vertex_count > MAX_VERTICES:
				return parts
			arrays[Mesh.ARRAY_TANGENT] = null
			mesh.add_surface_from_arrays(importer.get_surface_primitive_type(s), arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _prepare_material(importer.get_surface_material(s)))
		var part_name := String(node.original_name) if not String(node.original_name).is_empty() else String(node.resource_name)
		parts.append({"name": part_name, "mesh": mesh, "transform": _global_transform(nodes, i)})
	return parts


static func _global_transform(nodes: Array[GLTFNode], index: int) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var i := index
	var guard := 0
	while i >= 0 and guard < 64:
		var n: GLTFNode = nodes[i]
		xform = Transform3D(Basis(n.rotation).scaled(n.scale), n.position) * xform
		i = n.parent
		guard += 1
	return xform


## Nearest filtering to match the voxel look; instance colors carry the block's light level.
static func _prepare_material(source: Material) -> Material:
	var material: StandardMaterial3D = source.duplicate() if source is StandardMaterial3D else StandardMaterial3D.new()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	return material
