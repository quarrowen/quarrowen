extends Control
## Tutorial tracker, tips and hint markers.
## - The tracker (left side) shows the running tutorial's current step, its progress and a key to read
##   the linked guide page; it flashes when a step is done.
## - Tips slide in below it for a few seconds.
## - Hints: a bobbing marker above the nearest matching block or mob (or a position) and an arrow at
##   the screen edge while it is off screen. Blocks are searched a slice at a time around the player.
## - The tutorials panel (from the pause menu) lists tutorials to start or replay, skip/stop and tips.

signal action_requested(action: String, arg: String)

const SEARCH_RADIUS := 24
const SEARCH_DOWN := 10
const SEARCH_UP := 14
const MARKER_RANGE := 64.0

var client  # GameClient: world, registry, items, state, _entities, _crafting_screen
var tutorials: Array = []  # [{id, title, description, steps}]
var view := {}
var tip := {}

var _tracker: PanelContainer
var _header: Label
var _step_icon: TextureRect
var _step_title: Label
var _step_text: RichTextLabel
var _bar: ProgressBar
var _bar_label: Label
var _footer: Label
var _tip_card: PanelContainer
var _tip_icon: TextureRect
var _tip_text: RichTextLabel
var _tip_footer: Label
var _tip_until := 0.0
var _edge_arrow: Control
var _marker: Label3D
var panel: PanelContainer
var _panel_list: VBoxContainer
var _tips_box: CheckBox

# Hint search state.
var _hint := {}
var _hint_ids := PackedByteArray()  # block id -> 1 when it matches
var _scan_x := 0
var _scan_best := Vector3.INF
var _scan_center := Vector3i.ZERO
var _target := Vector3.INF


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	column.position = Vector2(16, -150)
	column.custom_minimum_size = Vector2(330, 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	_tracker = _card(Color(0.06, 0.05, 0.04, 0.78), Color(0.85, 0.65, 0.3, 0.9))
	column.add_child(_tracker)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	_tracker.add_child(box)
	_header = _label(13, Color(0.95, 0.75, 0.4))
	box.add_child(_header)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_step_icon = _icon_rect(28)
	row.add_child(_step_icon)
	_step_title = _label(19, Color.WHITE)
	_step_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_step_title)
	_step_text = _rich(15, Color(0.9, 0.88, 0.82))
	box.add_child(_step_text)
	var bar_row := HBoxContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar_row)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.7, 0.3)
	fill.set_corner_radius_all(3)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	back.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	bar_row.add_child(_bar)
	_bar_label = _label(13, Color(0.9, 0.88, 0.82))
	bar_row.add_child(_bar_label)
	_footer = _label(12, Color(0.7, 0.68, 0.62))
	box.add_child(_footer)
	_tracker.visible = false

	_tip_card = _card(Color(0.08, 0.12, 0.08, 0.85), Color(0.5, 0.8, 0.4, 0.9))
	column.add_child(_tip_card)
	var tip_box := VBoxContainer.new()
	tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_card.add_child(tip_box)
	var tip_row := HBoxContainer.new()
	tip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_row.add_theme_constant_override("separation", 8)
	tip_box.add_child(tip_row)
	_tip_icon = _icon_rect(24)
	tip_row.add_child(_tip_icon)
	_tip_text = _rich(15, Color(0.92, 0.96, 0.88))
	_tip_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_row.add_child(_tip_text)
	_tip_footer = _label(12, Color(0.65, 0.8, 0.6))
	tip_box.add_child(_tip_footer)
	_tip_card.visible = false

	_edge_arrow = Control.new()
	_edge_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_arrow.custom_minimum_size = Vector2(36, 36)
	_edge_arrow.size = Vector2(36, 36)
	_edge_arrow.pivot_offset = Vector2(18, 18)
	_edge_arrow.draw.connect(func():
		_edge_arrow.draw_colored_polygon(PackedVector2Array([Vector2(36, 18), Vector2(4, 4), Vector2(12, 18), Vector2(4, 32)]), Color(1.0, 0.8, 0.35))
		_edge_arrow.draw_polyline(PackedVector2Array([Vector2(36, 18), Vector2(4, 4), Vector2(12, 18), Vector2(4, 32), Vector2(36, 18)]), Color(0.2, 0.12, 0.02), 2.0))
	_edge_arrow.visible = false
	add_child(_edge_arrow)
	_build_panel()


