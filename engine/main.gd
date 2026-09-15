extends Node
## Entry point. Runs a dedicated server with `-- --server`, otherwise shows the main menu.
##
## User args (after `--`):
##   --server              run the dedicated server instead (same options as engine/server_main.gd)
##   --port=24565          port to connect to / host on
##   --connect=1.2.3.4     skip the menu and join a server
##   --host=skyblock       skip the menu, start a local server for that game and join it (vanilla,my_mod: with add-ons)
##   --dev                 with --host: developer mode (dev tools for everyone, reload mods on save)
##   --name=Steve          player name for --connect / --host
##   --export-identity=file.json   write your identity, encrypted, and quit
##   --import-identity=file.json   replace your identity with an exported one and quit
##                         both read the passphrase from VOXEL_IDENTITY_PASSPHRASE (or --passphrase=)

const GameClient = preload("res://engine/client/game_client.gd")
const ModLoader = preload("res://engine/server/mod_loader.gd")
const Identity = preload("res://engine/shared/identity.gd")
const Cosmetics = preload("res://engine/shared/cosmetics.gd")
const PlayerRig = preload("res://engine/shared/player_rig.gd")
const LookBuilder = preload("res://engine/client/avatar/look_builder.gd")
const AvatarStore = preload("res://engine/client/avatar/avatar_store.gd")
const AvatarEditor = preload("res://engine/client/avatar/avatar_editor.gd")
const ModTemplates = preload("res://engine/server/mod_templates.gd")
const CreationLibrary = preload("res://engine/client/creation_library.gd")
const MainMenu = preload("res://engine/client/menu/main_menu.gd")
const MenuBackdrop = preload("res://engine/client/menu/menu_backdrop.gd")
const MenuTheme = preload("res://engine/client/menu/menu_theme.gd")
const ClientSettings = preload("res://engine/client/settings/client_settings.gd")
const SocialClient = preload("res://engine/client/social/social_client.gd")
const InviteCode = preload("res://engine/shared/invite_code.gd")

const DEFAULT_PORT := 24565
const DEFAULT_GAME := "vanilla"

var _args := {}
var _server_pid := -1
var _client: Node
var _menu: MainMenu
var _backdrop: MenuBackdrop
var _backdrop_fallback: ColorRect
var _social: SocialClient
## A server to go to once the current game has closed (joining a friend from in game).
var _pending_join := {}


func _ready() -> void:
	_args = _parse_args()
	if _args.has("server"):
		_run_dedicated_server()
		return
	if _args.has("export-identity") or _args.has("import-identity"):
		get_tree().quit(_identity_cli())
		return
	get_tree().auto_accept_quit = false
	_build_menu()
	if _args.has("connect"):
		_start_client(_args.connect, int(_args.get("port", DEFAULT_PORT)), _args.get("name", "Player"), "")
	elif _args.has("host"):
		var game: String = _args.host if _args.host != "true" else DEFAULT_GAME
		_host(game, int(_args.get("port", DEFAULT_PORT)), _args.get("name", "Player"), PackedStringArray(["--dev"]) if _args.has("dev") else PackedStringArray())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _client and _server_pid > 0:
			await _client.disconnect_from_server()
		_stop_local_server()
		get_tree().quit()


static func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1] if parts.size() > 1 else "true"
	return out


func _identity_cli() -> int:
	var passphrase := OS.get_environment("VOXEL_IDENTITY_PASSPHRASE")
	passphrase = _args.get("passphrase", passphrase)
	var result := export_identity(_args["export-identity"], passphrase) if _args.has("export-identity") \
		else import_identity(_args["import-identity"], passphrase)
	if result.begins_with("Error"):
		printerr(result)
		return 1
	print(result)
	return 0


## Returns a status message; failures start with "Error".
static func export_identity(path: String, passphrase: String) -> String:
	if passphrase.length() < Identity.MIN_PASSPHRASE_LENGTH:
		return "Error: the passphrase must be at least %d characters" % Identity.MIN_PASSPHRASE_LENGTH
	var key := Identity.load_or_create()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "Error: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())]
	file.store_string(Identity.export_encrypted(key, passphrase))
	file.close()
	return "Exported identity %s to %s" % [Identity.player_id(key), path]


