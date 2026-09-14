extends RefCounted
## Meshes for items held in hands (third person and first person) and shown in the world:
##   blocks: a small cube textured from the block atlas
##   items with a glTF `model`: that model
##   other items: the icon extruded into a 1-pixel-thick voxel mesh, like a pixel-art sword
## Meshes are cached per item id for the lifetime of the loaded content.

const ModelLibrary = preload("res://engine/client/model_library.gd")

const BLOCK_SIZE := 0.3
const ITEM_SIZE := 0.7

var items
var registry
var atlas := {}
var atlas_image: Image
## asset name -> {hash, size} and a reader for downloaded bytes.
var model_bytes: Callable

var _cache := {}  # id -> Mesh
var _material: StandardMaterial3D


func _init(item_registry, block_registry, atlas_info: Dictionary, read_model: Callable) -> void:
	items = item_registry
	registry = block_registry
	atlas = atlas_info
	model_bytes = read_model
	if not atlas.is_empty():
		atlas_image = atlas.texture.get_image()
	_material = StandardMaterial3D.new()
	_material.albedo_texture = atlas.get("texture")
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_material.roughness = 1.0
	_material.vertex_color_use_as_albedo = true


## A node showing the item, oriented for a hand attachment: +Y points out of the fist, -Z runs down
## the forearm. With `first_person` it is instead oriented for the view model: origin at the hand in
## camera space, the icon's face turned towards the camera. null for nothing.
func node_for(id: int, first_person := false, item_data := {}) -> Node3D:
	if id <= 0 or not items.is_valid(id) or atlas.is_empty():
		return null
	var mesh := mesh_for(id, item_data)
	if mesh == null:
		return null
	var holder := Node3D.new()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(instance)
	var def: Dictionary = items.get_def(id)
	var kind := "block" if id < 65536 else ("model" if not String(def.get("model", "")).is_empty() else "icon")
	# Grip and tip markers in the mesh's own space: swing trails run between them, held effects sit at the tip.
	var ends: Array = {"block": [Vector3(0, -BLOCK_SIZE * 0.5, 0), Vector3(0, BLOCK_SIZE * 0.5, 0)],
		"model": [Vector3.ZERO, Vector3(0, 1, 0)],
		"icon": [Vector3(-ITEM_SIZE * 0.2, -ITEM_SIZE * 0.2, 0), Vector3(ITEM_SIZE * 0.42, ITEM_SIZE * 0.42, 0)]}[kind]
	for i in 2:
		var marker := Node3D.new()
		marker.name = ["grip", "tip"][i]
		marker.position = ends[i]
		instance.add_child(marker)
	if first_person:
		match kind:
			"block":
				instance.position = Vector3(0, BLOCK_SIZE * 0.3, -BLOCK_SIZE * 0.2)
				instance.rotation_degrees = Vector3(0, 35, 0)
			"model":
				instance.scale = Vector3.ONE * 0.5
				instance.rotation_degrees = Vector3(0, 145, 0)
			_:
				# Icons are drawn handle bottom-left, tip top-right: mirror so the tip leans in towards the
				# crosshair, turn it to recede a little, and hold it by the handle.
				instance.rotation_degrees = Vector3(-10, 145, 0)
				instance.position = Vector3(-ITEM_SIZE * 0.22, ITEM_SIZE * 0.3, -ITEM_SIZE * 0.1)
		return holder
	match kind:
		"block":
			instance.position = Vector3(0, 0, -BLOCK_SIZE * 0.4)
			instance.rotation_degrees = Vector3(20, 45, 0)
		"model":
			instance.scale = Vector3.ONE * 0.5
		_:
			# Tools and weapons: turn the icon's diagonal to point out of the fist (+Y) with the flat
			# side facing sideways, and grip it near the handle.
			instance.rotation_degrees = Vector3(0, 90, 45)
			instance.position = Vector3(0, ITEM_SIZE * 0.36, 0)
	return holder


