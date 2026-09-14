extends RefCounted
## Item icons for UI and held items. Most items use their atlas icon; stacks whose item data has
## `icon_layers` ([{sprite, color}], e.g. tools built from parts) get an icon composed from those
## sprites, each multiplied by its color. Composed icons are cached by their layers.

const SIZE := 16
const MAX_CACHE := 512

var items
var atlas := {}
## Asset name -> Image (all downloaded PNGs).
var images := {}

var _images := {}  # layers key -> Image
var _textures := {}  # layers key -> ImageTexture


func texture(id: int, item_data := {}) -> Texture2D:
	if id <= 0 or not items.is_valid(id) or atlas.is_empty():
		return null
	var layers = item_data.get("icon_layers") if item_data is Dictionary else null
	if layers is Array and not layers.is_empty():
		var key := str(layers)
		if not _textures.has(key):
			var img := composed(layers)
			if img == null:
				return _atlas_texture(id)
			_trim()
			_textures[key] = ImageTexture.create_from_image(img)
		return _textures[key]
	return _atlas_texture(id)


## The composed image for layers, or null when none of the sprites are available.
func composed(layers: Array) -> Image:
	var key := str(layers)
	if _images.has(key):
		return _images[key]
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var any := false
	for layer in layers.slice(0, 8):
		if not (layer is Dictionary) or not images.has(str(layer.get("sprite", ""))):
			continue
		var sprite: Image = (images[layer.sprite] as Image).duplicate()
		sprite.convert(Image.FORMAT_RGBA8)
		if sprite.get_size() != Vector2i(SIZE, SIZE):
			sprite.resize(SIZE, SIZE, Image.INTERPOLATE_NEAREST)
		var tint := Color.html(str(layer.get("color", "#ffffff"))) if Color.html_is_valid(str(layer.get("color", ""))) else Color.WHITE
		for y in SIZE:
			for x in SIZE:
				var p := sprite.get_pixel(x, y)
				if p.a > 0.05:
					out.set_pixel(x, y, Color(p.r * tint.r, p.g * tint.g, p.b * tint.b, p.a))
		any = true
	if not any:
		return null
	_images[key] = out
	return out


func _atlas_texture(id: int) -> Texture2D:
	var tex := AtlasTexture.new()
	tex.atlas = atlas.texture
	tex.region = atlas.pixels.get(items.icon_of(id), atlas.pixels[""])
	return tex


func _trim() -> void:
	if _textures.size() >= MAX_CACHE:
		_textures.clear()
		_images.clear()
