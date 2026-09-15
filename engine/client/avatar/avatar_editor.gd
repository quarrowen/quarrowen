extends Control
## Avatar editor: a turning 3D preview beside categories of cosmetics, colors and, in game, the
## per-slot choice between showing armor or cosmetics. Used from the main menu (built-in cosmetics,
## saved on this computer) and in game (also this server's cosmetics).

signal done(avatar: Dictionary)
signal cancelled

const Cosmetics = preload("res://engine/shared/cosmetics.gd")
const LookBuilder = preload("res://engine/client/avatar/look_builder.gd")
const Avatar = preload("res://engine/client/avatar/avatar.gd")
const Creations = preload("res://engine/shared/creations.gd")
const CreationLibrary = preload("res://engine/client/creation_library.gd")
const SkinPainter = preload("res://engine/client/avatar/skin_painter.gd")
const AccessoryBuilder = preload("res://engine/client/avatar/accessory_builder.gd")
const ModelImporter = preload("res://engine/client/avatar/model_importer.gd")

const EYE_COLORS := ["#3050c0", "#3a8a40", "#6a4428", "#202020", "#8a58c8", "#3d9c9c", "#9a9a9a", "#d94c4c"]
const BODY_TARGETS := ["all", "head", "torso", "arms", "legs"]

var cosmetics: Cosmetics
var looks: LookBuilder
var player_name := ""
## The avatar being edited (Cosmetics data).
var avatar := {}
## Server cosmetics the player owns (in game).
var owned := PackedStringArray()
var in_game := false
## Show the player's creations and the tools to make them.
var creations := false
var author_id := ""

var _rig: Dictionary
var _preview: Avatar
var _pivot: Node3D
var _category := "body"
var _body_target := "all"
var _tabs: HFlowContainer
var _grid: GridContainer
var _colors: HFlowContainer
var _colors_label: Label
var _body_row: HBoxContainer
var _armor_row: HBoxContainer
var _dragging := false
var _creation_row: HBoxContainer
var _painter: Control


func setup(registry: Cosmetics, look_builder: LookBuilder, rig: Dictionary, name_text: String, start: Dictionary, options := {}) -> void:
	cosmetics = registry
	looks = look_builder
	_rig = rig
	player_name = name_text
	in_game = bool(options.get("in_game", false))
	owned = options.get("owned", PackedStringArray())
	creations = bool(options.get("creations", false))
	author_id = str(options.get("author", ""))
	avatar = LookBuilder.resolve(start, name_text).duplicate(true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.11, 0.92)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	margin.add_child(row)

	var view_container := SubViewportContainer.new()
	view_container.stretch = true
	view_container.custom_minimum_size = Vector2(340, 420)
	view_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_container.size_flags_stretch_ratio = 0.8
	view_container.gui_input.connect(_on_preview_input)
	row.add_child(view_container)
	view_container.add_child(_build_preview())

	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 10)
	row.add_child(panel)
	var title := Label.new()
	title.text = "Customize avatar"
	title.add_theme_font_size_override("font_size", 28)
	panel.add_child(title)
	_tabs = HFlowContainer.new()
	panel.add_child(_tabs)

	_body_row = HBoxContainer.new()
	var target_label := Label.new()
	target_label.text = "Color applies to"
	_body_row.add_child(target_label)
	var target := OptionButton.new()
	for t in BODY_TARGETS:
		target.add_item(t.capitalize())
	target.item_selected.connect(func(i): _body_target = BODY_TARGETS[i])
	_body_row.add_child(target)
	panel.add_child(_body_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_creation_row = HBoxContainer.new()
	_creation_row.visible = creations
	_creation_row.add_theme_constant_override("separation", 8)
	panel.add_child(_creation_row)

	_colors_label = Label.new()
	_colors_label.text = "Color"
	panel.add_child(_colors_label)
	_colors = HFlowContainer.new()
	panel.add_child(_colors)

	_armor_row = HBoxContainer.new()
	_armor_row.visible = in_game and cosmetics.policy.armor == "player"
	var armor_label := Label.new()
	armor_label.text = "Show armor instead of cosmetics:"
	armor_label.tooltip_text = "Where a cosmetic covers an armor slot (like a hat over a helmet), choose which one others see."
	armor_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_armor_row.add_child(armor_label)
	for slot in Cosmetics.ARMOR_SLOTS:
		var check := CheckBox.new()
		check.name = "show_" + slot
		check.text = slot.capitalize()
		check.button_pressed = bool(avatar.get("show_armor", {}).get(slot, false))
		check.toggled.connect(func(on: bool):
			var show: Dictionary = avatar.get("show_armor", {})
			show[slot] = on
			avatar.show_armor = show)
		_armor_row.add_child(check)
	panel.add_child(_armor_row)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	panel.add_child(buttons)
	for entry in [["Randomize", _randomize], ["Reset", _reset], ["Cancel", func(): cancelled.emit()], ["Done", func(): done.emit(avatar.duplicate(true))]]:
		var b := Button.new()
		b.name = entry[0]
		b.text = entry[0]
		b.custom_minimum_size = Vector2(110, 40)
		b.pressed.connect(entry[1])
		buttons.add_child(b)
	_rebuild_tabs()
	_show_category("body")
	_refresh_preview()


func _process(delta: float) -> void:
	if _preview != null:
		_preview.animate(delta, Vector3.ZERO, true, 0.0)
		if not _dragging:
			_pivot.rotation.y += delta * 0.4


func _build_preview() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.2, 0.27)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.7
	viewport.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.1
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 35.0
	camera.position = Vector3(0, 1.05, 4.4)
	viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 0.95, 0))
	_pivot = Node3D.new()
	_pivot.rotation.y = PI  # face the camera
	viewport.add_child(_pivot)
	_preview = Avatar.new()
	_pivot.add_child(_preview)
	_preview.build(_rig)
	return viewport


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pivot.rotation.y += event.relative.x * 0.01


