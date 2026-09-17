extends VBoxContainer
## The settings screen, used in the main menu's Settings page and from the pause menu: tabs built from
## ClientSettings.SCHEMA (switches, sliders and choices with help text), key rebinding on the Controls
## tab, a reset button per tab, and extra tabs a host can add (the menu adds Account).
## Every change is saved and applied at once through ClientSettings.changed.

signal closed

const ClientSettings = preload("res://engine/client/settings/client_settings.gd")
const MenuTheme = preload("res://engine/client/menu/menu_theme.gd")
const Housekeeping = preload("res://engine/client/housekeeping.gd")

var settings = ClientSettings.shared()
## Shows a close button (the in-game overlay).
var closable := false

var _tab_bar: TabBar
var _pages := {}  # tab name -> Control
var _tab_names: Array[String] = []
var _widgets := {}  # key -> Control
var _value_labels := {}  # key -> Label
var _binding_buttons := {}  # action -> [Button, Button]
var _capture := {}  # {action, slot, button} while waiting for a key
var _binding_note: Label
var _extra := []  # [name, control] added before _ready


func add_tab(tab_name: String, control: Control) -> void:
	if _tab_bar == null:
		_extra.append([tab_name, control])
	else:
		_add_page(tab_name, control)


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	add_child(header)
	var title := MenuTheme.heading("Settings")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if closable:
		var close := Button.new()
		close.text = "Done"
		close.pressed.connect(func(): closed.emit())
		header.add_child(close)
	_tab_bar = TabBar.new()
	add_child(_tab_bar)
	var stack := MarginContainer.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(stack)
	_pages["__stack"] = stack
	for tab: String in ClientSettings.TABS:
		_add_page(tab, _build_tab(tab))
	_add_page("Files", _build_files())
	for e in _extra:
		_add_page(e[0], e[1])
	_extra.clear()
	var footer := HBoxContainer.new()
	add_child(footer)
	var reset := Button.new()
	reset.text = "Reset this tab"
	reset.pressed.connect(func():
		var tab := _tab_names[_tab_bar.current_tab]
		if ClientSettings.TABS.has(tab):
			settings.reset_tab(tab))
	footer.add_child(reset)
	settings.changed.connect(_on_changed)
	_tab_bar.tab_changed.connect(_show_tab)
	_show_tab(0)


func _exit_tree() -> void:
	if settings.changed.is_connected(_on_changed):
		settings.changed.disconnect(_on_changed)


func _add_page(tab_name: String, control: Control) -> void:
	_tab_names.append(tab_name)
	_tab_bar.add_tab(tab_name)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_right", 16)  # clear of the scroll bar
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_child(control)
	scroll.add_child(inset)
	_pages["__stack"].add_child(scroll)
	_pages[tab_name] = scroll
	scroll.visible = _tab_names.size() == 1


func show_tab(tab_name: String) -> void:
	var i := _tab_names.find(tab_name)
	if i >= 0:
		_tab_bar.current_tab = i


func _show_tab(index: int) -> void:
	for i in _tab_names.size():
		_pages[_tab_names[i]].visible = i == index
	_cancel_capture()


func _build_tab(tab: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	for key: String in ClientSettings.SCHEMA:
		var entry: Dictionary = ClientSettings.SCHEMA[key]
		if entry.tab == tab:
			box.add_child(_row(key, entry))
	if tab == "Controls":
		box.add_child(HSeparator.new())
		box.add_child(MenuTheme.heading("Keys", 20))
		var how := MenuTheme.muted("Click a key to change it, then press the new key or mouse button. Esc cancels, Backspace clears.", 13)
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		how.custom_minimum_size.x = 300
		box.add_child(how)
		_binding_note = MenuTheme.muted("", 13)
		_binding_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_binding_note.custom_minimum_size.x = 300
		_binding_note.add_theme_color_override("font_color", MenuTheme.WARN)
		box.add_child(_binding_note)
		for a in ClientSettings.ACTIONS:
			box.add_child(_binding_row(a[0], a[1]))
	return box


## The Files tab: every folder the game keeps things in, what it holds, how big it is, and a button that
## opens it in Finder.
##
## This exists because "where is the log?" had no answer a parent could act on. The folder is buried
## several levels inside Library, which is hidden by default, under a name that is not the game's - so
## telling somebody the path is not much better than not telling them. A button is.
func _build_files() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var intro := MenuTheme.muted("Where Quarrowen keeps things on this computer. The downloaded ones clear themselves out as they grow; the rest are yours.", 13)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 300
	box.add_child(intro)
	for folder in Housekeeping.listing():
		box.add_child(HSeparator.new())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 2)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var size_note: String = Housekeeping.human(int(folder.bytes)) if folder.exists else "empty"
		var heading := MenuTheme.heading("%s - %s" % [folder.title, size_note], 16)
		text.add_child(heading)
		var about := MenuTheme.muted(str(folder.about), 13)
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		about.custom_minimum_size.x = 260
		text.add_child(about)
		var open := Button.new()
		open.text = "Open"
		open.tooltip_text = str(folder.absolute)
		open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var path := str(folder.path)
		open.pressed.connect(func():
			# Made on demand: a folder nothing has written to yet does not exist, and a button that does
			# nothing is worse than one that opens an empty folder.
			DirAccess.make_dir_recursive_absolute(path)
			OS.shell_open(ProjectSettings.globalize_path(path)))
		row.add_child(open)
	return box


