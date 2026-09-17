extends Node
## The part of the mod list that touches the network: fetching the index, and downloading and installing
## a mod. The screen itself is in main_menu.gd; this holds no UI.
##
## The index comes from the address built into the client, not from a server, and every download is
## checked against the checksum the index gave before a single file is written - a mod is code that runs
## on whoever hosts the world.

## Something worth telling the player, in the menu banner's shape.
signal message(text: String, kind: String, action_text: String, action: Callable)
## The index arrived, or installing/removing finished: the screen should rebuild itself.
signal catalog_changed

const ModCatalog = preload("res://engine/client/mod_catalog.gd")
const Updater = preload("res://engine/client/updater.gd")
const Downloads = preload("res://engine/client/menu/downloads.gd")

## What the site offers, from the last fetch (or the cached copy from last time).
var index: Array = []
## True while a fetch or an install is running, so the screen can disable its buttons.
var busy := false
var _web: Node
var _fetched := false


func _ready() -> void:
	_web = Downloads.new()
	add_child(_web)
	index = ModCatalog.read_index(JSON.stringify(ModCatalog.cached_index()))


## Fetches the mod index. `force` asks again even if it was already fetched this session.
func refresh(force := false) -> void:
	if busy or (_fetched and not force):
		return
	busy = true
	var text: String = await _web.fetch(ModCatalog.index_url())
	# Signed like the update manifest: a checksum only proves a download matches *this* list, so the list
	# itself has to be the project's.
	var signature: String = await _web.fetch(ModCatalog.index_url() + ".sig") if not text.is_empty() else ""
	busy = false
	if not text.is_empty() and not Updater.signature_ok(text, signature.strip_edges()):
		message.emit("The mod list was not signed by the project, so it was ignored.", "error", "", Callable())
		catalog_changed.emit()
		return
	if text.is_empty():
		if force:
			message.emit("Could not reach the mod list. Check the internet connection.", "error", "", Callable())
		catalog_changed.emit()
		return
	var entries := ModCatalog.read_index(text)
	if entries.is_empty() and not index.is_empty():
		message.emit("The mod list could not be read, so the one from last time is still being shown.", "error", "", Callable())
		catalog_changed.emit()
		return
	_fetched = true
	index = entries
	ModCatalog.cache_index(text)
	catalog_changed.emit()


## Downloads and installs one mod, and anything it needs that is missing. `entry` is a row from the index.
func install(entry: Dictionary) -> void:
	if busy:
		return
	busy = true
	var queue := ModCatalog.missing_dependencies(entry, ModCatalog.installed(), index)
	for needed: Dictionary in queue:
		if needed.get("missing", false):
			busy = false
			message.emit("%s needs '%s', which is not in the mod list." % [entry.name, needed.id], "error", "", Callable())
			return
	queue.reverse()  # what a mod depends on goes on first
	queue.append(entry)
	for row: Dictionary in queue:
		message.emit("Getting %s…" % row.name, "info", "", Callable())
		var problem := await _install_one(row)
		if not problem.is_empty():
			busy = false
			message.emit(problem, "error", "", Callable())
			catalog_changed.emit()
			return
	busy = false
	var names: Array = queue.map(func(row): return str(row.name))
	message.emit("%s installed. Pick it when you make a world." % " and ".join(PackedStringArray(names)) if names.size() < 3
		else "%d mods installed." % names.size(), "success", "", Callable())
	catalog_changed.emit()


## Takes a mod off this computer.
func remove(id: String, mod_name := "") -> void:
	if busy:
		return
	var problem := ModCatalog.remove(id)
	if problem.is_empty():
		message.emit("%s was removed. Worlds that used it will not open until it is back." %
			(mod_name if not mod_name.is_empty() else id), "info", "", Callable())
	else:
		message.emit(problem, "error", "", Callable())
	catalog_changed.emit()


func _install_one(row: Dictionary) -> String:
	var url := str(row.get("url", ""))
	if not Updater.url_allowed(url):
		return "%s is not offered from the project's own download page, so it was not fetched." % row.get("name", row.get("id", "?"))
	var bytes: PackedByteArray = await _web.download(url, ModCatalog.CACHED_INDEX.get_base_dir())
	if bytes.is_empty():
		return "The download of %s did not finish. Try again later." % row.name
	if not Updater.verify(bytes, str(row.get("sha256", "")), int(row.get("size", 0))):
		return "%s did not match what the mod list says it should be, so it was thrown away." % row.name
	var problem := ModCatalog.install_package(bytes, str(row.get("id", "")))
	return "" if problem.is_empty() else "%s could not be installed: %s" % [row.name, problem]
