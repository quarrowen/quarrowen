extends Control
## Places an imported GLB model as an accessory: pick where it is worn, then scale, move and turn it
## while the preview shows it on your avatar. The file is checked (size, triangles, textures) before it
## can be saved to the creation library; the placement is stored with it.

signal saved(manifest: Dictionary)
signal closed

const Avatar = preload("res://engine/client/avatar/avatar.gd")
const LookBuilder = preload("res://engine/client/avatar/look_builder.gd")
const Cosmetics = preload("res://engine/shared/cosmetics.gd")
const Creations = preload("res://engine/shared/creations.gd")
const CreationLibrary = preload("res://engine/client/creation_library.gd")

const PREVIEW_ID := "preview:model"
const PREVIEW_ASSET := "preview:model.glb"

var cosmetics: Cosmetics
var looks: LookBuilder
var avatar := {}
var player_name := ""
var author_id := ""
var author_name := ""
var bytes := PackedByteArray()
var category := "hat"
var transform := {"position": [0.0, 0.0, 0.0], "rotation": [0.0, 0.0, 0.0], "scale": 0.5}
var edit_id := ""
var error := ""
var info := {}

var _rig: Dictionary
var _preview: Avatar
var _pivot: Node3D
var _dragging := false
var _reader: Callable
var _name_edit: LineEdit
var _status: Label
var _dirty := true


func setup(registry: Cosmetics, look_builder: LookBuilder, rig: Dictionary, look: Dictionary, name_text: String, glb: PackedByteArray, options := {}) -> void:
	cosmetics = registry
	looks = look_builder
	_rig = rig
	avatar = look.duplicate(true)
	player_name = name_text
	bytes = glb
	author_id = str(options.get("author", ""))
	author_name = str(options.get("author_name", name_text))
	category = str(options.get("category", "hat")) if str(options.get("category", "hat")) in Creations.ACCESSORY_CATEGORIES else "hat"
	if options.get("model_transform") is Dictionary:
		transform = Cosmetics._transform(options.model_transform)
	var measured := Creations.measure_model(glb)
	if measured.has("error"):
		error = measured.error
	elif glb.size() > Creations.MAX_MODEL_BYTES or measured.triangles > Creations.MAX_MODEL_TRIANGLES or measured.max_texture > Creations.MAX_MODEL_TEXTURE:
		error = Creations.validate(Creations.make("model", category, glb, "check"), glb).error
	info = measured


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_reader = looks.read_model
	looks.read_model = func(asset: String) -> PackedByteArray:
		return bytes if asset == PREVIEW_ASSET else (_reader.call(asset) if _reader.is_valid() else PackedByteArray())
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
	title.text = "Place a model"
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.custom_minimum_size = Vector2(360, 420)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event is InputEventMouseMotion and _dragging:
			_pivot.rotation.y += event.relative.x * 0.01)
	body.add_child(view)
	view.add_child(_build_preview())

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(320, 0)
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	var facts := Label.new()
	facts.text = error if not error.is_empty() else "%d KB · %d triangles · textures up to %d px" % [bytes.size() / 1024, int(info.get("triangles", 0)), int(info.get("max_texture", 0))]
	facts.add_theme_color_override("font_color", Color(1, 0.55, 0.45) if not error.is_empty() else Color(0.7, 0.8, 0.7))
	facts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts.custom_minimum_size = Vector2(300, 0)
	side.add_child(facts)
	var where := OptionButton.new()
	for c in Creations.ACCESSORY_CATEGORIES:
		where.add_item(c.capitalize())
	where.selected = Creations.ACCESSORY_CATEGORIES.find(category)
	where.item_selected.connect(func(i):
		category = Creations.ACCESSORY_CATEGORIES[i]
		_dirty = true)
	side.add_child(where)
	side.add_child(_slider("Size (blocks)", 0.05, 3.0, 0.01, float(transform.scale), func(v): transform.scale = v))
	for axis in [["Left / right", 0], ["Up / down", 1], ["Back / front", 2]]:
		side.add_child(_slider(axis[0] + " (pixels)", -24.0, 24.0, 0.5, float(transform.position[axis[1]]), func(v): transform.position[axis[1]] = v))
	for axis in [["Tilt", 0], ["Turn", 1], ["Roll", 2]]:
		side.add_child(_slider(axis[0] + " (degrees)", -180.0, 180.0, 5.0, float(transform.rotation[axis[1]]), func(v): transform.rotation[axis[1]] = v))

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	root.add_child(footer)
	var name_label := Label.new()
	name_label.text = "Name"
	footer.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "My model"
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
		b.disabled = entry[0] == "Save" and not error.is_empty()
		b.pressed.connect(entry[1])
		footer.add_child(b)


func _exit_tree() -> void:
	if looks != null and _reader.is_valid():
		looks.read_model = _reader
	if cosmetics != null:
		cosmetics.defs.erase(PREVIEW_ID)


func set_name_text(text: String) -> void:
	(func(): _name_edit.text = text).call_deferred()


func _slider(label: String, lo: float, hi: float, step: float, value: float, apply: Callable) -> Control:
	var row := VBoxContainer.new()
	var head := Label.new()
	head.text = "%s: %s" % [label, snappedf(value, step)]
	head.add_theme_color_override("font_color", Color(0.7, 0.74, 0.8))
	row.add_child(head)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.value_changed.connect(func(v):
		apply.call(v)
		head.text = "%s: %s" % [label, snappedf(v, step)]
		_dirty = true)
	row.add_child(s)
	return row


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
	camera.position = Vector3(0, 1.3, 3.6)
	viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 1.2, 0))
	_pivot = Node3D.new()
	_pivot.rotation.y = PI + 0.6
	viewport.add_child(_pivot)
	_preview = Avatar.new()
	_pivot.add_child(_preview)
	_preview.build(_rig)
	return viewport


func _process(delta: float) -> void:
	if _preview == null:
		return
	_preview.animate(delta, Vector3.ZERO, true, 0.0)
	if not _dragging:
		_pivot.rotation.y += delta * 0.3
	if _dirty:
		_dirty = false
		if error.is_empty():
			cosmetics.register({"name": PREVIEW_ID, "category": category, "display_name": "Preview", "model": PREVIEW_ASSET, "model_transform": transform})
			looks.clear_cache()
			var look := avatar.duplicate(true)
			var wear: Dictionary = look.get("wear", {})
			wear[category] = {"id": PREVIEW_ID, "color": "#ffffff"}
			look.wear = wear
			looks.apply(_preview, look, player_name)
		else:
			looks.apply(_preview, avatar, player_name)


func save() -> Dictionary:
	var name := _name_edit.text.strip_edges() if _name_edit != null else ""
	if name.is_empty():
		name = "My model"
	var manifest := Creations.make("model", category, bytes, name, author_id, author_name, {"model_transform": transform})
	var result := CreationLibrary.save(manifest, bytes)
	if not result.ok:
		if _status != null:
			_status.text = result.error
		return result
	if not edit_id.is_empty() and edit_id != result.manifest.id:
		CreationLibrary.remove(edit_id)
	saved.emit(result.manifest)
	return result
