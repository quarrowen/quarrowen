extends Control
## The crafting screen (C, or right-click a station): a searchable recipe book with category tabs and
## a "craftable" filter on the left, the selected recipe on the right with what you have and still
## need, how it compares to what you hold or wear, and Craft / Craft all / Pin buttons.
## "How to make" and "Used in" lookups filter the book to one item (from here or the inventory: R / U).
## The server owns crafting; this screen only asks it to craft and redraws what comes back.

signal craft_requested(index: int, times: int)
signal pin_requested(index: int)
signal closed

const Inventory = preload("res://engine/shared/inventory.gd")
const ItemVisuals = preload("res://engine/client/item_visuals.gd")
const RecipeRegistry = preload("res://engine/shared/recipe_registry.gd")
const COLUMNS := 7
const CELL := 58

var items  # ItemRegistry
var recipes: RecipeRegistry
var inventory: Inventory
var atlas := {}
## {name ("" = by hand), title, position}
var station := {}
## Items the station can draw from nearby chests: {item id: count}.
var stock := {}
## Smelting and other processes for lookups: {kind: {input id: {output, count, seconds}}}.
var processes := {}
var pinned := -1
var selected := -1

var _panel: PanelContainer
var _title: Label
var _search: LineEdit
var _tabs: HFlowContainer
var _craftable_only: Button
var _lookup_bar: HBoxContainer
var _lookup_label: Label
var _grid: GridContainer
var _empty_label: Label
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_info: Label
var _stats: RichTextLabel
var _ingredients: VBoxContainer
var _craft_button: Button
var _craft_all_button: Button
var _pin_button: Button
var _category := ""
var _lookup := {}  # {item, mode: "make" | "use"}
var _cells := {}  # recipe index -> Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.add_theme_stylebox_override("panel", _box(Color(0.07, 0.07, 0.09, 0.95), 14))
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(func(): closed.emit())
	header.add_child(close)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	# Recipe book.
	var book := VBoxContainer.new()
	book.custom_minimum_size = Vector2(COLUMNS * (CELL + 4), 460)
	book.add_theme_constant_override("separation", 6)
	body.add_child(book)
	var search_row := HBoxContainer.new()
	book.add_child(search_row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search recipes..."
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _rebuild_grid())
	search_row.add_child(_search)
	_craftable_only = Button.new()
	_craftable_only.toggle_mode = true
	_craftable_only.text = "Craftable only"
	_craftable_only.toggled.connect(func(_on): _rebuild_grid())
	search_row.add_child(_craftable_only)
	_tabs = HFlowContainer.new()
	book.add_child(_tabs)
	_lookup_bar = HBoxContainer.new()
	_lookup_bar.visible = false
	book.add_child(_lookup_bar)
	_lookup_label = Label.new()
	_lookup_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	_lookup_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lookup_bar.add_child(_lookup_label)
	var clear_lookup := Button.new()
	clear_lookup.text = "Show all"
	clear_lookup.pressed.connect(func(): show_lookup(0, ""))
	_lookup_bar.add_child(clear_lookup)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	book.add_child(scroll)
	var grid_box := VBoxContainer.new()
	grid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_box)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	grid_box.add_child(_grid)
	_empty_label = Label.new()
	_empty_label.modulate = Color(1, 1, 1, 0.5)
	grid_box.add_child(_empty_label)

	# Details.
	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(340, 0)
	detail.add_theme_constant_override("separation", 8)
	body.add_child(detail)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	detail.add_child(top)
	var icon_frame := PanelContainer.new()
	icon_frame.add_theme_stylebox_override("panel", _box(Color(0.12, 0.12, 0.15), 6))
	top.add_child(icon_frame)
	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(84, 84)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_detail_icon.pivot_offset = Vector2(42, 42)
	icon_frame.add_child(_detail_icon)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 20)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_detail_name)
	_detail_info = Label.new()
	_detail_info.modulate = Color(1, 1, 1, 0.65)
	_detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_detail_info)
	_stats = RichTextLabel.new()
	_stats.bbcode_enabled = true
	_stats.fit_content = true
	_stats.scroll_active = false
	_stats.custom_minimum_size = Vector2(320, 0)
	detail.add_child(_stats)
	var ingredients_title := Label.new()
	ingredients_title.text = "Ingredients"
	ingredients_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	detail.add_child(ingredients_title)
	_ingredients = VBoxContainer.new()
	_ingredients.add_theme_constant_override("separation", 4)
	_ingredients.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(_ingredients)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	detail.add_child(buttons)
	_craft_button = _action_button("Craft", func(): craft_requested.emit(selected, 1))
	buttons.add_child(_craft_button)
	_craft_all_button = _action_button("Craft all", func(): craft_requested.emit(selected, craftable_times(selected)))
	buttons.add_child(_craft_all_button)
	_pin_button = _action_button("Pin", func(): pin_requested.emit(selected))
	buttons.add_child(_pin_button)
	var hint := Label.new()
	hint.text = "Click an ingredient to see how it is made.  Shift+click a recipe: craft all.  R / U over items: recipe / uses."
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.add_theme_font_size_override("font_size", 12)
	root.add_child(hint)