func _rebuild_tabs() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	var names := [["body", "Body"]]
	for cat in cosmetics.categories:
		if not _choices(cat.name).is_empty():
			names.append([cat.name, cat.display_name])
	for entry in names:
		var b := Button.new()
		b.name = "tab_" + entry[0]
		b.text = entry[1]
		b.toggle_mode = true
		b.button_pressed = entry[0] == _category
		b.pressed.connect(_show_category.bind(entry[0]))
		_tabs.add_child(b)


## Cosmetics shown for a category: built-in ones where allowed, then this server's.
func _choices(cat_name: String) -> Array:
	var out := []
	for d in cosmetics.in_category(cat_name):
		if cosmetics.is_blocked(d.name) or d.name.begins_with("preview:"):
			continue
		if Cosmetics.is_builtin(d.name) and in_game and not cosmetics.policy.allow_builtin:
			continue
		out.append(d)
	return out


func _can_wear(d: Dictionary) -> bool:
	return Cosmetics.is_builtin(d.name) or d.unlocked or owned.has(d.name)


func _show_category(cat_name: String) -> void:
	_category = cat_name
	for b in _tabs.get_children():
		b.button_pressed = b.name == "tab_" + cat_name
	for child in _grid.get_children():
		child.queue_free()
	_body_row.visible = cat_name == "body"
	var worn := String(avatar.get("wear", {}).get(cat_name, {}).get("id", ""))
	if cat_name != "body":
		_grid.add_child(_choice_button("None", worn.is_empty(), true, "", _wear.bind("")))
		for d in _choices(cat_name):
			var wearable := _can_wear(d)
			var tip: String = d.description if wearable else "Locked on this server"
			var label: String = d.display_name if Cosmetics.is_builtin(d.name) else ("✎ %s" % d.display_name if Creations.is_id(d.name) else "%s ★" % d.display_name)
			_grid.add_child(_choice_button(label, d.name == worn, wearable, tip, _wear.bind(d.name)))
	_rebuild_colors()
	_rebuild_creation_row()


