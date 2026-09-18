extends Control
## Skin painter: paint a whole 64x64 skin on the unfolded layout while a 3D preview turns beside it.
## Tools: pencil, eraser, fill (within one face of a body part), color picker; mirror across the face;
## base or overlay layer (the overlay is the outer layer: jackets, hair, hats); undo and redo; import
## and export PNG. Saving validates the skin and puts it in the local creation library, where the avatar
## editor wears it in the Skin category.

signal saved(manifest: Dictionary)
signal closed

const Avatar = preload("res://engine/client/avatar/avatar.gd")
const LookBuilder = preload("res://engine/client/avatar/look_builder.gd")
const PlayerRig = preload("res://engine/shared/player_rig.gd")
const Cosmetics = preload("res://engine/shared/cosmetics.gd")
const Creations = preload("res://engine/shared/creations.gd")
const CreationLibrary = preload("res://engine/client/creation_library.gd")

const SIZE := 64
const MAX_UNDO := 60
## How different a neighbouring pixel may be and still be filled (cloth textures vary a little).
const FILL_TOLERANCE := 0.12
const TOOLS := ["pencil", "eraser", "fill", "picker"]
const TOOL_LABELS := {"pencil": "✎ Pencil", "eraser": "⌫ Eraser", "fill": "▧ Fill", "picker": "◉ Pick"}
const BASIC_COLORS := ["#ffffff", "#c8c8c8", "#8a8a8a", "#4a4a4a", "#1a1a1a", "#7a4a2a", "#b0452a", "#d94c4c", "#e8913a",
	"#e8cf4a", "#5aa84e", "#2f7a3a", "#3d9c9c", "#4a78d0", "#2a3f8a", "#8a58c8", "#d86ca8"]

var image: Image
var tool := "pencil"
var color := Color(0.85, 0.3, 0.3)
var mirror := false
var layer := "base"  # base | overlay
var show_grid := true
var author_id := ""
var author_name := ""
var edit_id := ""  # a library creation being edited ("" = new)

var _rig: Dictionary
var _texture: ImageTexture
var _preview: Avatar
var _pivot: Node3D
var _dragging := false
var _canvas: Control
var _faces: Array = []  # [{rect: Rect2i, region, side, overlay}]
var _undo: Array[PackedByteArray] = []
var _redo: Array[PackedByteArray] = []
var _stroke_open := false
var _hover := Vector2i(-1, -1)
var _tool_buttons := {}
var _layer_buttons := {}
var _color_button: ColorPickerButton
var _recent: HFlowContainer
var _recent_colors: Array[Color] = []
var _name_edit: LineEdit
var _status: Label
var _hover_label: Label
var _dirty := false


func setup(rig: Dictionary, start: Image, name_text := "", author := "", author_display := "") -> void:
	_rig = rig
	image = start.duplicate() if start != null else Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.convert(Image.FORMAT_RGBA8)
	if image.get_width() != SIZE or image.get_height() != SIZE:
		image.resize(SIZE, SIZE, Image.INTERPOLATE_NEAREST)
	author_id = author
	author_name = author_display
	_texture = ImageTexture.create_from_image(image)
	if not name_text.is_empty():
		call_deferred("_set_name", name_text)