# --- Server updates ---------------------------------------------------------------------------------

func set_view(v: Dictionary) -> void:
	var previous_step := "%s/%d" % [view.get("tutorial", ""), int(view.get("index", -1))]
	view = v
	_refresh_panel()
	if not v.has("tutorial"):
		_tracker.visible = false
		_set_hint({})
		return
	var step: Dictionary = v.step
	_tracker.visible = true
	_header.text = "TUTORIAL · %s   %d/%d" % [v.title, int(v.index) + 1, int(v.total)]
	_step_title.text = step.title
	_step_text.text = step.text
	_step_text.visible = not str(step.text).is_empty()
	var item_id: int = client.items.id_of(str(step.icon)) if not str(step.icon).is_empty() else -1
	_step_icon.texture = client._crafting_screen._icon(item_id) if item_id > 0 else null
	_step_icon.visible = _step_icon.texture != null
	var count := int(step.count)
	_bar.get_parent().visible = count > 1
	_bar.max_value = count
	_bar.value = int(step.progress)
	_bar_label.text = " %d/%d" % [mini(int(step.progress), count), count]
	_footer.text = "[%s] Read about it in the guide" % _key("guide") if not str(step.page).is_empty() else ""
	_footer.visible = not _footer.text.is_empty()
	if previous_step != "%s/%d" % [v.tutorial, int(v.index)]:
		_set_hint(step.hint if step.hint is Dictionary else {})
		_tracker.modulate = Color(1, 1, 1, 0)
		_tracker.create_tween().tween_property(_tracker, "modulate", Color.WHITE, 0.35)


## A step was finished: a quick green flash (the next step arrives with the view).
func step_done(kind: String) -> void:
	if not _tracker.visible:
		return
	var tween := _tracker.create_tween()
	var flash := Color(0.6, 1.4, 0.6) if kind != "skipped" else Color(1.2, 1.2, 1.2)
	tween.tween_property(_tracker, "self_modulate", flash, 0.12)
	tween.tween_property(_tracker, "self_modulate", Color.WHITE, 0.4)


func show_tip(t: Dictionary) -> void:
	tip = t
	_tip_text.text = str(t.get("text", ""))
	var item_id: int = client.items.id_of(str(t.get("icon", ""))) if not str(t.get("icon", "")).is_empty() else -1
	_tip_icon.texture = client._crafting_screen._icon(item_id) if item_id > 0 else null
	_tip_icon.visible = _tip_icon.texture != null
	_tip_footer.text = "Tip  ·  [%s] Read more" % _key("guide") if not str(t.get("page", "")).is_empty() else "Tip"
	_tip_until = _now() + float(t.get("seconds", 9.0))
	_tip_card.visible = true
	_tip_card.modulate.a = 0.0
	_tip_card.create_tween().tween_property(_tip_card, "modulate:a", 1.0, 0.3)


## The page the G key should open: the tip on show, else the current step's page (if not read yet).
func preferred_page(read: Dictionary) -> String:
	if _tip_card.visible and not str(tip.get("page", "")).is_empty():
		return tip.page
	if view.has("step") and not str(view.step.page).is_empty() and not read.has(view.step.page):
		return view.step.page
	return ""


# --- Hints ------------------------------------------------------------------------------------------

