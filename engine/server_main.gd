extends Node
## Dedicated server entry point (scenes/server.tscn). Contains no client code, so a server export or
## container only needs engine/shared, engine/server and engine/net.
##
## Every option can come from a CLI arg (after `--`) or an environment variable; CLI wins.
##   --port=24565          QW_PORT
##   --name="My Server"    QW_NAME          shown in server lists
##   --motd="Welcome!"     QW_MOTD          message shown in server lists
##   --query-port=24566    QW_QUERY_PORT    UDP port answering status queries (default port + 1, 0 = off)
##   --hub=https://...     QW_HUB           list this server on a hub (services/hub)
##   --public-address=host QW_PUBLIC_ADDRESS the address the hub lists (default: where the announce comes from)
##   --tags=pvp,modded     QW_TAGS          tags shown in the server browser
##   --allowlist=Ann,Ben   QW_ALLOWLIST     a private server: only these players (and admins) may join (/allow)
##   --chat-filter=on      QW_CHAT_FILTER   mask swear words in chat (the chat_filter gameplay rule)
##   --anticheat=kick      QW_ANTICHEAT     kick | log (only tell moderators) | off
##   --default-role=member QW_DEFAULT_ROLE  the role every player has (visitor: look around and chat, no building)
##   --max-players=64      QW_MAX_PLAYERS
##   --mods=vanilla        QW_MODS          comma-separated; dependencies load automatically
##   --mods-dir=/mods      QW_MODS_DIR      comma-separated folders searched before bundled mods
##   --data-dir=/data      QW_DATA_DIR      world saves (default user://worlds)
##   --world=name          QW_WORLD         defaults to the first mod id
##   --mod-settings=path   QW_MOD_SETTINGS  mod settings as a JSON file or inline JSON
##                                             ({"mod": {"setting": value}}); the data folder's
##                                             mod_settings.json is read anyway
##   --seed=123            QW_SEED          seed for a new world
##   --metrics=10          QW_METRICS       print tick/bandwidth stats every N seconds
##   --admin-token=xyz     QW_ADMIN_TOKEN   token the local host uses to shut down / become admin
##   --admins=a,b          QW_ADMINS        admin player ids (see /whoami) or names
##   --backup-interval=60  QW_BACKUP_INTERVAL  minutes between automatic world backups (0 = off)
##   --backup-keep=24      QW_BACKUP_KEEP   backups kept per world (oldest deleted)
##   --restore=latest      QW_RESTORE       restore a backup (latest, file name or path) before starting
##   --log-level=info      QW_LOG_LEVEL     debug | info | warn | error, or per mod: all:warn,my_mod:debug
##   --ugc=auto            QW_UGC           player creations: auto | trusted | approval | off
##   --dev                 QW_DEV           developer mode: every player gets the dev tools (F8), dashboard on
##   --dev-web=24580       QW_DEV_WEB       serve the dev dashboard on this port (default with --dev: port + 15)
##   --dev-web-host=127.0.0.1 QW_DEV_WEB_HOST address the dashboard listens on (token protected)

const GameServer = preload("res://engine/server/game_server.gd")
const Native = preload("res://engine/shared/native.gd")

const DEFAULTS := {
	"port": "24565",
	"name": "",
	"motd": "",
	"query-port": "",
	"hub": "",
	"public-address": "",
	"tags": "",
	"allowlist": "",
	"chat-filter": "",
	"default-role": "",
	"anticheat": "",
	"max-players": "64",
	"mods": "vanilla",
	"mods-dir": "",
	"data-dir": "user://worlds",
	"mod-settings": "",
	"world": "",
	"seed": "-1",
	"metrics": "0",
	"admin-token": "",
	"admins": "",
	"backup-interval": "60",
	"backup-keep": "24",
	"restore": "",
	"log-level": "",
	"dev": "",
	"ugc": "",
	"dev-web": "0",
	"dev-web-host": "127.0.0.1",
}

var _server: Node
var _signals := false
var _config := {}


func _ready() -> void:
	var options := read_options(OS.get_cmdline_user_args())
	var mods: PackedStringArray = String(options.mods).split(",", false)
	if mods.is_empty():
		printerr("[server] No mods configured (--mods / QW_MODS)")
		get_tree().quit(2)
		return
	# Save before exiting on window close, and on SIGTERM/SIGINT when the native extension is loaded
	# (Godot itself would terminate immediately, losing unsaved changes).
	get_tree().auto_accept_quit = false
	if ClassDB.class_exists(&"NativeProcess"):
		_signals = ClassDB.class_call_static(&"NativeProcess", &"install_shutdown_handlers")
	print("[server] native extension %s, graceful signal shutdown %s" % [
		"loaded" if Native.enabled() else "not loaded (GDScript fallbacks)", "on" if _signals else "off"])

	_config = {
		"port": int(options.port),
		"name": options.name,
		"motd": options.motd,
		"query_port": int(options["query-port"]) if not str(options["query-port"]).is_empty() else int(options.port) + 1,
		"hub": options.hub,
		"public_address": options["public-address"],
		"tags": options.tags,
		"allowlist": options.allowlist,
		"chat_filter": options["chat-filter"],
		"default_role": options["default-role"],
		"anticheat": options.anticheat,
		"max_players": int(options["max-players"]),
		"mods": mods,
		"mod_dirs": String(options["mods-dir"]).replace(";", ",").split(",", false),
		"data_dir": options["data-dir"],
		"mod_settings": options["mod-settings"],
		"world": options.world if not options.world.is_empty() else mods[0],
		"seed": int(options.seed),
		"metrics": float(options.metrics),
		"admin_token": options["admin-token"],
		"admins": options.admins,
		"backup_interval": float(options["backup-interval"]),
		"backup_keep": int(options["backup-keep"]),
		"restore": options.restore,
		"log_level": options["log-level"],
		"dev": options.dev == "true" or options.dev == "1",
		"ugc": options.ugc,
		"dev_web": int(options["dev-web"]),
		"dev_web_host": options["dev-web-host"],
	}
	var err := _start_server()
	_write_start_error(err)
	if err != OK:
		printerr("[server] Startup failed: %s" % error_string(err))
		get_tree().quit(1)


## A world started from the menu is a separate process whose output nobody sees, so why it refused is
## left in a file beside the worlds for the menu to read (engine/main.gd). Starting cleanly clears it.
func _write_start_error(err: Error) -> void:
	var path := str(_config.get("data_dir", "user://worlds")).path_join("last_start_error.txt")
	if err == OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	DirAccess.make_dir_recursive_absolute(str(_config.get("data_dir", "user://worlds")))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		var reason: String = _server.start_error if _server != null and not str(_server.start_error).is_empty() \
			else "The world could not start (%s)." % error_string(err)
		file.store_string(reason)
		file.close()


func _start_server() -> Error:
	_server = GameServer.new()
	_server.name = "GameServer"
	add_child(_server)
	var err: Error = _server.start(_config)
	_config.restore = ""  # a backup is restored once, not again on a full reload
	_config.dev_web_token = _server.dev_web.token  # open dashboards keep working after a full reload
	_server.full_reload_requested.connect(_full_reload, CONNECT_DEFERRED)
	return err


## /reload full: the old server saves (in _exit_tree) and closes its port, then a new one starts with
## the same settings, reading every mod again. Clients were told to reconnect.
func _full_reload() -> void:
	print("[server] Full reload")
	await get_tree().create_timer(0.3).timeout  # let the reloading notice reach clients
	var old := _server
	_server = null
	remove_child(old)
	old.free()
	Net.close()
	await get_tree().create_timer(0.5).timeout
	var err := _start_server()
	if err != OK:
		printerr("[server] Full reload failed to start: %s" % error_string(err))
		get_tree().quit(1)


func _process(_delta: float) -> void:
	if _signals and ClassDB.class_call_static(&"NativeProcess", &"is_shutdown_requested"):
		_signals = false
		_shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()


func _shutdown() -> void:
	print("[server] Shutting down")
	if _server:
		_server.queue_free()  # saves in _exit_tree
		_server = null
	get_tree().quit()


static func read_options(args: PackedStringArray) -> Dictionary:
	var options := {}
	for key: String in DEFAULTS:
		var env := OS.get_environment("QW_" + key.to_upper().replace("-", "_"))
		options[key] = env if not env.is_empty() else DEFAULTS[key]
	for arg in args:
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			if options.has(parts[0]):
				options[parts[0]] = parts[1] if parts.size() > 1 else "true"
	return options
