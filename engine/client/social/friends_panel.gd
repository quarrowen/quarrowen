extends VBoxContainer
## Friends and party, for the menu's Friends page and the pause menu: your friend code, adding friends,
## requests, the friends list (online, which server, join, invite to party, remove) and your party
## (members, the leader's server, invitations). Emits `join_requested` to go to a friend's server.

signal join_requested(address: String, port: int, server_name: String)
signal closed

const MenuTheme = preload("res://engine/client/menu/menu_theme.gd")
const SocialClient = preload("res://engine/client/social/social_client.gd")

var social: SocialClient
## Shows a Done button (the in-game overlay).
var closable := false

var _code_label: Label
var _add_edit: LineEdit
var _note: Label
var _list: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	add_child(header)
	var title := MenuTheme.heading("Friends")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	if closable:
		var done := Button.new()
		done.text = "Done"
		done.pressed.connect(func(): closed.emit())
		header.add_child(done)
	var code_row := HBoxContainer.new()
	add_child(code_row)
	_code_label = MenuTheme.muted("", 15)
	_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(_code_label)
	var copy := Button.new()
	copy.text = "Copy my code"
	copy.pressed.connect(func():
		var code := str(social.state.get("me", {}).get("friend_code", ""))
		if not code.is_empty():
			DisplayServer.clipboard_set(code)
			_on_notice("Copied %s: friends add you with it" % code))
	code_row.add_child(copy)
	var add_row := HBoxContainer.new()
	add_child(add_row)
	_add_edit = LineEdit.new()
	_add_edit.placeholder_text = "A friend's code (ABCD-EFGH)"
	_add_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_edit.text_submitted.connect(func(_t): _add_friend())
	add_row.add_child(_add_edit)
	var add := MenuTheme.primary(Button.new())
	add.text = "Add friend"
	add.pressed.connect(_add_friend)
	add_row.add_child(add)
	_note = MenuTheme.muted("", 14)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 300
	add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	social.state_changed.connect(_on_state)
	social.failed.connect(_on_failed)
	social.notice.connect(_on_notice)
	_render()
	social.refresh()


func _exit_tree() -> void:
	for pair in [[social.state_changed, _on_state], [social.failed, _on_failed], [social.notice, _on_notice]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])


func _on_state(_state: Dictionary) -> void:
	_render()


func _on_failed(error: String) -> void:
	_note.text = "⚠ " + error
	_note.add_theme_color_override("font_color", MenuTheme.BAD)
	_render()


func _on_notice(text: String) -> void:
	_note.text = text
	_note.add_theme_color_override("font_color", MenuTheme.GOOD)


func _add_friend() -> void:
	var code := _add_edit.text.strip_edges()
	if code.is_empty():
		return
	_add_edit.text = ""
	social.request_friend(code)


func _render() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var state: Dictionary = social.state
	var me: Dictionary = state.get("me", {})
	if not SocialClient.available():
		_code_label.text = ""
		_list.add_child(_muted("Friends and parties need a hub. Set one in Settings → Network."))
		return
	if state.is_empty():
		_code_label.text = "Signing in…" if social.last_error.is_empty() else ""
		return
	_code_label.text = "Your friend code: %s" % me.get("friend_code", "")
	var party = state.get("party")
	# Party invitations.
	for invite in state.get("party_invites", []):
		_list.add_child(_person_row("%s invited you to their party" % invite.leader_name, "%d in the party" % invite.members, [
			["Join party", func(): social.respond_party(invite.party_id, true), true],
			["Decline", func(): social.respond_party(invite.party_id, false), false]]))
	# The party.
	if party is Dictionary:
		_list.add_child(_section("Your party"))
		var leading: bool = party.leader == me.get("id", "")
		var leader_server := social.leader_server()
		if not leader_server.is_empty():
			_list.add_child(_person_row("The leader is playing on %s" % leader_server.name, "%s:%d" % [leader_server.address, leader_server.port], [
				["Join the leader", func(): join_requested.emit(leader_server.address, leader_server.port, leader_server.name), true]]))
		for m in party.members:
			var actions := []
			if leading and m.id != me.get("id", ""):
				actions.append(["Make leader", func(): social.promote(m.id), false])
				actions.append(["Remove", func(): social.kick(m.id), false])
			_list.add_child(_person_row(("★ " if m.id == party.leader else "") + m.name + (" (you)" if m.id == me.get("id", "") else ""), _status(m), actions))
		for m in party.invited:
			_list.add_child(_person_row(m.name, "invited", [["Cancel", func(): social.kick(m.id), false]] if leading else []))
		var leave_row := HBoxContainer.new()
		var leave := Button.new()
		leave.text = "Leave party"
		leave.pressed.connect(social.leave_party)
		leave_row.add_child(leave)
		_list.add_child(leave_row)
	# Requests.
	if not state.get("incoming", []).is_empty() or not state.get("outgoing", []).is_empty():
		_list.add_child(_section("Friend requests"))
	for r in state.get("incoming", []):
		_list.add_child(_person_row(r.name, "wants to be your friend", [
			["Accept", func(): social.respond_friend(r.id, true), true], ["Decline", func(): social.respond_friend(r.id, false), false]]))
	for r in state.get("outgoing", []):
		_list.add_child(_person_row(r.name, "request sent", [["Cancel", func(): social.cancel_request(r.id), false]]))
	# Friends, online first.
	var friends: Array = state.get("friends", []).duplicate()
	friends.sort_custom(func(a, b): return a.online and not b.online if a.online != b.online else a.name.naturalnocasecmp_to(b.name) < 0)
	_list.add_child(_section("Friends (%d online)" % friends.filter(func(f): return f.online).size()))
	if friends.is_empty():
		_list.add_child(_muted("No friends yet. Share your friend code, or add a friend's code above."))
	for f in friends:
		var actions := []
		if f.server is Dictionary and f.server.port > 0:
			actions.append(["Join", func(): join_requested.emit(f.server.address, f.server.port, f.server.name), true])
		if f.online and not f.in_my_party:
			actions.append(["Invite to party", func(): social.invite_to_party(f.id), false])
		actions.append(["Remove", func(): _confirm_remove(f), false])
		_list.add_child(_person_row(f.name, _status(f), actions, f.online))


static func _status(p: Dictionary) -> String:
	if p.server is Dictionary and not str(p.server.name).is_empty():
		return "Playing on %s" % p.server.name
	return "Online" if p.online else "Offline"


func _confirm_remove(f: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Remove friend"
	dialog.dialog_text = "Remove %s from your friends?" % f.name
	dialog.ok_button_text = "Remove"
	dialog.confirmed.connect(func():
		social.remove_friend(f.id)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _section(text: String) -> Control:
	var label := MenuTheme.heading(text, 18)
	return label


func _muted(text: String) -> Label:
	var label := MenuTheme.muted(text, 15)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 300
	return label


## A row: name (with an online dot), a status line and buttons [[text, callback, primary]].
func _person_row(title: String, subtitle: String, actions: Array, online := true) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.PANEL_LIGHT, 10, 14, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_color_override("font_color", MenuTheme.GOOD if online else Color(1, 1, 1, 0.25))
	row.add_child(dot)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var t := Label.new()
	t.text = title
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.add_theme_font_size_override("font_size", 17)
	text.add_child(t)
	var s := MenuTheme.muted(subtitle, 13)
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(s)
	for a in actions:
		var b := MenuTheme.primary(Button.new()) if a[2] else Button.new()
		b.text = a[0]
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(a[1])
		row.add_child(b)
	return panel