static func import_identity(path: String, passphrase: String) -> String:
	if not FileAccess.file_exists(path):
		return "Error: %s does not exist" % path
	var result := Identity.import_encrypted(FileAccess.get_file_as_string(path), passphrase)
	if result.has("error"):
		return "Error: %s" % result.error
	var err := Identity.install(result.key)
	if err != OK:
		return "Error: could not save the identity (%s)" % error_string(err)
	return "Imported identity %s (any different previous identity was kept as a .bak file)" % result.player_id


func _run_dedicated_server() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/server.tscn")


## `extra`: more server arguments (e.g. --dev, --mods-dir=...).
func _host(game: String, port: int, player_name: String, extra := PackedStringArray()) -> void:
	_stop_local_server()
	var token := "%x%x" % [randi(), randi()]
	var args := PackedStringArray()
	if not OS.has_feature("template"):
		# Running from the editor binary: point it at this project.
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--headless", "res://scenes/server.tscn", "--", "--mods=%s" % game, "--port=%d" % port, "--admin-token=%s" % token])
	args.append_array(extra)
	_server_pid = OS.create_process(OS.get_executable_path(), args)
	if _server_pid <= 0:
		_show_menu("Failed to launch local server process")
		return
	print("[menu] Started local %s server (pid %d)" % [game, _server_pid])
	_start_client("127.0.0.1", port, player_name, token)


func _stop_local_server() -> void:
	if _server_pid > 0:
		if OS.is_process_running(_server_pid):
			OS.kill(_server_pid)
		_server_pid = -1


func _start_client(address: String, port: int, player_name: String, token: String) -> void:
	_menu.visible = false
	_backdrop_fallback.visible = false
	_remove_backdrop()
	_client = GameClient.new()
	_client.server_address = address
	_client.server_port = port
	_client.player_name = player_name
	_client.admin_token = token
	_client.exited.connect(_on_client_exited)
	_client.social = _social
	_client.join_friend_requested.connect(func(to_address: String, to_port: int, to_name: String):
		_pending_join = {"address": to_address, "port": to_port, "name": to_name}
		_client.disconnect_from_server())
	add_child(_client)
	_set_presence(address, port, address)


## Tells friends where we play. A world hosted here is shared by its local network address (only
## friends on the same network can reach it); without one it is not shared.
func _set_presence(address: String, port: int, server_name: String) -> void:
	if address in ["127.0.0.1", "localhost", "::1"]:
		address = InviteCode.local_address()
	_social.current_server = {"name": server_name, "address": address, "port": port, "code": ""} if not address.is_empty() else {}
	_social.refresh()


func _process(_delta: float) -> void:
	# The server's real name arrives with the welcome.
	if _client != null and _client._welcomed and not _social.current_server.is_empty() \
			and _social.current_server.name != str(_client.server_info.get("name", _social.current_server.name)):
		_social.current_server.name = str(_client.server_info.name)
		_social.refresh()


func _on_client_exited(message: String) -> void:
	var reconnect: Dictionary = {}
	if _client:
		if _client.reload_pending:
			reconnect = {"address": _client.server_address, "port": _client.server_port, "name": _client.player_name, "token": _client.admin_token}
		_client.queue_free()
		_client = null
	_social.current_server = {}
	_social.refresh()
	if not _pending_join.is_empty():
		var target := _pending_join
		_pending_join = {}
		if _server_pid > 0:
			await get_tree().create_timer(1.0).timeout
			_stop_local_server()
		_start_client(target.address, target.port, _menu.player_name, "")
		return
	if not reconnect.is_empty():
		# A full reload: the server is restarting; the new client retries until it is back.
		_show_menu("Reloading mods… reconnecting")
		await get_tree().create_timer(2.0).timeout
		_start_client(reconnect.address, reconnect.port, reconnect.name, reconnect.token)
		return
	if _server_pid > 0:
		# The host asked the server to save and quit; kill it only if it is still around.
		await get_tree().create_timer(1.0).timeout
		_stop_local_server()
	_show_menu(message)


# --- Menu ---------------------------------------------------------------------------------------

