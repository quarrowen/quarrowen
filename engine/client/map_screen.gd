extends Control
## The map (M): the world from above, drawn from the chunks this client already has, with everyone on the
## server, your home and your grave marked. Nothing extra is downloaded - the picture is built from the
## blocks around you, so it only shows where somebody has been.

const MenuTheme = preload("res://engine/client/menu/menu_theme.gd")
const VoxelWorld = preload("res://engine/shared/voxel_world.gd")
const Chunk = preload("res://engine/shared/chunk.gd")

signal closed
signal refresh_requested

## Blocks per pixel at each zoom step.
const ZOOMS := [1, 2, 4]
const IMAGE_SIZE := 256

var client
var _image: Image
var _texture: ImageTexture
var _view: TextureRect
var _markers: Control
var _title: Label
var _zoom := 1
var _state := {}
var _colors := {}  # block id -> Color
var _centre := Vector2i.ZERO
var _timer := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	centre.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_title = MenuTheme.heading("Map", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	for entry in [["−", 1], ["+", -1]]:
		var zoom_button := Button.new()
		zoom_button.text = entry[0]
		zoom_button.tooltip_text = "Zoom out" if entry[1] > 0 else "Zoom in"
		zoom_button.pressed.connect(func():
			_zoom = clampi(_zoom + int(entry[1]), 0, ZOOMS.size() - 1)
			_redraw())
		header.add_child(zoom_button)
	var done := Button.new()
	done.text = "Close"
	done.pressed.connect(func(): closed.emit())
	header.add_child(done)

	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.05, 0.06, 0.09, 0.96), 12, 8, 8))
	box.add_child(frame)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(IMAGE_SIZE * 2.2, IMAGE_SIZE * 2.2)
	frame.add_child(stack)
	_view = TextureRect.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	stack.add_child(_view)
	_markers = Control.new()
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_markers)
	box.add_child(MenuTheme.muted("Only places someone has visited are drawn. M closes the map.", 12))
	_image = Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)
	_view.texture = _texture
	_redraw()
	refresh_requested.emit()


func receive(state: Dictionary) -> void:
	_state = state
	_draw_markers()


func _process(delta: float) -> void:
	_timer += delta
	if _timer < 1.0:
		return
	_timer = 0.0
	_redraw()
	refresh_requested.emit()


## Zooms in (+1) or out (-1). The buttons call this, and so does the mouse wheel: reaching for the wheel
## over a map is what everybody does, and it used to change the hotbar behind the map instead.
func zoom_by(steps: int) -> void:
	var wanted := clampi(_zoom - steps, 0, ZOOMS.size() - 1)
	if wanted != _zoom:
		_zoom = wanted
		_redraw()


## Paints the world from above: the colour of the highest solid block in each column.
func _redraw() -> void:
	if client == null or not is_instance_valid(client):
		return
	var step: int = ZOOMS[_zoom]
	_centre = Vector2i(floori(client.state.position.x), floori(client.state.position.z))
	var half := IMAGE_SIZE / 2
	var world = client.world
	var registry = client.registry
	_image.fill(Color(0.07, 0.08, 0.11, 1.0))
	# The first column pays for a full scan; the rest start just above whatever the tallest so far was.
	var highest := Chunk.SIZE_Y - 1
	for py in IMAGE_SIZE:
		var wz := _centre.y + (py - half) * step
		for px in IMAGE_SIZE:
			var wx := _centre.x + (px - half) * step
			var chunk = world.chunks.get(VoxelWorld.chunk_coord_at(wx, wz))
			if chunk == null:
				continue
			var color := Color(0, 0, 0, 0)
			# Straight into the chunk rather than through world.get_block, which looks the chunk up in a
			# dictionary on every call - and this loop is a quarter of a million columns deep. Start just
			# above the highest ground found so far instead of at the world ceiling: a surface world is
			# around y 60-90, so the old scan spent most of its time counting empty sky. Between them the
			# redraw went from visibly locking up to unnoticeable. (playtest, 2026-09-18)
			var column: int = (wx & 15) + ((wz & 15) << 4)
			var blocks: PackedByteArray = chunk.blocks
			for y in range(mini(Chunk.SIZE_Y - 1, highest + 8), 0, -1):
				var block: int = blocks.decode_u16((column + (y << 8)) << 1)
				if block == 0 or not registry.is_valid(block):
					continue
				if registry.solid_lut[block] == 0 and registry.liquid_lut[block] == 0:
					continue
				color = _color_of(block)
				# Higher ground reads lighter, so hills and valleys show.
				color = color.lightened(clampf((y - 60) / 90.0, -0.35, 0.35)) if y >= 60 else color.darkened(clampf((60 - y) / 90.0, 0.0, 0.35))
				highest = maxi(highest, y)
				break
			if color.a > 0.0:
				_image.set_pixel(px, py, color)
	_texture.update(_image)
	_title.text = "Map  (%d, %d)  1 pixel = %d block%s" % [_centre.x, _centre.y, step, "" if step == 1 else "s"]
	_draw_markers()


## The average colour of a block's texture, worked out once per block type.
func _color_of(block: int) -> Color:
	if _colors.has(block):
		return _colors[block]
	var color := Color(0.5, 0.5, 0.55)
	var textures: Array = client.registry.defs[block].textures
	var image: Image = client._asset_images.get(textures[0] if not textures.is_empty() else "")
	if image != null:
		var total := Color(0, 0, 0, 0)
		var samples := 0
		for y in range(0, image.get_height(), maxi(1, image.get_height() / 8)):
			for x in range(0, image.get_width(), maxi(1, image.get_width() / 8)):
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.2:
					total += pixel
					samples += 1
		if samples > 0:
			color = Color(total.r / samples, total.g / samples, total.b / samples)
	_colors[block] = color
	return color


func _draw_markers() -> void:
	for child in _markers.get_children():
		_markers.remove_child(child)
		child.queue_free()
	var step: int = ZOOMS[_zoom]
	var scale := _view.size.x / float(IMAGE_SIZE)
	var half := IMAGE_SIZE / 2.0
	for entry in _state.get("markers", []):
		_pin(entry.get("position", Vector3.ZERO), str(entry.get("label", "")), Color.html(str(entry.get("color", "#ffd166"))), false, step, scale, half)
	for entry in _state.get("players", []):
		var you: bool = entry.get("you", false)
		_pin(entry.get("position", Vector3.ZERO), str(entry.get("name", "?")), Color(1, 1, 1) if you else Color(0.42, 0.72, 1.0), you, step, scale, half)


func _pin(position: Vector3, label: String, color: Color, you: bool, step: int, scale: float, half: float) -> void:
	var px := (half + (position.x - _centre.x) / float(step)) * scale
	var py := (half + (position.z - _centre.y) / float(step)) * scale
	if px < 0.0 or py < 0.0 or px > _view.size.x or py > _view.size.y:
		return
	var dot := Panel.new()
	var size := 12.0 if you else 10.0
	dot.custom_minimum_size = Vector2(size, size)
	dot.size = Vector2(size, size)
	dot.position = Vector2(px - size * 0.5, py - size * 0.5)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(size * 0.5))
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(0, 0, 0, 0.6)
	dot.add_theme_stylebox_override("panel", style)
	_markers.add_child(dot)
	var name_label := Label.new()
	name_label.text = label
	name_label.position = Vector2(px + size * 0.6, py - 10.0)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", color)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers.add_child(name_label)