## Opens (or refreshes) the book for a station and its stock.
func open(station_info: Dictionary, station_stock: Dictionary) -> void:
	station = station_info
	stock = station_stock
	_title.text = String(station.get("title", "Crafting"))
	_rebuild_tabs()
	_rebuild_grid()
	if selected < 0 or not _cells.has(selected):
		_select(_first_visible())


## Filters the book to recipes making (`mode` "make") or using ("use") an item; item 0 clears.
func show_lookup(item: int, mode: String) -> void:
	_lookup = {} if item <= 0 else {"item": item, "mode": mode}
	_category = ""
	_rebuild_tabs()
	_rebuild_grid()
	_select(_first_visible())


func refresh() -> void:
	if not visible or recipes == null:
		return
	for index: int in _cells:
		_style_cell(_cells[index], index)
	_show_details()


## How many times a recipe could be crafted now (999 in creative).
func craftable_times(index: int) -> int:
	if index < 0 or index >= recipes.recipes.size():
		return 0
	var r: Dictionary = recipes.recipes[index]
	if not at_station(r):
		return 0
	if inventory.creative:
		return 64
	var times := 999
	for id: int in r.inputs:
		times = mini(times, have(id) / int(r.inputs[id]))
	return times


## Whether you hold every ingredient (ignoring where the recipe must be crafted).
func have_all(index: int) -> bool:
	var r: Dictionary = recipes.recipes[index]
	return r.inputs.keys().all(func(id): return have(id) >= int(r.inputs[id]))


func have(item: int) -> int:
	return inventory.count_of(item) + int(stock.get(item, 0))


func at_station(r: Dictionary) -> bool:
	return r.station.is_empty() or inventory.creative or r.station == station.get("name", "")


## Short text for a station name ("crafting_table" -> "Crafting Table").
static func station_title(station_name: String) -> String:
	return station_name.get_slice(":", station_name.count(":")).capitalize()


func _rebuild_tabs() -> void:
	for child in _tabs.get_children():
		child.queue_free()
	var present := {}
	for r in recipes.recipes:
		present[r.category] = true
	var tabs := [["", "All"]]
	for c in recipes.categories:
		if present.has(c.name):
			tabs.append([c.name, c.display_name])
	for t in tabs:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_pressed = t[0] == _category
		b.pressed.connect(func():
			_category = t[0]
			_rebuild_tabs()
			_rebuild_grid())
		_tabs.add_child(b)
	_lookup_bar.visible = not _lookup.is_empty()
	if not _lookup.is_empty():
		_lookup_label.text = ("How to make: %s" if _lookup.mode == "make" else "Used in: %s") % items.display_name(_lookup.item)


