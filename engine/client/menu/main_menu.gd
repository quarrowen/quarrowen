extends Control
## The main menu: a sidebar (Play, Multiplayer, Avatar, Create, Settings, Quit) and one page at a time
## over the live world backdrop, with a news column on the right. It only gathers choices and emits
## signals; engine/main.gd launches servers and clients.

signal play_world(world_id: String, mods: Array, dev: bool)
signal join_server(address: String, port: int, server_name: String)
signal avatar_requested
signal mod_wizard_requested
signal host_mod_requested(mods: String)
signal identity_file_chosen(path: String, exporting: bool, passphrase: String)
signal quit_requested
## The player asked to look for a new version (Settings > Account).
signal check_updates

const MenuTheme = preload("res://engine/client/menu/menu_theme.gd")
const WorldList = preload("res://engine/client/menu/world_list.gd")
const ServerBook = preload("res://engine/client/menu/server_book.gd")
const ServerPinger = preload("res://engine/client/menu/server_pinger.gd")
const InviteCode = preload("res://engine/shared/invite_code.gd")
const ModLoader = preload("res://engine/server/mod_loader.gd")
const Identity = preload("res://engine/shared/identity.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const SettingsScreen = preload("res://engine/client/settings/settings_screen.gd")
const ClientSettings = preload("res://engine/client/settings/client_settings.gd")
const HubClient = preload("res://engine/client/menu/hub_client.gd")
const FriendsPanel = preload("res://engine/client/social/friends_panel.gd")
const ModCatalog = preload("res://engine/client/mod_catalog.gd")
const ModBrowser = preload("res://engine/client/menu/mod_browser.gd")

const NEWS := "res://engine/client/menu/news.json"
const PAGES := ["play", "multiplayer", "create", "mods", "settings"]
const STATUS_REFRESH := 10.0
const TAB_BROWSE := 0
const TAB_LAN := 1
const TAB_FAVORITES := 2
const TAB_RECENT := 3

var player_name := "Player"
## engine/client/social/social_client.gd, from main.gd.
var social
var port := 24565

var _pages := {}
var _nav := {}
var _page := "play"
var _message: Label
var _banner: PanelContainer
var _banner_icon: Label
var _banner_action: Button
var _banner_serial := 0
var _name_edit: LineEdit
var _games: Array = []
var _addons: Array = []
# Mods
var _mod_browser: Node
var _mod_rows: VBoxContainer
var _mod_tab: TabBar
var _mod_note: Label
var _mod_buttons := {}
var _selected_mod := ""
# Play
var _world_rows: VBoxContainer
var _worlds: Array = []
var _selected_world := ""
var _world_buttons: Array[Button] = []
var _dev_check: CheckBox
# Multiplayer
var _book
var _server_tab: TabBar
var _server_rows: VBoxContainer
var _selected_server := ""
var _server_buttons := {}  # action -> Button
var _browse_search: LineEdit
var _server_note: Label
var _hub: HubClient
var _hub_servers: Array = []
var _hub_busy := false
var _hub_error := ""
var _lan_servers := {}  # key -> entry
var _lan_started := 0
var _direct_edit: LineEdit
var _statuses := {}  # key -> status entry
var _news_box: VBoxContainer
var _pinger: ServerPinger
var _status_timer := 0.0
# Settings
var _identity_label: Label
var _passphrase_edit: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MenuTheme.build()
	_book = ServerBook.load_book()
	_pinger = ServerPinger.new()
	_pinger.result.connect(_on_status)
	_pinger.lan_found.connect(_on_lan_found)
	_hub = HubClient.new()
	add_child(_hub)
	_hub.servers_received.connect(_on_hub_servers)
	ClientSettings.shared().changed.connect(_on_setting_changed)
	_mod_browser = ModBrowser.new()
	add_child(_mod_browser)
	_mod_browser.message.connect(func(text, kind, action_text, action): show_message(text, kind, action_text, action))
	_mod_browser.catalog_changed.connect(_on_catalog_changed)
	_discover_mods()
	_build()
	show_page("play")


func _exit_tree() -> void:
	_pinger.close()
	if ClientSettings.shared().changed.is_connected(_on_setting_changed):
		ClientSettings.shared().changed.disconnect(_on_setting_changed)


func _on_setting_changed(key: String) -> void:
	if key == "network/hub_url":
		_hub_servers = []
		_hub_error = ""
		_load_news()


func _discover_mods() -> void:
	_games = []
	_addons = []
	var available := ModLoader.discover(ModLoader.search_dirs(PackedStringArray()))
	for id: String in available:
		var m: Dictionary = available[id]
		if m.game:
			_games.append(m)
		elif id != "base" and not str(m.dir).begins_with("res://tests"):
			_addons.append(m)
	_games.sort_custom(func(a, b): return a.name < b.name)
	_addons.sort_custom(func(a, b): return a.name < b.name)


# --- Layout -------------------------------------------------------------------------------------

func _build() -> void:
	# Darken the left side so the panels read well over a bright world.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.7))
	gradient.set_color(1, Color(0, 0, 0, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_to = Vector2(1, 0)
	shade.texture = texture
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	shade.anchor_right = 0.75
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	margin.add_child(row)

	row.add_child(_build_sidebar())
	var content := PanelContainer.new()
	content.custom_minimum_size = Vector2(700, 0)
	row.add_child(content)
	var stack := Control.new()
	content.add_child(stack)
	_pages.play = _build_play()
	_pages.multiplayer = _build_multiplayer()
	_pages.friends = _build_friends()
	_pages.create = _build_create()
	_pages.mods = _build_mods()
	_pages.settings = _build_settings()
	for page: Control in _pages.values():
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.add_child(page)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_build_news())

	# Messages: a banner at the bottom. Errors are red and stay until dismissed; others fade.
	_banner = PanelContainer.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_banner.offset_bottom = -28
	_banner.custom_minimum_size.x = 760
	_banner.visible = false
	add_child(_banner)
	var banner_row := HBoxContainer.new()
	banner_row.add_theme_constant_override("separation", 12)
	_banner.add_child(banner_row)
	_banner_icon = Label.new()
	_banner_icon.add_theme_font_size_override("font_size", 22)
	banner_row.add_child(_banner_icon)
	_message = Label.new()
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size.x = 560
	_message.add_theme_font_size_override("font_size", 16)
	banner_row.add_child(_message)
	_banner_action = Button.new()
	_banner_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	banner_row.add_child(_banner_action)
	var dismiss := Button.new()
	dismiss.text = "✕"
	dismiss.tooltip_text = "Dismiss"
	dismiss.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dismiss.pressed.connect(func(): _banner.visible = false)
	banner_row.add_child(dismiss)


func _build_sidebar() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 230
	side.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Quarrowen"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("outline_size", 10)
	side.add_child(title)
	side.add_child(MenuTheme.muted("version %s" % Protocol.GAME_VERSION))
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	side.add_child(gap)
	var group := ButtonGroup.new()
	for entry in [["play", "Play"], ["multiplayer", "Multiplayer"], ["friends", "Friends"], ["avatar", "Avatar"], ["mods", "Mods"], ["create", "Create"], ["settings", "Settings"]]:
		var button := MenuTheme.nav(Button.new())
		button.text = entry[1]
		if entry[0] != "avatar":
			button.button_group = group
			button.pressed.connect(show_page.bind(entry[0]))
		else:
			button.toggle_mode = false
			button.pressed.connect(func(): avatar_requested.emit())
		side.add_child(button)
		_nav[entry[0]] = button
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(fill)
	# The player card: name and short identity.
	var card := PanelContainer.new()
	side.add_child(card)
	var card_box := VBoxContainer.new()
	card.add_child(card_box)
	card_box.add_child(MenuTheme.muted("Playing as"))
	_name_edit = LineEdit.new()
	_name_edit.text = player_name
	_name_edit.max_length = 16
	_name_edit.text_changed.connect(func(t):
		player_name = t
		ClientSettings.shared().set_value("player/name", t)  # the name sticks between sessions
		if social != null:
			social.player_name = t)
	card_box.add_child(_name_edit)
	var quit := MenuTheme.nav(Button.new())
	quit.toggle_mode = false
	quit.text = "Quit"
	quit.pressed.connect(func(): quit_requested.emit())
	side.add_child(quit)
	return side


func _build_news() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 290
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_news_box = VBoxContainer.new()
	_news_box.add_theme_constant_override("separation", 10)
	panel.add_child(_news_box)
	_load_news()
	return panel


## News from the hub when one is set, else (or when it cannot be reached) the bundled news.
func _load_news() -> void:
	var bundled = JSON.parse_string(FileAccess.get_file_as_string(NEWS)) if FileAccess.file_exists(NEWS) else []
	_show_news(bundled if bundled is Array else [])
	if HubClient.configured():
		_hub.news_received.connect(func(items: Array, error: String):
			if error.is_empty() and not items.is_empty():
				_show_news(items), CONNECT_ONE_SHOT)
		_hub.fetch_news()


func _show_news(items: Array) -> void:
	for child in _news_box.get_children():
		child.queue_free()
	_news_box.add_child(MenuTheme.heading("What's new", 20))
	for item in items.slice(0, 5):
		if not (item is Dictionary):
			continue
		var title := Label.new()
		title.text = str(item.get("title", ""))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", 16)
		_news_box.add_child(title)
		var body := MenuTheme.muted(str(item.get("body", "")), 13)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_news_box.add_child(body)


func show_page(page: String) -> void:
	_page = page
	for id: String in _pages:
		_pages[id].visible = id == page
	if _nav.has(page):
		_nav[page].button_pressed = true
	match page:
		"play": refresh_worlds()
		"multiplayer": refresh_servers(true)
		"mods":
			refresh_mods()
			_mod_browser.refresh()
		"settings": _refresh_identity()


## kind: "info" (fades after a few seconds), "success" (green, fades) or "error" (red, stays until
## dismissed). `action_text` + `action` add a button (e.g. retry).
func show_message(text: String, kind := "info", action_text := "", action := Callable()) -> void:
	_banner_serial += 1
	if text.is_empty():
		_banner.visible = false
		return
	var colors := {"error": MenuTheme.ERROR, "success": Color(0.2, 0.52, 0.28)}
	_banner.add_theme_stylebox_override("panel", MenuTheme.box(Color(colors[kind], 0.96) if colors.has(kind) else Color(0.1, 0.12, 0.16, 0.95),
		10, 16, 12, Color(1, 0.55, 0.5) if kind == "error" else Color(0, 0, 0, 0)))
	_banner_icon.text = {"error": "⚠", "success": "✓"}.get(kind, "ℹ")
	_message.text = text
	_message.add_theme_color_override("font_color", Color.WHITE)
	for connection in _banner_action.pressed.get_connections():
		_banner_action.pressed.disconnect(connection.callable)
	_banner_action.visible = not action_text.is_empty()
	_banner_action.text = action_text
	if action.is_valid():
		_banner_action.pressed.connect(func():
			_banner.visible = false
			action.call())
	_banner.visible = true
	_banner.modulate.a = 1.0
	if kind != "error":
		var serial := _banner_serial
		await get_tree().create_timer(5.0).timeout
		if serial == _banner_serial and is_instance_valid(_banner):
			var tween := create_tween()
			tween.tween_property(_banner, "modulate:a", 0.0, 0.5)
			tween.tween_callback(func():
				if serial == _banner_serial:
					_banner.visible = false)


func set_player_name(text: String) -> void:
	player_name = text
	if _name_edit != null:
		_name_edit.text = text


func _process(delta: float) -> void:
	_pinger.update()
	if _page == "multiplayer" and visible:
		_status_timer += delta
		if _status_timer >= STATUS_REFRESH:
			refresh_servers(true)


# --- Play ---------------------------------------------------------------------------------------

func _build_play() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	page.add_child(header)
	var title := MenuTheme.heading("Your worlds")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var new_button := MenuTheme.primary(Button.new())
	new_button.text = "New world…"
	new_button.pressed.connect(open_new_world)
	header.add_child(new_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_world_rows = VBoxContainer.new()
	_world_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_world_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_world_rows)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	page.add_child(actions)
	var play := MenuTheme.primary(Button.new())
	play.text = "Play"
	play.custom_minimum_size.x = 140
	play.pressed.connect(play_selected_world)
	actions.add_child(play)
	for entry in [["Rename…", _rename_world], ["Delete…", _delete_world], ["Open folder", _open_world_folder]]:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(entry[1])
		actions.add_child(b)
		_world_buttons.append(b)
	_world_buttons.append(play)
	_dev_check = CheckBox.new()
	_dev_check.text = "Developer mode: dev tools (F8) and mods reload when you save them"
	page.add_child(_dev_check)
	return page


func refresh_worlds() -> void:
	_worlds = WorldList.list()
	for child in _world_rows.get_children():
		child.queue_free()
	if _worlds.is_empty():
		var empty := VBoxContainer.new()
		empty.add_theme_constant_override("separation", 10)
		empty.add_child(MenuTheme.muted("No worlds yet. Create one to start playing.", 16))
		_world_rows.add_child(empty)
		_selected_world = ""
	elif not _worlds.any(func(w): return w.id == _selected_world):
		_selected_world = _worlds[0].id
	for w in _worlds:
		_world_rows.add_child(_world_row(w))
	for b in _world_buttons:
		b.disabled = _selected_world.is_empty()


func _world_row(w: Dictionary) -> Control:
	var game_name := str(w.game)
	for g in _games:
		if g.id == w.game:
			game_name = g.name
	var extras: Array = w.mods.filter(func(m): return m != w.game).map(func(m):
		for a in _addons:
			if a.id == m:
				return a.name
		return m)
	var subtitle := "%s%s · %s" % [game_name, " + %s" % ", ".join(extras) if not extras.is_empty() else "",
		"played %s" % WorldList.describe_time(w.last_played) if w.last_played > 0 else "new world"]
	return _row(w.id, str(w.title), subtitle, "", _selected_world == w.id,
		func():
			_selected_world = w.id
			refresh_worlds(),
		func():
			_selected_world = w.id
			play_selected_world())


func play_selected_world() -> void:
	for w in _worlds:
		if w.id == _selected_world:
			var mods: Array = w.mods if not w.mods.is_empty() else [w.game]
			if mods.is_empty() or str(mods[0]).is_empty():
				show_message("This world does not say which game it is", "error")
				return
			play_world.emit(w.id, mods, _dev_check.button_pressed)
			return


func open_new_world() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "New world"
	dialog.ok_button_text = "Create and play"
	dialog.dialog_hide_on_ok = false
	dialog.add_cancel_button("Cancel")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 8)
	dialog.add_child(box)
	var title: LineEdit = _labeled(box, "Name", LineEdit.new())
	title.text = "My World"
	title.max_length = 64
	var game: OptionButton = _labeled(box, "Game", OptionButton.new())
	for g in _games:
		game.add_item(g.name)
	var description := MenuTheme.muted("", 13)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size = Vector2(520, 36)  # wrapping labels need a width, or the dialog grows very tall
	box.add_child(description)
	game.item_selected.connect(func(i): description.text = str(_games[i].description))
	var preferred := _games.map(func(g): return g.id).find("vanilla")
	if preferred >= 0:
		game.select(preferred)
	if not _games.is_empty():
		description.text = str(_games[maxi(preferred, 0)].description)
	var checks := []
	if not _addons.is_empty():
		box.add_child(MenuTheme.muted("Add-ons"))
		var flow := HFlowContainer.new()
		flow.custom_minimum_size = Vector2(520, 40)  # a width, so it does not measure as one item per line
		box.add_child(flow)
		for a in _addons:
			var check := CheckBox.new()
			check.text = a.name
			check.tooltip_text = str(a.description)
			check.set_meta("id", a.id)
			flow.add_child(check)
			checks.append(check)
	var seed_edit: LineEdit = _labeled(box, "Seed", LineEdit.new())
	seed_edit.placeholder_text = "random (or any word or number)"
	var status := Label.new()
	status.add_theme_color_override("font_color", MenuTheme.BAD)
	box.add_child(status)
	dialog.confirmed.connect(func():
		if _games.is_empty():
			status.text = "No games are installed"
			return
		var mods := [_games[game.selected].id]
		for check in checks:
			if check.button_pressed:
				mods.append(check.get_meta("id"))
		var text := seed_edit.text.strip_edges()
		var world_seed := -1
		if not text.is_empty():
			world_seed = int(text) if text.is_valid_int() else (hash(text) & 0x7fffffff)
		var id := WorldList.create(title.text, mods, world_seed)
		dialog.queue_free()
		_selected_world = id
		refresh_worlds()
		play_world.emit(id, mods, _dev_check.button_pressed))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(580, 0))
	title.grab_focus()
	title.select_all()


