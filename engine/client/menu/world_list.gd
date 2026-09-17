extends RefCounted
## The player's local worlds, as the menu's Play tab shows them: folders in the worlds directory that
## hold a world.json (written by the server: seed, mods, game, created_at, last_played). A world's
## folder name is its id; its display name lives in world.json ("title").

const DEFAULT_DIR := "user://worlds"
## Folders next to the worlds that are not worlds.
const RESERVED := ["backups", "identity"]


static func dir() -> String:
	var override := OS.get_environment("VOXEL_DATA_DIR")
	return override if not override.is_empty() else DEFAULT_DIR


## [{id, title, game, mods, seed, created_at, last_played, size}] newest played first.
static func list(root := "") -> Array:
	root = root if not root.is_empty() else dir()
	var out := []
	# A player who has never made a world has no worlds folder, which is not a problem worth an error in
	# the log on the very first launch.
	if not DirAccess.dir_exists_absolute(root):
		return out
	for id in DirAccess.get_directories_at(root):
		if id in RESERVED or id.begins_with("."):
			continue
		var meta := read_meta(root.path_join(id))
		if meta.is_empty():
			continue
		var mods: Array = meta.get("mods", []) if meta.get("mods") is Array else []
		out.append({"id": id, "title": str(meta.get("title", id)), "game": str(meta.get("game", mods[0] if not mods.is_empty() else id)),  # older worlds were named after their game
			"mods": mods.map(func(m): return str(m)), "seed": int(meta.get("seed", 0)),
			"created_at": int(meta.get("created_at", 0)), "last_played": int(meta.get("last_played", 0)),
			"players": (meta.players as Dictionary).size() if meta.get("players") is Dictionary else 0})
	out.sort_custom(func(a, b): return a.last_played > b.last_played if a.last_played != b.last_played else a.title < b.title)
	return out


static func read_meta(world_dir: String) -> Dictionary:
	var path := world_dir.path_join("world.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## A folder name for a new world from its title: letters, digits and underscores, unique in `root`.
static func id_for(title: String, root := "") -> String:
	root = root if not root.is_empty() else dir()
	var base := ""
	for c in title.strip_edges().to_lower():
		base += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while base.contains("__"):
		base = base.replace("__", "_")
	base = base.trim_prefix("_").trim_suffix("_").left(40)
	if base.is_empty() or base in RESERVED:
		base = "world"
	var id := base
	var n := 2
	while DirAccess.dir_exists_absolute(root.path_join(id)):
		id = "%s_%d" % [base, n]
		n += 1
	return id


## Creates the folder and a world.json with the title, mods and seed, so the list shows it before the
## first launch. The server fills in the rest when it starts.
static func create(title: String, mods: Array, world_seed: int, root := "") -> String:
	root = root if not root.is_empty() else dir()
	var id := id_for(title, root)
	DirAccess.make_dir_recursive_absolute(root.path_join(id))
	var meta := {"title": title.strip_edges().left(64) if not title.strip_edges().is_empty() else id, "mods": mods,
		"game": str(mods[0]) if not mods.is_empty() else "", "created_at": int(Time.get_unix_time_from_system())}
	if world_seed >= 0:
		meta.seed = world_seed
	var f := FileAccess.open(root.path_join(id).path_join("world.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	return id


static func rename(id: String, title: String, root := "") -> bool:
	root = root if not root.is_empty() else dir()
	var meta := read_meta(root.path_join(id))
	if meta.is_empty() or title.strip_edges().is_empty():
		return false
	meta.title = title.strip_edges().left(64)
	var f := FileAccess.open(root.path_join(id).path_join("world.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t"))
	f.close()
	return true


## Deletes a world folder and its backups. Refuses ids that are not plain world folders.
static func delete(id: String, root := "") -> bool:
	root = root if not root.is_empty() else dir()
	if id.is_empty() or id != id.validate_filename() or id in RESERVED or read_meta(root.path_join(id)).is_empty():
		return false
	_remove_tree(root.path_join(id))
	_remove_tree(root.path_join("backups").path_join(id))
	return not DirAccess.dir_exists_absolute(root.path_join(id))


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


## "3 minutes ago", "yesterday", "12 Sep 2026".
static func describe_time(unix: int) -> String:
	if unix <= 0:
		return "never"
	var ago := int(Time.get_unix_time_from_system()) - unix
	if ago < 60:
		return "just now"
	if ago < 3600:
		return "%d minute%s ago" % [ago / 60, "" if ago / 60 == 1 else "s"]
	if ago < 86400:
		return "%d hour%s ago" % [ago / 3600, "" if ago / 3600 == 1 else "s"]
	if ago < 2 * 86400:
		return "yesterday"
	if ago < 7 * 86400:
		return "%d days ago" % (ago / 86400)
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%d %s %d" % [d.day, ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.month - 1], d.year]
