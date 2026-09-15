extends RefCounted
## Turns avatar data (see Cosmetics) into what an Avatar draws: a skin texture composed from body
## colors, the face and clothing layers, and accessory nodes for attachment points. Results are cached
## so players sharing a look share textures and meshes.

const Cosmetics = preload("res://engine/shared/cosmetics.gd")
const SkinCompositor = preload("res://engine/client/avatar/skin_compositor.gd")
const PlayerRig = preload("res://engine/shared/player_rig.gd")
const ModelLibrary = preload("res://engine/client/model_library.gd")

const MAX_CACHE := 128

var cosmetics: Cosmetics
## Asset name -> Image (server cosmetic textures).
var images := {}
## Asset name -> glTF bytes (server cosmetic models).
var read_model: Callable

var _skins := {}  # key -> ImageTexture
var _meshes := {}  # key -> Mesh
var _box_material: StandardMaterial3D


func _init(registry: Cosmetics, asset_images := {}, model_reader := Callable()) -> void:
	cosmetics = registry
	images = asset_images
	read_model = model_reader
	_box_material = StandardMaterial3D.new()
	_box_material.vertex_color_use_as_albedo = true
	_box_material.vertex_color_is_srgb = true
	_box_material.roughness = 1.0


## Forgets cached skins and meshes (after cosmetics or their images change).
func clear_cache() -> void:
	_skins.clear()
	_meshes.clear()


## The avatar to draw: the player's own data, or the default look for their name.
static func resolve(avatar: Dictionary, name_text: String) -> Dictionary:
	return avatar if not avatar.is_empty() else Cosmetics.default_avatar(name_text)


## Dresses an Avatar node with `avatar` data (skin and accessories; armor and held items are separate).
func apply(target, avatar: Dictionary, name_text: String) -> void:
	var look := resolve(avatar, name_text)
	target.set_skin(skin_texture(look))
	target.set_accessories(accessories(look, float(target.rig.get("height", 1.8)) / 1.8 * PlayerRig.PIXEL))


func skin_texture(look: Dictionary) -> ImageTexture:
	var key := JSON.stringify([look.get("skin", ""), look.get("body", {}), look.get("wear", {})])
	if _skins.has(key):
		return _skins[key]
	if _skins.size() >= MAX_CACHE:
		_skins.clear()
	var texture := ImageTexture.create_from_image(skin_image(look))
	_skins[key] = texture
	return texture


## The composed 64x64 skin: body colors, face, then clothing layers in category order.
func skin_image(look: Dictionary) -> Image:
	var skin := Color.html(String(look.get("skin", "#e8b48c")))
	var colors := {}
	for part in Cosmetics.BODY_PARTS:
		colors[part] = Color.html(String(look.get("body", {}).get(part, "#" + skin.to_html(false))))
	var face: Image = null
	var layers := []
	var wear: Dictionary = look.get("wear", {})
	# A whole painted skin replaces the painted layers (face, clothes); 3D accessories still show.
	var whole_skin: bool = not cosmetics.get_def(String(wear.get("skin", {}).get("id", ""))).get("texture", "").is_empty()
	for cat in cosmetics.categories:
		if not wear.has(cat.name):
			continue
		var d := cosmetics.get_def(String(wear[cat.name].get("id", "")))
		if d.is_empty() or (whole_skin and cat.name != "skin"):
			continue
		var tint := Color.html(String(wear[cat.name].get("color", d.color)))
		if not d.pixels.is_empty():
			face = _face_image(d.pixels, tint, colors.head)
		var layer := _layer_image(d, tint)
		if layer != null:
			layers.append(layer)
	return SkinCompositor.compose_skin(colors, face, layers)


## [{attach, node}] for cosmetics with boxes or models.
func accessories(look: Dictionary, pixel: float) -> Array:
	var out := []
	var wear: Dictionary = look.get("wear", {})
	for cat in cosmetics.categories:
		if cat.attach.is_empty() or not wear.has(cat.name):
			continue
		var d := cosmetics.get_def(String(wear[cat.name].get("id", "")))
		if d.is_empty() or (d.boxes.is_empty() and d.model.is_empty()):
			continue
		var tint := Color.html(String(wear[cat.name].get("color", d.color)))
		var holder := Node3D.new()
		holder.name = "cosmetic_" + cat.name
		holder.scale = Vector3.ONE * pixel  # accessories are laid out in skin pixels
		if not d.boxes.is_empty():
			var instance := MeshInstance3D.new()
			instance.mesh = _box_mesh(d, tint)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(instance)
		if not d.model.is_empty() and read_model.is_valid():
			var mesh := _model_mesh(d.model)
			if mesh != null:
				var instance := MeshInstance3D.new()
				instance.mesh = mesh
				var t: Dictionary = d.model_transform
				instance.position = Vector3(t.position[0], t.position[1], t.position[2])
				instance.rotation_degrees = Vector3(t.rotation[0], t.rotation[1], t.rotation[2])
				instance.scale = Vector3.ONE * float(t.scale) / pixel  # models are sized in blocks
				holder.add_child(instance)
		out.append({"attach": cat.attach, "node": holder})
	return out


