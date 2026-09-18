extends Control
## The crafting screen (C, or right-click a station): a searchable recipe book with category tabs and
## a "craftable" filter on the left, the selected recipe on the right with what you have and still
## need, how it compares to what you hold or wear, and Craft / Craft all / Pin buttons.
## "How to make" and "Used in" lookups filter the book to one item (from here or the inventory: R / U).
## The server owns crafting; this screen only asks it to craft and redraws what comes back.

signal craft_requested(index: int, times: int)
signal pin_requested(index: int)
## Station panel buttons: "upgrade" or "guide".
signal station_action(action: String)
## Co-op actions: "view" | "deposit" | "take" | "start_project" | "contribute" | "cancel_project".
signal coop_action(action: String, arg: int)
## Assemble: an assembly name and a backpack slot per assembly slot.
signal assemble_requested(assembly_name: String, slots: PackedInt32Array)
## Crafting by hand: product {recipe: index} or {assembly, slots}, relaxed timing, wait for a partner.
signal skill_requested(product: Dictionary, assist: bool, with_partner: bool)
## Join a team minigame waiting at this station.
signal minigame_join_requested(game_id: int)
## The experimentation grid's "Try": 9 item ids row by row (0 = empty).
signal experiment_requested(grid: PackedInt32Array)
signal closed

const Inventory = preload("res://engine/shared/inventory.gd")
const ClientSettings = preload("res://engine/client/settings/client_settings.gd")
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
## Every station's titles, tiers and upgrades (from the server) to explain recipe requirements.
var stations := {}
## ItemIcons (composed icons for parts and built tools); set by the client.
var icons
## The shared state at this station: {players, tray, jobs, project, owner, speedup}.
var session := {}
## Recipe ids this player has discovered, and whether the server uses discovery at all.
var known := {}
var discovery := false
var pinned := -1
var selected := -1

var _panel: PanelContainer
var _title: Label
var _search: LineEdit
var _tabs: HFlowContainer
var _craftable_only: Button
var _journal: Label
var _undiscovered: Button
var _lookup_bar: HBoxContainer
var _lookup_label: Label
var _grid: GridContainer
var _empty_label: Label
var _detail: VBoxContainer
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_info: Label
var _stats: RichTextLabel
var _ingredients: VBoxContainer
var _craft_button: Button
var _craft_all_button: Button
var _pin_button: Button
## Crafting minigames by name (from the server) and the player's relaxed-timing choice.
var minigames := {}
var relaxed := false
var player_name := ""
var _skill_row: HBoxContainer
var _skill_button: Button
var _skill_partner: Button
const Assembly = preload("res://engine/shared/assembly.gd")
## Materials, parts and tools built from parts (shared definitions from the server).
var assembly := Assembly.new()
var _forge: VBoxContainer
var _mode_forge: Button
var _forge_assembly := ""
var _forge_choice := {}  # slot name -> backpack slot
var _book: VBoxContainer
var _lab: VBoxContainer
var _mode_book: Button
var _mode_lab: Button
var _grid_items := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
var _grid_buttons: Array[Button] = []
var _palette: GridContainer
var _palette_item := 0
var _lab_result_icon: TextureRect
var _lab_hint: Label
var _lab_craft: Button
var _lab_recipe := -1
var _station_panel: VBoxContainer
var _coop_panel: VBoxContainer
var _side_scroll: ScrollContainer
var _coop_key := ""
var _job_bars: Array[ProgressBar] = []
var _project_bar: ProgressBar
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
	for mode in [["Recipe book", false], ["Experiment", true]]:
		var tab := Button.new()
		tab.text = mode[0]
		tab.toggle_mode = true
		tab.button_pressed = not mode[1]
		tab.pressed.connect(set_lab_mode.bind(mode[1]))
		header.add_child(tab)
		if mode[1]:
			_mode_lab = tab
		else:
			_mode_book = tab
	_mode_forge = Button.new()
	_mode_forge.text = "Assemble"
	_mode_forge.toggle_mode = true
	_mode_forge.visible = false
	_mode_forge.pressed.connect(set_forge_mode)
	header.add_child(_mode_forge)
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
	_book = book
	book.custom_minimum_size = Vector2(COLUMNS * (CELL + 4), 460)
	book.add_theme_constant_override("separation", 6)
	body.add_child(book)
	_build_lab(body)
	_forge = VBoxContainer.new()
	_forge.custom_minimum_size = _book.custom_minimum_size
	_forge.add_theme_constant_override("separation", 8)
	_forge.visible = false
	body.add_child(_forge)
	body.move_child(_forge, 2)
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
	var journal_row := HBoxContainer.new()
	book.add_child(journal_row)
	_journal = Label.new()
	_journal.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_journal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal_row.add_child(_journal)
	_undiscovered = Button.new()
	_undiscovered.toggle_mode = true
	_undiscovered.text = "Show undiscovered"
	_undiscovered.button_pressed = true
	_undiscovered.toggled.connect(func(_on): _rebuild_grid())
	journal_row.add_child(_undiscovered)
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
	_detail = detail
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
	_craft_button = _action_button("Craft", func():
		var r: Dictionary = recipes.recipes[selected]
		if r.get("project", false):
			coop_action.emit("contribute" if not session.get("project", {}).is_empty() else "start_project", selected)
		else:
			craft_requested.emit(selected, 1))
	buttons.add_child(_craft_button)
	_craft_all_button = _action_button("Craft all", func(): craft_requested.emit(selected, craftable_times(selected)))
	buttons.add_child(_craft_all_button)
	_pin_button = _action_button("Pin", func(): pin_requested.emit(selected))
	buttons.add_child(_pin_button)
	_skill_row = HBoxContainer.new()
	_skill_row.add_theme_constant_override("separation", 8)
	detail.add_child(_skill_row)
	_skill_button = _action_button("Craft by hand", func(): skill_requested.emit({"recipe": selected}, relaxed, false))
	_skill_row.add_child(_skill_button)
	_skill_partner = _action_button("With a partner", func(): skill_requested.emit({"recipe": selected}, relaxed, true))
	_skill_row.add_child(_skill_partner)
	_skill_row.add_child(_relaxed_toggle())
	var side_scroll := ScrollContainer.new()
	_side_scroll = side_scroll
	side_scroll.custom_minimum_size = Vector2(290, 460)
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	side_scroll.add_child(side)
	_station_panel = VBoxContainer.new()
	_station_panel.custom_minimum_size = Vector2(270, 0)
	_station_panel.add_theme_constant_override("separation", 6)
	side.add_child(_station_panel)
	_coop_panel = VBoxContainer.new()
	_coop_panel.add_theme_constant_override("separation", 6)
	side.add_child(_coop_panel)
	side_scroll.visible = false

	var hint := Label.new()
	hint.text = "Click an ingredient to see how it is made.  Shift+click a recipe: craft all.  R / U over items: recipe / uses."
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.add_theme_font_size_override("font_size", 12)
	root.add_child(hint)


## The experimentation grid: pick an item from your inventory below, click cells to place it (right-click
## clears a cell), then Try. Nothing is used up by experimenting.
func _build_lab(body: HBoxContainer) -> void:
	_lab = VBoxContainer.new()
	_lab.custom_minimum_size = _book.custom_minimum_size
	_lab.add_theme_constant_override("separation", 8)
	_lab.visible = false
	body.add_child(_lab)
	body.move_child(_lab, 1)
	_lab.add_child(_small("Arrange items you hold and try them. Nothing is used up. Some recipes care how things are arranged.", Color(1, 1, 1, 0.6)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_lab.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	row.add_child(grid)
	for i in 9:
		var cell := _slot_button(0, 0)
		cell.custom_minimum_size = Vector2(CELL, CELL)
		cell.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed:
				if event.button_index == MOUSE_BUTTON_RIGHT or _palette_item <= 0:
					_grid_items[i] = 0
				elif _placed(_palette_item) < _held(_palette_item) or _grid_items[i] == _palette_item:
					_grid_items[i] = _palette_item if _grid_items[i] != _palette_item else 0
				_redraw_lab()
				accept_event())
		grid.add_child(cell)
		_grid_buttons.append(cell)
	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_font_size_override("font_size", 36)
	row.add_child(arrow)
	var result_frame := PanelContainer.new()
	result_frame.add_theme_stylebox_override("panel", _box(Color(0.12, 0.12, 0.15), 6))
	row.add_child(result_frame)
	_lab_result_icon = TextureRect.new()
	_lab_result_icon.custom_minimum_size = Vector2(72, 72)
	_lab_result_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lab_result_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_lab_result_icon.pivot_offset = Vector2(36, 36)
	result_frame.add_child(_lab_result_icon)
	_lab_hint = Label.new()
	_lab_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lab_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lab_hint.custom_minimum_size = Vector2(380, 44)
	_lab_hint.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
	_lab.add_child(_lab_hint)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	_lab.add_child(buttons)
	var try := Button.new()
	try.text = "Try"
	try.custom_minimum_size = Vector2(110, 40)
	try.pressed.connect(func(): experiment_requested.emit(_grid_items))
	buttons.add_child(try)
	var clear := Button.new()
	clear.text = "Clear"
	clear.custom_minimum_size = Vector2(90, 40)
	clear.pressed.connect(func():
		_grid_items = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
		_lab_recipe = -1
		_lab_hint.text = ""
		_redraw_lab())
	buttons.add_child(clear)
	_lab_craft = Button.new()
	_lab_craft.text = "Craft it"
	_lab_craft.custom_minimum_size = Vector2(110, 40)
	_lab_craft.pressed.connect(func():
		if _lab_recipe >= 0:
			craft_requested.emit(_lab_recipe, 1))
	buttons.add_child(_lab_craft)
	_lab.add_child(_section("Your items"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_lab.add_child(scroll)
	_palette = GridContainer.new()
	_palette.columns = COLUMNS
	scroll.add_child(_palette)


func set_lab_mode(lab: bool) -> void:
	_lab.visible = lab
	_book.visible = not lab
	_forge.visible = false
	_detail.visible = true
	_mode_forge.button_pressed = false
	_mode_lab.button_pressed = lab
	_mode_book.button_pressed = not lab
	if lab:
		_redraw_lab()


## Assemblies this station builds (all of them in creative).
func _station_assemblies() -> Array:
	return assembly.assemblies.values().filter(func(a): return inventory.creative or (not a.station.is_empty() and a.station == station.get("name", "")))


func set_forge_mode() -> void:
	_forge.visible = true
	_detail.visible = false  # the preview replaces the recipe details
	_lab.visible = false
	_book.visible = false
	_mode_forge.button_pressed = true
	_mode_lab.button_pressed = false
	_mode_book.button_pressed = false
	if _forge_assembly.is_empty() or not assembly.assemblies.has(_forge_assembly):
		var list := _station_assemblies()
		_forge_assembly = list[0].name if not list.is_empty() else ""
		for a in list:  # start on something the player holds every part for
			if a.slots.all(func(s): return inventory.count_of(int(assembly.part_types[s.part].item)) > 0):
				_forge_assembly = a.name
				break
	_rebuild_forge()


## Pick what to build, then a part for each slot from your backpack; the preview shows the result.
func _rebuild_forge() -> void:
	for child in _forge.get_children():
		_forge.remove_child(child)
		child.queue_free()
	if not _forge.visible:
		return
	_forge.add_child(_small("Build a tool from parts made at this station. Each material changes its stats and adds a trait.", Color(1, 1, 1, 0.6)))
	var kinds := HFlowContainer.new()
	_forge.add_child(kinds)
	for a in _station_assemblies():
		var b := Button.new()
		b.text = a.display_name
		b.toggle_mode = true
		b.button_pressed = a.name == _forge_assembly
		b.pressed.connect(func():
			_forge_assembly = a.name
			_forge_choice.clear()
			_rebuild_forge())
		kinds.add_child(b)
	var a: Dictionary = assembly.assemblies.get(_forge_assembly, {})
	if a.is_empty():
		_forge.add_child(_small("This station does not build tools from parts.", Color(1, 1, 1, 0.5)))
		return
	var chosen := {}
	var slots := PackedInt32Array()
	for s in a.slots:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_forge.add_child(row)
		var label := Label.new()
		label.text = s.label
		label.custom_minimum_size = Vector2(80, 0)
		row.add_child(label)
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(300, 0)
		var options := []  # backpack slots holding this kind of part
		var part_item: int = int(assembly.part_types[s.part].item)
		for i in inventory.SIZE:
			if inventory.ids[i] == part_item and inventory.counts[i] > 0 and assembly.materials.has(str(inventory.data[i].get("material", ""))):
				options.append(i)
				picker.add_icon_item(_icon(part_item, inventory.data[i]), "%s  x%d" % [inventory.data[i].get("name", ""), inventory.counts[i]])
		if options.is_empty():
			picker.add_item("No %s in your backpack" % assembly.part_types[s.part].display_name)
			picker.disabled = true
		else:
			var pick: int = options.find(int(_forge_choice.get(s.name, options[0])))
			pick = maxi(pick, 0)
			picker.select(pick)
			_forge_choice[s.name] = options[pick]
			chosen[s.name] = str(inventory.data[options[pick]].material)
			slots.append(options[pick])
			picker.item_selected.connect(func(index):
				_forge_choice[s.name] = options[index]
				_rebuild_forge())
		row.add_child(picker)
		var how := Button.new()
		how.text = "?"
		how.tooltip_text = "How to make %s" % assembly.part_types[s.part].display_name
		how.pressed.connect(func():
			set_lab_mode(false)
			show_lookup(part_item, "make"))
		row.add_child(how)
	var result := assembly.build(_forge_assembly, chosen) if chosen.size() == a.slots.size() else {}
	var preview := HBoxContainer.new()
	preview.add_theme_constant_override("separation", 12)
	_forge.add_child(preview)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _box(Color(0.12, 0.12, 0.15), 6))
	preview.add_child(frame)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(84, 84)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _icon(int(a.item), result) if not result.is_empty() else null
	frame.add_child(icon)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size = Vector2(330, 0)
	if result.is_empty():
		text.text = "[color=#9a9a9a]Choose a part for every slot.[/color]"
	else:
		text.text = "\n".join(ItemVisuals.tooltip_lines(items, int(a.item), result))
	preview.add_child(text)
	var build := Button.new()
	build.text = "Assemble %s" % a.display_name
	build.custom_minimum_size = Vector2(200, 40)
	build.disabled = result.is_empty()
	build.pressed.connect(func(): assemble_requested.emit(_forge_assembly, slots))
	var build_row := HBoxContainer.new()
	build_row.add_theme_constant_override("separation", 8)
	build_row.add_child(build)
	_forge.add_child(build_row)
	var by_hand := HBoxContainer.new()
	by_hand.add_theme_constant_override("separation", 8)
	for with_partner in [false, true]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 40)
		b.pressed.connect(func(): skill_requested.emit({"assembly": _forge_assembly, "slots": Array(slots)}, relaxed, with_partner))
		by_hand.add_child(b)
	by_hand.add_child(_relaxed_toggle())
	_forge.add_child(by_hand)
	_update_skill_row(by_hand, str(a.get("skill", "")), not result.is_empty())
	(by_hand.get_child(1) as Button).text = "With a partner"


## Shows what an experiment did: the discovered or known result, or a hint.
func set_experiment_result(result: Dictionary) -> void:
	_lab_hint.text = String(result.get("hint", ""))
	_lab_recipe = int(result.get("recipe", -1)) if String(result.get("status", "")) in ["discovered", "known"] else -1
	var color: Color = {"discovered": Color(1.0, 0.85, 0.4), "known": Color(0.6, 0.9, 0.6), "close": Color(0.75, 0.8, 1.0),
		"blueprint": Color(0.7, 0.8, 1.0)}.get(String(result.get("status", "")), Color(1, 1, 1, 0.6))
	_lab_hint.add_theme_color_override("font_color", color)
	if _lab_recipe >= 0:
		_select(_lab_recipe)  # show the discovered or known recipe beside the grid
	_redraw_lab()
	if String(result.get("status", "")) == "discovered":
		var tween := _lab_result_icon.create_tween()
		_lab_result_icon.scale = Vector2(0.4, 0.4)
		tween.tween_property(_lab_result_icon, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _held(item: int) -> int:
	return 99 if inventory.creative else inventory.count_of(item)


func _placed(item: int) -> int:
	return Array(_grid_items).count(item)


func _redraw_lab() -> void:
	if _lab == null or not _lab.visible:
		return
	for i in 9:
		var id := _grid_items[i]
		if id > 0 and _placed(id) > _held(id):
			_grid_items[i] = 0  # used up or dropped since it was placed
			id = 0
		var icon: TextureRect = _grid_buttons[i].get_child(0)
		icon.texture = _icon(id) if id > 0 else null
	var r: Dictionary = recipes.recipes[_lab_recipe] if _lab_recipe >= 0 and _lab_recipe < recipes.recipes.size() else {}
	_lab_result_icon.texture = _icon(r.output) if not r.is_empty() else null
	_lab_craft.disabled = r.is_empty() or craftable_times(_lab_recipe) <= 0
	# Taken out of the tree before being freed. queue_free() alone happens at the end of the frame, so a
	# second redraw in the same frame - a stock update arriving as you switch tabs - saw the old children
	# still there *and* the new ones, and freed the lot: your items simply vanished until the screen was
	# reopened. Every rebuild in the client's UI was written this way. (playtest, 2026-09-18)
	for child in _palette.get_children():
		_palette.remove_child(child)
		child.queue_free()
	var seen := {}
	for i in inventory.SIZE:
		var id := inventory.ids[i]
		if id <= 0 or inventory.counts[i] <= 0 or seen.has(id):
			continue
		seen[id] = true
		var left := _held(id) - _placed(id)
		var b := _slot_button(id, left if not inventory.creative else 0)
		b.tooltip_text = items.display_name(id)
		if id == _palette_item:
			var style := _box(Color(0.25, 0.22, 0.1), 0)
			style.border_color = Color(1.0, 0.8, 0.35)
			style.set_border_width_all(2)
			for state in ["normal", "hover", "pressed"]:
				b.add_theme_stylebox_override(state, style)
		b.pressed.connect(func():
			_palette_item = id
			_redraw_lab())
		_palette.add_child(b)


## Opens (or refreshes) the book for a station and its stock.
func open(station_info: Dictionary, station_stock: Dictionary) -> void:
	station = station_info
	stock = station_stock
	if not station.has("position"):
		set_session({})
	_title.text = String(station.get("tier_title", station.get("title", "Crafting")))
	_rebuild_station_panel()
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
	_redraw_lab()
	_mode_forge.visible = not _station_assemblies().is_empty()
	if _forge.visible and not _mode_forge.visible:
		set_lab_mode(false)  # moved to a station without assemblies
	elif _forge.visible:
		_rebuild_forge()
	if not session.is_empty():
		set_session(session)
	for index: int in _cells:
		_style_cell(_cells[index], index)
	_show_details()


## How many times a recipe could be crafted now (999 in creative).
func craftable_times(index: int) -> int:
	if index < 0 or index >= recipes.recipes.size():
		return 0
	var r: Dictionary = recipes.recipes[index]
	if not at_station(r) or not is_known(r):
		return 0
	if inventory.creative:
		return 64
	var times := 999
	for id: int in r.inputs:
		times = mini(times, have(id) / int(r.inputs[id]))
	return times


func is_known(r: Dictionary) -> bool:
	return not discovery or inventory.creative or known.has(r.id) or r.get("unlock", "pickup") == "known"


## How much an undiscovered recipe reveals: 0 nothing, 1 one ingredient, 2 all ingredients, 3 the
## result too. Bookshelves (station hints) reveal more.
func _reveal(r: Dictionary) -> int:
	return 99 if is_known(r) else clampi(int(station.get("hints", 0)), 0, 3)


## Whether you hold every ingredient (ignoring where the recipe must be crafted).
func have_all(index: int) -> bool:
	var r: Dictionary = recipes.recipes[index]
	return r.inputs.keys().all(func(id): return have(id) >= int(r.inputs[id]))


func have(item: int) -> int:
	return inventory.count_of(item) + int(stock.get(item, 0))


func at_station(r: Dictionary) -> bool:
	if r.station.is_empty() or inventory.creative:
		return true
	if r.station != station.get("name", "") or not station.get("structure", {}).get("formed", true):
		return false
	return int(station.get("tier", 1)) >= int(r.get("tier", 0)) and r.get("needs", []).all(func(f): return station.get("features", []).has(f))


## What a recipe needs, in words: "Needs a Sturdy Workbench with Metalwork (an Anvil nearby)".
func requirement_text(r: Dictionary) -> String:
	if r.station.is_empty():
		return "Crafted anywhere"
	var s: Dictionary = stations.get(r.station, {})
	var where := String(s.get("title", station_title(r.station)))
	var tiers: Array = s.get("tiers", [])
	if int(r.get("tier", 0)) > 1 and int(r.tier) <= tiers.size() and not String(tiers[int(r.tier) - 1].title).is_empty():
		where = String(tiers[int(r.tier) - 1].title)
	elif int(r.get("tier", 0)) > 1:
		where += " (tier %d)" % int(r.tier)
	var text := "Needs a %s" % where
	var needs := PackedStringArray()
	for feature in r.get("needs", []):
		var source := ""
		for u in s.get("upgrades", []):
			if String(u.grants).to_lower().contains(String(feature).to_lower()):
				source = u.title
				break
		needs.append("%s%s" % [String(feature).capitalize(), " (%s nearby)" % source if not source.is_empty() else ""])
	if not needs.is_empty():
		text += " with " + ", ".join(needs)
	if not String(s.get("structure", "")).is_empty():
		text += " (build the structure)"
	return text


## The station's tier, workshop upgrades found and still possible, the next tier and structure status.
func _rebuild_station_panel() -> void:
	for child in _station_panel.get_children():
		_station_panel.remove_child(child)
		child.queue_free()
	_station_panel.visible = station.has("position")
	_side_scroll.visible = _station_panel.visible
	if not _station_panel.visible:
		return
	_station_panel.add_child(_section("Workshop"))
	var summary := PackedStringArray(["Tier %d" % int(station.get("tier", 1))])
	if float(station.get("speed", 0.0)) > 0.0:
		summary.append("+%d%% speed" % roundi(float(station.speed) * 100))
	if float(station.get("quality", 0.0)) > 0.0:
		summary.append("+%d%% quality" % roundi(float(station.quality) * 100))
	summary.append("chests within %d" % int(station.get("pull_radius", 4)))
	_station_panel.add_child(_small(" · ".join(summary), Color(1, 1, 1, 0.7)))
	if not station.get("features", []).is_empty():
		_station_panel.add_child(_small("Unlocks: " + ", ".join(PackedStringArray(station.features.map(func(f): return String(f).capitalize()))), Color(0.6, 0.85, 1.0)))
	for u in station.get("detected", []):
		_station_panel.add_child(_upgrade_row(u, true))
	for u in station.get("available", []):
		_station_panel.add_child(_upgrade_row(u, false))
	var structure: Dictionary = station.get("structure", {})
	if not structure.is_empty():
		_station_panel.add_child(_section(String(structure.title)))
		if structure.formed:
			_station_panel.add_child(_small("✓ Structure complete", Color(0.55, 0.9, 0.5)))
		else:
			_station_panel.add_child(_small("%d blocks missing or in the way" % int(structure.missing), Color(1.0, 0.55, 0.45)))
			var guide := Button.new()
			guide.text = "Show build guide"
			guide.pressed.connect(func(): station_action.emit("guide"))
			_station_panel.add_child(guide)
	var next: Dictionary = station.get("next", {})
	if not next.is_empty():
		_station_panel.add_child(_section("Next tier: %s" % next.title))
		if not String(next.grants).is_empty():
			_station_panel.add_child(_small(String(next.grants), Color(1, 1, 1, 0.7)))
		var kit := int(next.get("kit", 0))
		var owned := inventory.count_of(kit) if kit > 0 else 1
		var row := HBoxContainer.new()
		if kit > 0:
			var icon := TextureRect.new()
			icon.texture = _icon(kit)
			icon.custom_minimum_size = Vector2(24, 24)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			row.add_child(icon)
			row.add_child(_small("%s  %d / 1" % [items.display_name(kit), owned], Color(0.55, 0.9, 0.5) if owned > 0 else Color(1.0, 0.55, 0.45)))
		_station_panel.add_child(row)
		var upgrade := Button.new()
		upgrade.text = "Upgrade"
		upgrade.disabled = owned <= 0 and not inventory.creative
		upgrade.pressed.connect(func(): station_action.emit("upgrade"))
		_station_panel.add_child(upgrade)
		if kit > 0:
			var how := Button.new()
			how.text = "How to make the kit"
			how.flat = true
			how.pressed.connect(show_lookup.bind(kit, "make"))
			_station_panel.add_child(how)


## Applies a station session update; rebuilds the co-op panel only when more than progress changed.
func set_session(view: Dictionary) -> void:
	session = view
	var shape := view.duplicate(true)
	for job in shape.get("jobs", []):
		job.erase("fraction")
	if shape.get("project") is Dictionary:
		shape.project.erase("fraction")
	shape.erase("speedup")
	var key := str(shape) + str(inventory.ids.slice(0, Inventory.HOTBAR)) + str(inventory.counts.slice(0, Inventory.HOTBAR))
	if key != _coop_key:
		_coop_key = key
		_rebuild_coop_panel()
	else:
		for i in mini(_job_bars.size(), view.get("jobs", []).size()):
			_job_bars[i].value = float(view.jobs[i].fraction)
		if _project_bar != null and not view.get("project", {}).is_empty():
			_project_bar.value = float(view.project.fraction)
	if visible:
		_show_details()


func _rebuild_coop_panel() -> void:
	for child in _coop_panel.get_children():
		_coop_panel.remove_child(child)
		child.queue_free()
	_job_bars.clear()
	_project_bar = null
	if session.is_empty():
		return
	var players: Array = session.get("players", [])
	_coop_panel.add_child(_section("At this station (%d)" % players.size()))
	for entry in players:
		var looking := ""
		if int(entry.recipe) >= 0 and int(entry.recipe) < recipes.recipes.size():
			var seen: Dictionary = recipes.recipes[int(entry.recipe)]
			looking = "  → %s" % (items.display_name(seen.output) if _reveal(seen) >= 3 else "an undiscovered recipe")
		_coop_panel.add_child(_small("● %s%s" % [entry.name, looking], Color(0.75, 0.9, 1.0)))
	if players.size() > 1:
		_coop_panel.add_child(_small("Timed crafts go %s× faster together" % _num(float(session.get("speedup", 1.0))), Color(0.55, 0.9, 0.5)))
	for invite in session.get("invites", []):
		if str(invite.get("by_name", "")) == player_name:
			continue
		var join := Button.new()
		join.text = "Help %s: %s (bellows)" % [invite.by_name, str(invite.title).to_lower()]
		join.pressed.connect(func(): minigame_join_requested.emit(int(invite.id)))
		_coop_panel.add_child(join)

	_coop_panel.add_child(_section("Shared tray"))
	var owner := String(session.get("owner", ""))
	_coop_panel.add_child(_small(("Owner: %s. " % owner if not owner.is_empty() else "") + "Click to take back; crafting here uses tray items you may take.", Color(1, 1, 1, 0.55)))
	var tray := GridContainer.new()
	tray.columns = 5
	_coop_panel.add_child(tray)
	var tray_items: Array = session.get("tray", [])
	for i in 9:
		var entry: Dictionary = tray_items[i] if i < tray_items.size() else {}
		var b := _slot_button(int(entry.get("item", 0)), int(entry.get("count", 0)))
		if not entry.is_empty():
			b.tooltip_text = "%s x%d from %s" % [items.display_name(int(entry.item)), int(entry.count), entry.by_name]
			b.pressed.connect(func(): coop_action.emit("take", i))
		tray.add_child(b)
	_coop_panel.add_child(_small("Your hotbar (click to put in the tray):", Color(1, 1, 1, 0.55)))
	var hotbar := GridContainer.new()
	hotbar.columns = 5
	_coop_panel.add_child(hotbar)
	for i in Inventory.HOTBAR:
		var b := _slot_button(inventory.ids[i] if inventory.counts[i] > 0 else 0, inventory.counts[i])
		if inventory.counts[i] > 0:
			b.pressed.connect(func(): coop_action.emit("deposit", i))
		hotbar.add_child(b)

	var jobs: Array = session.get("jobs", [])
	if not jobs.is_empty():
		_coop_panel.add_child(_section("Queue"))
		for job in jobs:
			var r_index := int(job.recipe)
			if r_index < 0 or r_index >= recipes.recipes.size():
				continue
			var r: Dictionary = recipes.recipes[r_index]
			_coop_panel.add_child(_small("%d x %s  (%s)" % [int(r.count) * int(job.times), items.display_name(r.output), job.by_name], Color.WHITE))
			_job_bars.append(_bar(float(job.fraction), Color(0.95, 0.85, 0.4)))
			_coop_panel.add_child(_job_bars[-1])

	var project: Dictionary = session.get("project", {})
	if not project.is_empty() and int(project.recipe) >= 0:
		var r: Dictionary = recipes.recipes[int(project.recipe)]
		_coop_panel.add_child(_section("Project: %s" % items.display_name(r.output)))
		_project_bar = _bar(float(project.fraction), Color(0.5, 0.8, 1.0))
		_coop_panel.add_child(_project_bar)
		for id: int in r.inputs:
			var got := int(project.delivered.get(id, 0))
			_coop_panel.add_child(_small("%s  %d / %d" % [items.display_name(id), got, int(r.inputs[id])],
				Color(0.55, 0.9, 0.5) if got >= int(r.inputs[id]) else Color(1, 1, 1, 0.8)))
		var names := PackedStringArray()
		for c in project.contributors:
			names.append("%s (%d)" % [c.name, int(c.items)])
		if not names.is_empty():
			_coop_panel.add_child(_small("Contributors: " + ", ".join(names), Color(1.0, 0.85, 0.55)))
		var buttons := HBoxContainer.new()
		var give := Button.new()
		give.text = "Contribute"
		give.pressed.connect(func(): coop_action.emit("contribute", 0))
		buttons.add_child(give)
		var open := Button.new()
		open.text = "View recipe"
		open.pressed.connect(_select.bind(int(project.recipe)))
		buttons.add_child(open)
		var cancel := Button.new()
		cancel.text = "Cancel"
		cancel.tooltip_text = "Owner only: delivered items go to the tray"
		cancel.pressed.connect(func(): coop_action.emit("cancel_project", 0))
		buttons.add_child(cancel)
		_coop_panel.add_child(buttons)


func _slot_button(item: int, count: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(44, 44)
	var icon := TextureRect.new()
	icon.texture = _icon(item) if item > 0 else null
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	if count > 1:
		var label := Label.new()
		label.text = str(count)
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 2)
		label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(label)
	return b


func _bar(value: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(250, 12)
	bar.max_value = 1.0
	bar.step = 0.001
	bar.value = value
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.2, 0.2, 0.24)
	bar.add_theme_stylebox_override("background", track)
	return bar


func _upgrade_row(u: Dictionary, found: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.texture = _icon(int(u.block))
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.modulate = Color.WHITE if found else Color(1, 1, 1, 0.4)
	row.add_child(icon)
	var text := "%s %s%s" % ["✓" if found else "○", u.title, " x%d" % int(u.count) if int(u.get("max", 1)) > 1 and found else ""]
	var label := _small("%s\n%s" % [text, u.grants], Color(0.85, 0.95, 0.8) if found else Color(1, 1, 1, 0.5))
	label.tooltip_text = "" if found else "Place a %s near the station" % u.title
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	return row


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	return l


func _small(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(250, 0)
	return l


## Short text for a station name ("crafting_table" -> "Crafting Table").
static func station_title(station_name: String) -> String:
	return station_name.get_slice(":", station_name.count(":")).capitalize()


func _rebuild_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
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
		if r.get("removed", false):
			continue
		if not _lookup.is_empty() and ((_lookup.mode == "make" and r.output != _lookup.item) or (_lookup.mode == "use" and not r.inputs.has(_lookup.item))):
			continue
		if not _category.is_empty() and r.category != _category:
			continue
		if not is_known(r) and (r.get("unlock", "") == "secret" or not _undiscovered.button_pressed):
			continue
		# Searching by name finds things you have not discovered yet: the silhouette and its "how to find
		# this" is exactly what someone typing "anvil" is looking for. Only secrets stay hidden (above).
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
		_grid.remove_child(child)
		child.queue_free()
	_cells.clear()
	var shown := _visible_recipes()
	for index in shown:
		var cell := _make_cell(index)
		_grid.add_child(cell)
		_cells[index] = cell
	var total := 0
	var found := 0
	for r in recipes.recipes:
		if r.get("unlock", "") != "secret" or known.has(r.id):
			total += 1
			if is_known(r):
				found += 1
	_journal.text = "Discovered %d / %d recipes" % [found, total] if discovery and not inventory.creative else "%d recipes" % total
	_undiscovered.visible = discovery and not inventory.creative
	_empty_label.visible = shown.is_empty()
	_empty_label.text = "No recipes match." if recipes.recipes.size() > 0 else "This server has no recipes."
	if not _lookup.is_empty() and _lookup.mode == "make" and shown.is_empty():
		_empty_label.text = _process_note(_lookup.item) if not _process_note(_lookup.item).is_empty() else "Nothing here makes %s." % items.display_name(_lookup.item)
	refresh()


func _make_cell(index: int) -> Button:
	var r: Dictionary = recipes.recipes[index]
	var cell := Button.new()
	cell.custom_minimum_size = Vector2(CELL, CELL)
	cell.tooltip_text = items.display_name(r.output) if _reveal(r) >= 3 else "Undiscovered recipe"
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = _icon(r.output, r.get("output_data", {}))
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
	if _reveal(r) < 3:
		icon.modulate = Color(0.0, 0.0, 0.0, 0.75)  # a silhouette until discovered


func _select(index: int) -> void:
	if index != selected and station.has("position"):
		coop_action.emit("view", index)
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


## A checkbox for relaxed minigame timing (slower marker, bigger zones), remembered between sessions.
func _relaxed_toggle() -> CheckBox:
	var box := CheckBox.new()
	box.text = "Relaxed timing"
	box.tooltip_text = "Slower markers, bigger zones and longer windows. Every result is still at least Standard."
	box.button_pressed = relaxed
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(func(on):
		relaxed = on
		ClientSettings.shared().set_value("crafting/relaxed_timing", on))
	return box


func load_settings() -> void:
	relaxed = ClientSettings.shared().get_value("crafting/relaxed_timing")


## Shows the "by hand" buttons for something with a minigame.
func _update_skill_row(row: HBoxContainer, skill_name: String, can_make: bool) -> void:
	var def: Dictionary = minigames.get(skill_name, {})
	row.visible = not def.is_empty()
	if def.is_empty():
		return
	var main: Button = row.get_child(0)
	var partner: Button = row.get_child(1)
	main.text = str(def.get("title", "Craft by hand"))
	main.disabled = not can_make
	main.tooltip_text = "A short minigame for Fine, Superior or Masterwork quality (never worse than crafting normally)."
	partner.visible = bool(def.get("team", false)) and station.has("position") and session.get("players", []).size() >= 2
	partner.disabled = not can_make
	(row.get_child(2) as CheckBox).set_pressed_no_signal(relaxed)


func _show_details() -> void:
	for child in _ingredients.get_children():
		_ingredients.remove_child(child)
		child.queue_free()
	var has := selected >= 0 and selected < recipes.recipes.size()
	_skill_row.visible = false
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
	if not is_known(r):
		_show_undiscovered(r)
		return
	_detail_icon.modulate = Color.WHITE
	_detail_icon.texture = _icon(r.output, r.get("output_data", {}))
	_detail_name.text = ("%d x %s" % [r.count, items.display_name(r.output)]) if r.count > 1 else items.display_name(r.output)
	var where := requirement_text(r)
	if not at_station(r) and not r.station.is_empty():
		where += " (not here)"
	_detail_info.text = "%s  ·  %s" % [_category_name(r.category), where]
	_stats.text = "\n".join(stat_preview(r.output))
	for id: int in r.inputs:
		_ingredients.add_child(_ingredient_row(id, int(r.inputs[id])))
	var times := craftable_times(selected)
	_update_skill_row(_skill_row, str(r.get("skill", "")), times > 0 and not r.get("project", false))
	_craft_button.disabled = times <= 0
	_craft_all_button.disabled = times <= 1
	_craft_all_button.text = "Craft all (%d)" % times if times > 1 and not inventory.creative else "Craft all"
	_craft_all_button.visible = true
	_craft_button.text = "Craft"
	if float(r.get("time", 0.0)) > 0.0 and not inventory.creative:
		var speed := float(session.get("speedup", 1.0))
		_craft_button.text = "Queue (%s s)" % _num(float(r.time) / maxf(speed, 0.01))
	if r.get("project", false):
		var project: Dictionary = session.get("project", {})
		_craft_all_button.visible = false
		if project.is_empty():
			_craft_button.text = "Start project"
			_craft_button.disabled = not at_station(r) or not station.has("position")
		elif int(project.recipe) == selected:
			_craft_button.text = "Contribute"
			_craft_button.disabled = not r.inputs.keys().any(func(id): return inventory.count_of(id) > 0)
		else:
			_craft_button.text = "Another project is underway"
			_craft_button.disabled = true
	_pin_button.text = "Unpin" if pinned == selected else "Pin"


## Details of a recipe you have not discovered: how to discover it, plus what bookshelves reveal.
func _show_undiscovered(r: Dictionary) -> void:
	var reveal := _reveal(r)
	_detail_icon.texture = _icon(r.output, r.get("output_data", {}))
	_detail_icon.modulate = Color.WHITE if reveal >= 3 else Color(0, 0, 0, 0.8)
	_detail_name.text = items.display_name(r.output) if reveal >= 3 else "Undiscovered recipe"
	var how: String = {"pickup": "Discovered by picking up one of its ingredients.", "blueprint": "Learned from a blueprint.",
		"experiment": "Discovered by experimenting at a crafting grid.", "secret": "A secret."}.get(r.get("unlock", "pickup"), "")
	_detail_info.text = "%s  ·  %s" % [_category_name(r.category), requirement_text(r)]
	var lines := PackedStringArray([how])
	if not String(r.get("hint", "")).is_empty():
		lines.append("[color=#c8b8ff][i]%s[/i][/color]" % r.hint)
	if reveal == 0:
		lines.append("[color=#9a9a9a]Bookshelves around a station reveal more about undiscovered recipes.[/color]")
	_stats.text = "\n".join(lines)
	var ingredient_ids: Array = r.inputs.keys()
	for i in ingredient_ids.size():
		if reveal >= 2 or (reveal == 1 and i == 0):
			_ingredients.add_child(_ingredient_row(ingredient_ids[i], int(r.inputs[ingredient_ids[i]])))
		else:
			_ingredients.add_child(_small("??? ingredient", Color(1, 1, 1, 0.45)))
	_pin_button.disabled = true
	_craft_button.text = "Craft"
	_craft_button.disabled = true
	_craft_all_button.text = "Craft all"
	_craft_all_button.disabled = true
	_craft_all_button.visible = true


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


func _icon(item: int, item_data := {}) -> Texture2D:
	if atlas.is_empty() or not items.is_valid(item):
		return null
	if icons != null:
		return icons.texture(item, item_data)
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
