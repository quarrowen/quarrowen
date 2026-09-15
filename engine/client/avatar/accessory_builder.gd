extends Control
## Accessory builder: make hats, hair, glasses, capes and backpacks from colored voxels, one layer at a
## time on a top-down grid around the attachment point, while the 3D preview shows the result on your
## avatar. Saving merges the voxels into as few boxes as possible (at most Creations.MAX_BOXES) and puts
## the accessory in the local creation library.

signal saved(manifest: Dictionary)
signal closed

const Avatar = preload("res://engine/client/avatar/avatar.gd")
const LookBuilder = preload("res://engine/client/avatar/look_builder.gd")
const PlayerRig = preload("res://engine/shared/player_rig.gd")
const Cosmetics = preload("res://engine/shared/cosmetics.gd")
const Creations = preload("res://engine/shared/creations.gd")
const CreationLibrary = preload("res://engine/client/creation_library.gd")

const EXTENT := 12  # voxels from the attachment point on each axis: [-12, 11]
const PREVIEW_ID := "preview:accessory"
const MAX_UNDO := 60
const CATEGORY_LABELS := {"hat": "Hat", "hair": "Hair", "glasses": "Glasses", "back": "Back (capes, wings, backpacks)", "face": "Face (masks, beards)"}
const PALETTE := ["#ffffff", "#c8c8c8", "#8a8a8a", "#4a4a4a", "#1a1a1a", "#7a4a2a", "#a8743e", "#d8b36a", "#b0452a", "#d94c4c",
	"#e8913a", "#e8cf4a", "#5aa84e", "#2f7a3a", "#3d9c9c", "#4a78d0", "#2a3f8a", "#8a58c8", "#d86ca8", "#f0d9a0"]

## Vector3i (skin pixels from the attachment point) -> "#rrggbb".
var voxels := {}
var category := "hat"
var layer := 0
var tool := "place"  # place | erase | pick
var color := "#d94c4c"
var mirror := false
var edit_id := ""
var author_id := ""
var author_name := ""

var _rig: Dictionary
var cosmetics: Cosmetics
var looks: LookBuilder
var avatar := {}
var player_name := ""
var _preview: Avatar
var _pivot: Node3D
var _camera: Camera3D
var _orbit := Vector2(PI + 0.5, -0.25)
var _zoom := 2.2
var _dragging := false
var _grid: Control
var _layer_label: Label
var _count_label: Label
var _status: Label
var _name_edit: LineEdit
var _category_select: OptionButton
var _color_button: ColorPickerButton
var _tool_buttons := {}
var _undo: Array = []
var _redo: Array = []
var _stroke_open := false
var _hover := Vector2i(999, 999)
var _dirty := true


