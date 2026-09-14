extends Control
## The developer overlay (F8, for admins or on --dev servers): a side panel with Logs, Errors, Inspect,
## Events, Perf and Draw tabs fed by the server's dev tools. The game keeps running beside it: click the
## world to play, F8 to get the mouse back, F8 again (or the ✕) to close.

signal request(action: String, args: Dictionary)
## The Inspect tab wants a fresh pick of what the crosshair points at.
signal pick_requested
signal closed

const LEVEL_COLORS := {"debug": "#8a8f98", "info": "#d8dce2", "warn": "#ffcc55", "error": "#ff6b5e"}
const MAX_LOG_LINES := 1500
const MAX_EVENTS := 300

var logs: Array = []
var errors: Array = []
var events: Array = []
var perf: Array = []
var inspected := {}
var draw_mods := false
var draw_ai := false

var _panel: PanelContainer
var _tabs: TabContainer
var _log_text: RichTextLabel
var _log_source: OptionButton
var _log_level: OptionButton
var _log_search: LineEdit
var _log_pause: CheckBox
var _sources := {}
var _error_list: ItemList
var _error_detail: RichTextLabel
var _inspect_title: Label
var _inspect_tree: Tree
var _event_list: ItemList
var _event_detail: Tree
var _event_filter: LineEdit
var _event_pause: CheckBox
var _perf_tree: Tree
var _perf_totals: CheckBox
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.anchor_left = 0.52
	_panel.offset_left = 0
	_panel.offset_right = -10
	_panel.offset_top = 10
	_panel.offset_bottom = -10
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.93)
	style.border_color = Color(0.35, 0.55, 0.9, 0.8)
	style.border_width_left = 2
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var root := VBoxContainer.new()
	_panel.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Dev tools"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	header.add_child(title)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	_status.text = "F8: mouse / close   click the world to play"
	header.add_child(_status)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.pressed.connect(func(): closed.emit())
	header.add_child(close)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_i): _subscribe())
	root.add_child(_tabs)
	_build_logs()
	_build_errors()
	_build_inspect()
	_build_events()
	_build_perf()
	_build_draw()


func channels() -> Array:
	var out := []
	if draw_mods:
		out.append("draw")
	if draw_ai:
		out.append("ai")
	if visible:
		out.append_array(["logs", "errors"])
		match _tabs.get_current_tab_control().name:
			"Inspect": out.append("inspect")
			"Events": out.append("events")
			"Perf": out.append("perf")
	return out


func _subscribe() -> void:
	request.emit("subscribe", {"channels": channels()})


func set_open(open: bool) -> void:
	visible = open
	_subscribe()


func receive(kind: String, data) -> void:
	match kind:
		"logs":
			for e in data:
				_add_log(e)
		"errors":
			errors = data
			_refresh_errors()
		"error":
			errors = errors.filter(func(e): return e.id != data.id)
			errors.push_front(data)
			_refresh_errors()
		"events":
			if not _event_pause.button_pressed:
				events.append_array(data)
				if events.size() > MAX_EVENTS:
					events = events.slice(-MAX_EVENTS)
				_refresh_events()
		"perf":
			perf = data
			_refresh_perf()
		"inspect":
			inspected = data
			_refresh_inspect()


# --- Logs -------------------------------------------------------------------------------------------

func _build_logs() -> void:
	var box := _tab("Logs")
	var bar := HBoxContainer.new()
	box.add_child(bar)
	_log_source = OptionButton.new()
	_log_source.add_item("All sources")
	_log_source.item_selected.connect(func(_i): _refresh_logs())
	bar.add_child(_log_source)
	_log_level = OptionButton.new()
	for level in ["debug", "info", "warn", "error"]:
		_log_level.add_item(level.capitalize() + "+")
	_log_level.item_selected.connect(func(_i): _refresh_logs())
	bar.add_child(_log_level)
	_log_search = LineEdit.new()
	_log_search.placeholder_text = "Filter text"
	_log_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_search.text_changed.connect(func(_t): _refresh_logs())
	bar.add_child(_log_search)
	_log_pause = CheckBox.new()
	_log_pause.text = "Pause"
	bar.add_child(_log_pause)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(func():
		logs.clear()
		_refresh_logs())
	bar.add_child(clear)
	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.scroll_following = true
	_log_text.selection_enabled = true
	_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_text.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_log_text)


func _add_log(e: Dictionary) -> void:
	logs.append(e)
	if logs.size() > MAX_LOG_LINES:
		logs.pop_front()
	if not _sources.has(e.source):
		_sources[e.source] = true
		_log_source.add_item(e.source)
	if not _log_pause.button_pressed and _log_matches(e):
		_log_text.append_text(_log_line(e) + "\n")


func _log_matches(e: Dictionary) -> bool:
	var source := _log_source.get_item_text(_log_source.selected) if _log_source.selected > 0 else ""
	var levels := ["debug", "info", "warn", "error"]
	return (source.is_empty() or e.source == source) and levels.find(e.level) >= _log_level.selected \
		and (_log_search.text.is_empty() or str(e.message).to_lower().contains(_log_search.text.to_lower()))


