extends Control
## Every block and item there is, for a creative player to take from (B).
##
## A creative game ships no recipes, so the recipe book - which is how a player finds out what exists
## - is empty in exactly the game where that question matters most. This is the other half of it.
##
## The server decides what is in here, because the client cannot know which items a mod meant to be
## takeable, and it hands over a stack when asked rather than the client granting itself one.
##
## Deliberately plain: a search box, groups, and a grid. A builder opens this a hundred times an hour
## and wants the block, not an experience. (2026-09-22)

## item id, and whether the whole stack was asked for.
signal take_requested(item: int, whole_stack: bool)

var _search: LineEdit
var _grid: GridContainer
var _groups := {}
var _items
var _atlas


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 560)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = -280
	panel.offset_bottom = 280
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := Label.new()
	title.text = "Everything"
	column.add_child(title)

	_search = LineEdit.new()
	_search.placeholder_text = "Search"
	_search.text_changed.connect(func(_t): _rebuild())
	column.add_child(_search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 12
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	var hint := Label.new()
	hint.text = "Click for one, right-click for a full stack. B or Esc to close."
	column.add_child(hint)
	visible = false


## Called when the server sends the catalogue.
func show_palette(groups: Dictionary, items, atlas) -> void:
	_groups = groups
	_items = items
	_atlas = atlas
	visible = true
	_search.grab_focus()
	_rebuild()


func _rebuild() -> void:
	if _items == null:
		return
	for child in _grid.get_children():
		# Out of the tree first: queue_free runs at the end of the frame, so a rebuild twice in one
		# frame would free the new children too (CLAUDE.md).
		_grid.remove_child(child)
		child.queue_free()
	var needle := _search.text.strip_edges().to_lower()
	var group_names: Array = _groups.keys()
	group_names.sort()
	for group: String in group_names:
		for id: int in _groups[group]:
			if not _items.is_valid(id):
				continue
			var label := String(_items.display_name(id))
			if not needle.is_empty() and not label.to_lower().contains(needle) \
					and not String(_items.name_of(id)).to_lower().contains(needle):
				continue
			_grid.add_child(_slot(id, label))


func _slot(id: int, label: String) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(56, 56)
	button.tooltip_text = label
	# The same atlas lookup the inventory screen uses: an item's icon is a region of the block atlas.
	if _atlas != null and _atlas.has("texture"):
		var tex := AtlasTexture.new()
		tex.atlas = _atlas.texture
		tex.region = _atlas.pixels.get(_items.icon_of(id), _atlas.pixels.get("", Rect2()))
		button.icon = tex
		button.expand_icon = true
	else:
		button.text = label.left(3)
	button.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				take_requested.emit(id, false)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				take_requested.emit(id, true))
	return button