func setup(registry: Cosmetics, look_builder: LookBuilder, rig: Dictionary, look: Dictionary, name_text: String, options := {}) -> void:
	cosmetics = registry
	looks = look_builder
	_rig = rig
	avatar = look.duplicate(true)
	player_name = name_text
	category = str(options.get("category", "hat")) if str(options.get("category", "hat")) in Creations.ACCESSORY_CATEGORIES else "hat"
	author_id = str(options.get("author", ""))
	author_name = str(options.get("author_name", name_text))
	var boxes = options.get("boxes")
	if boxes is Array:
		load_boxes(boxes)
	layer = _default_layer()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	var title := Label.new()
	title.text = "Build an accessory"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.custom_minimum_size = Vector2(320, 420)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_stretch_ratio = 0.8
	view.gui_input.connect(_on_preview_input)
	view.tooltip_text = "Drag to turn, scroll to zoom"
	body.add_child(view)
	view.add_child(_build_preview())

	var grid_box := AspectRatioContainer.new()
	grid_box.ratio = 1.0
	grid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(grid_box)
	_grid = Control.new()
	_grid.custom_minimum_size = Vector2(360, 360)
	_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.draw.connect(_draw_grid)
	_grid.gui_input.connect(_on_grid_input)
	grid_box.add_child(_grid)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(260, 0)
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	side.add_child(_heading("Worn as"))
	_category_select = OptionButton.new()
	for c in Creations.ACCESSORY_CATEGORIES:
		_category_select.add_item(CATEGORY_LABELS[c])
	_category_select.selected = Creations.ACCESSORY_CATEGORIES.find(category)
	_category_select.item_selected.connect(func(i):
		category = Creations.ACCESSORY_CATEGORIES[i]
		_dirty = true)
	side.add_child(_category_select)
	side.add_child(_heading("Layer (height)"))
	var layer_row := HBoxContainer.new()
	side.add_child(layer_row)
	var down := Button.new()
	down.text = "▼"
	down.tooltip_text = "Layer down (S or Page Down)"
	down.pressed.connect(func(): set_layer(layer - 1))
	layer_row.add_child(down)
	_layer_label = Label.new()
	_layer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer_row.add_child(_layer_label)
	var up := Button.new()
	up.text = "▲"
	up.tooltip_text = "Layer up (W or Page Up)"
	up.pressed.connect(func(): set_layer(layer + 1))
	layer_row.add_child(up)
	side.add_child(_heading("Tool"))
	var tools := HBoxContainer.new()
	side.add_child(tools)
	for t in [["place", "Place"], ["erase", "Erase"], ["pick", "Pick"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(set_tool.bind(t[0]))
		tools.add_child(b)
		_tool_buttons[t[0]] = b
	var mirror_box := CheckBox.new()
	mirror_box.text = "Mirror left and right (M)"
	mirror_box.toggled.connect(func(on): mirror = on)
	side.add_child(mirror_box)
	var layer_tools := HBoxContainer.new()
	side.add_child(layer_tools)
	for entry in [["Copy layer below", copy_layer_below], ["Clear layer", clear_layer]]:
		var b := Button.new()
		b.text = entry[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(entry[1])
		layer_tools.add_child(b)
	side.add_child(_heading("Color"))
	_color_button = ColorPickerButton.new()
	_color_button.color = Color.html(color)
	_color_button.custom_minimum_size = Vector2(0, 34)
	_color_button.color_changed.connect(func(c): color = "#" + c.to_html(false))
	side.add_child(_color_button)
	var palette := GridContainer.new()
	palette.columns = 5
	side.add_child(palette)
	for hex in PALETTE:
		palette.add_child(_swatch(hex))
	var edit_row := HBoxContainer.new()
	side.add_child(edit_row)
	for entry in [["↶ Undo", undo], ["↷ Redo", redo]]:
		var b := Button.new()
		b.text = entry[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(entry[1])
		edit_row.add_child(b)
	_count_label = Label.new()
	side.add_child(_count_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	root.add_child(footer)
	var name_label := Label.new()
	name_label.text = "Name"
	footer.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "My hat"
	_name_edit.max_length = Creations.MAX_NAME
	_name_edit.custom_minimum_size = Vector2(220, 0)
	footer.add_child(_name_edit)
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
	set_tool("place")
	set_layer(layer)


func set_name_text(text: String) -> void:
	if _name_edit != null:
		_name_edit.text = text
	else:
		(func(): _name_edit.text = text).call_deferred()


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	return l


func _swatch(hex: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(40, 30)
	b.tooltip_text = hex
	var style := StyleBoxFlat.new()
	style.bg_color = Color.html(hex)
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.2)
	b.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.border_color = Color.WHITE
	b.add_theme_stylebox_override("hover", hover)
	b.pressed.connect(func(): set_color(hex))
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
	_camera = Camera3D.new()
	_camera.fov = 35.0
	viewport.add_child(_camera)
	_pivot = Node3D.new()
	viewport.add_child(_pivot)
	_preview = Avatar.new()
	_pivot.add_child(_preview)
	_preview.build(_rig)
	return viewport


func _process(delta: float) -> void:
	if _preview == null:
		return
	_preview.animate(delta, Vector3.ZERO, true, 0.0)
	if _dirty:
		_dirty = false
		_refresh()
	# Orbit the camera around the attachment point.
	var target := _attach_node().global_position if _attach_node() != null else Vector3(0, 1.4, 0)
	var dir := Vector3(sin(_orbit.x) * cos(_orbit.y), -sin(_orbit.y), cos(_orbit.x) * cos(_orbit.y))
	_camera.look_at_from_position(target + dir * _zoom, target)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(0.8, _zoom * 0.9)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(6.0, _zoom * 1.1)
	elif event is InputEventMouseMotion and _dragging:
		_orbit.x -= event.relative.x * 0.01
		_orbit.y = clampf(_orbit.y + event.relative.y * 0.01, -1.3, 1.3)


func _attach_node() -> Node3D:
	if _preview == null:
		return null
	var cat := cosmetics.category(category)
	return _preview.attachments.get(cat.get("attach", ""))


## Redraws the avatar wearing the accessory as it is now, with a ghost of the current layer.
func _refresh() -> void:
	var def := {"name": PREVIEW_ID, "category": category, "display_name": "Preview", "boxes": build_boxes(), "tint": false}
	cosmetics.register(def)
	looks.clear_cache()
	var look := avatar.duplicate(true)
	var wear: Dictionary = look.get("wear", {})
	wear[category] = {"id": PREVIEW_ID, "color": "#ffffff"}
	look.wear = wear
	looks.apply(_preview, look, player_name)
	var node := _attach_node()
	if node != null:
		var plane := MeshInstance3D.new()
		var quad := PlaneMesh.new()
		quad.size = Vector2(EXTENT * 2, EXTENT * 2)
		plane.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.4, 0.7, 1.0, 0.18)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true
		quad.material = mat
		plane.position = Vector3(0, layer, 0)
		var holder := Node3D.new()
		holder.scale = Vector3.ONE * PlayerRig.PIXEL * float(_rig.get("height", 1.8)) / 1.8
		holder.add_child(plane)
		_preview._accessories.append(holder)
		node.add_child(holder)
	var boxes := build_boxes().size()
	if _count_label != null:
		_count_label.text = "%d voxels · %d / %d boxes" % [voxels.size(), boxes, Creations.MAX_BOXES]
		_count_label.add_theme_color_override("font_color", Color(1, 0.5, 0.4) if boxes > Creations.MAX_BOXES else Color(0.75, 0.78, 0.84))
	if _grid != null:
		_grid.queue_redraw()


# --- Editing ----------------------------------------------------------------------------------------

func set_tool(t: String) -> void:
	tool = t
	for key in _tool_buttons:
		_tool_buttons[key].button_pressed = key == t


func set_color(hex: String) -> void:
	color = hex
	if _color_button != null:
		_color_button.color = Color.html(hex)


func set_layer(value: int) -> void:
	layer = clampi(value, -EXTENT, EXTENT - 1)
	if _layer_label != null:
		_layer_label.text = "%d  (%s)" % [layer, "above the attachment point" if layer >= 0 else "below it"]
	_dirty = true


func _default_layer() -> int:
	return 0


func begin_stroke() -> void:
	if _stroke_open:
		return
	_stroke_open = true
	_undo.append(voxels.duplicate())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func end_stroke() -> void:
	_stroke_open = false


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(voxels.duplicate())
	voxels = _undo.pop_back()
	_dirty = true


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(voxels.duplicate())
	voxels = _redo.pop_back()
	_dirty = true


## Applies the current tool at a grid cell (x, z) of the current layer.
func apply_at(cell: Vector2i, erase := false) -> void:
	if cell.x < -EXTENT or cell.x >= EXTENT or cell.y < -EXTENT or cell.y >= EXTENT:
		return
	var p := Vector3i(cell.x, layer, cell.y)
	if tool == "pick" and not erase:
		if voxels.has(p):
			set_color(voxels[p])
		return
	begin_stroke()
	var targets := [p]
	if mirror:
		targets.append(Vector3i(-p.x - 1, p.y, p.z))
	for t in targets:
		if erase or tool == "erase":
			voxels.erase(t)
		else:
			voxels[t] = color
	_dirty = true


func copy_layer_below() -> void:
	begin_stroke()
	for p in voxels.keys():
		if p.y == layer - 1:
			voxels[Vector3i(p.x, layer, p.z)] = voxels[p]
	end_stroke()
	_dirty = true


func clear_layer() -> void:
	begin_stroke()
	for p in voxels.keys():
		if p.y == layer:
			voxels.erase(p)
	end_stroke()
	_dirty = true


## Merges voxels into boxes (greedy: along x, then z, then y, same color only).
func build_boxes() -> Array:
	var left := voxels.duplicate()
	var keys := left.keys()
	keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and (a.z < b.z or (a.z == b.z and a.x < b.x))))
	var boxes := []
	for start in keys:
		if not left.has(start):
			continue
		var c: String = left[start]
		var sx := 1
		while left.get(start + Vector3i(sx, 0, 0), "") == c:
			sx += 1
		var sz := 1
		while _row_matches(left, start + Vector3i(0, 0, sz), sx, c):
			sz += 1
		var sy := 1
		while _slab_matches(left, start + Vector3i(0, sy, 0), sx, sz, c):
			sy += 1
		for y in sy:
			for z in sz:
				for x in sx:
					left.erase(start + Vector3i(x, y, z))
		boxes.append({"from": [start.x, start.y, start.z], "size": [sx, sy, sz], "color": c})
	return boxes


static func _row_matches(left: Dictionary, origin: Vector3i, length: int, c: String) -> bool:
	for x in length:
		if left.get(origin + Vector3i(x, 0, 0), "") != c:
			return false
	return true


static func _slab_matches(left: Dictionary, origin: Vector3i, sx: int, sz: int, c: String) -> bool:
	for z in sz:
		if not _row_matches(left, origin + Vector3i(0, 0, z), sx, c):
			return false
	return true


## Turns boxes back into voxels (for editing a saved accessory).
func load_boxes(boxes: Array) -> void:
	voxels.clear()
	for b in boxes:
		if not (b is Dictionary) or not (b.get("from") is Array) or not (b.get("size") is Array):
			continue
		for y in int(b.size[1]):
			for z in int(b.size[2]):
				for x in int(b.size[0]):
					voxels[Vector3i(int(b.from[0]) + x, int(b.from[1]) + y, int(b.from[2]) + z)] = str(b.get("color", "#ffffff"))


func save() -> Dictionary:
	var name := _name_edit.text.strip_edges() if _name_edit != null else ""
	if name.is_empty():
		name = "My %s" % category
	var boxes := build_boxes()
	var payload := JSON.stringify({"boxes": boxes}).to_utf8_buffer()
	var result := CreationLibrary.save(Creations.make("accessory", category, payload, name, author_id, author_name), payload)
	if not result.ok:
		if _status != null:
			_status.text = result.error
		return result
	if not edit_id.is_empty() and edit_id != result.manifest.id:
		CreationLibrary.remove(edit_id)
	cosmetics.defs.erase(PREVIEW_ID)
	saved.emit(result.manifest)
	return result


# --- Grid -------------------------------------------------------------------------------------------

func _cell() -> float:
	return minf(_grid.size.x, _grid.size.y) / (EXTENT * 2)


## Grid cell (x, z) under a position: x grows right, z grows down (front of the avatar at the top).
func _cell_at(pos: Vector2) -> Vector2i:
	var c := _cell()
	return Vector2i(floori(pos.x / c) - EXTENT, floori(pos.y / c) - EXTENT)


func _draw_grid() -> void:
	var c := _cell()
	var size := Vector2.ONE * c * EXTENT * 2
	_grid.draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.14, 0.18))
	# Where the body part is at this height, as a guide.
	for part_rect in _body_guides():
		_grid.draw_rect(Rect2((part_rect.position + Vector2.ONE * EXTENT) * c, part_rect.size * c), Color(0.95, 0.75, 0.55, 0.16))
		_grid.draw_rect(Rect2((part_rect.position + Vector2.ONE * EXTENT) * c, part_rect.size * c), Color(0.95, 0.75, 0.55, 0.5), false, 1.5)
	# The layer below, faintly.
	for p in voxels:
		var cell := Vector2(p.x + EXTENT, p.z + EXTENT) * c
		if p.y == layer - 1:
			_grid.draw_rect(Rect2(cell, Vector2.ONE * c), Color(Color.html(voxels[p]), 0.25))
	for p in voxels:
		if p.y == layer:
			var cell := Vector2(p.x + EXTENT, p.z + EXTENT) * c
			_grid.draw_rect(Rect2(cell, Vector2.ONE * c), Color.html(voxels[p]))
	var line := Color(1, 1, 1, 0.08)
	for i in EXTENT * 2 + 1:
		_grid.draw_line(Vector2(i * c, 0), Vector2(i * c, size.y), line)
		_grid.draw_line(Vector2(0, i * c), Vector2(size.x, i * c), line)
	_grid.draw_line(Vector2(EXTENT * c, 0), Vector2(EXTENT * c, size.y), Color(0.4, 0.7, 1.0, 0.35), 1.5)
	_grid.draw_line(Vector2(0, EXTENT * c), Vector2(size.x, EXTENT * c), Color(0.4, 0.7, 1.0, 0.35), 1.5)
	_grid.draw_string(ThemeDB.fallback_font, Vector2(6, 16), "front", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5))
	if _hover.x > -999 and _hover.x >= -EXTENT and _hover.x < EXTENT and _hover.y >= -EXTENT and _hover.y < EXTENT:
		_grid.draw_rect(Rect2(Vector2(_hover + Vector2i.ONE * EXTENT) * c, Vector2.ONE * c), Color.WHITE, false, 2.0)