func _build_menu() -> void:
	var settings = ClientSettings.shared()
	settings.apply_display(get_window())
	settings.apply_audio()
	settings.changed.connect(_on_setting_changed)
	_backdrop_fallback = ColorRect.new()
	_backdrop_fallback.color = Color(0.1, 0.13, 0.18)
	_backdrop_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop_fallback)
	_social = SocialClient.new()
	_social.name = "Social"
	add_child(_social)
	_menu = MainMenu.new()
	_menu.social = _social
	_menu.player_name = _args.get("name", "Player%d" % (randi() % 1000))
	_menu.port = int(_args.get("port", DEFAULT_PORT))
	add_child(_menu)
	_social.player_name = _menu.player_name
	_social.notice.connect(func(text: String):
		if _client != null:
			_client.notify("✉ " + text)
		elif _menu.visible:
			_menu.show_message(text))
	_social.refresh()
	_menu.play_world.connect(func(world_id: String, mods: Array, dev: bool):
		var extra := PackedStringArray(["--world=%s" % world_id])
		if dev:
			extra.append("--dev")
		_host(",".join(mods), _menu.port, _menu.player_name, extra))
	_menu.join_server.connect(func(address: String, port: int, _server_name: String):
		_start_client(address, port, _menu.player_name, ""))
	_menu.avatar_requested.connect(_open_avatar_editor)
	_menu.mod_wizard_requested.connect(_open_mod_wizard)
	_menu.host_mod_requested.connect(func(mods: String):
		_host(mods, _menu.port, _menu.player_name, PackedStringArray(["--dev", "--world=dev_%s" % mods.replace(",", "_")])))
	_menu.identity_file_chosen.connect(func(path: String, exporting: bool, passphrase: String):
		_menu.show_message(export_identity(path, passphrase) if exporting else import_identity(path, passphrase)))
	_menu.quit_requested.connect(func(): get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST))
	_add_backdrop()


## The live world behind the menu (not in headless runs such as tests).
func _add_backdrop() -> void:
	if _backdrop != null or DisplayServer.get_name() == "headless" or OS.get_environment("VOXEL_MENU_BACKDROP") == "0" \
			or not ClientSettings.shared().get_value("graphics/menu_backdrop"):
		return
	_backdrop = MenuBackdrop.new()
	_backdrop.avatar_look = AvatarStore.load_avatar()
	_backdrop.player_name = _menu.player_name
	_backdrop.motion = ClientSettings.shared().get_value("accessibility/menu_motion")
	_backdrop.ready_to_show.connect(func():
		var tween := create_tween()
		tween.tween_property(_backdrop_fallback, "modulate:a", 0.0, 0.8)
		tween.tween_callback(func(): _backdrop_fallback.visible = false))
	add_child(_backdrop)
	move_child(_backdrop, 0)


func _on_setting_changed(key: String) -> void:
	var settings = ClientSettings.shared()
	match key:
		"graphics/window_mode", "graphics/vsync", "graphics/max_fps", "interface/scale":
			settings.apply_display(get_window())
		"audio/volume", "audio/world", "audio/interface":
			settings.apply_audio()
		"graphics/menu_backdrop":
			if _client == null and settings.get_value(key):
				_add_backdrop()
			elif not settings.get_value(key):
				_remove_backdrop()
				_backdrop_fallback.visible = true
				_backdrop_fallback.modulate.a = 1.0
		"accessibility/menu_motion":
			if _backdrop != null:
				_backdrop.motion = settings.get_value(key)


func _remove_backdrop() -> void:
	if _backdrop != null:
		_backdrop.queue_free()
		_backdrop = null


## Your portable look: built-in cosmetics, saved on this computer and shown on every server that allows them.
func _open_avatar_editor() -> void:
	var registry := Cosmetics.new()
	var images := {}
	CreationLibrary.register_all(registry, images)
	var editor := AvatarEditor.new()
	editor.setup(registry, LookBuilder.new(registry, images, CreationLibrary.read_model), PlayerRig.default_rig(), _menu.player_name,
		AvatarStore.load_avatar(), {"creations": true, "author": Identity.player_id(Identity.load_or_create())})
	editor.done.connect(func(edited: Dictionary):
		AvatarStore.save_avatar(registry.sanitize_avatar(edited))
		if _backdrop != null:
			_backdrop.refresh_avatar(AvatarStore.load_avatar(), _menu.player_name)
		_menu.visible = true
		editor.queue_free())
	editor.cancelled.connect(func():
		_menu.visible = true
		editor.queue_free())
	_menu.visible = false
	add_child(editor)