func _rename_world() -> void:
	var w := _world(_selected_world)
	if w.is_empty():
		return
	_prompt("Rename world", "Name", str(w.title), func(text):
		WorldList.rename(w.id, text)
		refresh_worlds())


func _delete_world() -> void:
	var w := _world(_selected_world)
	if w.is_empty():
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete world"
	dialog.dialog_text = "Delete \"%s\" and its backups? This cannot be undone." % w.title
	dialog.ok_button_text = "Delete"
	dialog.confirmed.connect(func():
		if WorldList.delete(w.id):
			show_message("Deleted \"%s\"" % w.title, "success")
		else:
			show_message("Could not delete \"%s\"" % w.title, "error")
		refresh_worlds()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _open_world_folder() -> void:
	var w := _world(_selected_world)
	if not w.is_empty():
		OS.shell_open(ProjectSettings.globalize_path(WorldList.dir().path_join(w.id)))


func _world(id: String) -> Dictionary:
	for w in _worlds:
		if w.id == id:
			return w
	return {}


# --- Multiplayer --------------------------------------------------------------------------------

func _build_multiplayer() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.add_child(MenuTheme.heading("Multiplayer"))
	var direct := HBoxContainer.new()
	page.add_child(direct)
	_direct_edit = LineEdit.new()
	_direct_edit.placeholder_text = "Server address or invite code (QW-…)"
	_direct_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_direct_edit.text_submitted.connect(func(_t): _join_direct())
	direct.add_child(_direct_edit)
	var join := MenuTheme.primary(Button.new())
	join.text = "Join"
	join.pressed.connect(_join_direct)
	direct.add_child(join)
	var tabs_row := HBoxContainer.new()
	page.add_child(tabs_row)
	_server_tab = TabBar.new()
	for tab_name in ["Browse", "LAN", "Favorites", "Recent"]:
		_server_tab.add_tab(tab_name)
	_server_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server_tab.tab_changed.connect(func(_i):
		_selected_server = ""
		refresh_servers(true))
	tabs_row.add_child(_server_tab)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(refresh_servers.bind(true))
	tabs_row.add_child(refresh)
	_browse_search = LineEdit.new()
	_browse_search.placeholder_text = "Search servers by name, message or tag"
	_browse_search.text_submitted.connect(func(_t): refresh_servers(true))
	page.add_child(_browse_search)
	_server_note = MenuTheme.muted("", 14)
	_server_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_server_note.custom_minimum_size.x = 300
	page.add_child(_server_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_server_rows = VBoxContainer.new()
	_server_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_server_rows)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	page.add_child(actions)
	for entry in [["join", "Join", join_selected_server], ["add", "Add server…", open_server_editor.bind({})], ["favorite", "Add to favorites", _favorite_selected],
			["edit", "Edit…", _edit_server], ["remove", "Remove", _remove_server], ["invite", "Copy invite", _copy_invite]]:
		var b := MenuTheme.primary(Button.new()) if entry[0] == "join" else Button.new()
		b.text = entry[1]
		b.pressed.connect(entry[2])
		actions.add_child(b)
		_server_buttons[entry[0]] = b
	_server_buttons.join.custom_minimum_size.x = 120
	return page


## The rows of the current tab: [{name, address, port, code?, ...}].
func _server_list() -> Array:
	match _server_tab.current_tab:
		TAB_BROWSE: return _hub_servers
		TAB_LAN: return _lan_servers.values()
		TAB_FAVORITES: return _book.favorites
	return _book.recent


## Redraws the list; `query` asks again (the hub, the network, or each server for its status).
func refresh_servers(query := false) -> void:
	var tab := _server_tab.current_tab
	var list := _server_list()
	_browse_search.visible = tab == TAB_BROWSE and HubClient.configured()
	for child in _server_rows.get_children():
		child.queue_free()
	var note := ""
	match tab:
		TAB_BROWSE:
			if not HubClient.configured():
				note = "No server list hub is set. Add one in Settings → Network to browse public servers."
			elif _hub_busy:
				note = "Loading servers…"
			elif not _hub_error.is_empty():
				note = "The server list is not available: %s" % _hub_error
			elif list.is_empty():
				note = "No public servers match." if not _browse_search.text.is_empty() else "No public servers are listed right now."
		TAB_LAN:
			if not ClientSettings.shared().get_value("network/lan_discovery"):
				note = "Finding servers on your network is off (Settings → Network)."
			elif list.is_empty():
				note = "Looking for games on your network…" if Time.get_ticks_msec() - _lan_started < 2500 else "No games found on your network."
		TAB_FAVORITES:
			if list.is_empty():
				note = "No favorite servers yet. Add one, or join by address or invite code above."
		TAB_RECENT:
			if list.is_empty():
				note = "Servers you join show up here."
	_server_note.text = note
	_server_note.visible = not note.is_empty()
	var keys := list.map(func(e): return ServerBook.key(e.address, e.port))
	if not keys.has(_selected_server):
		_selected_server = keys[0] if not keys.is_empty() else ""
	for e in list:
		_server_rows.add_child(_server_row(e))
	var none := _selected_server.is_empty()
	_server_buttons.join.disabled = none
	_server_buttons.invite.disabled = none
	_server_buttons.favorite.visible = tab in [TAB_BROWSE, TAB_LAN, TAB_RECENT]
	_server_buttons.favorite.disabled = none or _book.find_favorite(_selected_entry().get("address", ""), int(_selected_entry().get("port", 0))) >= 0
	_server_buttons.edit.visible = tab == TAB_FAVORITES
	_server_buttons.edit.disabled = none
	_server_buttons.remove.visible = tab in [TAB_FAVORITES, TAB_RECENT]
	_server_buttons.remove.disabled = none
	_server_buttons.add.visible = tab in [TAB_FAVORITES, TAB_RECENT]
	if not query:
		return
	_status_timer = 0.0
	match tab:
		TAB_BROWSE:
			if HubClient.configured() and not _hub_busy:
				_hub_busy = true
				_hub.list_servers(_browse_search.text.strip_edges())
				refresh_servers()
		TAB_LAN:
			if ClientSettings.shared().get_value("network/lan_discovery"):
				_lan_servers.clear()
				_lan_started = Time.get_ticks_msec()
				_pinger.discover_lan([port])
				get_tree().create_timer(2.6).timeout.connect(func():
					if _page == "multiplayer" and _server_tab.current_tab == TAB_LAN:
						refresh_servers())
		_:
			for e in list:
				_pinger.ping(ServerBook.key(e.address, e.port), e.address, e.port)


func _server_row(e: Dictionary) -> Control:
	var k := ServerBook.key(e.address, e.port)
	var s: Dictionary = _statuses.get(k, {})
	var subtitle := "%s:%d" % [e.address, e.port]
	var right := "…"
	var right_color := MenuTheme.MUTED
	if s.is_empty() and e.has("players"):
		# A hub listing: its own numbers until a ping answers.
		s = {"online": true, "info": e, "ping_ms": -1}
	if not s.is_empty():
		if s.online:
			var info: Dictionary = s.info
			subtitle = "%s · %s" % [info.game_name if not info.game_name.is_empty() else info.game, info.motd if not info.motd.is_empty() else subtitle]
			right = "%d/%d" % [info.players, info.max_players] + ("  ·  %d ms" % s.ping_ms if s.ping_ms >= 0 else "")
			right_color = MenuTheme.MUTED if s.ping_ms < 0 else (MenuTheme.GOOD if s.ping_ms < 80 else (MenuTheme.WARN if s.ping_ms < 200 else MenuTheme.BAD))
			if not info.get("compatible", true):
				right = "version %s" % info.version
				right_color = MenuTheme.BAD
		else:
			right = "offline"
			right_color = MenuTheme.BAD
	var shown_name := str(e.get("name", ""))
	if not s.is_empty() and s.online and (shown_name == e.address or shown_name.is_empty()):
		shown_name = s.info.name
	var row := _row(k, shown_name, subtitle, right, _selected_server == k,
		func():
			_selected_server = k
			refresh_servers(),
		func():
			_selected_server = k
			join_selected_server())
	row.get_meta("right").add_theme_color_override("font_color", right_color)
	return row


func _on_status(k: String, entry: Dictionary) -> void:
	_statuses[k] = entry
	if _page == "multiplayer":
		refresh_servers()


func _on_lan_found(k: String, entry: Dictionary) -> void:
	_statuses[ServerBook.key(entry.address, entry.port)] = entry
	_lan_servers[k] = {"name": entry.info.name, "address": entry.address, "port": entry.port, "code": entry.info.code}
	if _page == "multiplayer" and _server_tab.current_tab == TAB_LAN:
		refresh_servers()


func _on_hub_servers(servers: Array, _total: int, error: String) -> void:
	_hub_busy = false
	_hub_error = error
	_hub_servers = servers
	if _page == "multiplayer" and _server_tab.current_tab == TAB_BROWSE:
		refresh_servers()
		for e in servers:
			_pinger.ping(ServerBook.key(e.address, e.port), e.address, e.port)


func join_selected_server() -> void:
	var e := _selected_entry()
	if not e.is_empty():
		_join(e.address, e.port, str(e.get("name", "")))


func _join_direct() -> void:
	var parsed := InviteCode.parse(_direct_edit.text)
	if parsed.has("error"):
		show_message(parsed.error[0].to_upper() + parsed.error.substr(1), "error")
		return
	if parsed.has("hub_code"):
		_resolve_hub_code(parsed.hub_code, func(entry: Dictionary): _join(entry.address, entry.port, entry.name))
		return
	_join(parsed.address, parsed.port, "")


## Looks a hub code up, then calls `then` with {address, port, name}.
func _resolve_hub_code(code: String, then: Callable) -> void:
	if not HubClient.configured():
		show_message("%s is a hub code: set a server list hub in Settings → Network first" % code, "error")
		return
	show_message("Looking up %s…" % code)
	var on_resolved := func(entry: Dictionary, error: String):
		if not error.is_empty():
			show_message("%s: %s" % [code, error], "error")
			return
		show_message("" if entry.online else "%s was last seen at %s:%d (not online right now)" % [entry.name, entry.address, entry.port])
		then.call(entry)
	_hub.code_resolved.connect(on_resolved, CONNECT_ONE_SHOT)
	_hub.resolve_code(code)


func _join(address: String, game_port: int, server_name: String) -> void:
	var s: Dictionary = _statuses.get(ServerBook.key(address, game_port), {})
	if server_name.is_empty() or server_name == address:
		server_name = s.info.name if not s.is_empty() and s.online else address
	_book.note_joined(server_name, address, game_port)
	join_server.emit(address, game_port, server_name)


func open_server_editor(entry: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Edit server" if not entry.is_empty() else "Add server"
	dialog.ok_button_text = "Save"
	dialog.dialog_hide_on_ok = false
	dialog.add_cancel_button("Cancel")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	dialog.add_child(box)
	var name_edit: LineEdit = _labeled(box, "Name", LineEdit.new())
	name_edit.text = str(entry.get("name", ""))
	name_edit.placeholder_text = "shown in your list"
	var address_edit: LineEdit = _labeled(box, "Address", LineEdit.new())
	address_edit.placeholder_text = "host, host:port or invite code"
	if not entry.is_empty():
		address_edit.text = entry.address if int(entry.port) == InviteCode.DEFAULT_PORT else "%s:%d" % [entry.address, entry.port]
	var status := Label.new()
	status.add_theme_color_override("font_color", MenuTheme.BAD)
	box.add_child(status)
	var save := func(address: String, game_port: int):
		if not entry.is_empty():
			_book.remove_favorite(entry.address, int(entry.port))
		if not _book.add_favorite(name_edit.text, address, game_port):
			status.text = "Your favorites list is full"
			return
		_selected_server = ServerBook.key(address, game_port)
		_server_tab.current_tab = TAB_FAVORITES
		dialog.queue_free()
		refresh_servers(true)
	dialog.confirmed.connect(func():
		var parsed := InviteCode.parse(address_edit.text)
		if parsed.has("error"):
			status.text = parsed.error
		elif parsed.has("hub_code"):
			_resolve_hub_code(parsed.hub_code, func(found: Dictionary):
				if name_edit.text.strip_edges().is_empty():
					name_edit.text = found.name
				save.call(found.address, found.port))
		else:
			save.call(parsed.address, parsed.port))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	name_edit.grab_focus()


func _selected_entry() -> Dictionary:
	for e in _server_list():
		if ServerBook.key(e.address, e.port) == _selected_server:
			return e
	return {}


func _favorite_selected() -> void:
	var e := _selected_entry()
	if not e.is_empty() and _book.add_favorite(str(e.get("name", "")), e.address, e.port):
		show_message("Added %s to your favorites" % e.get("name", e.address), "success")
		refresh_servers()


func _edit_server() -> void:
	var e := _selected_entry()
	if not e.is_empty():
		open_server_editor(e)


func _remove_server() -> void:
	var e := _selected_entry()
	if e.is_empty():
		return
	if _server_tab.current_tab == TAB_FAVORITES:
		_book.remove_favorite(e.address, e.port)
	else:
		_book.recent = _book.recent.filter(func(x): return ServerBook.key(x.address, x.port) != _selected_server)
		_book.save()
	_selected_server = ""
	refresh_servers()


## A hub code when the server has one (shorter, works for any address), else an address code.
func _copy_invite() -> void:
	var e := _selected_entry()
	if e.is_empty():
		return
	var s: Dictionary = _statuses.get(_selected_server, {})
	var code := str(e.get("code", ""))
	if code.is_empty() and not s.is_empty() and s.online:
		code = str(s.info.get("code", ""))
	var text := code if not code.is_empty() else InviteCode.share_text(e.address, e.port)
	DisplayServer.clipboard_set(text)
	show_message("Copied %s" % text)


# --- Friends ------------------------------------------------------------------------------------

func _build_friends() -> Control:
	var panel := FriendsPanel.new()
	panel.social = social
	panel.join_requested.connect(func(address: String, game_port: int, server_name: String): _join(address, game_port, server_name))
	return panel


# --- Create -------------------------------------------------------------------------------------

## Mods: what is on this computer, what the project offers, and putting one on or taking it off.
## Installing only matters for hosting - joining a server needs nothing, because its mods run there.
func _build_mods() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.add_child(MenuTheme.heading("Mods"))
	var tabs_row := HBoxContainer.new()
	page.add_child(tabs_row)
	_mod_tab = TabBar.new()
	for tab_name in ["Installed", "Available", "Updates"]:
		_mod_tab.add_tab(tab_name)
	_mod_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mod_tab.tab_changed.connect(func(_i):
		_selected_mod = ""
		refresh_mods())
	tabs_row.add_child(_mod_tab)
	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.pressed.connect(func(): _mod_browser.refresh(true))
	tabs_row.add_child(refresh)
	_mod_note = MenuTheme.muted("", 14)
	_mod_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mod_note.custom_minimum_size.x = 300
	page.add_child(_mod_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_mod_rows = VBoxContainer.new()
	_mod_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mod_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_mod_rows)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	page.add_child(actions)
	for entry in [["install", "Install", _install_selected_mod], ["remove", "Remove", _remove_selected_mod],
			["folder", "Open mods folder", func(): OS.shell_open(ProjectSettings.globalize_path(ModLoader.creation_dir()))]]:
		var b := MenuTheme.primary(Button.new()) if entry[0] == "install" else Button.new()
		b.text = entry[1]
		b.pressed.connect(entry[2])
		actions.add_child(b)
		_mod_buttons[entry[0]] = b
	return page


## The rows of the current tab, from what is installed here and what the index offers.
func refresh_mods() -> void:
	if _mod_rows == null:
		return
	for child in _mod_rows.get_children():
		child.queue_free()
	var rows: Array = ModCatalog.merge(ModCatalog.installed(), _mod_browser.index)
	var wanted := ["installed", "update"] if _mod_tab.current_tab == 0 else (["available"] if _mod_tab.current_tab == 1 else ["update"])
	var shown: Array = rows.filter(func(row): return wanted.has(row.state))
	for row: Dictionary in shown:
		_mod_rows.add_child(_mod_row(row))
	var selected := _selected_mod_row()
	_mod_buttons.install.disabled = selected.is_empty() or selected.state == "installed" or _mod_browser.busy
	_mod_buttons.install.text = "Update" if selected.get("state", "") == "update" else "Install"
	_mod_buttons.remove.disabled = not selected.get("removable", false) or _mod_browser.busy
	if shown.is_empty():
		_mod_note.text = {
			0: "No mods found, which should not happen - the game ships with some.",
			1: "Everything the project offers is already installed.",
			2: "Every mod you installed is up to date.",
		}.get(_mod_tab.current_tab, "")
		if _mod_browser.index.is_empty():
			_mod_note.text = "The mod list has not been fetched yet. Press Refresh."
		return
	_mod_note.text = "Mods run on whoever hosts the world, so installing one is only needed to host it. Joining a server needs nothing."


func _mod_row(row: Dictionary) -> Control:
	var kinds := {"game": "game", "addon": "add-on", "library": "used by other mods", "example": "example"}
	var kind := str(kinds.get(str(row.get("kind", "addon")), "add-on"))
	var where := ""
	match str(row.state):
		"available": where = "%s · %s" % [kind, _size_text(int(row.get("size", 0)))]
		"update": where = "%s · %s is out" % [kind, row.get("offered", "")]
		_: where = "%s · %s" % [kind, "installed here" if row.get("removable", false) else "comes with the game"]
	var right := str(row.get("version", ""))
	if row.state == "update":
		right = "%s → %s" % [row.version, row.offered]
	elif row.state == "available":
		right = "not installed"
	var subtitle := str(row.get("description", ""))
	return _row(row.id, "%s  %s" % [row.name, ""], "%s\n%s" % [where, subtitle] if not subtitle.is_empty() else where,
		right, _selected_mod == row.id,
		func():
			_selected_mod = row.id
			refresh_mods(),
		func():
			_selected_mod = row.id
			if row.state != "installed":
				_install_selected_mod())


func _selected_mod_row() -> Dictionary:
	for row: Dictionary in ModCatalog.merge(ModCatalog.installed(), _mod_browser.index):
		if row.id == _selected_mod:
			return row
	return {}


func _install_selected_mod() -> void:
	var row := _selected_mod_row()
	if not row.is_empty() and row.state != "installed":
		_mod_browser.install(row)


func _remove_selected_mod() -> void:
	var row := _selected_mod_row()
	if row.is_empty() or not row.get("removable", false):
		return
	var needed: Array = ModCatalog.needed_by(str(row.id), ModCatalog.installed())
	var question := "Remove %s?" % row.name
	if not needed.is_empty():
		question += "\n%s needs it and will not load without it." % ", ".join(PackedStringArray(needed))
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = question + "\nWorlds that use it will not open until it is back."
	dialog.ok_button_text = "Remove"
	dialog.confirmed.connect(func(): _mod_browser.remove(str(row.id), str(row.name)))
	dialog.visibility_changed.connect(func(): if not dialog.visible: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


## A mod went on or came off: the new world dialog and the create page have to see it too.
func _on_catalog_changed() -> void:
	_discover_mods()
	if _pages.has("create"):
		var old: Control = _pages.create
		var rebuilt := _build_create()
		rebuilt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rebuilt.visible = old.visible
		old.get_parent().add_child(rebuilt)
		_pages.create = rebuilt
		old.queue_free()
	refresh_mods()


static func _size_text(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1048576.0) if bytes >= 1048576 else "%d KB" % maxi(1, bytes / 1024)


func _build_create() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.add_child(MenuTheme.heading("Create"))
	page.add_child(_card("Make a mod", "A starter mod in GDScript or JavaScript with a block, an item, recipes, a command, a guide page and a tutorial.",
		"Create a mod…", func(): mod_wizard_requested.emit()))
	page.add_child(_card("Your mods folder", ModLoader.creation_dir(), "Open folder", func():
		# Nothing creates this folder until a mod is installed, and opening a path that is not there does
		# nothing at all - which looks like a broken button.
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ModLoader.creation_dir()))
		OS.shell_open(ProjectSettings.globalize_path(ModLoader.creation_dir()))))
	# docs/ is not in the exported app, so the local file only exists when running from source; released
	# builds open the same page on the site instead of a button that does nothing.
	var docs_local := FileAccess.file_exists("res://docs/api/index.html")
	page.add_child(_card("Mod API reference", "Every function, event and type mods can use.", "Open docs",
		func(): OS.shell_open(ProjectSettings.globalize_path("res://docs/api/index.html") if docs_local
			else "https://github.com/quarrowen/quarrowen/blob/master/docs/api/index.html")))
	if not _addons.is_empty() or not _games.is_empty():
		page.add_child(MenuTheme.muted("Try a mod with developer tools (F8, reload on save):"))
		var flow := HFlowContainer.new()
		page.add_child(flow)
		for m in _games + _addons:
			var b := Button.new()
			b.text = m.name
			b.tooltip_text = str(m.description)
			var mods: String = m.id if m.game else "vanilla,%s" % m.id
			b.pressed.connect(func(): host_mod_requested.emit(mods))
			flow.add_child(b)
	return page


func _card(title: String, body: String, action: String, callback: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.PANEL_LIGHT, 10, 14, 12))
	var row := HBoxContainer.new()
	panel.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 18)
	text.add_child(heading)
	var description := MenuTheme.muted(body, 13)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(description)
	var button := Button.new()
	button.text = action
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(callback)
	row.add_child(button)
	return panel