func _set_name(text: String) -> void:
	if _name_edit != null:
		_name_edit.text = text


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if image == null:
		setup(PlayerRig.default_rig(), null)
	_build_faces()
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.11, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Paint a skin"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_hover_label = Label.new()
	_hover_label.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	header.add_child(_hover_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	# 3D preview.
	var view := SubViewportContainer.new()
	view.stretch = true
	view.custom_minimum_size = Vector2(300, 420)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_stretch_ratio = 0.6
	view.gui_input.connect(_on_preview_input)
	body.add_child(view)
	view.add_child(_build_preview())

	# Canvas.
	var canvas_box := AspectRatioContainer.new()
	canvas_box.ratio = 1.0
	canvas_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(canvas_box)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.custom_minimum_size = Vector2(384, 384)
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_on_canvas_input)
	_canvas.mouse_exited.connect(func():
		_hover = Vector2i(-1, -1)
		_canvas.queue_redraw())
	canvas_box.add_child(_canvas)

	# Tools and colors.
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(250, 0)
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	side.add_child(_heading("Tool"))
	var tools := GridContainer.new()
	tools.columns = 2
	side.add_child(tools)
	for t in TOOLS:
		var b := Button.new()
		b.text = TOOL_LABELS[t]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(118, 36)
		b.tooltip_text = {"pencil": "Paint pixels (P)", "eraser": "Make pixels transparent (E)", "fill": "Fill connected pixels of one color on one face (F)",
			"picker": "Take a color from the skin (I, or right-click)"}[t]
		b.pressed.connect(set_tool.bind(t))
		tools.add_child(b)
		_tool_buttons[t] = b
	var mirror_box := CheckBox.new()
	mirror_box.text = "Mirror (M)"
	mirror_box.tooltip_text = "Paint both halves of each face at once"
	mirror_box.toggled.connect(func(on): mirror = on)
	side.add_child(mirror_box)
	var grid_box := CheckBox.new()
	grid_box.text = "Grid"
	grid_box.button_pressed = true
	grid_box.toggled.connect(func(on):
		show_grid = on
		_canvas.queue_redraw())
	side.add_child(grid_box)
	side.add_child(_heading("Layer"))
	var layers := HBoxContainer.new()
	side.add_child(layers)
	for l in [["base", "Body"], ["overlay", "Outer layer"]]:
		var b := Button.new()
		b.text = l[1]
		b.toggle_mode = true
		b.tooltip_text = "The body itself" if l[0] == "base" else "A second, slightly larger layer for jackets, hair and hats"
		b.pressed.connect(set_layer.bind(l[0]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layers.add_child(b)
		_layer_buttons[l[0]] = b
	side.add_child(_heading("Color"))
	_color_button = ColorPickerButton.new()
	_color_button.color = color
	_color_button.custom_minimum_size = Vector2(0, 36)
	_color_button.color_changed.connect(func(c): color = c)
	side.add_child(_color_button)
	var palette := GridContainer.new()
	palette.columns = 6
	side.add_child(palette)
	for hex in BASIC_COLORS + Cosmetics.SKIN_TONES:
		palette.add_child(_swatch(Color.html(hex)))
	side.add_child(_heading("Recent"))
	_recent = HFlowContainer.new()
	side.add_child(_recent)
	var edit_row := HBoxContainer.new()
	side.add_child(edit_row)
	for entry in [["↶ Undo", undo, "Ctrl+Z"], ["↷ Redo", redo, "Ctrl+Y"]]:
		var b := Button.new()
		b.text = entry[0]
		b.tooltip_text = entry[2]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(entry[1])
		edit_row.add_child(b)

	# Save row.
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	root.add_child(footer)
	var name_label := Label.new()
	name_label.text = "Name"
	footer.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "My skin"
	_name_edit.max_length = Creations.MAX_NAME
	_name_edit.custom_minimum_size = Vector2(220, 0)
	footer.add_child(_name_edit)
	for entry in [["Import PNG…", _import], ["Export PNG…", _export]]:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(entry[1])
		footer.add_child(b)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("font_color", Color(1.0, 0.75, 0.6))
	footer.add_child(_status)
	for entry in [["Cancel", func(): closed.emit()], ["Save", save]]:
		var b := Button.new()
		b.text = entry[0]
		b.custom_minimum_size = Vector2(110, 40)
		b.pressed.connect(entry[1])
		footer.add_child(b)
	set_tool("pencil")
	set_layer("base")
	_update_preview()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	return l


func _swatch(c: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(34, 30)
	b.tooltip_text = "#" + c.to_html(false)
	var style := StyleBoxFlat.new()
	style.bg_color = c
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.2)
	b.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.border_color = Color.WHITE
	b.add_theme_stylebox_override("hover", hover)
	b.pressed.connect(func(): set_color(c))
	return b


func _build_preview() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.2, 0.27)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.82, 0.88)
	env.environment.ambient_light_energy = 0.8
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 35.0
	camera.position = Vector3(0, 1.05, 4.2)
	viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 0.95, 0))
	_pivot = Node3D.new()
	_pivot.rotation.y = PI
	viewport.add_child(_pivot)
	_preview = Avatar.new()
	_pivot.add_child(_preview)
	_preview.build(_rig)
	return viewport


func _process(delta: float) -> void:
	if _preview != null:
		_preview.animate(delta, Vector3.ZERO, true, 0.0)
		if not _dragging:
			_pivot.rotation.y += delta * 0.35
	if _dirty:
		_dirty = false
		_update_preview()


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pivot.rotation.y += event.relative.x * 0.01


func _update_preview() -> void:
	_texture.update(image)
	if _preview != null:
		_preview.set_skin(_texture)
	if _canvas != null:
		_canvas.queue_redraw()


# --- Layout -----------------------------------------------------------------------------------------