## "Create a mod": name, language and kind; writes a starter mod and offers to host it in developer mode.
func _open_mod_wizard() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Create a mod"
	dialog.ok_button_text = "Create"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.custom_minimum_size = Vector2(540, 0)  # wrapping labels need a width, or the dialog grows very tall
	dialog.add_child(box)
	var intro := Label.new()
	intro.text = "A starter mod with a block, an item, recipes, a command,\na guide page and a tutorial, ready to edit."
	box.add_child(intro)
	var name_edit: LineEdit = _labeled(box, "Name", LineEdit.new())
	name_edit.placeholder_text = "My Cool Mod"
	var id_edit: LineEdit = _labeled(box, "Id", LineEdit.new())
	id_edit.placeholder_text = "my_cool_mod"
	var id_touched := [false]
	name_edit.text_changed.connect(func(t):
		if not id_touched[0]:
			id_edit.text = ModTemplates.id_from_name(t))
	id_edit.text_changed.connect(func(_t): id_touched[0] = true)
	var language: OptionButton = _labeled(box, "Language", OptionButton.new())
	language.add_item("GDScript")
	language.add_item("JavaScript")
	var kind: OptionButton = _labeled(box, "Kind", OptionButton.new())
	kind.add_item("Add-on (play it with Vanilla)")
	kind.add_item("Game (its own world)")
	var author: LineEdit = _labeled(box, "Author", LineEdit.new())
	author.text = _menu.player_name
	var where := Label.new()
	where.text = "Saved in %s" % ModLoader.creation_dir()
	where.modulate = Color(1, 1, 1, 0.6)
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	where.tooltip_text = ModLoader.creation_dir()
	box.add_child(where)
	var status := Label.new()
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	box.add_child(status)
	dialog.dialog_hide_on_ok = false
	dialog.confirmed.connect(func():
		var result := ModTemplates.create(ModLoader.creation_dir(), {"id": id_edit.text.strip_edges(), "name": name_edit.text,
			"language": "javascript" if language.selected == 1 else "gdscript", "kind": "game" if kind.selected == 1 else "addon", "author": author.text})
		if not result.ok:
			status.text = result.error
			return
		dialog.queue_free()
		_mod_created(result, id_edit.text.strip_edges()))
	dialog.canceled.connect(dialog.queue_free)
	_menu.add_child(dialog)
	dialog.popup_centered()
	name_edit.grab_focus()


func _mod_created(result: Dictionary, id: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Mod created"
	dialog.dialog_text = "%s\n\n%d files, including %s and README.md. Host it now with developer mode: edit and save to reload, F8 for the dev tools." % [
		result.dir, result.files.size(), "main.js" if result.language == "javascript" else "main.gd"]
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(560, 0)
	dialog.size = Vector2i(560, 200)
	dialog.ok_button_text = "Host with dev tools"
	dialog.cancel_button_text = "Later"
	dialog.add_button("Open folder", false, "open")
	dialog.custom_action.connect(func(action):
		if action == "open":
			OS.shell_open(ProjectSettings.globalize_path(result.dir)))
	dialog.confirmed.connect(func():
		dialog.queue_free()
		var mods := id if result.game else "vanilla,%s" % id
		_host(mods, _menu.port, _menu.player_name, PackedStringArray(["--dev", "--world=dev_%s" % id])))
	dialog.canceled.connect(dialog.queue_free)
	_menu.add_child(dialog)
	dialog.popup_centered()


func _labeled(parent: Control, label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 130
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)
	return control


func _show_menu(message: String) -> void:
	_menu.visible = true
	_backdrop_fallback.visible = true
	_backdrop_fallback.modulate.a = 1.0
	_menu.show_message(message)
	_menu.show_page(_menu._page)
	_add_backdrop()