# --- Settings -----------------------------------------------------------------------------------

func _build_settings() -> Control:
	var screen := SettingsScreen.new()
	var account := VBoxContainer.new()
	account.add_theme_constant_override("separation", 12)
	account.add_child(MenuTheme.heading("Identity", 20))
	_identity_label = MenuTheme.muted("")
	_identity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_identity_label.custom_minimum_size.x = 300
	account.add_child(_identity_label)
	var about := MenuTheme.muted("Your identity key is your account on every server. Export it (encrypted with a passphrase) to play from another computer.", 13)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size.x = 300
	account.add_child(about)
	_passphrase_edit = _labeled(account, "Passphrase", LineEdit.new())
	_passphrase_edit.secret = true
	_passphrase_edit.placeholder_text = "at least %d characters" % Identity.MIN_PASSPHRASE_LENGTH
	var identity_row := HBoxContainer.new()
	account.add_child(identity_row)
	for mode in ["Export identity…", "Import identity…"]:
		var button := Button.new()
		button.text = mode
		button.pressed.connect(_pick_identity_file.bind(mode.begins_with("Export")))
		identity_row.add_child(button)
	account.add_child(HSeparator.new())
	account.add_child(MenuTheme.heading("Hosting", 20))
	var port_edit: SpinBox = _labeled(account, "Port", SpinBox.new())
	port_edit.min_value = 1024
	port_edit.max_value = 65534
	port_edit.value = port
	port_edit.value_changed.connect(func(v): port = int(v))
	account.add_child(MenuTheme.muted("Worlds you play are hosted on this port (and the next one answers server list pings).", 13))
	account.add_child(HSeparator.new())
	account.add_child(MenuTheme.heading("Version", 20))
	account.add_child(MenuTheme.muted("Quarrowen %s" % Protocol.GAME_VERSION, 14))
	var independent := MenuTheme.muted("Quarrowen is an independent project and is not affiliated with, endorsed by or connected to "
		+ "Mojang Synergies AB, Microsoft or Roblox Corporation. Minecraft is a trademark of Mojang Synergies AB; "
		+ "Roblox is a trademark of Roblox Corporation.\n\nBuilt from scratch with Claude Code.", 12)
	independent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	independent.custom_minimum_size.x = 300
	account.add_child(independent)
	var update_button := Button.new()
	update_button.text = "Check for updates"
	update_button.pressed.connect(func(): check_updates.emit())
	account.add_child(update_button)
	account.add_child(MenuTheme.muted("Updates are downloaded from the project's own release page, never from a game server.", 12))
	screen.add_tab("Account", account)
	return screen


