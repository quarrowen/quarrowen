extends RefCounted
## Builds the textures an avatar is drawn with, in the 64x64 skin layout (see PlayerRig):
##   skin  = body colors, then the face, then clothing layers (shirt, pants, decals) in order
##   armor = each visible armor piece's texture, masked to the regions its slot covers
## Layers may be 64x64 or larger multiples (128, 256); the result uses the largest size given.

const PlayerRig = preload("res://engine/shared/player_rig.gd")

const BASE := 64
const MAX_SIZE := 256

## Which part regions body colors apply to.
const COLOR_REGIONS := {"head": ["head"], "torso": ["torso"], "arms": ["arm_r", "arm_l"], "legs": ["leg_r", "leg_l"]}

## Armor slot -> [region, first row, last row] of the region's side height (tops and bottoms follow).
const ARMOR_ROWS := {
	"feet": [["leg_r", 9, 12], ["leg_l", 9, 12]],
	"legs": [["leg_r", 0, 9], ["leg_l", 0, 9], ["torso", 8, 12]],
	"chest": [["torso", 0, 12], ["arm_r", 0, 12], ["arm_l", 0, 12]],
	"head": [["head", 0, 8]],
}
const ARMOR_ORDER := ["feet", "legs", "chest", "head"]


## `colors`: {head, torso, arms, legs} as Color; `face`: an 8x8 image (or null); `layers`: Images in
## the skin layout drawn over the body in order.
static func compose_skin(colors: Dictionary, face: Image, layers: Array) -> Image:
	var size := _size_for(layers)
	var scale := size / BASE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for key in COLOR_REGIONS:
		var base: Color = colors.get(key, Color(0.8, 0.65, 0.5))
		for region_name in COLOR_REGIONS[key]:
			for rect in unfold(PlayerRig.REGIONS[region_name]):
				for y in range(rect.position.y * scale, rect.end.y * scale):
					for x in range(rect.position.x * scale, rect.end.x * scale):
						var shade := 1.0 + rng.randf_range(-0.035, 0.035)  # a little texture so flat colors don't look plastic
						img.set_pixel(x, y, Color(base.r * shade, base.g * shade, base.b * shade, 1.0))
	if face != null:
		var f := face.duplicate()
		f.convert(Image.FORMAT_RGBA8)
		f.resize(8 * scale, 8 * scale, Image.INTERPOLATE_NEAREST)
		img.blend_rect(f, Rect2i(Vector2i.ZERO, f.get_size()), Vector2i(8, 8) * scale)
	for layer in layers:
		if layer is Image:
			img.blend_rect(_fit(layer, size), Rect2i(0, 0, size, size), Vector2i.ZERO)
	return img


## `pieces`: {slot name: Image} for visible armor. Returns null when nothing is worn.
static func compose_armor(pieces: Dictionary) -> Image:
	if pieces.is_empty():
		return null
	var size := _size_for(pieces.values())
	var scale := size / BASE
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for slot in ARMOR_ORDER:
		if not pieces.has(slot) or not ARMOR_ROWS.has(slot):
			continue
		var source := _fit(pieces[slot], size)
		for entry in ARMOR_ROWS[slot]:
			var r: Array = PlayerRig.REGIONS[entry[0]]
			for rect in unfold(r, int(entry[1]), int(entry[2])):
				var scaled := Rect2i(rect.position * scale, rect.size * scale)
				img.blit_rect(source, scaled, scaled.position)
	return img


## Box unfold rectangles of a region [u, v, w, h, d]; `rows` limits the side faces to part of the
## height (the top face is included only from row 0, the bottom only to the last row).
static func unfold(r: Array, row_from := 0, row_to := -1) -> Array[Rect2i]:
	var u: int = r[0]
	var v: int = r[1]
	var w: int = r[2]
	var h: int = r[3]
	var d: int = r[4]
	if row_to < 0:
		row_to = h
	var rects: Array[Rect2i] = []
	if row_from == 0:
		rects.append(Rect2i(u + d, v, w, d))  # top
	if row_to == h:
		rects.append(Rect2i(u + d + w, v, w, d))  # bottom
	var side_y := v + d + row_from
	var side_h := row_to - row_from
	rects.append(Rect2i(u, side_y, d, side_h))  # right
	rects.append(Rect2i(u + d, side_y, w, side_h))  # front
	rects.append(Rect2i(u + d + w, side_y, d, side_h))  # left
	rects.append(Rect2i(u + 2 * d + w, side_y, w, side_h))  # back
	return rects


static func _size_for(images: Array) -> int:
	var size := BASE
	for img in images:
		if img is Image:
			size = maxi(size, mini(nearest_po2(maxi(img.get_width(), img.get_height())), MAX_SIZE))
	return size


static func _fit(img: Image, size: int) -> Image:
	var out := img.duplicate()
	out.convert(Image.FORMAT_RGBA8)
	if out.get_width() != size or out.get_height() != size:
		out.resize(size, size, Image.INTERPOLATE_NEAREST)
	return out