## Makes a held item node glow: {color, energy, light}. Additive, so pixels glow in their own colors.
func apply_glow(node: Node3D, glow: Dictionary) -> void:
	if node == null or glow.is_empty() or node.get_child_count() == 0:
		return
	var instance := node.get_child(0) as MeshInstance3D
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	overlay.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var model := instance.mesh != null and not (instance.mesh.surface_get_material(0) == _material)
	if not model:
		overlay.albedo_texture = atlas.get("texture")
	var color := Color.html(String(glow.color))
	var strength := clampf(float(glow.energy), 0.0, 8.0) * 0.45
	overlay.albedo_color = Color(color.r * strength, color.g * strength, color.b * strength)
	instance.material_overlay = overlay
	if float(glow.get("light", 0.0)) > 0.0:
		var light := OmniLight3D.new()
		light.name = "glow_light"
		light.light_color = color
		light.light_energy = clampf(float(glow.energy), 0.2, 4.0)
		light.omni_range = float(glow.light)
		light.shadow_enabled = false
		var tip := instance.get_node_or_null("tip")
		(tip if tip != null else node).add_child(light)


## Composed icons (ItemIcons) for stacks with icon_layers; set by the client.
var icons


func mesh_for(id: int, item_data := {}) -> Mesh:
	var layers = item_data.get("icon_layers") if item_data is Dictionary else null
	if layers is Array and not layers.is_empty() and icons != null:
		var key := str(layers)
		if not _cache.has(key):
			var img: Image = icons.composed(layers)
			_cache[key] = _extruded_image(img) if img != null else null
		if _cache[key] != null:
			return _cache[key]
	if _cache.has(id):
		return _cache[id]
	var mesh: Mesh = null
	var def: Dictionary = items.get_def(id)
	if id < 65536 and registry.is_valid(id):
		var block: Dictionary = registry.defs[id]
		if not String(block.get("model", "")).is_empty():
			mesh = _model(block.model)
		if mesh == null:
			mesh = _cube(block.textures)
	elif not String(def.get("model", "")).is_empty():
		mesh = _model(def.model)
	if mesh == null:
		mesh = _extruded(items.icon_of(id))
	_cache[id] = mesh
	return mesh


func _model(asset: String) -> Mesh:
	var bytes: PackedByteArray = model_bytes.call(asset)
	return ModelLibrary.load_mesh(bytes) if not bytes.is_empty() else null


func _cube(textures: Array) -> Mesh:
	var s := BLOCK_SIZE * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_material)
	# textures order: +X, -X, +Y, -Y, +Z, -Z
	var faces := [
		[Vector3.RIGHT, [Vector3(s, s, s), Vector3(s, s, -s), Vector3(s, -s, -s), Vector3(s, -s, s)], 0.8],
		[Vector3.LEFT, [Vector3(-s, s, -s), Vector3(-s, s, s), Vector3(-s, -s, s), Vector3(-s, -s, -s)], 0.8],
		[Vector3.UP, [Vector3(-s, s, -s), Vector3(s, s, -s), Vector3(s, s, s), Vector3(-s, s, s)], 1.0],
		[Vector3.DOWN, [Vector3(-s, -s, s), Vector3(s, -s, s), Vector3(s, -s, -s), Vector3(-s, -s, -s)], 0.5],
		[Vector3.BACK, [Vector3(-s, s, s), Vector3(s, s, s), Vector3(s, -s, s), Vector3(-s, -s, s)], 0.9],
		[Vector3.FORWARD, [Vector3(s, s, -s), Vector3(-s, s, -s), Vector3(-s, -s, -s), Vector3(s, -s, -s)], 0.9],
	]
	for i in 6:
		var rect: Rect2 = atlas.uv.get(textures[i] if i < textures.size() else "", atlas.uv[""])
		var uvs := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(faces[i][2], faces[i][2], faces[i][2]))
			st.set_normal(faces[i][0])
			st.set_uv(uvs[k])
			st.add_vertex(faces[i][1][k])
	return st.commit()