func _refresh_identity() -> void:
	var exists := FileAccess.file_exists(Identity.path_for())
	_identity_label.text = "Identity: %s" % (Identity.player_id(Identity.load_or_create()) if exists else "created when you first join")


func _pick_identity_file(exporting: bool) -> void:
	if _passphrase_edit.text.length() < Identity.MIN_PASSPHRASE_LENGTH:
		show_message("Enter a passphrase of at least %d characters first" % Identity.MIN_PASSPHRASE_LENGTH, "error")
		return
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.json ; Quarrowen identity"])
	dialog.current_file = "quarrowen-identity.json"
	dialog.file_selected.connect(func(path: String):
		identity_file_chosen.emit(path, exporting, _passphrase_edit.text)
		_passphrase_edit.text = ""
		_refresh_identity()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


# --- Helpers ------------------------------------------------------------------------------------

## A selectable list row: title, subtitle and a right-hand note. Click selects, double click activates.
func _row(_key: String, title: String, subtitle: String, right: String, selected: bool, on_select: Callable, on_activate: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.PANEL_SELECTED if selected else MenuTheme.PANEL_LIGHT, 10, 14, 10,
		MenuTheme.ACCENT if selected else Color(0, 0, 0, 0)))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				on_activate.call()
			else:
				on_select.call())
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 18)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(t)
	var s := MenuTheme.muted(subtitle, 13)
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(s)
	var r := MenuTheme.muted(right, 14)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(r)
	panel.set_meta("right", r)
	return panel


func _labeled(parent: Control, label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 110
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)
	return control


func _prompt(title: String, label: String, value: String, callback: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	dialog.add_child(box)
	var edit: LineEdit = _labeled(box, label, LineEdit.new())
	edit.text = value
	dialog.confirmed.connect(func():
		callback.call(edit.text)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	edit.grab_focus()
	edit.select_all()
