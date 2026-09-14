extends Control
## The inventory screen (E): 27 main slots above the 9 hotbar slots. Clicks go to the server, which
## owns the inventory and the stack held by the cursor; the screen just redraws what it sends back.
##   left click: pick up / put down / merge / swap     right click: pick up half / put down one
##   shift+click: move between hotbar and main          click outside the panel: drop the held stack

signal slot_clicked(slot: int, button: int, shift: bool)
## R / U over an item: show how it is made or what it is used for.
signal lookup_requested(item: int, mode: String)

const Inventory = preload("res://engine/shared/inventory.gd")
const ItemVisuals = preload("res://engine/client/item_visuals.gd")
const SLOT_SIZE := 52
## Container slots are clicked as CONTAINER_BASE + index (see Containers on the server).
const CONTAINER_BASE := 1000

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
## The open container ({} when none): {title, size, groups, bars, slots, data, progress}.
var container := {}
var _container_box: VBoxContainer
var _container_slots: Array[Panel] = []
var _bars := {}  # bar name -> ProgressBar


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
	_container_box = VBoxContainer.new()
	_container_box.add_theme_constant_override("separation", 6)
	_container_box.visible = false
	box.add_child(_container_box)
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
	hint.text = "Left: move stack   Right: split / place one   Shift: quick move   Outside: drop   R / U: recipe / uses"
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


## Shows a container above the inventory (or hides it with {}).
func set_container(view: Dictionary) -> void:
	container = view
	for child in _container_box.get_children():
		child.queue_free()
	_container_slots.clear()
	_bars.clear()
	_container_box.visible = not view.is_empty()
	if view.is_empty():
		return
	var title := Label.new()
	title.text = String(view.get("title", "Container"))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	_container_box.add_child(title)
	_container_slots.resize(int(view.get("size", 0)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_container_box.add_child(row)
	for g in view.get("groups", []):
		var column := VBoxContainer.new()
		if not String(g.label).is_empty():
			var label := Label.new()
			label.text = g.label
			label.modulate = Color(1, 1, 1, 0.6)
			label.add_theme_font_size_override("font_size", 12)
			column.add_child(label)
		var grid := GridContainer.new()
		grid.columns = int(g.columns)
		column.add_child(grid)
		for i in range(int(g.start), int(g.start) + int(g.count)):
			if i >= _container_slots.size():
				break
			var slot := _make_slot(CONTAINER_BASE + i)
			if g.take_only:
				(slot.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color(0.16, 0.13, 0.08, 0.9)
			_container_slots[i] = slot
			grid.add_child(slot)
		row.add_child(column)
	if not view.get("bars", []).is_empty():
		var bars := VBoxContainer.new()
		bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bars)
		for b in view.bars:
			var label := Label.new()
			label.text = String(b.label)
			label.modulate = Color(1, 1, 1, 0.6)
			label.add_theme_font_size_override("font_size", 12)
			bars.add_child(label)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(120, 12)
			bar.max_value = 1.0
			bar.step = 0.001
			bar.show_percentage = false
			var fill := StyleBoxFlat.new()
			fill.bg_color = Color.html(String(b.color)) if Color.html_is_valid(String(b.color)) else Color.WHITE
			bar.add_theme_stylebox_override("fill", fill)
			var track := StyleBoxFlat.new()
			track.bg_color = Color(0.2, 0.2, 0.24)
			bar.add_theme_stylebox_override("background", track)
			bars.add_child(bar)
			_bars[b.name] = bar
	_container_box.add_child(HSeparator.new())
	refresh()


## Applies {slots, data, progress} for the open container.
func update_container(view: Dictionary) -> void:
	if container.is_empty():
		return
	container.merge(view, true)
	refresh()


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
	if not container.is_empty():
		var packed: PackedInt32Array = container.get("slots", PackedInt32Array())
		var n := _container_slots.size()
		for i in n:
			if _container_slots[i] == null or packed.size() < n * 2:
				continue
			var id := packed[i] if items.is_valid(packed[i]) else 0
			_draw_stack(_container_slots[i].get_node("Icon"), _container_slots[i].get_node("Count"), id, packed[n + i], true)
			ItemVisuals.update_wear_bar(_container_slots[i], items, id, _container_data(i))
		for bar_name in _bars:
			_bars[bar_name].value = float(container.get("progress", {}).get(bar_name, 0.0))


func _container_data(i: int) -> Dictionary:
	var value = container.get("data", {}).get(i, {})
	return value if value is Dictionary and var_to_bytes(value).size() <= Inventory.MAX_DATA_BYTES else {}


func _draw_stack(icon: TextureRect, count: Label, id: int, amount: int, exact := false) -> void:
	var has_item: bool = items.is_valid(id) and id > 0 and (amount > 0 or (inventory.creative and not exact))
	if has_item:
		var tex := AtlasTexture.new()
		tex.atlas = atlas.texture
		tex.region = atlas.pixels.get(items.icon_of(id), atlas.pixels[""])
		icon.texture = tex
	else:
		icon.texture = null
	count.text = str(amount) if has_item and amount > 1 else ""


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode != KEY_R and event.physical_keycode != KEY_U:
		return
	var item := 0
	if _hovered >= 0 and _hovered < inventory.total() and inventory.counts[_hovered] > 0:
		item = inventory.ids[_hovered]
	var packed: PackedInt32Array = container.get("slots", PackedInt32Array())
	var c := _hovered - CONTAINER_BASE
	if c >= 0 and c < _container_slots.size() and packed.size() >= _container_slots.size() * 2 and packed[_container_slots.size() + c] > 0:
		item = packed[c]
	if item > 0:
		lookup_requested.emit(item, "make" if event.physical_keycode == KEY_R else "use")
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	var mouse := get_local_mouse_position()
	_cursor_icon.position = mouse - Vector2(18, 18)
	var id := inventory.ids[_hovered] if _hovered >= 0 and _hovered < inventory.total() and inventory.counts[_hovered] > 0 else 0
	var hovered_data: Dictionary = inventory.data[_hovered] if id > 0 else {}
	var packed: PackedInt32Array = container.get("slots", PackedInt32Array())
	var c := _hovered - CONTAINER_BASE
	if c >= 0 and c < _container_slots.size() and packed.size() >= _container_slots.size() * 2 and packed[_container_slots.size() + c] > 0:
		id = packed[c] if items.is_valid(packed[c]) else 0
		hovered_data = _container_data(c)
	_tooltip.visible = id > 0 and inventory.cursor_count <= 0
	if _tooltip.visible:
		_tooltip_label.text = "\n".join(ItemVisuals.tooltip_lines(items, id, hovered_data))
		_tooltip.position = mouse + Vector2(18, 12)
		_tooltip.reset_size()