## The item's 2D icon as an image (composed icons included), or null for blocks and models.
func icon_image(id: int, item_data := {}) -> Image:
	var layers = item_data.get("icon_layers") if item_data is Dictionary else null
	if layers is Array and not layers.is_empty() and icons != null:
		return icons.composed(layers)
	if id < 65536 or atlas.is_empty() or not String(items.get_def(id).get("model", "")).is_empty():
		return null
	var rect: Rect2 = atlas.pixels.get(items.icon_of(id), atlas.pixels[""])
	return atlas_image.get_region(Rect2i(rect))


## The icon extruded with `bites` (0-3) bites taken out of its top-right edge, for eating. Falls back
## to the normal mesh for blocks and models.
func bitten_mesh(id: int, item_data: Dictionary, bites: int) -> Mesh:
	var img := icon_image(id, item_data)
	if bites <= 0 or img == null:
		return mesh_for(id, item_data)
	var key := "bitten|%d|%s|%d" % [id, str(item_data.get("icon_layers", "")), bites]
	if _cache.has(key):
		return _cache[key]
	img = img.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var size := img.get_size()
	var lo := Vector2(size)
	var hi := Vector2(-1, -1)
	for y in size.y:
		for x in size.x:
			if img.get_pixel(x, y).a > 0.5:
				lo = lo.min(Vector2(x, y))
				hi = hi.max(Vector2(x, y))
	if hi.x < 0:
		return mesh_for(id, item_data)
	var extent := (hi - lo + Vector2.ONE)
	var radius := maxf(extent.x, extent.y) * 0.27
	# Each bite is a circle nibbling inwards from the top-right, with a scalloped (toothy) edge.
	var centers := [Vector2(hi.x - extent.x * 0.02, lo.y + extent.y * 0.18), Vector2(hi.x - extent.x * 0.42, lo.y + extent.y * 0.02),
		Vector2(hi.x - extent.x * 0.05, lo.y + extent.y * 0.6)]
	for b in mini(bites, centers.size()):
		for y in size.y:
			for x in size.x:
				var d := Vector2(x, y).distance_to(centers[b])
				var teeth := 0.6 if (x + y) % 2 == 0 else 0.0
				if d < radius + teeth:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
	_cache[key] = _extruded_image(img)
	return _cache[key]


## A round plate to serve food on (lies in the XY plane like an icon; turn it flat where it is used).
func plate_mesh() -> Mesh:
	if _cache.has("plate"):
		return _cache.plate
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length()
			if d < 7.6:
				var rim := d > 5.8
				var shade := 0.93 + 0.04 * float((x * 7 + y * 3) % 3) / 2.0
				img.set_pixel(x, y, Color(0.72, 0.8, 0.9) * (1.0 if y < 8 else 0.9) if rim else Color(0.96, 0.94, 0.88) * shade)
	_cache.plate = _extruded_image(img)
	return _cache.plate


