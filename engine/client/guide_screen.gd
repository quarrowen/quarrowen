extends Control
## The guidebook (G key or a guide item): chapters and pages from mods drawn as an illustrated book.
## Contents on the left (with search; locked pages show "???" and what reveals them), the open page
## on the right on paper, with back/forward history and previous/next page buttons.

signal closed
## The page on show (the server marks it read and remembers it).
signal page_viewed(page_id: String)
## An item in the book was clicked: open the recipe book on it ("make" or "use").
signal lookup_requested(item: int, mode: String)

const GuideRegistry = preload("res://engine/shared/guide_registry.gd")
const EntityView = preload("res://engine/client/entity_view.gd")

const PAPER := Color(0.93, 0.88, 0.76)
const INK := Color(0.22, 0.16, 0.1)
const INK_SOFT := Color(0.42, 0.33, 0.24)
const ACCENT := Color(0.55, 0.25, 0.12)
const COVER := Color(0.32, 0.18, 0.1, 0.97)
const MAX_RECIPE_CARDS := 2

var registry := GuideRegistry.new()
var items  # ItemRegistry
var recipes  # RecipeRegistry
var entity_types  # EntityRegistry
## The crafting screen: icons, recipe knowledge and station requirement text.
var crafting
## Builds a Node3D model of an entity type by name (null if it has no model).
var make_entity_view: Callable
## Texture of an asset by name (image blocks).
var texture_of: Callable
var unlocked := {}
var read := {}
var current := ""

var _contents: VBoxContainer
var _search: LineEdit
var _page_scroll: ScrollContainer
var _page: VBoxContainer
var _title: Label
var _crumb: Label
var _back: Button
var _forward: Button
var _prev: Button
var _next: Button
var _history: Array[String] = []
var _future: Array[String] = []
var _collapsed := {}
var _portraits: Array[Node3D] = []
var _cover: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var cover := PanelContainer.new()
	cover.set_anchors_preset(Control.PRESET_CENTER)
	cover.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cover.grow_vertical = Control.GROW_DIRECTION_BOTH
	_cover = cover
	_fit()
	get_viewport().size_changed.connect(_fit)
	cover.add_theme_stylebox_override("panel", _style(COVER, 12, Color(0.6, 0.42, 0.2), 3, 10))
	add_child(cover)
	var spread := HBoxContainer.new()
	spread.add_theme_constant_override("separation", 10)
	cover.add_child(spread)

	# Left page: contents.
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(290, 0)
	left.add_theme_stylebox_override("panel", _style(PAPER.darkened(0.06), 12, PAPER.darkened(0.3), 1, 6))
	spread.add_child(left)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 8)
	left.add_child(left_box)
	var book_title := Label.new()
	book_title.text = "Guidebook"
	book_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	book_title.add_theme_font_size_override("font_size", 24)
	book_title.add_theme_color_override("font_color", ACCENT)
	left_box.add_child(book_title)
	_search = LineEdit.new()
	_search.placeholder_text = "Search the guide..."
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _rebuild_contents())
	left_box.add_child(_search)
	var contents_scroll := ScrollContainer.new()
	contents_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_box.add_child(contents_scroll)
	_contents = VBoxContainer.new()
	_contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_contents.add_theme_constant_override("separation", 2)
	contents_scroll.add_child(_contents)

	# Right page: the open page.
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_stylebox_override("panel", _style(PAPER, 12, PAPER.darkened(0.3), 1, 6))
	spread.add_child(right)
	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 6)
	right.add_child(right_box)
	var header := HBoxContainer.new()
	right_box.add_child(header)
	_back = _nav_button("◀", "Back", _go_back)
	header.add_child(_back)
	_forward = _nav_button("▶", "Forward", _go_forward)
	header.add_child(_forward)
	_crumb = Label.new()
	_crumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crumb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crumb.add_theme_color_override("font_color", INK_SOFT)
	header.add_child(_crumb)
	header.add_child(_nav_button("✕", "Close (Esc)", func(): closed.emit()))
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", INK)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right_box.add_child(_title)
	var rule := ColorRect.new()
	rule.color = ACCENT
	rule.custom_minimum_size = Vector2(0, 2)
	right_box.add_child(rule)
	_page_scroll = ScrollContainer.new()
	_page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_box.add_child(_page_scroll)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 10)
	_page_scroll.add_child(_page)
	var footer := HBoxContainer.new()
	right_box.add_child(footer)
	_prev = _nav_button("◀ Previous", "Previous page", func(): _step(-1))
	footer.add_child(_prev)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_next = _nav_button("Next ▶", "Next page", func(): _step(1))
	footer.add_child(_next)


## Takes more of large screens, never less than 960 x 620.
func _fit() -> void:
	var view := get_viewport_rect().size
	_cover.custom_minimum_size = Vector2(clampf(view.x * 0.55, 960.0, 1500.0), clampf(view.y * 0.62, 620.0, 950.0))


func _process(delta: float) -> void:
	for p in _portraits:
		if is_instance_valid(p):
			p.rotation.y += delta * 0.8


## Opens the book at a page ("" = the current page, or the first unlocked one).
func open(page_id := "") -> void:
	visible = true
	_rebuild_contents()
	if page_id.is_empty():
		page_id = current
	if registry.get_page(page_id).is_empty():
		page_id = _first_page()
	show_page(page_id, false)


func set_state(unlocked_pages: PackedStringArray, read_pages: PackedStringArray, last: String) -> void:
	unlocked.clear()
	read.clear()
	for id in unlocked_pages:
		unlocked[id] = true
	for id in read_pages:
		read[id] = true
	current = last
	if visible:
		_rebuild_contents()


## Adds newly unlocked pages; returns them.
func add_unlocked(pages: PackedStringArray) -> Array:
	var fresh := []
	for id in pages:
		if not unlocked.has(id):
			unlocked[id] = true
			fresh.append(id)
	if visible and not fresh.is_empty():
		_rebuild_contents()
		if not current.is_empty() and fresh.has(current):
			show_page(current, false)
	return fresh


func unread_count() -> int:
	return unlocked.keys().filter(func(id): return not read.has(id) and not registry.get_page(id).is_empty()).size()


func show_page(page_id: String, remember := true) -> void:
	var page := registry.get_page(page_id)
	if page.is_empty():
		_show_empty()
		return
	if remember and not current.is_empty() and current != page_id:
		_history.append(current)
		_future.clear()
	current = page_id
	for child in _page.get_children():
		_page.remove_child(child)
		child.queue_free()
	_portraits.clear()
	var chapter := registry.get_chapter(page.chapter)
	_crumb.text = str(chapter.get("title", ""))
	var open := unlocked.has(page_id)
	_title.text = page.title if open else "???"
	if open:
		for b in page.blocks:
			var node := _block(b)
			if node != null:
				_page.add_child(node)
		if not read.has(page_id):
			read[page_id] = true
		page_viewed.emit(page_id)
	else:
		var locked := _paragraph("[i]This page is still blank.[/i]")
		_page.add_child(locked)
		_page.add_child(_tip(lock_hint(page)))
	_page_scroll.scroll_vertical = 0
	var neighbours := _neighbours(page_id)
	_prev.disabled = neighbours[0].is_empty()
	_next.disabled = neighbours[1].is_empty()
	_back.disabled = _history.is_empty()
	_forward.disabled = _future.is_empty()
	_rebuild_contents()


## What reveals a locked page.
func lock_hint(page: Dictionary) -> String:
	if not str(page.get("hint", "")).is_empty():
		return page.hint
	var u: Dictionary = page.unlock
	if u.has("item"):
		return "Get hold of [b]%s[/b] to fill in this page." % _item_title(u.item)
	if u.has("recipe"):
		var index: int = recipes.index_of(u.recipe) if recipes != null else -1
		var what: String = items.display_name(recipes.recipes[index].output) if index >= 0 else "a new recipe"
		return "Learn to make [b]%s[/b] to fill in this page." % what
	if u.has("entity"):
		return "Meet a [b]%s[/b] to fill in this page." % _entity_title(u.entity)
	if u.has("biome"):
		return "Explore a [b]%s[/b] to fill in this page." % str(u.biome).get_slice(":", 1).replace("_", " ").capitalize()
	if u.has("page"):
		return "Read [b]%s[/b] first." % str(registry.get_page(u.page).get("title", "another page"))
	return "Keep playing to fill in this page."


# --- Contents ---------------------------------------------------------------------------------------

