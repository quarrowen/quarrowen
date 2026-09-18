extends VBoxContainer
## Server settings for admins, from the pause menu: the gameplay rules as switches, the time of day, the
## game mode everyone plays in, who may join, cheat checks and a backup button - the things an admin would
## otherwise type as commands. The server sends the state (s_server_panel) and checks every change against
## the caller's role; this only shows it and asks.

signal action_requested(action: String, args: Dictionary)
signal closed

const MenuTheme = preload("res://engine/client/menu/menu_theme.gd")

var _list: VBoxContainer
var _note: Label
var _state := {}


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	add_child(header)
	var title := MenuTheme.heading("Server settings")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(func(): closed.emit())
	header.add_child(done)
	_note = MenuTheme.muted("Loading…", 14)
	add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	action_requested.emit("", {})


func receive(state: Dictionary) -> void:
	_state = state
	_render()


func _render() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _state.get("denied", false):
		_note.text = "Only admins can change server settings."
		_note.add_theme_color_override("font_color", MenuTheme.BAD)
		return
	_note.remove_theme_color_override("font_color")
	var server: Dictionary = _state.get("server", {})
	_note.text = "%s  -  world '%s'  -  %d online  -  version %s" % [server.get("name", "Server"), server.get("world", "?"),
		int(server.get("players", 0)), server.get("version", "?")]

	_section("The world right now")
	var time_row := _row()
	time_row.add_child(MenuTheme.muted("Time of day", 14))
	for entry in [["Morning", "day"], ["Noon", "noon"], ["Evening", "dusk"], ["Night", "night"]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(func(): action_requested.emit("time", {"value": entry[1]}))
		time_row.add_child(button)
	var clock: float = float(_state.get("time_of_day", 0.0))
	time_row.add_child(MenuTheme.muted("(%02d:%02d)" % [int(clock * 24.0), int(fmod(clock * 24.0, 1.0) * 60.0)], 14))

	var mode_row := _row()
	mode_row.add_child(MenuTheme.muted("Everyone plays in", 14))
	for mode in ["survival", "creative"]:
		var button := Button.new()
		button.text = mode.capitalize()
		button.tooltip_text = "Switches everyone now, and new players start in %s" % mode
		button.pressed.connect(func(): action_requested.emit("gamemode", {"mode": mode}))
		mode_row.add_child(button)

	_section("Rules")
	for rule in _state.get("rules", []):
		if not (rule is Dictionary):
			continue
		var check := CheckBox.new()
		check.text = str(rule.get("label", rule.get("key", "")))
		check.button_pressed = bool(rule.get("value", false))
		check.tooltip_text = str(rule.get("help", ""))
		check.toggled.connect(func(on): action_requested.emit("set", {"key": rule.key, "value": "true" if on else "false"}))
		_list.add_child(check)
		if not str(rule.get("help", "")).is_empty():
			var help := MenuTheme.muted(str(rule.help), 12)
			help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			help.custom_minimum_size.x = 380
			_list.add_child(help)

	_section("Who may join")
	var allowlist: Dictionary = _state.get("allowlist", {})
	var on: bool = bool(allowlist.get("enabled", false))
	var allow_check := CheckBox.new()
	allow_check.text = "Only players on the list"
	allow_check.button_pressed = on
	allow_check.toggled.connect(func(enabled): action_requested.emit("allowlist", {"mode": "on" if enabled else "off"}))
	_list.add_child(allow_check)
	var names: Array = allowlist.get("names", [])
	var chips := HFlowContainer.new()
	_list.add_child(chips)
	for entry in names:
		var chip := Button.new()
		chip.text = "%s  ✕" % entry
		chip.tooltip_text = "Take %s off the list" % entry
		chip.pressed.connect(func(): action_requested.emit("allowlist", {"mode": "remove", "name": entry}))
		chips.add_child(chip)
	if names.is_empty():
		chips.add_child(MenuTheme.muted("nobody listed yet", 13))
	var add_row := _row()
	var add_name := LineEdit.new()
	add_name.placeholder_text = "Name to allow"
	add_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(add_name)
	var add_button := Button.new()
	add_button.text = "Add"
	add_button.pressed.connect(func():
		if not add_name.text.strip_edges().is_empty():
			action_requested.emit("allowlist", {"mode": "add", "name": add_name.text.strip_edges()})
			add_name.text = "")
	add_row.add_child(add_button)

	_mod_settings()

	_section("Cheat checks and backups")
	var cheat_row := _row()
	cheat_row.add_child(MenuTheme.muted("When someone cheats", 14))
	for entry in [["Kick them", "kick"], ["Only log it", "log"], ["Off", "off"]]:
		var button := Button.new()
		button.text = entry[0]
		button.disabled = str(_state.get("anticheat", "")) == entry[1]
		button.pressed.connect(func(): action_requested.emit("anticheat", {"mode": entry[1]}))
		cheat_row.add_child(button)
	var backup := Button.new()
	backup.text = "Back up the world now"
	backup.pressed.connect(func(): action_requested.emit("save", {}))
	_list.add_child(backup)


## One section per mod that has settings, built from the schema the server sent - the client knows nothing
## about what any of these mean, and every change goes back to the server to check and keep.
func _mod_settings() -> void:
	var settings: Array = _state.get("mod_settings", [])
	var names: Dictionary = _state.get("mod_names", {})
	var current_mod := ""
	for entry in settings:
		if not (entry is Dictionary):
			continue
		if entry.get("mod", "") != current_mod:
			current_mod = str(entry.mod)
			_section(str(names.get(current_mod, current_mod)))
		_setting_row(entry)


func _setting_row(entry: Dictionary) -> void:
	var mod := str(entry.get("mod", ""))
	var key := str(entry.get("key", ""))
	var label := str(entry.get("label", key))
	var change := func(value): action_requested.emit("modset", {"mod": mod, "key": key, "value": str(value)})
	match str(entry.get("type", "")):
		"bool":
			var check := CheckBox.new()
			check.text = label
			check.button_pressed = bool(entry.get("value", false))
			check.toggled.connect(func(on): change.call("true" if on else "false"))
			_list.add_child(check)
		"int", "float":
			var row := _row()
			row.add_child(MenuTheme.muted(label, 14))
			var slider := HSlider.new()
			slider.min_value = float(entry.get("min", 0.0))
			slider.max_value = float(entry.get("max", 1.0))
			slider.step = float(entry.get("step", 1.0))
			slider.value = float(entry.get("value", slider.min_value))
			slider.custom_minimum_size.x = 160
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(slider)
			var shown := MenuTheme.muted(str(entry.get("value", "")), 14)
			shown.custom_minimum_size.x = 48
			row.add_child(shown)
			slider.value_changed.connect(func(value): shown.text = str(int(value) if entry.type == "int" else snappedf(value, 0.01)))
			slider.drag_ended.connect(func(changed): if changed: change.call(slider.value))
			# Keyboard and click-on-the-track changes do not count as a drag.
			slider.gui_input.connect(func(event):
				if event is InputEventKey and event.pressed:
					change.call(slider.value))
		"choice":
			var row := _row()
			row.add_child(MenuTheme.muted(label, 14))
			for choice in entry.get("choices", []):
				if not (choice is Array and choice.size() == 2):
					continue
				var button := Button.new()
				button.text = str(choice[1])
				button.disabled = str(entry.get("value", "")) == str(choice[0])
				button.pressed.connect(func(): change.call(choice[0]))
				row.add_child(button)
		"text":
			var row := _row()
			row.add_child(MenuTheme.muted(label, 14))
			var edit := LineEdit.new()
			edit.text = str(entry.get("value", ""))
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.text_submitted.connect(func(text): change.call(text))
			edit.focus_exited.connect(func(): change.call(edit.text))
			row.add_child(edit)
	var help := str(entry.get("help", ""))
	if not help.is_empty():
		var note := MenuTheme.muted(help, 12)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 380
		_list.add_child(note)


func _section(text: String) -> void:
	if _list.get_child_count() > 0:
		_list.add_child(HSeparator.new())
	var label := MenuTheme.muted(text, 15)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_list.add_child(label)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_list.add_child(row)
	return row