func _visible_recipes() -> Array:
	var query := _search.text.strip_edges().to_lower()
	var out := []
	for i in recipes.recipes.size():
		var r: Dictionary = recipes.recipes[i]
		if not _lookup.is_empty() and ((_lookup.mode == "make" and r.output != _lookup.item) or (_lookup.mode == "use" and not r.inputs.has(_lookup.item))):
			continue
		if not _category.is_empty() and r.category != _category:
			continue
		if not query.is_empty() and not items.display_name(r.output).to_lower().contains(query):
			continue
		if _craftable_only.button_pressed and craftable_times(i) <= 0:
			continue
		out.append(i)
	# Craftable first, then recipes for this station, then by name.
	out.sort_custom(func(a, b):
		var ka := [craftable_times(a) <= 0, not at_station(recipes.recipes[a]), items.display_name(recipes.recipes[a].output)]
		var kb := [craftable_times(b) <= 0, not at_station(recipes.recipes[b]), items.display_name(recipes.recipes[b].output)]
		return ka < kb)
	return out


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	_cells.clear()
	var shown := _visible_recipes()
	for index in shown:
		var cell := _make_cell(index)
		_grid.add_child(cell)
		_cells[index] = cell
	_empty_label.visible = shown.is_empty()
	_empty_label.text = "No recipes match." if recipes.recipes.size() > 0 else "This server has no recipes."
	if not _lookup.is_empty() and _lookup.mode == "make" and shown.is_empty():
		_empty_label.text = _process_note(_lookup.item) if not _process_note(_lookup.item).is_empty() else "Nothing here makes %s." % items.display_name(_lookup.item)
	refresh()


func _make_cell(index: int) -> Button:
	var r: Dictionary = recipes.recipes[index]
	var cell := Button.new()
	cell.custom_minimum_size = Vector2(CELL, CELL)
	cell.tooltip_text = items.display_name(r.output)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = _icon(r.output)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 9)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	if r.count > 1:
		var count := Label.new()
		count.text = str(r.count)
		count.add_theme_color_override("font_shadow_color", Color.BLACK)
		count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 3)
		count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count.grow_vertical = Control.GROW_DIRECTION_BEGIN
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(count)
	cell.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if event.shift_pressed:
				craft_requested.emit(index, craftable_times(index))
			elif event.double_click:
				craft_requested.emit(index, 1)
			_select(index)
			accept_event())
	return cell


func _style_cell(cell: Button, index: int) -> void:
	var r: Dictionary = recipes.recipes[index]
	var craftable := craftable_times(index) > 0
	var style := _box(Color(0.14, 0.15, 0.13) if craftable else Color(0.1, 0.1, 0.12), 0)
	style.border_color = Color(1.0, 0.8, 0.35) if index == selected else (Color(0.4, 0.62, 0.35) if craftable else Color(0.28, 0.28, 0.32))
	style.set_border_width_all(2)
	for state in ["normal", "hover", "pressed", "focus"]:
		cell.add_theme_stylebox_override(state, style)
	var icon: TextureRect = cell.get_node("Icon")
	icon.modulate = Color.WHITE if craftable else (Color(0.55, 0.55, 0.55) if at_station(r) else Color(0.35, 0.35, 0.38))


