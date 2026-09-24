extends Control
## The task list: what this player has been asked to do, and how far along they are.
##
## **Objectives existed on the server for weeks with nothing to show them.** A mod could register a
## task, give it, advance it and finish it, and the player saw nothing at all - which is exactly what
## was reported the first time Firstlight was played: *"isnt it supposed to be a guided story? i dont
## see the quest/task list"*. The engine was doing the work and never saying so. (2026-09-24)
##
## Top right, out of the way of the tutorial tracker on the left, the compass above and the chat below.
## It hides itself when there is nothing to do, because an empty panel is worse than no panel.

const ACCENT := Color(0.55, 0.8, 1.0)

var _card: PanelContainer
var _title: Label
var _list: VBoxContainer
var _active: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	# Grows leftwards from the right edge, so a long task name does not walk off the screen.
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.position = Vector2(-16, 64)
	column.custom_minimum_size = Vector2(300, 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04, 0.06, 0.09, 0.78)
	box.border_color = Color(ACCENT, 0.9)
	box.border_width_right = 3
	box.set_corner_radius_all(6)
	box.set_content_margin_all(10)
	_card.add_theme_stylebox_override("panel", box)
	column.add_child(_card)

	var inner := VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 6)
	_card.add_child(inner)
	_title = _label(13, ACCENT)
	_title.text = "Things to do"
	inner.add_child(_title)
	_list = VBoxContainer.new()
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 8)
	inner.add_child(_list)
	_card.visible = false


## {active: [{name, display_name, step, of, text, progress, needed}]} from the server.
func set_view(view: Dictionary) -> void:
	_active = view.get("active") if view.get("active") is Array else []
	_rebuild()


func _rebuild() -> void:
	# Out of the tree before freeing: queue_free happens at the end of the frame, so a rebuild that
	# runs twice in one frame would free the new rows too.
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_card.visible = not _active.is_empty()
	if not _card.visible:
		return
	for task in _active:
		if not (task is Dictionary):
			continue
		var row := VBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 2)
		_list.add_child(row)
		var name_label := _label(15, Color.WHITE)
		name_label.text = String(task.get("display_name", ""))
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(name_label)
		var step := _label(14, Color(0.88, 0.9, 0.94))
		# A tick rather than a bullet, because the step you are on is the one that is not done yet.
		step.text = "• %s" % String(task.get("text", ""))
		step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(step)
		var needed := int(task.get("needed", 1))
		var of := int(task.get("of", 1))
		var notes := []
		if needed > 1:
			notes.append("%d of %d" % [int(task.get("progress", 0)), needed])
		if of > 1:
			notes.append("step %d of %d" % [int(task.get("step", 0)) + 1, of])
		if not notes.is_empty():
			var foot := _label(12, Color(0.6, 0.68, 0.78))
			foot.text = "  ".join(notes)
			row.add_child(foot)


func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l
