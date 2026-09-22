extends RefCounted
## Packs block textures downloaded from the server into one nearest-filtered atlas.

const MIN_TILE := 16
const MAX_TILE := 128
const MISSING := ""

## How much the colour's own shading is believed as relief. Lower is bumpier; this is the z of the
## unnormalised normal, so it is a slope rather than a depth.
const RELIEF := 2.2
const SOBEL_X := [-1.0, 0.0, 1.0, -2.0, 0.0, 2.0, -1.0, 0.0, 1.0]
const SOBEL_Y := [-1.0, -2.0, -1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 1.0]


## `images`: asset name -> Image. Returns {texture, surface, uv: name -> Rect2, pixels: name -> Rect2}.
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
	# The tiles as they were laid down, so the relief pass can be run later without resolving names,
	# sizes and fallbacks a second time.
	var placed := {}
	for i in names.size():
		var name: String = names[i]
		var cell := Vector2i((i % columns) * tile, (i / columns) * tile)
		var img: Image = images.get(name, _missing_image(tile))
		img = img.duplicate()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != tile or img.get_height() != tile:
			img.resize(tile, tile, Image.INTERPOLATE_NEAREST)
		atlas.blit_rect(img, Rect2i(0, 0, tile, tile), cell)
		placed[name] = img
		pixels[name] = Rect2(cell, Vector2(tile, tile))
		uv[name] = Rect2(Vector2(cell) / atlas_size + inset, Vector2(tile, tile) / atlas_size - inset * 2.0)
	return {"texture": ImageTexture.create_from_image(atlas), "uv": uv, "pixels": pixels,
		"tiles": placed, "tile": tile, "columns": columns, "rows": rows}


## The relief and roughness atlas for an already-built one. **Slow on purpose to call, not to run.**
##
## Split out because it is the expensive half - a Sobel over every pixel of every texture - and doing it
## inside `build()` put two and a half seconds on the main thread during world load. That is not merely
## a hitch: the client stops draining its socket, Godot starts printing "Buffer full, dropping packets",
## the chunks never arrive and the world comes up empty. Run this on a worker and hand the texture over
## when it is ready; relief appearing a second after the world does is nothing anybody notices.
## (2026-09-22)
static func build_surface(built: Dictionary) -> Image:
	var tile: int = built.tile
	var columns: int = built.columns
	var surface := Image.create(columns * tile, int(built.rows) * tile, false, Image.FORMAT_RGBA8)
	var names: Array = built.tiles.keys()
	for name: String in names:
		var rect: Rect2 = built.pixels[name]
		surface.blit_rect(_surface_of(built.tiles[name]), Rect2i(0, 0, tile, tile), Vector2i(rect.position))
	return surface


## Relief and roughness worked out from the colour, because nobody is going to draw them by hand.
##
## **This is why it is derived rather than authored.** A normal map is a thing an artist makes, and
## neither the person building this engine nor most people writing mods for it is one - so an engine
## that needs one per texture is an engine whose realistic preset only ever works for blocks somebody
## paid an artist for. A texture's own light and shade is already a decent guess at its relief: mortar
## lines are darker than brick, grain is darker than wood. Sobel over luminance turns that into a
## normal, and every mod's textures get relief without the mod knowing this exists. (2026-09-22)
##
## Packed RG = normal x and y, B = roughness. Z is not stored: it is positive by construction and the
## shader can work it out, which buys a channel for the roughness.
##
## Roughness comes from local contrast: a busy texture (dirt, grass, bark) scatters light, a flat one
## (metal, ice, polished stone) does not. That is a heuristic rather than a physical measurement, and a
## block that wants to argue with it can - `register_block` takes a `roughness`.
static func _surface_of(source: Image) -> Image:
	var size := source.get_width()
	# **Raw bytes, not get_pixel.** The first version of this read nine neighbours per pixel through
	# `Image.get_pixel`, which allocates a Color and bounds-checks every call: 6.7 seconds for an atlas
	# of 128px tiles, on the main thread, during world load. The client stopped draining its socket long
	# enough for Godot to start printing "Buffer full, dropping packets", the chunks never arrived, and
	# the world came up empty - a graphics change presenting as a network fault. (2026-09-22)
	var src := source.get_data()
	var light := PackedFloat32Array()
	light.resize(size * size)
	for i in size * size:
		var o := i * 4
		light[i] = (src[o] * 0.299 + src[o + 1] * 0.587 + src[o + 2] * 0.114) / 255.0

	# Wrapped neighbour indices worked out once per row and column rather than a posmod per tap. A block
	# texture tiles, so clamping here would put a seam down every edge in the world.
	var back := PackedInt32Array()
	var fwd := PackedInt32Array()
	back.resize(size)
	fwd.resize(size)
	for i in size:
		back[i] = (i - 1 + size) % size
		fwd[i] = (i + 1) % size

	var out := PackedByteArray()
	out.resize(size * size * 4)
	for y in size:
		var row := y * size
		var up := back[y] * size
		var down := fwd[y] * size
		for x in size:
			var left := back[x]
			var right := fwd[x]
			var tl := light[up + left]
			var tc := light[up + x]
			var tr := light[up + right]
			var ml := light[row + left]
			var mr := light[row + right]
			var bl := light[down + left]
			var bc := light[down + x]
			var br := light[down + right]
			var dx := (tl + 2.0 * ml + bl) - (tr + 2.0 * mr + br)
			var dy := (tl + 2.0 * tc + tr) - (bl + 2.0 * bc + br)
			var normal := Vector3(-dx, -dy, 1.0 / RELIEF).normalized()
			# Roughness from local contrast: a busy texture (dirt, bark) scatters light, a flat one
			# (metal, ice) does not. A heuristic, and a block may override it.
			var lowest := minf(minf(minf(tl, tc), minf(tr, ml)), minf(minf(mr, bl), minf(bc, br)))
			var highest := maxf(maxf(maxf(tl, tc), maxf(tr, ml)), maxf(maxf(mr, bl), maxf(bc, br)))
			var o := (row + x) * 4
			out[o] = int((normal.x * 0.5 + 0.5) * 255.0)
			out[o + 1] = int((normal.y * 0.5 + 0.5) * 255.0)
			out[o + 2] = int(clampf(0.55 + (highest - lowest) * 0.8, 0.0, 1.0) * 255.0)
			out[o + 3] = 255
	return Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, out)


static func _missing_image(tile: int) -> Image:
	var img := Image.create(tile, tile, false, Image.FORMAT_RGBA8)
	var half := tile / 2
	for y in tile:
		for x in tile:
			img.set_pixel(x, y, Color.MAGENTA if (x < half) == (y < half) else Color.BLACK)
	return img