func _build_faces() -> void:
	_faces.clear()
	for region in PlayerRig.REGIONS:
		var r: Array = PlayerRig.REGIONS[region]
		var rects := LookBuilder.side_rects(r, 0, r[3], Cosmetics.SIDES)
		var names := ["top", "bottom", "right", "front", "left", "back"]
		for i in rects.size():
			_faces.append({"rect": rects[i], "region": region, "side": names[i], "overlay": region.ends_with("_overlay")})


func face_at(p: Vector2i) -> Dictionary:
	for f in _faces:
		if (f.rect as Rect2i).has_point(p):
			return f
	return {}


# --- Editing ----------------------------------------------------------------------------------------

func set_tool(t: String) -> void:
	tool = t
	for key in _tool_buttons:
		_tool_buttons[key].button_pressed = key == t


func set_layer(l: String) -> void:
	layer = l
	for key in _layer_buttons:
		_layer_buttons[key].button_pressed = key == l
	if _canvas != null:
		_canvas.queue_redraw()


func set_color(c: Color) -> void:
	color = c
	if _color_button != null:
		_color_button.color = c


func _remember_color(c: Color) -> void:
	for existing in _recent_colors:
		if existing.is_equal_approx(c):
			return
	_recent_colors.push_front(c)
	if _recent_colors.size() > 12:
		_recent_colors.pop_back()
	if _recent != null:
		for child in _recent.get_children():
			_recent.remove_child(child)
			child.queue_free()
		for rc in _recent_colors:
			_recent.add_child(_swatch(rc))


## Starts an undoable change (once per stroke).
func begin_stroke() -> void:
	if _stroke_open:
		return
	_stroke_open = true
	_undo.append(image.get_data())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func end_stroke() -> void:
	_stroke_open = false


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(image.get_data())
	image.set_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, _undo.pop_back())
	_dirty = true


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(image.get_data())
	image.set_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, _redo.pop_back())
	_dirty = true


## Applies the current tool at a skin pixel. Only faces of the current layer take paint.
func apply_tool(p: Vector2i, alt := false) -> void:
	var face := face_at(p)
	if face.is_empty():
		return
	if alt or tool == "picker":
		var picked := image.get_pixelv(p)
		if picked.a > 0.0:
			set_color(Color(picked.r, picked.g, picked.b))
		return
	if face.overlay != (layer == "overlay"):
		return
	begin_stroke()
	var paint := Color(0, 0, 0, 0) if tool == "eraser" else Color(color.r, color.g, color.b, 1.0)
	if tool != "eraser":
		_remember_color(paint)
	var targets := [p]
	if mirror:
		var r: Rect2i = face.rect
		targets.append(Vector2i(r.position.x + r.size.x - 1 - (p.x - r.position.x), p.y))
	for t in targets:
		if tool == "fill":
			_flood(t, paint, face.rect)
		else:
			image.set_pixelv(t, paint)
	_dirty = true


func _flood(start: Vector2i, paint: Color, bounds: Rect2i) -> void:
	var target := image.get_pixelv(start)
	if _close(target, paint, 0.001):
		return
	var stack: Array[Vector2i] = [start]
	var seen := {}
	while not stack.is_empty():
		var q: Vector2i = stack.pop_back()
		if seen.has(q) or not bounds.has_point(q) or not _close(image.get_pixelv(q), target, FILL_TOLERANCE):
			continue
		seen[q] = true
		image.set_pixelv(q, paint)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			stack.append(q + d)


static func _close(a: Color, b: Color, tolerance: float) -> bool:
	return absf(a.r - b.r) <= tolerance and absf(a.g - b.g) <= tolerance and absf(a.b - b.b) <= tolerance and absf(a.a - b.a) <= tolerance


# --- Canvas -----------------------------------------------------------------------------------------

func _cell() -> float:
	return minf(_canvas.size.x, _canvas.size.y) / SIZE


func _pixel_at(pos: Vector2) -> Vector2i:
	var c := _cell()
	return Vector2i(floori(pos.x / c), floori(pos.y / c))