func _set_hint(hint: Dictionary) -> void:
	_hint = hint
	_target = Vector3.INF
	_scan_best = Vector3.INF
	_scan_x = -SEARCH_RADIUS
	_hint_ids = PackedByteArray()
	if hint.has("block"):
		_hint_ids.resize(client.registry.defs.size())
		for i in client.registry.defs.size():
			if _name_matches(hint.block, str(client.registry.defs[i].name)):
				_hint_ids[i] = 1
	elif hint.get("position") is Array:
		_target = Vector3(hint.position[0], hint.position[1], hint.position[2])


static func _name_matches(targets, actual: String) -> bool:
	for t in (targets if targets is Array else [targets]):
		if t == actual or (str(t).contains("*") and actual.match(t)):
			return true
	return false


func _process(delta: float) -> void:
	if _tip_card.visible and _now() > _tip_until and _tip_card.modulate.a >= 1.0:
		var tween := _tip_card.create_tween()
		tween.tween_property(_tip_card, "modulate:a", 0.0, 0.5)
		tween.tween_callback(func(): _tip_card.visible = false)
	if client == null or _hint.is_empty() or not _tracker.visible:
		_show_marker(Vector3.INF, delta)
		return
	var me: Vector3 = client.state.position
	if _hint.has("block"):
		_scan_blocks(me)
	elif _hint.has("entity"):
		var best := Vector3.INF
		for v in client._entities.values():
			if is_instance_valid(v) and not v.dying and _name_matches(_hint.entity, str(v.type_def.get("name", ""))):
				var at: Vector3 = v.position + Vector3(0, float(v.height), 0)
				if at.distance_to(me) < best.distance_to(me):
					best = at
		_target = best
	_show_marker(_target, delta)


## Scans one x slice of the box around the player per frame; the nearest match wins the sweep.
func _scan_blocks(me: Vector3) -> void:
	if _scan_x == -SEARCH_RADIUS:
		_scan_center = Vector3i(floori(me.x), floori(me.y), floori(me.z))
		_scan_best = Vector3.INF
	var world = client.world
	var x := _scan_center.x + _scan_x
	for z in range(_scan_center.z - SEARCH_RADIUS, _scan_center.z + SEARCH_RADIUS + 1):
		for y in range(_scan_center.y - SEARCH_DOWN, _scan_center.y + SEARCH_UP + 1):
			var id: int = world.get_block(x, y, z)
			if id > 0 and id < _hint_ids.size() and _hint_ids[id] == 1:
				var at := Vector3(x + 0.5, y + 1.3, z + 0.5)
				if at.distance_squared_to(me) < _scan_best.distance_squared_to(me):
					_scan_best = at
	_scan_x += 1
	if _scan_x > SEARCH_RADIUS:
		_scan_x = -SEARCH_RADIUS
		# Keep the old target while it still exists and is about as close.
		_target = _scan_best