func _rebuild_contents() -> void:
	if _contents == null:
		return
	for child in _contents.get_children():
		_contents.remove_child(child)
		child.queue_free()
	var query := _search.text.strip_edges().to_lower()
	var found := 0
	for chapter in registry.sorted_chapters():
		var pages := registry.chapter_pages(chapter.id)
		if not query.is_empty():
			pages = pages.filter(func(p): return unlocked.has(p.id) and GuideRegistry.page_text(p).contains(query))
			if pages.is_empty() and not chapter.title.to_lower().contains(query):
				continue
		if pages.is_empty() and query.is_empty():
			continue
		found += pages.size()
		var fresh := pages.filter(func(p): return unlocked.has(p.id) and not read.has(p.id)).size()
		var head := Button.new()
		head.flat = true
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var folded: bool = query.is_empty() and _collapsed.get(chapter.id, false)
		head.text = "%s %s%s" % ["▸" if folded else "▾", chapter.title, "  (%d new)" % fresh if fresh > 0 else ""]
		head.icon = _item_icon(chapter.icon)
		head.expand_icon = false
		head.add_theme_constant_override("icon_max_width", 24)
		head.add_theme_font_size_override("font_size", 17)
		_color_button(head, ACCENT)
		head.tooltip_text = chapter.description
		head.pressed.connect(func():
			_collapsed[chapter.id] = not _collapsed.get(chapter.id, false)
			_rebuild_contents())
		_contents.add_child(head)
		if folded:
			continue
		for page in pages:
			var open: bool = unlocked.has(page.id)
			var b := Button.new()
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text = "      %s%s" % [page.title if open else "???", "  •" if open and not read.has(page.id) else ""]
			b.clip_text = true
			if open:
				b.icon = _item_icon(page.icon)
				b.add_theme_constant_override("icon_max_width", 20)
			_color_button(b, INK if open else INK_SOFT.lerp(PAPER, 0.35))
			if page.id == current:
				b.add_theme_stylebox_override("normal", _style(PAPER.darkened(0.18), 4, Color.TRANSPARENT, 0, 2))
			b.pressed.connect(show_page.bind(page.id))
			_contents.add_child(b)
	if found == 0 and not query.is_empty():
		var none := Label.new()
		none.text = "Nothing found for \"%s\"." % _search.text
		none.add_theme_color_override("font_color", INK_SOFT)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_contents.add_child(none)


func _first_page() -> String:
	for chapter in registry.sorted_chapters():
		for page in registry.chapter_pages(chapter.id):
			if unlocked.has(page.id):
				return page.id
	return ""


## [previous, next] page ids in reading order (unlocked or not).
func _neighbours(page_id: String) -> Array:
	var order := []
	for chapter in registry.sorted_chapters():
		for page in registry.chapter_pages(chapter.id):
			order.append(page.id)
	var i := order.find(page_id)
	if i < 0:
		return ["", ""]
	return [order[i - 1] if i > 0 else "", order[i + 1] if i < order.size() - 1 else ""]


func _step(direction: int) -> void:
	var target: String = _neighbours(current)[0 if direction < 0 else 1]
	if not target.is_empty():
		show_page(target)


func _go_back() -> void:
	if _history.is_empty():
		return
	_future.append(current)
	var target: String = _history.pop_back()
	show_page(target, false)


func _go_forward() -> void:
	if _future.is_empty():
		return
	_history.append(current)
	var target: String = _future.pop_back()
	show_page(target, false)


func _show_empty() -> void:
	for child in _page.get_children():
		_page.remove_child(child)
		child.queue_free()
	_title.text = "An empty book"
	_crumb.text = ""
	_page.add_child(_paragraph("No pages have been written for this world yet."))
	for b in [_prev, _next, _back, _forward]:
		b.disabled = true


# --- Page blocks ------------------------------------------------------------------------------------