func _draw_canvas() -> void:
	var c := _cell()
	var full := Rect2(Vector2.ZERO, Vector2.ONE * c * SIZE)
	# Checkerboard behind transparent pixels.
	for y in 16:
		for x in 16:
			_canvas.draw_rect(Rect2(Vector2(x, y) * c * 4, Vector2.ONE * c * 4), Color(0.22, 0.24, 0.28) if (x + y) % 2 == 0 else Color(0.18, 0.2, 0.24))
	_canvas.draw_texture_rect(_texture, full, false)
	# Dim the faces of the other layer and outline this layer's faces.
	for f in _faces:
		var r := Rect2(Vector2(f.rect.position) * c, Vector2(f.rect.size) * c)
		if f.overlay != (layer == "overlay"):
			_canvas.draw_rect(r, Color(0.06, 0.08, 0.11, 0.62))
		else:
			_canvas.draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)
	if show_grid and c >= 6.0:
		var line := Color(0, 0, 0, 0.18)
		for i in SIZE + 1:
			_canvas.draw_line(Vector2(i * c, 0), Vector2(i * c, SIZE * c), line)
			_canvas.draw_line(Vector2(0, i * c), Vector2(SIZE * c, i * c), line)
	if _hover.x >= 0:
		_canvas.draw_rect(Rect2(Vector2(_hover) * c, Vector2.ONE * c), Color.WHITE, false, 2.0)
		if mirror:
			var face := face_at(_hover)
			if not face.is_empty():
				var r: Rect2i = face.rect
				var m := Vector2i(r.position.x + r.size.x - 1 - (_hover.x - r.position.x), _hover.y)
				_canvas.draw_rect(Rect2(Vector2(m) * c, Vector2.ONE * c), Color(1, 1, 1, 0.5), false, 2.0)


func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var p := _pixel_at(event.position)
		if p != _hover:
			_hover = p
			var face := face_at(p)
			_hover_label.text = "%s · %s  (%d, %d)" % [str(face.region).replace("_", " "), face.side, p.x, p.y] if not face.is_empty() else ""
			_canvas.queue_redraw()
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and tool in ["pencil", "eraser"]:
			apply_tool(p)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			apply_tool(_pixel_at(event.position))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			apply_tool(_pixel_at(event.position), true)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		end_stroke()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _name_edit != null and _name_edit.has_focus():
		return
	var ctrl: bool = event.ctrl_pressed or event.meta_pressed
	match event.keycode:
		KEY_Z when ctrl:
			redo() if event.shift_pressed else undo()
		KEY_Y when ctrl:
			redo()
		KEY_P:
			set_tool("pencil")
		KEY_E:
			set_tool("eraser")
		KEY_F:
			set_tool("fill")
		KEY_I:
			set_tool("picker")
		KEY_M:
			mirror = not mirror
		KEY_ESCAPE:
			closed.emit()
		_:
			return
	get_viewport().set_input_as_handled()


# --- Files ------------------------------------------------------------------------------------------

## Validates and saves to the local library. Returns the result ({ok, error, manifest}).
func save() -> Dictionary:
	var name := _name_edit.text.strip_edges() if _name_edit != null else ""
	if name.is_empty():
		name = "My skin"
	var png := image.save_png_to_buffer()
	var manifest := Creations.make("skin", "skin", png, name, author_id, author_name)
	var result := CreationLibrary.save(manifest, png)
	if not result.ok:
		if _status != null:
			_status.text = result.error
		return result
	if not edit_id.is_empty() and edit_id != result.manifest.id:
		CreationLibrary.remove(edit_id)  # an edited skin is new content; replace the old file
	saved.emit(result.manifest)
	return result


func load_png(bytes: PackedByteArray) -> String:
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return "that file is not a PNG image"
	if img.get_width() != SIZE or img.get_height() != SIZE:
		return "a skin must be %dx%d pixels (this one is %dx%d)" % [SIZE, SIZE, img.get_width(), img.get_height()]
	begin_stroke()
	end_stroke()
	img.convert(Image.FORMAT_RGBA8)
	image.copy_from(img)
	_dirty = true
	return ""


func _import() -> void:
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.png ; 64x64 skin"])
	dialog.file_selected.connect(func(path: String):
		var error := load_png(FileAccess.get_file_as_bytes(path))
		# Importing is for a picture you drew yourself. Anything worn can be shared with a server, where
		# other players may wear it in turn, so somebody else's artwork should not start that journey.
		_status.text = error if not error.is_empty() else "Imported. Only share pictures you drew yourself."
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _export() -> void:
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.filters = PackedStringArray(["*.png ; 64x64 skin"])
	dialog.current_file = (_name_edit.text.strip_edges() if not _name_edit.text.strip_edges().is_empty() else "skin").validate_filename() + ".png"
	dialog.file_selected.connect(func(path: String):
		_status.text = "Exported" if image.save_png(path) == OK else "Could not write %s" % path
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)
