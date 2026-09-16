extends RefCounted
## Brings a player's things across when the game's name changes.
##
## Godot keeps a game's data in a folder named after the project ("…/app_userdata/<name>"), so renaming
## the game hides everything a player had: their identity key (which *is* their account on every server,
## and what an allowlist entry is bound to), their settings, their local worlds and their server list.
##
## On the first start under a new name, anything found in an older name's folder is copied across. It is a
## copy, not a move: the old folder stays untouched in case someone goes back to the old build.

## Older names this game has had, newest first.
const PREVIOUS_NAMES := ["VoxelCraft"]
## What is worth bringing across, by name: the player's identity and account, their worlds, their settings
## and their server list. Caches and downloads rebuild themselves and are left behind.
const BRING := ["identity", "worlds", "known_servers", "mods", "mod_cache", "creations",
	"settings.cfg", "servers.json", "crafting_pins.cfg"]


## Copies an older installation's data if this one is empty. Returns what it brought, for the log.
static func run() -> Array:
	var here := OS.get_user_data_dir()
	if not DirAccess.dir_exists_absolute(here):
		DirAccess.make_dir_recursive_absolute(here)
	if _has_content(here):
		return []
	for name in PREVIOUS_NAMES:
		var previous := here.get_base_dir().path_join(name)
		if previous == here or not DirAccess.dir_exists_absolute(previous) or not _has_content(previous):
			continue
		var brought := []
		for entry in BRING:
			var source := previous.path_join(entry)
			if DirAccess.dir_exists_absolute(source):
				if _copy_tree(source, here.path_join(entry)):
					brought.append(entry)
			elif FileAccess.file_exists(source) and DirAccess.copy_absolute(source, here.path_join(entry)) == OK:
				brought.append(entry)
		if not brought.is_empty():
			print("[main] Brought %d things across from %s (identity, worlds and settings)" % [brought.size(), name])
		return brought
	return []


## Whether this folder already holds a player's things (so nothing should be copied over them).
static func _has_content(path: String) -> bool:
	for entry in BRING:
		if DirAccess.dir_exists_absolute(path.path_join(entry)) or FileAccess.file_exists(path.path_join(entry)):
			return true
	return false


static func _copy_tree(from: String, to: String) -> bool:
	var dir := DirAccess.open(from)
	if dir == null:
		return false
	DirAccess.make_dir_recursive_absolute(to)
	var ok := true
	for sub in dir.get_directories():
		ok = _copy_tree(from.path_join(sub), to.path_join(sub)) and ok
	for file in dir.get_files():
		ok = DirAccess.copy_absolute(from.path_join(file), to.path_join(file)) == OK and ok
	return ok