## Buttons to make and manage creations for the category on show.
func _rebuild_creation_row() -> void:
	if _creation_row == null:
		return
	for child in _creation_row.get_children():
		child.queue_free()
	if not creations:
		return
	var worn := String(avatar.get("wear", {}).get(_category, {}).get("id", ""))
	if _category in ["body", "skin"]:
		_creation_row.add_child(_small_button("Paint a skin…", open_painter.bind("")))
	if _category in Creations.ACCESSORY_CATEGORIES:
		_creation_row.add_child(_small_button("Build…", open_builder.bind("")))
		_creation_row.add_child(_small_button("Import model…", _pick_model))
	if Creations.is_id(worn):
		var m := CreationLibrary.get_manifest(worn)
		if not m.is_empty():
			match m.kind:
				"skin": _creation_row.add_child(_small_button("Edit", open_painter.bind(worn)))
				"accessory": _creation_row.add_child(_small_button("Edit", open_builder.bind(worn)))
				"model": _creation_row.add_child(_small_button("Edit placement", open_model_importer.bind(CreationLibrary.get_payload(worn), worn)))
			_creation_row.add_child(_small_button("Delete", _delete_creation.bind(worn)))


func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(action)
	return b


## Opens the skin painter on a library skin (id) or, for "", on the current look.
func open_painter(id: String) -> void:
	var start: Image
	var name := ""
	if not id.is_empty():
		start = Image.new()
		start.load_png_from_buffer(CreationLibrary.get_payload(id))
		name = str(CreationLibrary.get_manifest(id).get("name", ""))
	else:
		var look := avatar.duplicate(true)
		if look.get("wear", {}).has("skin"):
			look.wear.erase("skin")
		start = looks.skin_image(look)
	var painter := SkinPainter.new()
	painter.setup(_rig, start, name, author_id, player_name)
	painter.edit_id = id
	painter.saved.connect(func(manifest: Dictionary):
		CreationLibrary.add_to(cosmetics, looks.images, manifest, CreationLibrary.get_payload(manifest.id))
		looks.clear_cache()
		_category = "skin"
		_rebuild_tabs()
		_wear(manifest.id)
		painter.queue_free()
		_painter = null)
	painter.closed.connect(func():
		painter.queue_free()
		_painter = null)
	_painter = painter
	add_child(painter)


## Opens the accessory builder, empty or on a library accessory.
func open_builder(id: String) -> void:
	var options := {"category": _category, "author": author_id, "author_name": player_name}
	var name := ""
	if not id.is_empty():
		var m := CreationLibrary.get_manifest(id)
		var data = JSON.parse_string(CreationLibrary.get_payload(id).get_string_from_utf8())
		options.boxes = data.get("boxes", []) if data is Dictionary else []
		options.category = m.get("category", _category)
		name = str(m.get("name", ""))
	var look := avatar.duplicate(true)
	var builder := AccessoryBuilder.new()
	builder.setup(cosmetics, looks, _rig, look, player_name, options)
	builder.edit_id = id
	if not name.is_empty():
		builder.set_name_text(name)
	_open_tool(builder)


func open_model_importer(glb: PackedByteArray, id := "") -> void:
	var options := {"category": _category if _category in Creations.ACCESSORY_CATEGORIES else "hat", "author": author_id, "author_name": player_name}
	var name := ""
	if not id.is_empty():
		var m := CreationLibrary.get_manifest(id)
		options.category = m.get("category", options.category)
		options.model_transform = m.get("model_transform", {})
		name = str(m.get("name", ""))
	var importer := ModelImporter.new()
	importer.setup(cosmetics, looks, _rig, avatar, player_name, glb, options)
	importer.edit_id = id
	if not name.is_empty():
		importer.set_name_text(name)
	_open_tool(importer)


func _pick_model() -> void:
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.glb ; Binary glTF model"])
	dialog.file_selected.connect(func(path: String):
		dialog.queue_free()
		open_model_importer(FileAccess.get_file_as_bytes(path))
		if _painter != null:
			_painter.set_name_text(path.get_file().get_basename().capitalize()))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


