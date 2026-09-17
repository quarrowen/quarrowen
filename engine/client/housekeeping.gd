extends RefCounted
## The client's folders: what they are for, how big they are allowed to get, and where to find them.
##
## Everything here is a cache or a record. Nothing a player would miss is touched: their identity key,
## worlds, creations and settings are listed so they can be opened, never pruned. The rest rebuilds
## itself by downloading again, so the only question is how much disk it may use meanwhile.
##
## Caches were unbounded before this: every texture and model from every server ever joined, every skin
## seen on anyone, and every version of every mod ever loaded, kept for good. On a child's laptop that is
## the kind of thing nobody notices until the disk is full.
##
## `sweep()` runs once at startup. Pruning is by last-modified time, oldest first, down to a byte budget:
## a cache entry that has not been wanted in a long time is the one to lose, and re-downloading it is
## only a wait.

## A folder: where it is, what to call it, and what it may cost. `budget` 0 means never pruned.
const FOLDERS := [
	{"key": "logs", "path": "user://logs", "title": "Logs",
		"about": "What the game recorded, most recent last. Worth opening when something went wrong.", "budget": 0},
	{"key": "assets", "path": "user://cache/assets", "title": "Downloaded content",
		"about": "Textures, models and sounds from servers you have played on.", "budget": 512 * 1024 * 1024},
	{"key": "ugc", "path": "user://ugc_cache", "title": "Other players' creations",
		"about": "Skins and models other people were wearing.", "budget": 128 * 1024 * 1024},
	{"key": "mod_cache", "path": "user://mod_cache", "title": "Unpacked mods",
		"about": "Working copies of mods, one per version.", "budget": 256 * 1024 * 1024},
	{"key": "updates", "path": "user://updates", "title": "Downloaded updates",
		"about": "Only used while an update installs.", "budget": 1},
	{"key": "worlds", "path": "user://worlds", "title": "Your worlds",
		"about": "Worlds you made on this computer, and their backups.", "budget": 0},
	{"key": "mods", "path": "user://mods", "title": "Your mods",
		"about": "Mods you installed yourself.", "budget": 0},
	{"key": "creations", "path": "user://creations", "title": "Your creations",
		"about": "Things you built in the creation editor.", "budget": 0},
	{"key": "identity", "path": "user://identity", "title": "Your account key",
		"about": "What servers know you by. Do not share or delete this.", "budget": 0},
]


## Prunes every cache back inside its budget. Returns bytes freed, for the log.
static func sweep() -> int:
	var freed := 0
	for folder in FOLDERS:
		if int(folder.budget) > 0:
			freed += prune(str(folder.path), int(folder.budget))
	return freed


## Deletes oldest-first until what is left fits in `budget` bytes. Directly under `dir` only: entries are
## whole units (a file, or an unpacked mod's folder), and half an unpacked mod is worse than none.
static func prune(dir: String, budget: int) -> int:
	var entries := _entries(dir)
	var total := 0
	for e in entries:
		total += int(e.size)
	if total <= budget:
		return 0
	entries.sort_custom(func(a, b): return int(a.time) < int(b.time))
	var freed := 0
	for e in entries:
		if total - freed <= budget:
			break
		if _remove(str(e.path)):
			freed += int(e.size)
	return freed


## What a folder currently costs, for the settings screen.
static func size_of(dir: String) -> int:
	var total := 0
	for e in _entries(dir):
		total += int(e.size)
	return total


## The folders, with their sizes filled in.
static func listing() -> Array:
	var out := []
	for folder in FOLDERS:
		var entry: Dictionary = folder.duplicate()
		entry.absolute = ProjectSettings.globalize_path(str(folder.path))
		entry.exists = DirAccess.dir_exists_absolute(str(folder.path))
		entry.bytes = size_of(str(folder.path)) if entry.exists else 0
		out.append(entry)
	return out


## "412 MB", "9.1 GB" - sizes a person reads rather than a number they count the digits of.
static func human(bytes: int) -> String:
	if bytes < 1024:
		return "%d bytes" % bytes
	if bytes < 1024 * 1024:
		return "%d KB" % (bytes / 1024)
	if bytes < 1024 * 1024 * 1024:
		return "%d MB" % (bytes / (1024 * 1024))
	return "%.1f GB" % (float(bytes) / (1024.0 * 1024.0 * 1024.0))


static func _entries(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for file in d.get_files():
		var path := dir.path_join(file)
		out.append({"path": path, "size": _file_size(path), "time": FileAccess.get_modified_time(path)})
	for sub in d.get_directories():
		var path := dir.path_join(sub)
		out.append({"path": path, "size": _tree_size(path), "time": FileAccess.get_modified_time(path)})
	return out


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


static func _tree_size(path: String) -> int:
	var total := 0
	var d := DirAccess.open(path)
	if d == null:
		return 0
	for file in d.get_files():
		total += _file_size(path.path_join(file))
	for sub in d.get_directories():
		total += _tree_size(path.path_join(sub))
	return total


static func _remove(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return DirAccess.remove_absolute(path) == OK
	var d := DirAccess.open(path)
	if d == null:
		return false
	for file in d.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub in d.get_directories():
		_remove(path.path_join(sub))
	return DirAccess.remove_absolute(path) == OK