func _block(b: Dictionary) -> Control:
	match str(b.get("type", "")):
		"text":
			return _paragraph(str(b.get("text", "")))
		"heading":
			var l := Label.new()
			l.text = str(b.get("text", ""))
			l.add_theme_font_size_override("font_size", 20)
			l.add_theme_color_override("font_color", ACCENT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			return l
		"tip":
			return _tip(str(b.get("text", "")))
		"items":
			return _item_row(b.get("items") if b.get("items") is Array else [])
		"recipe":
			return _recipe_cards(str(b.get("output", "")))
		"entity":
			return _portrait(str(b.get("entity", "")), str(b.get("text", "")))
		"image":
			var tex: Texture2D = texture_of.call(str(b.get("asset", ""))) if texture_of.is_valid() else null
			if tex == null:
				return null
			var rect := TextureRect.new()
			rect.texture = tex
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			var scale := maxf(1.0, floorf(minf(560.0 / tex.get_width(), 280.0 / tex.get_height())))
			rect.custom_minimum_size = Vector2(tex.get_width(), tex.get_height()) * scale
			return rect
		"link":
			var target := str(b.get("page", ""))
			var link := Button.new()
			link.flat = true
			link.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var title := str(registry.get_page(target).get("title", target)) if unlocked.has(target) else "??? (not found yet)"
			link.text = "→ %s" % str(b.get("text", title))
			_color_button(link, ACCENT)
			link.pressed.connect(show_page.bind(target))
			return link
		"keys":
			var action := str(b.get("action", ""))
			return _paragraph("[bgcolor=#5a3a20][color=#f4ead0] %s [/color][/bgcolor]  %s" % [key_name(action), str(b.get("text", ""))])
	return null


## The first key bound to an input action ("G", "Space", "Left Mouse").
static func key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return action.capitalize()
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			return OS.get_keycode_string(code)
		if ev is InputEventMouseButton:
			return {MOUSE_BUTTON_LEFT: "Left Click", MOUSE_BUTTON_RIGHT: "Right Click", MOUSE_BUTTON_MIDDLE: "Middle Click"}.get(ev.button_index, "Mouse")
	return action.capitalize()


func _paragraph(text: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.add_theme_color_override("default_color", INK)
	r.add_theme_font_size_override("normal_font_size", 16)
	r.add_theme_font_size_override("bold_font_size", 16)
	r.add_theme_font_size_override("italics_font_size", 16)
	r.text = text
	r.meta_clicked.connect(func(meta): show_page(str(meta)))
	return r


func _tip(text: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.85, 0.9, 0.7), 10, Color(0.45, 0.6, 0.3), 2, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var mark := Label.new()
	mark.text = "Tip"
	mark.add_theme_color_override("font_color", Color(0.3, 0.45, 0.15))
	mark.add_theme_font_size_override("font_size", 15)
	row.add_child(mark)
	var body := _paragraph(text)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_color_override("default_color", Color(0.18, 0.24, 0.1))
	row.add_child(body)
	return panel


func _item_row(names: Array) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for n in names.slice(0, 24):
		var id: int = items.id_of(str(n)) if items != null else -1
		if id <= 0:
			continue
		var b := Button.new()
		b.text = items.display_name(id)
		b.icon = _icon(id)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 32)
		b.tooltip_text = "Show recipes for %s" % items.display_name(id)
		b.add_theme_stylebox_override("normal", _style(PAPER.darkened(0.1), 6, PAPER.darkened(0.35), 1, 4))
		b.add_theme_stylebox_override("hover", _style(PAPER.darkened(0.2), 6, ACCENT, 1, 4))
		b.add_theme_stylebox_override("pressed", _style(PAPER.darkened(0.25), 6, ACCENT, 1, 4))
		_color_button(b, INK)
		b.pressed.connect(func(): lookup_requested.emit(id, "make"))
		flow.add_child(b)
	return flow


## Cards for every recipe that makes an item: ingredients → result, and where it is made.
func _recipe_cards(output_name: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var out_id: int = items.id_of(output_name) if items != null else -1
	if out_id <= 0 or recipes == null:
		return null
	var matching: Array = recipes.recipes.filter(func(r): return r.output == out_id)
	# Recipes you know first; a few cards at most (the recipe book has the rest).
	matching.sort_custom(func(a, b): return crafting != null and crafting.is_known(a) and not crafting.is_known(b))
	for r in matching.slice(0, MAX_RECIPE_CARDS):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _style(Color(0.82, 0.74, 0.6), 10, Color(0.5, 0.38, 0.24), 2, 6))
		box.add_child(card)
		var col := VBoxContainer.new()
		card.add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		col.add_child(row)
		var known: bool = crafting == null or crafting.is_known(r)
		for input_id in r.inputs:
			row.add_child(_stack(int(input_id), int(r.inputs[input_id]), known))
		var arrow := Label.new()
		arrow.text = "→"
		arrow.add_theme_font_size_override("font_size", 26)
		arrow.add_theme_color_override("font_color", INK)
		row.add_child(arrow)
		row.add_child(_stack(out_id, int(r.count), true))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var show := Button.new()
		show.text = "Open in recipe book"
		show.pressed.connect(func(): lookup_requested.emit(out_id, "make"))
		row.add_child(show)
		var where := Label.new()
		var text: String = crafting.requirement_text(r) if crafting != null else ""
		if not known:
			text = "Not discovered yet" + (": " + str(r.hint) if not str(r.get("hint", "")).is_empty() else "")
		elif float(r.get("time", 0.0)) > 0.0:
			text += " · %d s" % ceili(float(r.time))
		where.text = text
		where.add_theme_color_override("font_color", INK_SOFT)
		where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(where)
	if matching.size() > MAX_RECIPE_CARDS:
		var more := Button.new()
		more.flat = true
		more.alignment = HORIZONTAL_ALIGNMENT_LEFT
		more.text = "→ %d more ways to make %s in the recipe book" % [matching.size() - MAX_RECIPE_CARDS, items.display_name(out_id)]
		_color_button(more, ACCENT)
		more.pressed.connect(func(): lookup_requested.emit(out_id, "make"))
		box.add_child(more)
	# Smelting and other processes that turn something into it.
	var processes: Dictionary = crafting.processes if crafting != null else {}
	var processed := false
	for kind in processes:
		for input in processes[kind]:
			var proc: Dictionary = processes[kind][input]
			if int(proc.get("output", 0)) != out_id:
				continue
			processed = true
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", _style(Color(0.86, 0.72, 0.6), 10, Color(0.6, 0.35, 0.2), 2, 6))
			box.add_child(card)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			card.add_child(row)
			row.add_child(_stack(int(input), 1, true))
			var arrow := Label.new()
			arrow.text = "→"
			arrow.add_theme_font_size_override("font_size", 26)
			arrow.add_theme_color_override("font_color", INK)
			row.add_child(arrow)
			row.add_child(_stack(out_id, int(proc.get("count", 1)), true))
			var how := Label.new()
			how.text = "  %s · %d s" % [str(kind).capitalize(), ceili(float(proc.get("seconds", 0.0)))]
			how.add_theme_color_override("font_color", INK_SOFT)
			row.add_child(how)
	if matching.is_empty() and not processed:
		var none := _paragraph("[i]%s is not crafted; it is found in the world.[/i]" % items.display_name(out_id))
		box.add_child(none)
	return box


func _stack(item: int, count: int, known: bool) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(52, 52)
	cell.tooltip_text = items.display_name(item) if known else "?"
	cell.add_theme_stylebox_override("panel", _style(Color(0.2, 0.15, 0.1, 0.85), 4, Color(0.1, 0.07, 0.05), 1, 3))
	var icon := TextureRect.new()
	icon.texture = _icon(item)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color.WHITE if known else Color(0, 0, 0, 0.7)
	cell.add_child(icon)
	if count > 1:
		var label := Label.new()
		label.text = str(count)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		cell.add_child(label)
	return cell


## A slowly turning 3D model of a mob, with its name.
func _portrait(entity_name: String, caption: String) -> Control:
	var model: Node3D = make_entity_view.call(entity_name) if make_entity_view.is_valid() else null
	if model == null:
		return null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _style(Color(0.62, 0.74, 0.82), 4, Color(0.4, 0.3, 0.2), 3, 6))
	row.add_child(frame)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(180, 180)
	frame.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	var height := float(entity_types.defs[entity_types.id_of(entity_name)].get("height", 1.0)) if entity_types != null else 1.0
	var width := float(entity_types.defs[entity_types.id_of(entity_name)].get("width", 1.0)) if entity_types != null else 1.0
	var size := maxf(height, width * 1.4)
	var camera := Camera3D.new()
	camera.fov = 40.0
	camera.position = Vector3(0, height * 0.55 + size * 0.25, size * 1.9 + 0.6)
	viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, height * 0.45, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	viewport.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment.ambient_light_energy = 0.8
	viewport.add_child(env)
	viewport.add_child(model)
	model.rotation.y = 0.6
	_portraits.append(model)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = _entity_title(entity_name)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", ACCENT)
	text.add_child(name_label)
	if not caption.is_empty():
		var body := _paragraph(caption)
		text.add_child(body)
	return row


