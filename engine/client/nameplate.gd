extends Node3D
## The label over a thing's head: a name, a health bar, and whatever lines a mod added.
##
## The bar is two `Sprite3D`s with a plain white texture made in code, tinted and scaled - so a health
## bar needs no artist and no file. Drawing it as text (a row of blocks) was the alternative and reads
## badly at small sizes, where a bar still reads as "nearly dead" at a glance.
##
## **It fades with distance rather than switching off.** A plate that pops in at exactly 24 blocks
## draws the eye to the popping; one that arrives over a couple of blocks does not.

const BAR_WIDTH := 0.62
const BAR_HEIGHT := 0.085
## Where it stops being drawn at all, unless the plate asks for something else.
const DEFAULT_RANGE := 24.0
## Over how many blocks it fades in at the edge of that range.
const FADE := 4.0

var _name_label: Label3D
var _lines_label: Label3D
var _bar_back: Sprite3D
var _bar_fill: Sprite3D
var _range := DEFAULT_RANGE
var _height := 1.8
var _shown := false


static func _white() -> ImageTexture:
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	return ImageTexture.create_from_image(img)


func setup(height: float) -> void:
	_height = height
	_name_label = _make_label(44)
	_lines_label = _make_label(30)
	var white := _white()
	_bar_back = _make_bar(white, Color(0.05, 0.05, 0.06, 0.75), BAR_WIDTH, BAR_HEIGHT)
	_bar_fill = _make_bar(white, Color(0.45, 0.85, 0.4), BAR_WIDTH, BAR_HEIGHT)
	# Slightly in front of its own backing, or the two fight over which is drawn and the bar flickers.
	_bar_fill.position.z = 0.002
	visible = false


func _make_label(size: int) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = size
	label.pixel_size = 0.005
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.85)
	add_child(label)
	return label


func _make_bar(texture: ImageTexture, color: Color, width: float, height: float) -> Sprite3D:
	var bar := Sprite3D.new()
	bar.texture = texture
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.no_depth_test = true
	bar.modulate = color
	bar.pixel_size = 1.0
	bar.scale = Vector3(width, height, 1.0)
	add_child(bar)
	return bar


## The plate as the server describes it: {name, lines, show_health, health, color, hidden, range}.
func apply(plate: Dictionary) -> void:
	_shown = not plate.is_empty() and not bool(plate.get("hidden", false))
	if not _shown:
		visible = false
		return
	_range = clampf(float(plate.get("range", DEFAULT_RANGE)), 4.0, 96.0)
	_name_label.text = String(plate.get("name", ""))
	_name_label.modulate = Color.html(String(plate.get("color", "#ffffff")))
	var lines: Array = plate.get("lines", []) if plate.get("lines") is Array else []
	_lines_label.text = "\n".join(lines.map(func(l): return String(l)))
	_lines_label.visible = not lines.is_empty()
	var health_shown := bool(plate.get("show_health", false))
	_bar_back.visible = health_shown
	_bar_fill.visible = health_shown
	if health_shown:
		var fraction := clampf(float(plate.get("health", 1.0)), 0.0, 1.0)
		_bar_fill.scale.x = BAR_WIDTH * fraction
		# Anchored left so it empties from the right, rather than shrinking towards its middle.
		_bar_fill.position.x = -BAR_WIDTH * 0.5 + BAR_WIDTH * fraction * 0.5
		# Green through amber to red, so "nearly dead" reads without reading the number.
		_bar_fill.modulate = Color(0.9, 0.25, 0.2).lerp(Color(0.45, 0.85, 0.4), fraction) if fraction < 0.6 \
			else Color(0.45, 0.85, 0.4)
	_layout(health_shown, lines.size())


## Stacked from the head upwards: bar, then name, then the mod's lines above it.
func _layout(health_shown: bool, line_count: int) -> void:
	var y := _height + 0.3
	if health_shown:
		_bar_back.position.y = y
		_bar_fill.position.y = y
		y += 0.16
	_name_label.position.y = y
	if line_count > 0:
		_lines_label.position.y = y + 0.22


## Fades with distance and hides when there is nothing to say. Called by the client each frame with
## where the camera is, because a plate has no way of knowing on its own.
func update_for_camera(camera_position: Vector3) -> void:
	if not _shown:
		return
	var distance := global_position.distance_to(camera_position)
	if distance > _range:
		visible = false
		return
	visible = true
	var alpha := clampf((_range - distance) / FADE, 0.0, 1.0)
	_name_label.modulate.a = alpha
	_lines_label.modulate.a = alpha
	_bar_back.modulate.a = 0.75 * alpha
	_bar_fill.modulate.a = alpha