func _select(index: int) -> void:
	selected = index
	for i: int in _cells:
		_style_cell(_cells[i], i)
	_show_details()
	if index >= 0:
		var tween := _detail_icon.create_tween()
		_detail_icon.scale = Vector2(0.85, 0.85)
		tween.tween_property(_detail_icon, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _first_visible() -> int:
	var shown := _visible_recipes()
	return shown[0] if not shown.is_empty() else -1


func _show_details() -> void:
	for child in _ingredients.get_children():
		child.queue_free()
	var has := selected >= 0 and selected < recipes.recipes.size()
	_craft_button.disabled = true
	_craft_all_button.disabled = true
	_pin_button.disabled = not has
	if not has:
		_detail_icon.texture = null
		_detail_name.text = "Pick a recipe"
		_detail_info.text = ""
		_stats.text = ""
		return
	var r: Dictionary = recipes.recipes[selected]
	_detail_icon.texture = _icon(r.output)
	_detail_name.text = ("%d x %s" % [r.count, items.display_name(r.output)]) if r.count > 1 else items.display_name(r.output)
	var where := "Crafted anywhere" if r.station.is_empty() else "Needs a %s" % station_title(r.station)
	if not at_station(r):
		where += " (not here)"
	_detail_info.text = "%s  ·  %s" % [_category_name(r.category), where]
	_stats.text = "\n".join(stat_preview(r.output))
	for id: int in r.inputs:
		_ingredients.add_child(_ingredient_row(id, int(r.inputs[id])))
	var times := craftable_times(selected)
	_craft_button.disabled = times <= 0
	_craft_all_button.disabled = times <= 1
	_craft_all_button.text = "Craft all (%d)" % times if times > 1 and not inventory.creative else "Craft all"
	_pin_button.text = "Unpin" if pinned == selected else "Pin"


func _ingredient_row(id: int, need: int) -> Control:
	var row := Button.new()
	row.flat = true
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.tooltip_text = "How is %s made?" % items.display_name(id)
	row.custom_minimum_size = Vector2(0, 30)
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	row.add_child(box)
	var icon := TextureRect.new()
	icon.texture = _icon(id)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var label := Label.new()
	label.text = items.display_name(id)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	var got := have(id)
	var amount := Label.new()
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if inventory.creative:
		amount.text = "x%d" % need
	else:
		amount.text = "%d / %d" % [mini(got, 9999), need]
		if int(stock.get(id, 0)) > 0:
			amount.text += "  (+%d nearby)" % stock[id]
	amount.add_theme_color_override("font_color", Color(0.55, 0.9, 0.5) if got >= need or inventory.creative else Color(1.0, 0.45, 0.4))
	box.add_child(amount)
	row.pressed.connect(show_lookup.bind(id, "make"))
	return row


## BBCode lines describing an item and how it compares to what you hold (tools, weapons) or wear (armor).
func stat_preview(item: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var def: Dictionary = items.get_def(item)
	if def.is_empty():
		return lines
	var slot := String(def.get("equip_slot", ""))
	var current := 0
	if not slot.is_empty():
		var index := inventory.equipment_index(slot)
		current = inventory.ids[index] if index >= 0 else 0
	else:
		current = inventory.selected_item()
	var cur: Dictionary = items.get_def(current) if current != item else {}
	var weapon: Dictionary = def.get("weapon", {})
	if not weapon.is_empty():
		lines.append(_compare("Damage", float(weapon.damage), float(cur.get("weapon", {}).get("damage", 1.0 if cur.is_empty() or current < items.FIRST_ITEM else 0.0)), cur))
	var tool: Dictionary = def.get("tool", {})
	if not tool.is_empty():
		lines.append(_compare("Mining speed", float(tool.speed), float(cur.get("tool", {}).get("speed", 1.0)), cur))
		lines.append(_compare("Tier", float(tool.tier), float(cur.get("tool", {}).get("tier", 0)), cur))
	var armor: Dictionary = def.get("armor", {})
	if not armor.is_empty():
		lines.append(_compare("Armor", float(armor.armor), float(cur.get("armor", {}).get("armor", 0.0)), cur))
	if int(def.get("durability", 0)) > 0:
		lines.append(_compare("Durability", float(def.durability), float(cur.get("durability", 0)), cur))
	for line in def.get("lore", []):
		lines.append("[color=#a8a0c0][i]%s[/i][/color]" % String(line))
	return lines


func _compare(label: String, value: float, other: float, current: Dictionary) -> String:
	var text := "%s  [b]%s[/b]" % [label, _num(value)]
	if current.is_empty():
		return text
	var delta := value - other
	if absf(delta) < 0.001:
		return text + "  [color=#9a9a9a](same as %s)[/color]" % current.get("display_name", "")
	var color := "#7fdc6a" if delta > 0 else "#ff7a6a"
	return text + "  [color=%s]%s%s[/color] [color=#9a9a9a]vs %s[/color]" % [color, "+" if delta > 0 else "", _num(delta), current.get("display_name", "")]


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


func _process_note(item: int) -> String:
	for kind in processes:
		for input in processes[kind]:
			var p: Dictionary = processes[kind][input]
			if int(p.output) == item:
				return "Made by %s %s (%s s)." % [String(kind), items.display_name(int(input)), _num(float(p.seconds))]
	return ""


func _category_name(category: String) -> String:
	for c in recipes.categories:
		if c.name == category:
			return c.display_name
	return category.capitalize()


func _icon(item: int) -> Texture2D:
	if atlas.is_empty() or not items.is_valid(item):
		return null
	var tex := AtlasTexture.new()
	tex.atlas = atlas.texture
	tex.region = atlas.pixels.get(items.icon_of(item), atlas.pixels[""])
	return tex


func _action_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 40)
	b.pressed.connect(func():
		if selected >= 0:
			action.call())
	return b


static func _box(color: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.45, 0.35, 0.7, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(margin)
	return style


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		closed.emit()
		get_viewport().set_input_as_handled()
