extends RefCounted
## Looks the client can draw without downloading anything: a default face and simple clothing layers
## in the skin layout. Used for players without cosmetics; the cosmetics catalog builds on these.

const SkinCompositor = preload("res://engine/client/avatar/skin_compositor.gd")
const PlayerRig = preload("res://engine/shared/player_rig.gd")

const SKIN_TONES := [Color(0.96, 0.8, 0.66), Color(0.87, 0.67, 0.5), Color(0.72, 0.52, 0.36), Color(0.55, 0.38, 0.25), Color(0.4, 0.27, 0.18)]


## A friendly default look derived from a name, so players are told apart before cosmetics exist.
static func default_appearance(seed_text: String) -> Dictionary:
	var h := hash(seed_text)
	var shirt := Color.from_hsv(fmod(abs(h) * 0.000137, 1.0), 0.55, 0.75)
	var pants := Color.from_hsv(fmod(abs(h >> 3) * 0.000071, 1.0), 0.35, 0.35)
	var tone: Color = SKIN_TONES[abs(h) % SKIN_TONES.size()]
	return {"colors": {"head": tone, "torso": tone, "arms": tone, "legs": tone}, "shirt": shirt, "pants": pants}


static func face() -> Image:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for p in [Vector2i(1, 3), Vector2i(2, 3), Vector2i(5, 3), Vector2i(6, 3)]:
		img.set_pixel(p.x, p.y, Color(1, 1, 1))
	img.set_pixel(2, 3, Color(0.25, 0.35, 0.8))
	img.set_pixel(5, 3, Color(0.25, 0.35, 0.8))
	for x in range(3, 5):
		img.set_pixel(x, 6, Color(0.55, 0.3, 0.28))
	for x in range(1, 7):
		img.set_pixel(x, 1, Color(0.3, 0.2, 0.12, 0.9))  # hairline
	return img


## A t-shirt: torso plus short sleeves.
static func shirt(color: Color) -> Image:
	var img := _layer()
	_paint(img, "torso", 0, 12, color)
	_paint(img, "arm_r", 0, 4, color.darkened(0.08))
	_paint(img, "arm_l", 0, 4, color.darkened(0.08))
	return img


## Trousers with darker shoes.
static func pants(color: Color) -> Image:
	var img := _layer()
	_paint(img, "leg_r", 0, 10, color)
	_paint(img, "leg_l", 0, 10, color)
	_paint(img, "leg_r", 10, 12, color.darkened(0.5))
	_paint(img, "leg_l", 10, 12, color.darkened(0.5))
	_paint(img, "torso", 10, 12, color.darkened(0.2))
	return img


static func _layer() -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _paint(img: Image, region: String, row_from: int, row_to: int, color: Color) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(region) + row_from
	for rect in SkinCompositor.unfold(PlayerRig.REGIONS[region], row_from, row_to):
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var shade := 1.0 + rng.randf_range(-0.04, 0.04)
				img.set_pixel(x, y, Color(color.r * shade, color.g * shade, color.b * shade, 1.0))
