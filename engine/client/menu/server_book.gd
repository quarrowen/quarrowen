extends RefCounted
## Saved servers for the menu's Multiplayer tab: favorites the player added and servers joined
## recently (user://servers.json, or QW_SERVER_BOOK for tests).
##   {"favorites": [{name, address, port, added_at}], "recent": [{name, address, port, last_joined}]}

const DEFAULT_PATH := "user://servers.json"
const MAX_RECENT := 12
const MAX_FAVORITES := 100

var favorites: Array = []
var recent: Array = []


static func path() -> String:
	var override := OS.get_environment("QW_SERVER_BOOK")
	return override if not override.is_empty() else DEFAULT_PATH


static func load_book():
	var book = load("res://engine/client/menu/server_book.gd").new()
	if FileAccess.file_exists(path()):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path()))
		if parsed is Dictionary:
			book.favorites = _clean(parsed.get("favorites", []))
			book.recent = _clean(parsed.get("recent", []))
	return book


static func _clean(entries) -> Array:
	var out := []
	if not (entries is Array):
		return out
	for e in entries:
		if e is Dictionary and not str(e.get("address", "")).strip_edges().is_empty():
			var entry: Dictionary = e.duplicate()
			entry.address = str(e.address).strip_edges().left(253)
			entry.port = clampi(int(e.get("port", 24565)), 1, 65535)
			entry.name = str(e.get("name", entry.address)).left(64)
			out.append(entry)
	return out


func save() -> void:
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"favorites": favorites, "recent": recent}, "\t"))
		f.close()


static func key(address: String, port: int) -> String:
	return "%s:%d" % [address.to_lower(), port]


func find_favorite(address: String, port: int) -> int:
	for i in favorites.size():
		if key(favorites[i].address, favorites[i].port) == key(address, port):
			return i
	return -1


## Adds or updates a favorite. Returns false when the list is full.
func add_favorite(server_name: String, address: String, port: int) -> bool:
	var i := find_favorite(address, port)
	var entry := {"name": server_name.strip_edges().left(64) if not server_name.strip_edges().is_empty() else address,
		"address": address.strip_edges(), "port": port, "added_at": int(Time.get_unix_time_from_system())}
	if i >= 0:
		entry.added_at = favorites[i].get("added_at", entry.added_at)
		favorites[i] = entry
	elif favorites.size() >= MAX_FAVORITES:
		return false
	else:
		favorites.append(entry)
	save()
	return true


func remove_favorite(address: String, port: int) -> void:
	var i := find_favorite(address, port)
	if i >= 0:
		favorites.remove_at(i)
		save()


func move_favorite(address: String, port: int, by: int) -> void:
	var i := find_favorite(address, port)
	var j := i + by
	if i < 0 or j < 0 or j >= favorites.size():
		return
	var entry = favorites[i]
	favorites.remove_at(i)
	favorites.insert(j, entry)
	save()


## Remembers a join (most recent first). `server_name` may be updated later by a status answer.
func note_joined(server_name: String, address: String, port: int) -> void:
	recent = recent.filter(func(e): return key(e.address, e.port) != key(address, port))
	recent.push_front({"name": server_name.left(64) if not server_name.is_empty() else address, "address": address, "port": port,
		"last_joined": int(Time.get_unix_time_from_system())})
	recent = recent.slice(0, MAX_RECENT)
	save()


func clear_recent() -> void:
	recent.clear()
	save()