## Extrudes a standalone icon image (composed icons) with its own material.
func _extruded_image(img: Image) -> Mesh:
	var tile := img.get_width()
	var px := ITEM_SIZE / tile
	var depth := px
	var material := _material.duplicate() as StandardMaterial3D
	material.albedo_texture = ImageTexture.create_from_image(img)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material)
	var opaque := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < tile and y < tile and img.get_pixel(x, y).a > 0.5
	for y in tile:
		for x in tile:
			if not opaque.call(x, y):
				continue
			var x0 := (x - tile * 0.5) * px
			var x1 := x0 + px
			var y1 := (tile * 0.5 - y) * px
			var y0 := y1 - px
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / tile
			_face(st, [Vector3(x0, y1, depth), Vector3(x1, y1, depth), Vector3(x1, y0, depth), Vector3(x0, y0, depth)], Vector3.BACK, uv, 1.0)
			_face(st, [Vector3(x1, y1, -depth), Vector3(x0, y1, -depth), Vector3(x0, y0, -depth), Vector3(x1, y0, -depth)], Vector3.FORWARD, uv, 0.85)
			if not opaque.call(x, y - 1):
				_face(st, [Vector3(x0, y1, -depth), Vector3(x1, y1, -depth), Vector3(x1, y1, depth), Vector3(x0, y1, depth)], Vector3.UP, uv, 1.0)
			if not opaque.call(x, y + 1):
				_face(st, [Vector3(x0, y0, depth), Vector3(x1, y0, depth), Vector3(x1, y0, -depth), Vector3(x0, y0, -depth)], Vector3.DOWN, uv, 0.6)
			if not opaque.call(x - 1, y):
				_face(st, [Vector3(x0, y1, -depth), Vector3(x0, y1, depth), Vector3(x0, y0, depth), Vector3(x0, y0, -depth)], Vector3.LEFT, uv, 0.75)
			if not opaque.call(x + 1, y):
				_face(st, [Vector3(x1, y1, depth), Vector3(x1, y1, -depth), Vector3(x1, y0, -depth), Vector3(x1, y0, depth)], Vector3.RIGHT, uv, 0.75)
	return st.commit()


## Extrudes an icon: front and back faces for opaque pixels, side faces where a neighbour is empty.
func _extruded(icon: String) -> Mesh:
	var rect: Rect2 = atlas.pixels.get(icon, atlas.pixels[""])
	var uv_rect: Rect2 = atlas.uv.get(icon, atlas.uv[""])
	var tile := int(rect.size.x)
	var px := ITEM_SIZE / tile
	var depth := px
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_material)
	var opaque := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= tile or y >= tile:
			return false
		return atlas_image.get_pixel(int(rect.position.x) + x, int(rect.position.y) + y).a > 0.5
	for y in tile:
		for x in tile:
			if not opaque.call(x, y):
				continue
			var x0 := (x - tile * 0.5) * px
			var x1 := x0 + px
			var y1 := (tile * 0.5 - y) * px
			var y0 := y1 - px
			var uv := uv_rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) / tile * uv_rect.size
			_face(st, [Vector3(x0, y1, depth), Vector3(x1, y1, depth), Vector3(x1, y0, depth), Vector3(x0, y0, depth)], Vector3.BACK, uv, 1.0)
			_face(st, [Vector3(x1, y1, -depth), Vector3(x0, y1, -depth), Vector3(x0, y0, -depth), Vector3(x1, y0, -depth)], Vector3.FORWARD, uv, 0.85)
			if not opaque.call(x, y - 1):
				_face(st, [Vector3(x0, y1, -depth), Vector3(x1, y1, -depth), Vector3(x1, y1, depth), Vector3(x0, y1, depth)], Vector3.UP, uv, 1.0)
			if not opaque.call(x, y + 1):
				_face(st, [Vector3(x0, y0, depth), Vector3(x1, y0, depth), Vector3(x1, y0, -depth), Vector3(x0, y0, -depth)], Vector3.DOWN, uv, 0.6)
			if not opaque.call(x - 1, y):
				_face(st, [Vector3(x0, y1, -depth), Vector3(x0, y1, depth), Vector3(x0, y0, depth), Vector3(x0, y0, -depth)], Vector3.LEFT, uv, 0.75)
			if not opaque.call(x + 1, y):
				_face(st, [Vector3(x1, y1, depth), Vector3(x1, y1, -depth), Vector3(x1, y0, -depth), Vector3(x1, y0, depth)], Vector3.RIGHT, uv, 0.75)
	return st.commit()


static func _face(st: SurfaceTool, corners: Array, normal: Vector3, uv: Vector2, shade: float) -> void:
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(shade, shade, shade))
		st.set_normal(normal)
		st.set_uv(uv)
		st.add_vertex(corners[k])
