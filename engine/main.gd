extends Node
## Entry point. Runs a dedicated server with `-- --server`, otherwise shows the main menu.
##
## User args (after `--`):
##   --server              run the dedicated server instead (same options as engine/server_main.gd)
##   --port=24565          port to connect to / host on
##   --connect=1.2.3.4     skip the menu and join a server
##   --host=my_game        skip the menu, start a local server for that game and join it (my_game,my_addon: with add-ons)
##   --dev                 with --host: developer mode (dev tools for everyone, reload mods on save)
##   --name=Robin          player name for --connect / --host
##   --export-identity=file.json   write your identity, encrypted, and quit
##   --import-identity=file.json   replace your identity with an exported one and quit
##                         both read the passphrase from QW_IDENTITY_PASSPHRASE (or --passphrase=)

const GameClient = preload("res://engine/client/game_client.gd")
const WorldList = preload("res://engine/client/menu/world_list.gd")
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
const Housekeeping = preload("res://engine/client/housekeeping.gd")
const UpdateCheck = preload("res://engine/client/menu/update_check.gd")
const SocialClient = preload("res://engine/client/social/social_client.gd")
const InviteCode = preload("res://engine/shared/invite_code.gd")
const KnownServers = preload("res://engine/net/known_servers.gd")

const DEFAULT_PORT := 24565

var _args := {}
var _server_pid := -1
var _client: Node
var _menu: MainMenu
var _backdrop: MenuBackdrop
var _backdrop_fallback: ColorRect
var _social: SocialClient
var _updates: Node
## A server to go to once the current game has closed (joining a friend from in game).
var _pending_join := {}


func _ready() -> void:
	_args = _parse_args()
	if _args.has("server"):
		_run_dedicated_server()
		return
	# Caches back inside their budgets, before the game has a chance to add to them. Only caches: see
	# engine/client/housekeeping.gd for what is never touched.
	var freed := Housekeeping.sweep()
	if freed > 0:
		print("[main] Freed %s of cached downloads" % Housekeeping.human(freed))
	if _args.has("export-identity") or _args.has("import-identity"):
		get_tree().quit(_identity_cli())
		return
	get_tree().auto_accept_quit = false
	_build_menu()
	if _args.has("connect"):
		_start_client(_args.connect, int(_args.get("port", DEFAULT_PORT)), _args.get("name", "Player"), "")
	elif _args.has("host"):
		# No default game to fall back on. "vanilla" stood here until that mod was deleted on
		# 21 September 2026, so a bare --host started a server for a game that is not installed and
		# reported it as a missing mod. Say what is actually wrong instead.
		if _args.host == "true":
			printerr("[client] --host needs the game to host: --host=<mod id> (add-ons: --host=<game>,<add-on>).")
			get_tree().quit(2)
			return
		var game: String = _args.host
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
	var passphrase := OS.get_environment("QW_IDENTITY_PASSPHRASE")
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
	# **A real random token, and not on the command line.** It was two `randi()` calls - a
	# non-cryptographic PRNG seeded from the clock, so guessable - and it was passed as
	# `--admin-token=...`, which puts it in `ps` for every other user on the machine. This token makes
	# whoever holds it an admin of the world and can shut it down. The server reads `QW_ADMIN_TOKEN`
	# for any option, so the environment carries it instead: inherited by the child we are about to
	# start, invisible to everybody else. (2026-09-24)
	var token := Crypto.new().generate_random_bytes(24).hex_encode()
	OS.set_environment("QW_ADMIN_TOKEN", token)
	var args := PackedStringArray()
	if not OS.has_feature("template"):
		# Running from the editor binary: point it at this project and its server scene.
		args.append_array(["--path", ProjectSettings.globalize_path("res://"), "--headless", "res://scenes/server.tscn", "--"])
	else:
		# Exported builds cannot be given a scene on the command line: --server switches to it (see _ready).
		args.append_array(["--headless", "--", "--server"])
	args.append_array(["--mods=%s" % game, "--port=%d" % port])
	args.append_array(extra)
	_server_pid = OS.create_process(OS.get_executable_path(), args)
	if _server_pid <= 0:
		_show_menu("Your world could not be started. Try closing the game and opening it again.")
		return
	print("[menu] Started local %s server (pid %d)" % [game, _server_pid])
	_start_client("127.0.0.1", port, player_name, token)


func _stop_local_server() -> void:
	if _server_pid > 0:
		if OS.is_process_running(_server_pid):
			OS.kill(_server_pid)
		_server_pid = -1


func _start_client(address: String, port: int, player_name: String, token: String, ticket := {}) -> void:
	_menu.visible = false
	_backdrop_fallback.visible = false
	_remove_backdrop()
	_client = GameClient.new()
	_client.server_address = address
	_client.server_port = port
	_client.player_name = player_name
	_client.admin_token = token
	_client.transfer_ticket = ticket
	_client.exited.connect(_on_client_exited)
	_client.social = _social
	_client.join_friend_requested.connect(func(to_address: String, to_port: int, to_name: String):
		_pending_join = {"address": to_address, "port": to_port, "name": to_name, "player": _client.player_name}
		_client.disconnect_from_server())
	# A server sending us on (portal, /server, a mod): leave and connect there with the ticket.
	_client.transfer_requested.connect(func(to_address: String, to_port: int, to_name: String, ticket: Dictionary):
		_pending_join = {"address": to_address, "port": to_port, "name": to_name, "ticket": ticket, "player": _client.player_name}
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
	var ended := {}
	if _client:
		ended = {"kind": _client.exit_kind, "address": _client.server_address, "port": _client.server_port}
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
		_start_client(target.address, target.port, str(target.get("player", _menu.player_name)), "", target.get("ticket", {}))
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
		var local_problem := _local_start_error() if ended.get("kind", "") == "connect" else ""
		_stop_local_server()
		if not local_problem.is_empty():
			# The world's own process said why it gave up; that is far more use than an address.
			_show_menu(local_problem)
			return
	_show_menu(message, ended)


## What the world's own process said when it refused to start, or "".
func _local_start_error() -> String:
	# Through WorldList rather than a bare `user://`, so QW_DATA_DIR and QW_USER_DIR both reach it.
	var path := WorldList.dir().path_join("last_start_error.txt")
	if not FileAccess.file_exists(path):
		return ""
	var reason := FileAccess.get_file_as_string(path).strip_edges()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return reason


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
	_updates = UpdateCheck.new()
	_updates.name = "Updates"
	_updates.message.connect(func(text: String, kind: String, action_text: String, action: Callable):
		if _menu != null:
			_menu.show_message(text, kind, action_text, action))
	add_child(_updates)
	_social = SocialClient.new()
	_social.name = "Social"
	add_child(_social)
	_menu = MainMenu.new()
	_menu.social = _social
	var saved_name := str(ClientSettings.shared().get_value("player/name")).strip_edges()
	if saved_name.is_empty():
		# Keep the first generated name instead of rolling a new one every launch: a child who never
		# notices the name field would otherwise be a different player each day, and an allowlisted name
		# (how a family server is set up) would stop letting them in.
		saved_name = "Player%d" % (randi() % 1000)
		ClientSettings.shared().set_value("player/name", saved_name)
	_menu.player_name = _args.get("name", saved_name)
	_menu.port = int(_args.get("port", DEFAULT_PORT))
	add_child(_menu)
	_social.player_name = _menu.player_name
	_menu.check_updates.connect(func(): _updates.check(true))
	if ClientSettings.shared().get_value("network/auto_update"):
		_updates.check()
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
		var result := export_identity(path, passphrase) if exporting else import_identity(path, passphrase)
		_menu.show_message(result, "error" if result.begins_with("Error") else "success"))
	_menu.quit_requested.connect(func(): get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST))
	_add_backdrop()


## The live world behind the menu (not in headless runs such as tests).
func _add_backdrop() -> void:
	if _backdrop != null or DisplayServer.get_name() == "headless" or OS.get_environment("QW_MENU_BACKDROP") == "0" \
			or not ClientSettings.shared().get_value("graphics/menu_backdrop"):
		return
	# Which game to generate it from. The backdrop used to hardcode "vanilla"; with no game installed
	# there is nothing to show, so leave the still image up rather than start a server that will only
	# fail. (2026-09-21)
	var installed: Array = _menu.installed_games()
	if installed.is_empty():
		return
	_backdrop = MenuBackdrop.new()
	_backdrop.game = String(installed[0].id)
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
	if not result.game:
		# An add-on adds to a game rather than being one, so on its own there is nothing to add to.
		dialog.dialog_text += "\n\nThis is an add-on, so hosting it alone gives an empty world. Run it with a game once you have one installed: --host=<game>,%s" % id
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
		# Just the new mod. This used to prepend "vanilla" for an add-on, which is a mod that no
		# longer exists; an add-on hosted alone gives an empty world, which the dialog now says.
		var mods := id
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


## `ended`: {kind, address, port} of the game that just closed, to offer the right fix with the message.
func _show_menu(message: String, ended := {}) -> void:
	_menu.visible = true
	_backdrop_fallback.visible = true
	_backdrop_fallback.modulate.a = 1.0
	if message.is_empty() or message.begins_with("Reloading"):
		_menu.show_message(message)
	elif ended.get("kind", "") == "identity":
		var endpoint := "%s:%d" % [ended.address, ended.port]
		_menu.show_message(message + " Only trust the new identity if you know the server was reset.", "error", "Trust new identity", func():
			KnownServers.forget(endpoint)
			_start_client(ended.address, ended.port, _menu.player_name, ""))
	elif message.contains("Please update your client"):
		# The server runs a newer version: offer the update from the client's own source, never the server's.
		_menu.show_message(message, "error", "Update now", func(): _updates.check(true))
		_updates.check()
	else:
		_menu.show_message(message, "error")
	_menu.show_page(_menu._page)
	_add_backdrop()
