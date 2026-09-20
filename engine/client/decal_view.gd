extends Node3D
## Marks left on the world: scorch where an explosion went off, a stain under a leak, a footprint.
##
## Godot draws these for us - a Decal projects onto whatever is underneath, so a scorch mark follows
## the shape of the ground and does not need to know what it landed on. The one thing worth being
## careful about is *how many*: a mod that marks the ground every time something happens will fill a
## scene with them, so the oldest go when the limit is reached and they fade rather than blink out.

const MAX_DECALS := 128

var _decals: Array = []
var _texture: Texture2D


func _ready() -> void:
	_texture = _soft_mark()


## look: {color, size, seconds (0 stays until the limit pushes it out)}.
func add(pos: Vector3, normal: Vector3i, look: Dictionary) -> void:
	while _decals.size() >= MAX_DECALS:
		var oldest: Dictionary = _decals.pop_front()
		if is_instance_valid(oldest.node):
			oldest.node.queue_free()
	var decal := Decal.new()
	var size := clampf(float(look.get("size", 1.0)), 0.1, 8.0)
	decal.size = Vector3(size, maxf(size, 1.0), size)
	decal.texture_albedo = _texture
	decal.modulate = Color(String(look.get("color", "#000000")))
	decal.position = pos
	# Turned to face the surface it landed on, so a scorch on a wall lies on the wall.
	if normal.y == 0 and normal != Vector3i.ZERO:
		decal.rotation = Vector3(PI * 0.5, atan2(float(normal.x), float(normal.z)), 0.0)
	add_child(decal)
	_decals.append({"node": decal, "left": float(look.get("seconds", 0.0)), "seconds": float(look.get("seconds", 0.0))})


func _process(delta: float) -> void:
	if _decals.is_empty():
		return
	var still_there := []
	for mark: Dictionary in _decals:
		if not is_instance_valid(mark.node):
			continue
		if mark.seconds <= 0.0:
			still_there.append(mark)  # stays until the limit pushes it out
			continue
		mark.left -= delta
		if mark.left <= 0.0:
			mark.node.queue_free()
			continue
		mark.node.albedo_mix = clampf(mark.left / mark.seconds, 0.0, 1.0)
		still_there.append(mark)
	_decals = still_there


func clear() -> void:
	for mark: Dictionary in _decals:
		if is_instance_valid(mark.node):
			mark.node.queue_free()
	_decals.clear()


## A soft round smudge, made here rather than shipped: it is two dozen lines and saves an asset that
## every mod would otherwise have to provide for itself.
func _soft_mark() -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := clampf(1.0 - d * d, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, a * 0.85))
	return ImageTexture.create_from_image(image)
