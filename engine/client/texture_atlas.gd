extends RefCounted
## Packs block textures downloaded from the server into one nearest-filtered atlas.

const MIN_TILE := 16
const MAX_TILE := 128
const MISSING := ""


## `images`: asset name -> Image. Returns {texture, uv: name -> Rect2, pixels: name -> Rect2}.
## Unknown names should fall back to the MISSING ("") entry, a magenta checker.
static func build(images: Dictionary) -> Dictionary:
	var names: Array = images.keys()
	names.sort()
	names.push_front(MISSING)
	var tile := MIN_TILE
	for img: Image in images.values():
		tile = maxi(tile, maxi(img.get_width(), img.get_height()))
	tile = mini(tile, MAX_TILE)

	var columns := maxi(1, ceili(sqrt(names.size())))
	var rows := ceili(names.size() / float(columns))
	var atlas := Image.create(columns * tile, rows * tile, false, Image.FORMAT_RGBA8)
	var atlas_size := Vector2(atlas.get_width(), atlas.get_height())
	var inset := Vector2(0.01, 0.01) / atlas_size
	var uv := {}
	var pixels := {}
	for i in names.size():
		var name: String = names[i]
		var cell := Vector2i((i % columns) * tile, (i / columns) * tile)
		var img: Image = images.get(name, _missing_image(tile))
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != tile or img.get_height() != tile:
			img.resize(tile, tile, Image.INTERPOLATE_NEAREST)
		atlas.blit_rect(img, Rect2i(0, 0, tile, tile), cell)
		pixels[name] = Rect2(cell, Vector2(tile, tile))
		uv[name] = Rect2(Vector2(cell) / atlas_size + inset, Vector2(tile, tile) / atlas_size - inset * 2.0)
	return {"texture": ImageTexture.create_from_image(atlas), "uv": uv, "pixels": pixels}


static func _missing_image(tile: int) -> Image:
	var img := Image.create(tile, tile, false, Image.FORMAT_RGBA8)
	var half := tile / 2
	for y in tile:
		for x in tile:
			img.set_pixel(x, y, Color.MAGENTA if (x < half) == (y < half) else Color.BLACK)
	return img
