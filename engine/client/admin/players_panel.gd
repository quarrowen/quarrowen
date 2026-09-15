extends VBoxContainer
## Players and roles, for admins (roles.manage) from the pause menu: everyone who has played here, online
## first, with their roles as chips (✕ takes one away), a menu to give a role, and Kick for online players.
## The server sends the list (s_roles_panel) and does every check; this only shows it and asks.

signal action_requested(action: String, args: Dictionary)
signal closed

const MenuTheme = preload("res://engine/client/menu/menu_theme.gd")

var _list: VBoxContainer
var _note: Label
var _search: LineEdit
var _state := {}


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	add_child(header)
	var title := MenuTheme.heading("Players and roles")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(func(): closed.emit())
	header.add_child(done)
	var help := MenuTheme.muted("Roles decide what people may do: members build and chat, builders also save structures, moderators can kick and review creations, admins can do everything. /role info <role> shows the details.", 13)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 300
	add_child(help)
	_search = LineEdit.new()
	_search.placeholder_text = "Find a player"
	_search.text_changed.connect(func(_t): _render())
	add_child(_search)
	_note = MenuTheme.muted("Loading…", 14)
	add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	action_requested.emit("list", {})


func receive(state: Dictionary) -> void:
	_state = state
	_render()


func _render() -> void:
	for child in _list.get_children():
		child.queue_free()
	if _state.get("denied", false):
		_note.text = "Only admins can manage players and roles."
		_note.add_theme_color_override("font_color", MenuTheme.BAD)
		return
	var roles: Array = _state.get("roles", [])
	var needle := _search.text.strip_edges().to_lower()
	var shown := 0
	for p in _state.get("players", []):
		if not (p is Dictionary) or (not needle.is_empty() and not str(p.get("name", "")).to_lower().contains(needle)):
			continue
		_list.add_child(_row(p, roles))
		shown += 1
	_note.text = "%d players%s" % [shown, " matching" if not needle.is_empty() else ""]
	_note.remove_theme_color_override("font_color")


func _row(p: Dictionary, roles: Array) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.PANEL_LIGHT, 10, 12, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_color_override("font_color", MenuTheme.GOOD if p.get("online", false) else Color(1, 1, 1, 0.25))
	row.add_child(dot)
	var name_label := Label.new()
	name_label.text = str(p.get("name", "?")) + ("  (you)" if str(p.get("id", "")) == str(_state.get("me", "")) else "")
	name_label.custom_minimum_size.x = 150
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)
	var chips := HFlowContainer.new()
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(chips)
	var assigned: Array = p.get("assigned", [])
	for r in p.get("roles", []):
		var def := _role(roles, str(r))
		var chip := Button.new()
		var removable: bool = assigned.has(r) and def.get("manageable", false)
		chip.text = str(r) + ("  ✕" if removable else "")
		chip.tooltip_text = "Take the %s role" % r if removable else ("Everyone has this role" if def.get("default", false) else "")
		chip.disabled = not removable
		var color := Color.html(str(def.get("color", ""))) if Color.html_is_valid(str(def.get("color", ""))) else Color(1, 1, 1, 0.35)
		chip.add_theme_stylebox_override("normal", MenuTheme.box(Color(color, 0.28), 12, 10, 4, color))
		chip.add_theme_stylebox_override("disabled", MenuTheme.box(Color(color, 0.18), 12, 10, 4))
		chip.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.8))
		if removable:
			chip.pressed.connect(func(): action_requested.emit("take", {"player_id": p.id, "role": r}))
		chips.add_child(chip)
	var give := OptionButton.new()
	give.add_item("Give role…")
	for def in roles:
		if def.get("manageable", false) and not p.get("roles", []).has(def.name):
			give.add_item(str(def.name))
	give.disabled = give.item_count <= 1
	give.item_selected.connect(func(i):
		if i > 0:
			action_requested.emit("give", {"player_id": p.id, "role": give.get_item_text(i)}))
	row.add_child(give)
	if _state.get("can_kick", false) and p.get("online", false) and str(p.get("id", "")) != str(_state.get("me", "")):
		var kick := Button.new()
		kick.text = "Kick"
		kick.pressed.connect(func(): action_requested.emit("kick", {"peer": int(p.get("peer", 0))}))
		row.add_child(kick)
	return panel


static func _role(roles: Array, role_name: String) -> Dictionary:
	for def in roles:
		if def is Dictionary and def.get("name", "") == role_name:
			return def
	return {}