## Shows a creation tool over the editor; saving wears the result.
func _open_tool(tool_node: Control) -> void:
	tool_node.saved.connect(func(manifest: Dictionary):
		for preview in ["preview:accessory", "preview:model"]:
			cosmetics.defs.erase(preview)
		CreationLibrary.add_to(cosmetics, looks.images, manifest, CreationLibrary.get_payload(manifest.id))
		looks.clear_cache()
		_category = manifest.category
		_rebuild_tabs()
		_wear(manifest.id)
		tool_node.queue_free()
		_painter = null)
	tool_node.closed.connect(func():
		tool_node.queue_free()
		_painter = null
		_refresh_preview())
	_painter = tool_node
	add_child(tool_node)


func _delete_creation(id: String) -> void:
	CreationLibrary.remove(id)
	cosmetics.defs.erase(id)
	_wear("")
	_rebuild_tabs()


func _choice_button(label: String, selected: bool, enabled: bool, tip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_pressed = selected
	b.disabled = not enabled
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(150, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.pressed.connect(action)
	return b


func _rebuild_colors() -> void:
	for child in _colors.get_children():
		child.queue_free()
	var palette := []
	var worn: Dictionary = avatar.get("wear", {}).get(_category, {})
	if _category == "body":
		palette = Cosmetics.SKIN_TONES
	elif not worn.is_empty() and cosmetics.get_def(worn.id).get("tint", false):
		palette = {"hair": Cosmetics.HAIR_COLORS, "face": EYE_COLORS}.get(_category, Cosmetics.CLOTHING_COLORS)
	var allowed: bool = not in_game or cosmetics.policy.allow_colors
	_colors_label.visible = allowed and not palette.is_empty()
	_colors_label.text = "Skin color" if _category == "body" else ("Eye color" if _category == "face" else "Color")
	if not allowed:
		return
	for hex in palette:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(34, 34)
		swatch.tooltip_text = hex
		var style := StyleBoxFlat.new()
		style.bg_color = Color.html(hex)
		style.set_corner_radius_all(6)
		style.set_border_width_all(2)
		style.border_color = Color(1, 1, 1, 0.25)
		var hover := style.duplicate()
		hover.border_color = Color.WHITE
		swatch.add_theme_stylebox_override("normal", style)
		swatch.add_theme_stylebox_override("hover", hover)
		swatch.add_theme_stylebox_override("pressed", hover)
		swatch.pressed.connect(_set_color.bind(hex))
		_colors.add_child(swatch)


func _wear(cosmetic_name: String) -> void:
	var wear: Dictionary = avatar.get("wear", {})
	if cosmetic_name.is_empty():
		wear.erase(_category)
	else:
		var previous: Dictionary = wear.get(_category, {})
		var d := cosmetics.get_def(cosmetic_name)
		# Keep a chosen color when switching styles within a category.
		wear[_category] = {"id": cosmetic_name, "color": previous.get("color", d.color) if not previous.is_empty() else d.color}
	avatar.wear = wear
	_show_category(_category)
	_refresh_preview()


func _set_color(hex: String) -> void:
	if _category == "body":
		if _body_target == "all":
			avatar.skin = hex
			avatar.erase("body")
		else:
			var body: Dictionary = avatar.get("body", {})
			body[_body_target] = hex
			avatar.body = body
	elif avatar.get("wear", {}).has(_category):
		avatar.wear[_category].color = hex
	_refresh_preview()


func _randomize() -> void:
	var fresh := Cosmetics.default_avatar(str(randi()))
	for cat in ["hat", "glasses", "back", "jacket"]:
		var choices := _choices(cat).filter(_can_wear)
		if not choices.is_empty() and randf() < 0.4:
			var d: Dictionary = choices.pick_random()
			fresh.wear[cat] = {"id": d.name, "color": Cosmetics.CLOTHING_COLORS.pick_random()}
	fresh.show_armor = avatar.get("show_armor", {})
	avatar = fresh
	_show_category(_category)
	_refresh_preview()


func _reset() -> void:
	avatar = Cosmetics.default_avatar(player_name)
	_show_category(_category)
	_refresh_preview()


func _refresh_preview() -> void:
	if _preview != null:
		looks.apply(_preview, avatar, player_name)