## Rectangles (x, z) of rig parts that cross the current layer, in attachment coordinates.
func _body_guides() -> Array:
	var out := []
	var cat := cosmetics.category(category)
	var a: Dictionary = _rig.get("attachments", {}).get(cat.get("attach", ""), {})
	if a.is_empty():
		return out
	for part in _rig.parts:
		if part.name != a.part:
			continue
		var lo := Vector3(part.box[0], part.box[1], part.box[2]) - Vector3(a.position[0], a.position[1], a.position[2])
		if layer >= lo.y and layer < lo.y + part.size[1]:
			out.append(Rect2(lo.x, lo.z, part.size[0], part.size[2]))
	return out


func _on_grid_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _cell_at(event.position)
		if cell != _hover:
			_hover = cell
			_grid.queue_redraw()
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			apply_at(cell)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			apply_at(cell, true)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			apply_at(_cell_at(event.position))
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			apply_at(_cell_at(event.position), true)
		elif not event.pressed:
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
		KEY_W, KEY_PAGEUP:
			set_layer(layer + 1)
		KEY_S, KEY_PAGEDOWN:
			set_layer(layer - 1)
		KEY_M:
			mirror = not mirror
		KEY_ESCAPE:
			closed.emit()
		_:
			return
	get_viewport().set_input_as_handled()