func _show_marker(target: Vector3, _delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var active := target != Vector3.INF and camera != null and client != null and target.distance_to(client.state.position) < MARKER_RANGE
	if _marker == null and active:
		_marker = Label3D.new()
		_marker.text = "▼"
		_marker.font_size = 64
		_marker.outline_size = 12
		_marker.modulate = Color(1.0, 0.8, 0.35)
		_marker.outline_modulate = Color(0.2, 0.12, 0.02)
		_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_marker.no_depth_test = true
		_marker.fixed_size = true
		_marker.pixel_size = 0.0006
		client.add_child(_marker)
	if _marker != null:
		_marker.visible = active
	if not active:
		_edge_arrow.visible = false
		return
	var t := _now()
	_marker.global_position = target + Vector3(0, 0.25 + sin(t * 4.0) * 0.15, 0)
	var distance := target.distance_to(client.state.position)
	_marker.text = "▼\n%d m" % roundi(distance) if distance > 6.0 else "▼"
	# Off screen (or behind): an arrow at the edge pointing the way.
	var rect := get_viewport_rect()
	var behind := camera.is_position_behind(target)
	var screen := camera.unproject_position(target)
	var on_screen := not behind and rect.grow(-40).has_point(screen)
	_edge_arrow.visible = not on_screen
	if on_screen:
		return
	var center := rect.size * 0.5
	# The direction in camera space; targets behind point to the nearer side.
	var local: Vector3 = camera.global_transform.basis.inverse() * (target - camera.global_position)
	var dir := Vector2(local.x, -local.y)
	if local.z > 0.0:
		dir = Vector2(signf(local.x) if absf(local.x) > 0.01 else 1.0, clampf(-local.y / maxf(local.length(), 0.01), -0.5, 0.5))
	if dir.length() < 0.001:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var margin := rect.size * 0.5 - Vector2(60, 60)
	var scale := minf(absf(margin.x / dir.x) if absf(dir.x) > 0.001 else INF, absf(margin.y / dir.y) if absf(dir.y) > 0.001 else INF)
	_edge_arrow.position = center + dir * scale - _edge_arrow.size * 0.5
	_edge_arrow.rotation = dir.angle()
	_edge_arrow.scale = Vector2.ONE * (1.0 + sin(t * 5.0) * 0.08)


# --- Tutorials panel --------------------------------------------------------------------------------

func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(460, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _box(Color(0.07, 0.07, 0.09, 0.96), Color(0.85, 0.65, 0.3, 0.8), 14))
	panel.visible = false
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _label(22, Color(1.0, 0.82, 0.4))
	title.text = "Tutorials"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(func(): panel.visible = false)
	head.add_child(close)
	_panel_list = VBoxContainer.new()
	_panel_list.add_theme_constant_override("separation", 8)
	box.add_child(_panel_list)
	_tips_box = CheckBox.new()
	_tips_box.text = "Show tips while playing"
	_tips_box.toggled.connect(func(on): action_requested.emit("tips_on" if on else "tips_off", ""))
	box.add_child(_tips_box)


func open_panel() -> void:
	_refresh_panel()
	panel.visible = true


func _refresh_panel() -> void:
	if _panel_list == null:
		return
	for child in _panel_list.get_children():
		child.queue_free()
	var done: Array = view.get("done", [])
	if tutorials.is_empty():
		var none := _label(15, Color(0.7, 0.7, 0.7))
		none.text = "This server has no tutorials."
		_panel_list.add_child(none)
	for t in tutorials:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_panel_list.add_child(row)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var active: bool = view.get("tutorial", "") == t.id
		var name_label := _label(17, Color.WHITE)
		name_label.text = "%s%s" % [t.title, "  ✓" if done.has(t.id) else ("  (in progress)" if active else "")]
		text.add_child(name_label)
		if not str(t.description).is_empty():
			var desc := _label(13, Color(0.7, 0.7, 0.72))
			desc.text = t.description
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.add_child(desc)
		if active:
			for pair in [["Skip step", "skip"], ["Stop", "stop"]]:
				var b := Button.new()
				b.text = pair[0]
				b.pressed.connect(func(): action_requested.emit(pair[1], ""))
				row.add_child(b)
		else:
			var start := Button.new()
			start.text = "Replay" if done.has(t.id) else "Start"
			start.pressed.connect(func():
				action_requested.emit("start", t.id)
				panel.visible = false)
			row.add_child(start)
	_tips_box.set_pressed_no_signal(not bool(view.get("tips_off", false)))


# --- Helpers ----------------------------------------------------------------------------------------

func _key(action: String) -> String:
	return preload("res://engine/client/guide_screen.gd").key_name(action)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _card(bg: Color, border: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _box(bg, border, 10))
	return card


static func _box(bg: Color, border: Color, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = 3
	s.set_corner_radius_all(6)
	s.set_content_margin_all(margin)
	return s


func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _rich(font_size: int, color: Color) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_color_override("default_color", color)
	for key in ["normal_font_size", "bold_font_size", "italics_font_size"]:
		r.add_theme_font_size_override(key, font_size)
	return r


func _icon_rect(size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon
