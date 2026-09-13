extends Node
## Entry point. Runs a dedicated server with `-- --server`, otherwise shows the main menu.
##
## User args (after `--`):
##   --server              run the dedicated server instead (same options as engine/server_main.gd)
##   --port=24565          port to connect to / host on
##   --connect=1.2.3.4     skip the menu and join a server
##   --host=skyblock       skip the menu, start a local server for that game and join it
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

const DEFAULT_PORT := 24565
const DEFAULT_GAME := "vanilla"

var _args := {}
var _server_pid := -1
var _client: Node
var _menu: Control
var _name_edit: LineEdit
var _address_edit: LineEdit
var _port_edit: SpinBox
var _game_select: OptionButton
var _message_label: Label
var _games: Array = []
var _identity_label: Label
var _passphrase_edit: LineEdit


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
		_host(game, int(_args.get("port", DEFAULT_PORT)), _args.get("name", "Player"))


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


func _host(game: String, port: int, player_name: String) -> void:
	_stop_local_server()
	var token := "%x%x" % [randi(), randi()]
	var args := PackedStringArray()
	if not OS.has_feature("template"):
		# Running from the editor binary: point it at this project.
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--headless", "res://scenes/server.tscn", "--", "--mods=%s" % game, "--port=%d" % port, "--admin-token=%s" % token])
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
	_client = GameClient.new()
	_client.server_address = address
	_client.server_port = port
	_client.player_name = player_name
	_client.admin_token = token
	_client.exited.connect(_on_client_exited)
	add_child(_client)


func _on_client_exited(message: String) -> void:
	if _client:
		_client.queue_free()
		_client = null
	if _server_pid > 0:
		# The host asked the server to save and quit; kill it only if it is still around.
		await get_tree().create_timer(1.0).timeout
		_stop_local_server()
	_show_menu(message)


# --- Menu ---------------------------------------------------------------------------------------

func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)

	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.13, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(400, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "VoxelCraft"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)

	_name_edit = _labeled(box, "Name", LineEdit.new())
	_name_edit.text = _args.get("name", "Player%d" % (randi() % 1000))
	var avatar_button := Button.new()
	avatar_button.text = "Customize avatar"
	avatar_button.custom_minimum_size.y = 36
	avatar_button.pressed.connect(_open_avatar_editor)
	box.add_child(avatar_button)
	_port_edit = _labeled(box, "Port", SpinBox.new())
	_port_edit.min_value = 1024
	_port_edit.max_value = 65535
	_port_edit.value = int(_args.get("port", DEFAULT_PORT))

	box.add_child(HSeparator.new())
	_address_edit = _labeled(box, "Server address", LineEdit.new())
	_address_edit.text = "127.0.0.1"
	var join_button := Button.new()
	join_button.text = "Join server"
	join_button.custom_minimum_size.y = 44
	join_button.pressed.connect(func(): _start_client(_address_edit.text.strip_edges(), int(_port_edit.value), _name_edit.text, ""))
	box.add_child(join_button)

	box.add_child(HSeparator.new())
	_game_select = _labeled(box, "Game", OptionButton.new())
	var available := ModLoader.discover(ModLoader.search_dirs(PackedStringArray()))
	for id: String in available:
		if available[id].game:
			_games.append(available[id])
	_games.sort_custom(func(a, b): return a.name < b.name)
	for game in _games:
		_game_select.add_item(game.name)
	var host_button := Button.new()
	host_button.text = "Host game (local server)"
	host_button.custom_minimum_size.y = 44
	host_button.disabled = _games.is_empty()
	host_button.pressed.connect(func(): _host(_games[_game_select.selected].id, int(_port_edit.value), _name_edit.text))
	box.add_child(host_button)
	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.modulate = Color(1, 1, 1, 0.7)
	box.add_child(description)
	_game_select.item_selected.connect(func(i): description.text = _games[i].description)
	if not _games.is_empty():
		description.text = _games[0].description

	box.add_child(HSeparator.new())
	_identity_label = Label.new()
	_identity_label.modulate = Color(1, 1, 1, 0.7)
	_identity_label.tooltip_text = "Your identity key is your account on every server. Export it to play from another computer."
	_identity_label.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_identity_label)
	_refresh_identity_label()
	_passphrase_edit = _labeled(box, "Passphrase", LineEdit.new())
	_passphrase_edit.secret = true
	_passphrase_edit.placeholder_text = "for identity export / import"
	var identity_row := HBoxContainer.new()
	box.add_child(identity_row)
	for mode in ["Export identity...", "Import identity..."]:
		var button := Button.new()
		button.text = mode
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_pick_identity_file.bind(mode.begins_with("Export")))
		identity_row.add_child(button)

	box.add_child(HSeparator.new())
	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size.y = 44
	quit_button.pressed.connect(func(): get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST))
	box.add_child(quit_button)

	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.6))
	box.add_child(_message_label)


## Your portable look: built-in cosmetics, saved on this computer and shown on every server that allows them.
func _open_avatar_editor() -> void:
	var registry := Cosmetics.new()
	var editor := AvatarEditor.new()
	editor.setup(registry, LookBuilder.new(registry), PlayerRig.default_rig(), _name_edit.text, AvatarStore.load_avatar())
	editor.done.connect(func(edited: Dictionary):
		AvatarStore.save_avatar(registry.sanitize_avatar(edited))
		editor.queue_free())
	editor.cancelled.connect(editor.queue_free)
	add_child(editor)


func _refresh_identity_label() -> void:
	var exists := FileAccess.file_exists(Identity.path_for())
	_identity_label.text = "Identity: %s" % (Identity.player_id(Identity.load_or_create()) if exists else "created when you first join")


func _pick_identity_file(exporting: bool) -> void:
	if _passphrase_edit.text.length() < Identity.MIN_PASSPHRASE_LENGTH:
		_message_label.text = "Enter a passphrase of at least %d characters first" % Identity.MIN_PASSPHRASE_LENGTH
		return
	var dialog := FileDialog.new()
	dialog.use_native_dialog = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.json ; VoxelCraft identity"])
	dialog.current_file = "voxelcraft-identity.json"
	dialog.file_selected.connect(func(path: String):
		_message_label.text = "Working..."
		await get_tree().process_frame
		_message_label.text = export_identity(path, _passphrase_edit.text) if exporting else import_identity(path, _passphrase_edit.text)
		_passphrase_edit.text = ""
		_refresh_identity_label()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


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
	_message_label.text = message
