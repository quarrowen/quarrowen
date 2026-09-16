extends Node
## Looks for a new version when the menu opens, and installs one when the player asks.
##
## The manifest and the download both come from the address built into Updater; a server never gets a say
## in where the game fetches its own code from. Progress and problems go to the menu's banner.

signal message(text: String, kind: String, action_text: String, action: Callable)

const Updater = preload("res://engine/client/updater.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const ClientSettings = preload("res://engine/client/settings/client_settings.gd")

var _http: HTTPRequest
var _update := {}
var _busy := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 30.0
	add_child(_http)


## Asks the release page what the newest version is. `manual` also reports "you are up to date".
func check(manual := false) -> void:
	if _busy or Updater.installed_path().is_empty():
		if manual:
			message.emit("This copy was not installed as an app, so it cannot update itself.", "info", "", Callable())
		return
	_busy = true
	var text := await _fetch(Updater.manifest_url())
	var signature := await _fetch(Updater.manifest_url() + ".sig") if not text.is_empty() else ""
	_busy = false
	if text.is_empty():
		if manual:
			message.emit("Could not reach the update page. Check the internet connection.", "error", "", Callable())
		return
	_update = Updater.check(text, Protocol.GAME_VERSION, "", signature.strip_edges())
	if not _update.available:
		if manual:
			message.emit("You are on the newest version (%s)." % Protocol.GAME_VERSION if _update.reason.is_empty() else _update.reason,
				"info", "", Callable())
		return
	var note: String = _update.notes if not str(_update.notes).is_empty() else "A new version is ready."
	message.emit("Version %s is out: %s" % [_update.version, note], "info", "Update now", install)


## Downloads the update, checks it and hands over to the installer script.
func install() -> void:
	if _busy or not _update.get("available", false):
		return
	_busy = true
	message.emit("Downloading version %s…" % _update.version, "info", "", Callable())
	var bytes := await _download(str(_update.url))
	_busy = false
	if bytes.is_empty():
		message.emit("The download did not finish. Try again later.", "error", "Try again", install)
		return
	if not Updater.verify(bytes, str(_update.sha256), int(_update.size)):
		message.emit("The download did not match what the release page says it should be, so it was thrown away.",
			"error", "", Callable())
		return
	var problem := _hand_over(bytes)
	if problem.is_empty():
		message.emit("Installing version %s. The game will close and open again." % _update.version, "success", "", Callable())
		await get_tree().create_timer(1.5).timeout
		get_tree().quit()
	else:
		message.emit(problem, "error", "", Callable())


## Writes the zip and the installer script, starts the script and returns "" (or why it could not).
func _hand_over(bytes: PackedByteArray) -> String:
	var installed := Updater.installed_path()
	if installed.is_empty():
		return "This copy was not installed as an app, so it cannot update itself."
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Updater.DOWNLOAD_DIR))
	var work := ProjectSettings.globalize_path(Updater.DOWNLOAD_DIR)
	var zip_path := work.path_join("Quarrowen-%s.zip" % _update.version)
	var zip := FileAccess.open(zip_path, FileAccess.WRITE)
	if zip == null:
		return "The update could not be saved (%s)." % error_string(FileAccess.get_open_error())
	zip.store_buffer(bytes)
	zip.close()
	var script_path := work.path_join("install.sh")
	var script := FileAccess.open(script_path, FileAccess.WRITE)
	if script == null:
		return "The installer could not be written (%s)." % error_string(FileAccess.get_open_error())
	script.store_string(Updater.install_script(zip_path, work, installed, OS.get_process_id()))
	script.close()
	if OS.create_process("/bin/sh", [script_path]) <= 0:
		return "The installer could not be started."
	return ""


func _fetch(url: String) -> String:
	_http.cancel_request()
	_http.download_file = ""
	if _http.request(url) != OK:
		return ""
	var result: Array = await _http.request_completed
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		return ""
	return (result[3] as PackedByteArray).get_string_from_utf8()


func _download(url: String) -> PackedByteArray:
	_http.cancel_request()
	var path := ProjectSettings.globalize_path(Updater.DOWNLOAD_DIR).path_join("download.zip")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Updater.DOWNLOAD_DIR))
	_http.download_file = path
	if _http.request(url) != OK:
		return PackedByteArray()
	var result: Array = await _http.request_completed
	_http.download_file = ""
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(path)
	DirAccess.remove_absolute(path)
	return bytes