func _row(key: String, entry: Dictionary) -> Control:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 2)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	outer.add_child(row)
	var label := Label.new()
	label.text = entry.label
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	match entry.type:
		"bool":
			var toggle := CheckButton.new()
			toggle.focus_mode = Control.FOCUS_NONE
			toggle.toggled.connect(func(on): settings.set_value(key, on))
			row.add_child(toggle)
			_widgets[key] = toggle
		"float":
			var slider := HSlider.new()
			slider.min_value = entry.min
			slider.max_value = entry.max
			slider.step = entry.step
			slider.custom_minimum_size.x = 220
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.focus_mode = Control.FOCUS_NONE
			var value_label := Label.new()
			value_label.custom_minimum_size.x = 56
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			# Apply while dragging, save when released.
			slider.value_changed.connect(func(v):
				value_label.text = _format(entry, v)
				settings.set_value(key, v, false))
			slider.drag_ended.connect(func(_changed): settings.save())
			row.add_child(slider)
			row.add_child(value_label)
			_widgets[key] = slider
			_value_labels[key] = value_label
		"text":
			var edit := LineEdit.new()
			edit.custom_minimum_size.x = 300
			edit.placeholder_text = str(entry.get("placeholder", ""))
			# Saved when done typing (Enter or leaving the field), not on every letter.
			edit.text_submitted.connect(func(t): settings.set_value(key, t))
			edit.focus_exited.connect(func(): settings.set_value(key, edit.text))
			row.add_child(edit)
			_widgets[key] = edit
		"choice":
			var option := OptionButton.new()
			option.custom_minimum_size.x = 220
			option.focus_mode = Control.FOCUS_NONE
			for c in entry.choices:
				option.add_item(c[1])
			option.item_selected.connect(func(i): settings.set_value(key, entry.choices[i][0]))
			row.add_child(option)
			_widgets[key] = option
	if entry.has("help"):
		var help := MenuTheme.muted(entry.help, 13)
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.custom_minimum_size.x = 300
		outer.add_child(help)
	_refresh(key)
	return outer


static func _format(entry: Dictionary, v: float) -> String:
	if entry.get("percent", false):
		return "%d%%" % roundi(v * 100.0)
	return "%d%s" % [roundi(v), entry.get("suffix", "")]


## Puts the stored value in a widget without firing its signal.
func _refresh(key: String) -> void:
	var widget = _widgets.get(key)
	if widget == null:
		return
	var entry: Dictionary = ClientSettings.SCHEMA[key]
	var v = settings.get_value(key)
	match entry.type:
		"bool":
			widget.set_pressed_no_signal(v)
		"float":
			widget.set_value_no_signal(v)
			_value_labels[key].text = _format(entry, v)
		"text":
			if not widget.has_focus():
				widget.text = v
		"choice":
			for i in entry.choices.size():
				if entry.choices[i][0] == v:
					widget.select(i)


func _on_changed(key: String) -> void:
	if key == "bindings":
		for action: String in _binding_buttons:
			_refresh_binding(action)
		return
	if key == "graphics/preset":
		for k: String in _widgets:
			if k.begins_with("graphics/"):
				_refresh(k)
	_refresh(key)


# --- Key bindings -------------------------------------------------------------------------------

func _binding_row(action: String, label_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var buttons := []
	for slot in 2:
		var b := Button.new()
		b.custom_minimum_size.x = 130
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_start_capture.bind(action, slot, b))
		row.add_child(b)
		buttons.append(b)
	var reset := Button.new()
	reset.text = "↺"
	reset.tooltip_text = "Default keys"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func(): settings.set_events(action, ClientSettings.default_events(action)))
	row.add_child(reset)
	_binding_buttons[action] = buttons
	_refresh_binding(action)
	return row


func _refresh_binding(action: String) -> void:
	var list: Array = settings.events(action)
	for slot in 2:
		var b: Button = _binding_buttons[action][slot]
		b.text = ClientSettings.describe(list[slot]) if slot < list.size() else "—"


func _start_capture(action: String, slot: int, button: Button) -> void:
	_cancel_capture()
	_capture = {"action": action, "slot": slot, "button": button}
	button.text = "Press a key…"


func _cancel_capture() -> void:
	if not _capture.is_empty():
		var action: String = _capture.action
		_capture = {}
		_refresh_binding(action)


func _input(event: InputEvent) -> void:
	if _capture.is_empty() or not event.is_pressed() or event.is_echo():
		return
	var descriptor := ClientSettings.descriptor_of(event)
	if descriptor.is_empty():
		return
	get_viewport().set_input_as_handled()
	var action: String = _capture.action
	var slot: int = _capture.slot
	var list: Array = settings.events(action).duplicate()
	_capture = {}
	if descriptor == "key:Escape" and action != "pause":
		_refresh_binding(action)
		return
	if descriptor == "key:BackSpace":
		if slot < list.size():
			list.remove_at(slot)
		settings.set_events(action, list)
		return
	# Clicking the button itself to start capturing must not bind the left mouse to it at once.
	if descriptor == "mouse:1" and not action in ["break", "place"]:
		_binding_note.text = "The left mouse button is kept for breaking and placing."
		_refresh_binding(action)
		return
	if slot < list.size():
		list[slot] = descriptor
	else:
		list.append(descriptor)
	var other: String = settings.action_using(descriptor, action)
	_binding_note.text = "%s is also used for %s." % [ClientSettings.describe(descriptor), _label_of(other)] if not other.is_empty() else ""
	settings.set_events(action, list)


static func _label_of(action: String) -> String:
	for a in ClientSettings.ACTIONS:
		if a[0] == action:
			return String(a[1]).to_lower()
	return action
