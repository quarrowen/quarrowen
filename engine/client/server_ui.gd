extends Control
## Renders UI described by the server as plain data. Only the element types below exist, so a
## server can lay out and update interface but never run code on the client.
##
## Panel spec:
##   {
##     "anchor": "top_left" | "top_right" | "bottom_left" | "bottom_right" | "center" |
##               "center_top" | "center_left" | "center_right",
##     "modal": false,            true frees the mouse and pauses gameplay input while shown
##     "children": [element...]
##   }
## Elements:
##   {"type": "label", "text": "...", "size": 16, "color": "#ffffff"}
##   {"type": "button", "text": "...", "action": "id", "disabled": false}  -> ui_action event
##   {"type": "progress", "value": 3, "max": 10}
##   {"type": "image", "asset": "mod:textures/x.png", "size": 32}
##   {"type": "vbox" | "hbox", "children": [...]}
##   {"type": "spacer", "size": 8}

signal action_pressed(ui_id: String, action: String)

const MAX_DEPTH := 6
const MAX_CHILDREN := 64
const MAX_TEXT := 400
const MARGIN := 12

## anchor name -> [horizontal, vertical] with 0 = start, 0.5 = center, 1 = end.
const ANCHORS := {
	"top_left": [0.0, 0.0],
	"top_right": [1.0, 0.0],
	"bottom_left": [0.0, 1.0],
	"bottom_right": [1.0, 1.0],
	"center": [0.5, 0.5],
	"center_top": [0.5, 0.0],
	"center_left": [0.0, 0.5],
	"center_right": [1.0, 0.5],
}

## asset name -> Texture2D, provided by the client after content loads.
var textures := {}

var _panels := {}  # ui_id -> PanelContainer
var _modal := {}  # ui_id -> true
var _title: Label
var _subtitle: Label
var _title_until := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.position.y = -120
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_title = _shadow_label(54)
	_subtitle = _shadow_label(24)
	for label in [_title, _subtitle]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.visible = false
	box.add_child(_title)
	box.add_child(_subtitle)


func _process(_delta: float) -> void:
	if _title.visible and Time.get_ticks_msec() / 1000.0 > _title_until:
		_title.visible = false
		_subtitle.visible = false


func has_modal() -> bool:
	return not _modal.is_empty()


func show_title(text: String, subtitle: String, seconds: float) -> void:
	_title.text = text.left(MAX_TEXT)
	_subtitle.text = subtitle.left(MAX_TEXT)
	_title.visible = true
	_subtitle.visible = not subtitle.is_empty()
	_title_until = Time.get_ticks_msec() / 1000.0 + clampf(seconds, 0.1, 30.0)


func show_panel(ui_id: String, spec: Dictionary) -> void:
	hide_panel(ui_id)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.72)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	panel.add_child(content)
	_add_children(content, spec.get("children"), ui_id, 1)
	add_child(panel)
	_panels[ui_id] = panel
	if bool(spec.get("modal", false)):
		_modal[ui_id] = true
	else:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var anchor: Array = ANCHORS.get(String(spec.get("anchor", "top_right")), ANCHORS.top_right)
	_anchor(panel, anchor[0], anchor[1])


## Pins a control to a point of the screen and lets it grow away from that point, so it stays in
## place at its minimum size whenever the window or its contents change.
static func _anchor(control: Control, h: float, v: float) -> void:
	control.anchor_left = h
	control.anchor_right = h
	control.anchor_top = v
	control.anchor_bottom = v
	var dx := MARGIN if h == 0.0 else (-MARGIN if h == 1.0 else 0)
	var dy := MARGIN if v == 0.0 else (-MARGIN if v == 1.0 else 0)
	control.offset_left = dx
	control.offset_right = dx
	control.offset_top = dy
	control.offset_bottom = dy
	control.grow_horizontal = _grow(h)
	control.grow_vertical = _grow(v)


static func _grow(anchor: float) -> Control.GrowDirection:
	if anchor == 0.0:
		return Control.GROW_DIRECTION_END
	if anchor == 1.0:
		return Control.GROW_DIRECTION_BEGIN
	return Control.GROW_DIRECTION_BOTH


func hide_panel(ui_id: String) -> void:
	var panel: Control = _panels.get(ui_id)
	if panel:
		panel.queue_free()
	_panels.erase(ui_id)
	_modal.erase(ui_id)


func clear() -> void:
	for ui_id: String in _panels.keys():
		hide_panel(ui_id)


func _add_children(parent: Control, children, ui_id: String, depth: int) -> void:
	if not (children is Array) or depth > MAX_DEPTH:
		return
	for i in mini(children.size(), MAX_CHILDREN):
		if children[i] is Dictionary:
			var element := _build(children[i], ui_id, depth)
			if element:
				parent.add_child(element)


func _build(spec: Dictionary, ui_id: String, depth: int) -> Control:
	match String(spec.get("type", "")):
		"label":
			var label := _shadow_label(clampi(int(spec.get("size", 16)), 8, 64))
			label.text = String(spec.get("text", "")).left(MAX_TEXT)
			var color := String(spec.get("color", ""))
			if Color.html_is_valid(color):
				label.add_theme_color_override("font_color", Color.html(color))
			return label
		"button":
			var button := Button.new()
			button.text = String(spec.get("text", "")).left(64)
			button.disabled = bool(spec.get("disabled", false))
			var action := String(spec.get("action", "")).left(64)
			button.pressed.connect(func(): action_pressed.emit(ui_id, action))
			return button
		"progress":
			var bar := ProgressBar.new()
			bar.max_value = maxf(float(spec.get("max", 1)), 0.001)
			bar.value = float(spec.get("value", 0))
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(180, 10)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return bar
		"image":
			var rect := TextureRect.new()
			rect.texture = textures.get(String(spec.get("asset", "")))
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			var s := clampi(int(spec.get("size", 32)), 8, 256)
			rect.custom_minimum_size = Vector2(s, s)
			return rect
		"vbox", "hbox":
			var box: BoxContainer = VBoxContainer.new() if spec.type == "vbox" else HBoxContainer.new()
			box.add_theme_constant_override("separation", 6)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_add_children(box, spec.get("children"), ui_id, depth + 1)
			return box
		"spacer":
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2.ONE * clampi(int(spec.get("size", 8)), 0, 128)
			return spacer
	return null


func _shadow_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
