extends Control
## The inventory screen (E): 27 main slots above the 9 hotbar slots. Clicks go to the server, which
## owns the inventory and the stack held by the cursor; the screen just redraws what it sends back.
##   left click: pick up / put down / merge / swap     right click: pick up half / put down one
##   shift+click: move between hotbar and main          click outside the panel: drop the held stack

signal slot_clicked(slot: int, button: int, shift: bool)

const Inventory = preload("res://engine/shared/inventory.gd")
const ItemVisuals = preload("res://engine/client/item_visuals.gd")
const SLOT_SIZE := 52

var inventory: Inventory
var items  # ItemRegistry
var atlas := {}

var _slots: Array[Panel] = []
var _panel: PanelContainer
var _cursor_icon: TextureRect
var _cursor_count: Label
var _title: Label
var _equipment_box: VBoxContainer
var _tooltip: PanelContainer
var _tooltip_label: Label
var _hovered := -2


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.add_theme_stylebox_override("panel", _box_style(Color(0.08, 0.08, 0.1, 0.92), 12))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	_title = Label.new()
	_title.text = "Inventory"
	box.add_child(_title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	box.add_child(columns)
	_equipment_box = VBoxContainer.new()
	columns.add_child(_equipment_box)
	var backpack := VBoxContainer.new()
	columns.add_child(backpack)
	var main := GridContainer.new()
	main.columns = Inventory.HOTBAR
	backpack.add_child(main)
	backpack.add_child(HSeparator.new())
	var hotbar := GridContainer.new()
	hotbar.columns = Inventory.HOTBAR
	backpack.add_child(hotbar)
	_slots.resize(Inventory.SIZE)
	for i in Inventory.SIZE:
		var slot := _make_slot(i)
		_slots[i] = slot
		(hotbar if i < Inventory.HOTBAR else main).add_child(slot)
	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip.add_theme_stylebox_override("panel", _box_style(Color(0.05, 0.03, 0.1, 0.95), 8))
	_tooltip_label = Label.new()
	_tooltip.add_child(_tooltip_label)
	var hint := Label.new()
	hint.text = "Left: move stack   Right: split / place one   Shift: quick move   Outside: drop"
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	_cursor_icon = TextureRect.new()
	_cursor_icon.custom_minimum_size = Vector2(36, 36)
	_cursor_icon.size = Vector2(36, 36)
	_cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cursor_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cursor_icon)
	_cursor_count = Label.new()
	_cursor_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_count.add_theme_color_override("font_shadow_color", Color.BLACK)
	_cursor_icon.add_child(_cursor_count)
	_cursor_count.position = Vector2(22, 20)
	add_child(_tooltip)


## Builds one slot per equipment slot the server defined (called once content is known).
func build_equipment(slot_defs: Array) -> void:
	for child in _equipment_box.get_children():
		child.queue_free()
	_slots.resize(Inventory.SIZE + slot_defs.size())
	for i in slot_defs.size():
		var row := HBoxContainer.new()
		var slot := _make_slot(Inventory.SIZE + i)
		_slots[Inventory.SIZE + i] = slot
		row.add_child(slot)
		var label := Label.new()
		label.text = String(slot_defs[i].get("display_name", slot_defs[i].get("name", "")))
		label.modulate = Color(1, 1, 1, 0.55)
		label.add_theme_font_size_override("font_size", 12)
		row.add_child(label)
		_equipment_box.add_child(row)


static func _box_style(color: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.45, 0.35, 0.7, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(margin)
	return style


func _make_slot(index: int) -> Panel:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.85)
	style.set_border_width_all(2)
	style.border_color = Color(0.35, 0.35, 0.4)
	slot.add_theme_stylebox_override("panel", style)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)
	var count := Label.new()
	count.name = "Count"
	count.add_theme_color_override("font_shadow_color", Color.BLACK)
	count.add_theme_constant_override("shadow_offset_x", 1)
	count.add_theme_constant_override("shadow_offset_y", 1)
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 3)
	count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(count)
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			var button := 1 if event.button_index == MOUSE_BUTTON_LEFT else (2 if event.button_index == MOUSE_BUTTON_RIGHT else 3)
			slot_clicked.emit(index, button, event.shift_pressed)
			accept_event())
	slot.mouse_entered.connect(func(): _hovered = index)
	slot.mouse_exited.connect(func():
		if _hovered == index:
			_hovered = -2)
	return slot


func _gui_input(event: InputEvent) -> void:
	# Clicks that reach the background (outside the panel) drop the held stack.
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] \
			and not _panel.get_global_rect().has_point(event.global_position):
		slot_clicked.emit(-1, 1 if event.button_index == MOUSE_BUTTON_LEFT else 2, false)
		accept_event()


func refresh() -> void:
	if inventory == null or atlas.is_empty() or _slots.is_empty():
		return
	for i in mini(_slots.size(), inventory.total()):
		if _slots[i] == null:
			continue
		_draw_stack(_slots[i].get_node("Icon"), _slots[i].get_node("Count"), inventory.ids[i], inventory.counts[i])
		ItemVisuals.update_wear_bar(_slots[i], items, inventory.ids[i] if inventory.counts[i] > 0 else 0, inventory.data[i])
		var style: StyleBoxFlat = _slots[i].get_theme_stylebox("panel")
		style.border_color = Color(0.9, 0.9, 0.9) if i == inventory.selected else Color(0.35, 0.35, 0.4)
	_draw_stack(_cursor_icon, _cursor_count, inventory.cursor_id, inventory.cursor_count)


func _draw_stack(icon: TextureRect, count: Label, id: int, amount: int) -> void:
	var has_item: bool = items.is_valid(id) and (amount > 0 or inventory.creative)
	if has_item:
		var tex := AtlasTexture.new()
		tex.atlas = atlas.texture
		tex.region = atlas.pixels.get(items.icon_of(id), atlas.pixels[""])
		icon.texture = tex
	else:
		icon.texture = null
	count.text = str(amount) if has_item and amount > 1 else ""


func _process(_delta: float) -> void:
	if not visible:
		return
	var mouse := get_local_mouse_position()
	_cursor_icon.position = mouse - Vector2(18, 18)
	var id := inventory.ids[_hovered] if _hovered >= 0 and _hovered < inventory.total() and inventory.counts[_hovered] > 0 else 0
	_tooltip.visible = id > 0 and inventory.cursor_count <= 0
	if _tooltip.visible:
		_tooltip_label.text = "\n".join(ItemVisuals.tooltip_lines(items, id, inventory.data[_hovered]))
		_tooltip.position = mouse + Vector2(18, 12)
		_tooltip.reset_size()