func _face_image(pixels: Dictionary, tint: Color, skin: Color) -> Image:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 8:
		var row: String = pixels.rows[y]
		for x in 8:
			var entry := String(pixels.palette.get(row[x], ""))
			if entry.is_empty():
				continue
			var c := tint if entry == "tint" else (skin.darkened(0.18) if entry == "skin" else Color.html(entry))
			img.set_pixel(x, y, c)
	return img


func _layer_image(d: Dictionary, tint: Color) -> Image:
	if d.paint.is_empty() and d.texture.is_empty():
		return null
	var img := Image.create(SkinCompositor.BASE, SkinCompositor.BASE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if not d.texture.is_empty() and images.has(d.texture):
		img = (images[d.texture] as Image).duplicate()
		img.convert(Image.FORMAT_RGBA8)
		if d.tint:
			for y in img.get_height():
				for x in img.get_width():
					var p := img.get_pixel(x, y)
					if p.a > 0.0:
						img.set_pixel(x, y, Color(p.r * tint.r, p.g * tint.g, p.b * tint.b, p.a))
	var scale := img.get_width() / SkinCompositor.BASE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(d.name)
	for op in d.paint:
		var base: Color = tint if op.color.is_empty() else Color.html(op.color)
		base = Color(base.r * op.shade, base.g * op.shade, base.b * op.shade)
		for rect in side_rects(PlayerRig.REGIONS[op.region], op.rows[0], op.rows[1], op.get("sides", Cosmetics.SIDES)):
			for y in range(rect.position.y * scale, rect.end.y * scale):
				for x in range(rect.position.x * scale, rect.end.x * scale):
					var shade := 1.0 + rng.randf_range(-0.04, 0.04)  # a little cloth texture
					img.set_pixel(x, y, Color(base.r * shade, base.g * shade, base.b * shade, 1.0))
	return img


## Rectangles of a region [u, v, w, h, d] for the chosen sides, limited to rows of the side height.
static func side_rects(r: Array, row_from: int, row_to: int, sides: Array) -> Array[Rect2i]:
	var u: int = r[0]
	var v: int = r[1]
	var w: int = r[2]
	var h: int = r[3]
	var d: int = r[4]
	row_from = clampi(row_from, 0, h)
	row_to = clampi(row_to, row_from, h)
	var rects: Array[Rect2i] = []
	if row_from == 0 and sides.has("top"):
		rects.append(Rect2i(u + d, v, w, d))
	if row_to == h and sides.has("bottom"):
		rects.append(Rect2i(u + d + w, v, w, d))
	if row_to > row_from:
		var y := v + d + row_from
		var n := row_to - row_from
		for side in [["right", u, d], ["front", u + d, w], ["left", u + d + w, d], ["back", u + 2 * d + w, w]]:
			if sides.has(side[0]):
				rects.append(Rect2i(side[1], y, side[2], n))
	return rects


func _box_mesh(d: Dictionary, tint: Color) -> Mesh:
	var key := "%s|%s" % [d.name, tint.to_html()]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_box_material)
	for b in d.boxes:
		var c: Color = tint if b.color.is_empty() else Color.html(b.color)
		c = Color(c.r * b.shade, c.g * b.shade, c.b * b.shade)
		var lo := Vector3(b.from[0], b.from[1], b.from[2])
		var hi := lo + Vector3(b.size[0], b.size[1], b.size[2])
		_add_box(st, lo, hi, c)
	var mesh := st.commit()
	if _meshes.size() >= MAX_CACHE:
		_meshes.clear()
	_meshes[key] = mesh
	return mesh


static func _add_box(st: SurfaceTool, lo: Vector3, hi: Vector3, color: Color) -> void:
	var faces := [
		[Vector3.UP, [Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]],
		[Vector3.DOWN, [Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(lo.x, lo.y, lo.z)]],
		[Vector3.FORWARD, [Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z)]],
		[Vector3.BACK, [Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z)]],
		[Vector3.RIGHT, [Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z)]],
		[Vector3.LEFT, [Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z)]],
	]
	for face in faces:
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(color)
			st.set_normal(face[0])
			st.add_vertex(face[1][k])


func _model_mesh(asset: String) -> Mesh:
	if _meshes.has(asset):
		return _meshes[asset]
	var bytes: PackedByteArray = read_model.call(asset)
	var mesh: Mesh = ModelLibrary.load_mesh(bytes) if not bytes.is_empty() else null
	_meshes[asset] = mesh
	return mesh
