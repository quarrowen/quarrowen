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

## How many slots fit across. Fixed rather than measured: a grid that reflows as the window changes
## moves a block out from under a builder's cursor, and they open this a hundred times an hour.
##
## **Sixteen, to match a colour set.** The palette is colour-led (see mods/base/colours.gd), so a set
## of sixteen hues reads as one row in the order they were declared - a ramp you can scan - instead of
## wrapping into fourteen and two. (2026-09-23)
const COLUMNS := 16

var _search: LineEdit
var _drawers: VBoxContainer
var _empty: Label
var _groups := {}
var _items
var _atlas


func _ready() -> void:
	# **Anchors *and* offsets.** `set_anchors_preset` alone moves the anchors and leaves the offsets
	# where they were, so the root kept a stale rect and every child anchored inside nothing. Every
	# other screen here uses the and_offsets form; this one did not, and nobody saw it because the
	# palette had nothing in it to draw. (2026-09-23)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	# **Inset from the edges rather than a fixed 760x560.** A fixed size is a size that is wrong on
	# every screen but one, and this holds 185 entries in base alone.
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80
	panel.offset_right = -80
	panel.offset_top = 56
	panel.offset_bottom = -56
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
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	# A column of drawers rather than one grid: each `group` a mod named gets a heading and its own
	# rows, which is the whole reason the key exists.
	_drawers = VBoxContainer.new()
	_drawers.add_theme_constant_override("separation", 10)
	_drawers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_drawers)

	_empty = Label.new()
	_empty.visible = false
	column.add_child(_empty)

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
	for child in _drawers.get_children():
		# Out of the tree first: queue_free runs at the end of the frame, so a rebuild twice in one
		# frame would free the new children too (CLAUDE.md).
		_drawers.remove_child(child)
		child.queue_free()
	var needle := _search.text.strip_edges().to_lower()
	var group_names: Array = _groups.keys()
	group_names.sort()
	# Only say which mod a drawer belongs to when more than one is installed. On a single-mod game
	# "base · Stone" on every heading is noise; with three mods it is the thing you need.
	var mods := {}
	for group: String in group_names:
		mods[group.get_slice("/", 0)] = true
	var shown := 0
	for group: String in group_names:
		var grid := GridContainer.new()
		grid.columns = COLUMNS
		var found := 0
		for id: int in _groups[group]:
			if not _items.is_valid(id):
				continue
			var label := String(_items.display_name(id))
			if not needle.is_empty() and not label.to_lower().contains(needle) \
					and not String(_items.name_of(id)).to_lower().contains(needle):
				continue
			grid.add_child(_slot(id, label))
			found += 1
		if found == 0:
			grid.queue_free()  # never entered the tree; nothing to take out of it first
			continue
		var heading := Label.new()
		heading.text = group.get_slice("/", 1) if mods.size() < 2 else "%s  ·  %s" % [group.get_slice("/", 1), group.get_slice("/", 0)]
		heading.add_theme_font_size_override("font_size", 13)
		_drawers.add_child(heading)
		_drawers.add_child(grid)
		shown += found
	# A search that matches nothing looks exactly like a palette that is broken - which this one was,
	# for a day, and nobody could tell. Say which it is. (2026-09-23)
	_empty.visible = shown == 0
	_empty.text = "Nothing matches \"%s\"." % _search.text.strip_edges() if not needle.is_empty() \
		else "This game has nothing to take."


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
