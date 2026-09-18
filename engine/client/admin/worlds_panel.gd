extends VBoxContainer
## The worlds this server is linked to (its network.json), from the pause menu: where you are, where you
## can go, and whether your things come with you. Travelling is the same trip a portal makes.

signal action_requested(action: String, args: Dictionary)
signal closed

const MenuTheme = preload("res://engine/client/menu/menu_theme.gd")

## What the server last sent (also read by tests).
var last_state := {}
var _list: VBoxContainer
var _note: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	add_child(header)
	var title := MenuTheme.heading("Worlds")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(func(): closed.emit())
	header.add_child(done)
	_note = MenuTheme.muted("Loading…", 14)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 360
	add_child(_note)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	add_child(_list)
	action_requested.emit("", {})


func receive(state: Dictionary) -> void:
	last_state = state
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var worlds: Array = state.get("worlds", [])
	if worlds.size() <= 1:
		_note.text = "This server stands alone. An admin can link others in network.json, and then they show up here."
		return
	_note.text = str(state.get("hint", ""))
	for entry in worlds:
		if not (entry is Dictionary):
			continue
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.PANEL_LIGHT, 10, 12, 8))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		panel.add_child(row)
		var name_box := VBoxContainer.new()
		name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_box)
		var label := Label.new()
		label.text = str(entry.get("name", "?"))
		name_box.add_child(label)
		var detail := "You are here" if entry.get("here", false) else \
			("Your things come with you" if entry.get("carries_inventory", false) else "Your things stay here")
		name_box.add_child(MenuTheme.muted(detail, 12))
		if not entry.get("here", false):
			var go := Button.new()
			go.text = "Travel"
			go.disabled = not entry.get("allowed", false)
			go.tooltip_text = "Only admins can send players to this one" if go.disabled else "Go to %s" % entry.get("name", "")
			go.pressed.connect(func(): action_requested.emit("travel", {"server": entry.get("key", "")}))
			row.add_child(go)
		_list.add_child(panel)