func _log_line(e: Dictionary) -> String:
	var time := Time.get_time_string_from_unix_time(int(e.time))
	return "[color=#6a7080]%s[/color] [color=%s][%s] %s[/color]" % [time, LEVEL_COLORS.get(e.level, "#ffffff"), e.source,
		str(e.message).replace("[", "[lb]")]


func _refresh_logs() -> void:
	_log_text.clear()
	for e in logs:
		if _log_matches(e):
			_log_text.append_text(_log_line(e) + "\n")


# --- Errors -----------------------------------------------------------------------------------------

func _build_errors() -> void:
	var box := _tab("Errors")
	var bar := HBoxContainer.new()
	box.add_child(bar)
	var hint := Label.new()
	hint.text = "Script errors by mod, newest first"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hint)
	var clear := Button.new()
	clear.text = "Clear all"
	clear.pressed.connect(func():
		request.emit("clear_errors", {})
		errors.clear()
		_refresh_errors())
	bar.add_child(clear)
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	_error_list = ItemList.new()
	_error_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_error_list.custom_minimum_size.y = 180
	_error_list.item_selected.connect(_show_error)
	split.add_child(_error_list)
	_error_detail = RichTextLabel.new()
	_error_detail.bbcode_enabled = true
	_error_detail.selection_enabled = true
	_error_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(_error_detail)


func _refresh_errors() -> void:
	var selected := _error_list.get_selected_items()
	_error_list.clear()
	for e in errors:
		var where := " — %s:%d" % [str(e.file).get_file(), int(e.line)] if not str(e.file).is_empty() else ""
		var i := _error_list.add_item("[%s] ×%d  %s%s" % [e.source, int(e.count), str(e.message).left(140), where])
		_error_list.set_item_custom_fg_color(i, Color.from_string(LEVEL_COLORS.get(e.level, "#ff6b5e"), Color.RED))
	_tabs.set_tab_title(1, "Errors (%d)" % errors.size() if not errors.is_empty() else "Errors")
	if not selected.is_empty() and selected[0] < errors.size():
		_error_list.select(selected[0])


func _show_error(index: int) -> void:
	var e: Dictionary = errors[index]
	var text := "[b]%s[/b]  in [color=#8fb8ff]%s[/color]\n%s\n\n" % [str(e.message).replace("[", "[lb]"), e.source,
		"[color=#aaaaaa]%s:%d[/color]" % [e.file, int(e.line)] if not str(e.file).is_empty() else ""]
	text += "Seen %d times, first %s, last %s\n\n[b]Stack[/b]\n" % [int(e.count), Time.get_time_string_from_unix_time(int(e.first)),
		Time.get_time_string_from_unix_time(int(e.last))]
	for frame in e.get("stack", []):
		text += "  %s\n" % str(frame).replace("[", "[lb]")
	_error_detail.text = text


# --- Inspect ----------------------------------------------------------------------------------------

func _build_inspect() -> void:
	var box := _tab("Inspect")
	var bar := HBoxContainer.new()
	box.add_child(bar)
	_inspect_title = Label.new()
	_inspect_title.text = "Look at a block, mob or player and press Inspect"
	_inspect_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspect_title.add_theme_font_size_override("font_size", 16)
	bar.add_child(_inspect_title)
	var pick := Button.new()
	pick.text = "Inspect crosshair"
	pick.pressed.connect(func(): pick_requested.emit())
	bar.add_child(pick)
	var note := Label.new()
	note.text = "Updates every second while this tab is open."
	note.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	box.add_child(note)
	_inspect_tree = _tree(["Field", "Value"])
	box.add_child(_inspect_tree)


func _refresh_inspect() -> void:
	_inspect_title.text = "%s%s" % [inspected.get("title", ""), "  (%s)" % inspected.kind if inspected.has("kind") else ""]
	_fill_tree(_inspect_tree, inspected.get("fields", {}))


# --- Events -----------------------------------------------------------------------------------------

func _build_events() -> void:
	var box := _tab("Events")
	var bar := HBoxContainer.new()
	box.add_child(bar)
	_event_filter = LineEdit.new()
	_event_filter.placeholder_text = "Events to trace, e.g. block_*, player_eat (empty: all but tick)"
	_event_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_event_filter.text_submitted.connect(func(t): request.emit("trace_filter", {"filter": t}))
	bar.add_child(_event_filter)
	_event_pause = CheckBox.new()
	_event_pause.text = "Pause"
	bar.add_child(_event_pause)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(func():
		events.clear()
		_refresh_events())
	bar.add_child(clear)
	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)
	_event_list = ItemList.new()
	_event_list.custom_minimum_size.y = 200
	_event_list.item_selected.connect(_show_event)
	split.add_child(_event_list)
	_event_detail = _tree(["Field", "Value"])
	split.add_child(_event_detail)