# --- Helpers ----------------------------------------------------------------------------------------

func _icon(item: int) -> Texture2D:
	return crafting._icon(item) if crafting != null else null


func _item_icon(item_name: String) -> Texture2D:
	if item_name.is_empty() or items == null:
		return null
	var id: int = items.id_of(item_name)
	return _icon(id) if id > 0 else null


func _item_title(item_name: String) -> String:
	var id: int = items.id_of(item_name) if items != null else -1
	return items.display_name(id) if id > 0 else item_name.get_slice(":", 1).capitalize()


func _entity_title(entity_name: String) -> String:
	if entity_types != null and entity_types.id_of(entity_name) >= 0:
		var def: Dictionary = entity_types.defs[entity_types.id_of(entity_name)]
		if not str(def.get("display_name", "")).is_empty():
			return def.display_name
	return entity_name.get_slice(":", 1).capitalize()


func _nav_button(text: String, tooltip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.tooltip_text = tooltip
	_color_button(b, INK)
	b.pressed.connect(action)
	return b


static func _color_button(b: Button, color: Color) -> void:
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, color if key == "font_color" else color.lightened(0.15))
	b.add_theme_color_override("font_disabled_color", Color(color, 0.35))


static func _style(color: Color, margin: int, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		closed.emit()
		get_viewport().set_input_as_handled()