func _refresh_events() -> void:
	var keep_bottom := _event_list.get_v_scroll_bar().value >= _event_list.get_v_scroll_bar().max_value - _event_list.size.y - 30
	_event_list.clear()
	for ev in events:
		var owners := PackedStringArray()
		for h in ev.handlers:
			owners.append(str(h.owner))
		var line := "%s  %s  (%s)  %.2f ms%s%s" % [Time.get_time_string_from_unix_time(int(ev.time)), ev.event, ", ".join(owners) if not owners.is_empty() else "no handlers",
			float(ev.ms), "  CANCELLED" if ev.get("cancelled", false) else "", "  changed" if ev.has("changed") else ""]
		var i := _event_list.add_item(line)
		if ev.get("cancelled", false):
			_event_list.set_item_custom_fg_color(i, Color(1.0, 0.6, 0.4))
	if keep_bottom and _event_list.item_count > 0:
		_event_list.ensure_current_is_visible()
		_event_list.get_v_scroll_bar().value = _event_list.get_v_scroll_bar().max_value


func _show_event(index: int) -> void:
	var ev: Dictionary = events[index]
	var handlers := {}
	for i in ev.handlers.size():
		var h: Dictionary = ev.handlers[i]
		handlers["%d. %s" % [i + 1, h.owner]] = "%.3f ms%s" % [float(h.ms), "  → cancelled=%s" % h.cancelled if h.has("cancelled") else ""]
	var fields := {"event": ev.event, "payload": ev.payload, "handlers (in order)": handlers}
	if ev.has("changed"):
		fields["payload after handlers"] = ev.changed
	_fill_tree(_event_detail, fields)


# --- Perf -------------------------------------------------------------------------------------------

func _build_perf() -> void:
	var box := _tab("Perf")
	var bar := HBoxContainer.new()
	box.add_child(bar)
	var note := Label.new()
	note.text = "Server time per mod over the last 10 s (a tick has 16.7 ms)"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(note)
	_perf_totals = CheckBox.new()
	_perf_totals.text = "Totals per mod only"
	_perf_totals.toggled.connect(func(_on): _refresh_perf())
	bar.add_child(_perf_totals)
	_perf_tree = _tree(["Mod", "What", "ms / s", "Calls", "Avg ms", "Max ms"])
	box.add_child(_perf_tree)


func _refresh_perf() -> void:
	_perf_tree.clear()
	var root := _perf_tree.create_item()
	for row in perf:
		if _perf_totals.button_pressed != (row.category == "total"):
			continue
		var item := _perf_tree.create_item(root)
		var values := [row.owner, row.category, "%.3f" % float(row.ms_per_s), str(int(row.calls)), "%.3f" % float(row.avg_ms), "%.2f" % float(row.max_ms)]
		for c in values.size():
			item.set_text(c, values[c])
		if float(row.max_ms) > 5.0:
			item.set_custom_color(5, Color(1.0, 0.5, 0.4))
		if float(row.ms_per_s) > 2.0:
			item.set_custom_color(2, Color(1.0, 0.8, 0.4))


# --- Draw -------------------------------------------------------------------------------------------

func _build_draw() -> void:
	var box := _tab("Draw")
	var mods := CheckBox.new()
	mods.text = "Show debug drawings from mods (api.debug_box / api.draw.*)"
	mods.toggled.connect(func(on):
		draw_mods = on
		_subscribe())
	box.add_child(mods)
	var ai := CheckBox.new()
	ai.text = "Show mob AI: behaviour, target lines, paths and homes (within 32 blocks)"
	ai.toggled.connect(func(on):
		draw_ai = on
		_subscribe())
	box.add_child(ai)
	var note := Label.new()
	note.text = "Drawings stay on after you close the overlay."
	note.add_theme_color_override("font_color", Color(0.55, 0.58, 0.65))
	box.add_child(note)


# --- Helpers ----------------------------------------------------------------------------------------

func _tab(tab_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = tab_name
	_tabs.add_child(box)
	return box


func _tree(columns: Array) -> Tree:
	var tree := Tree.new()
	tree.columns = columns.size()
	tree.column_titles_visible = true
	for i in columns.size():
		tree.set_column_title(i, columns[i])
		tree.set_column_expand(i, true)
	tree.set_column_expand_ratio(columns.size() - 1, 3 if columns.size() == 2 else 1)
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.select_mode = Tree.SELECT_ROW
	return tree


func _fill_tree(tree: Tree, fields: Dictionary) -> void:
	tree.clear()
	var root := tree.create_item()
	_add_fields(tree, root, fields, 0)


func _add_fields(tree: Tree, parent: TreeItem, value, depth: int) -> void:
	var keys: Array = value.keys() if value is Dictionary else range(value.size())
	for k in keys:
		var v = value[k]
		var item := tree.create_item(parent)
		item.set_text(0, str(k))
		if (v is Dictionary or v is Array) and not v.is_empty():
			item.set_text(1, "{%d}" % v.size() if v is Dictionary else "[%d]" % v.size())
			item.set_custom_color(1, Color(0.55, 0.58, 0.65))
			_add_fields(tree, item, v, depth + 1)
			item.collapsed = depth >= 1 and v.size() > 6
		else:
			item.set_text(1, JSON.stringify(v) if not (v is String) else v)
