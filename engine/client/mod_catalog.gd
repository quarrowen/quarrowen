extends RefCounted
## What mods this computer has, what the project's site offers, and putting one on or taking it off.
##
## Installing only matters for **hosting**: joining a server needs nothing, because mods run on the server
## and the client already downloads the textures, models and sounds it needs. This is what the menu's mod
## screen and the New world dialog read.
##
## Mods live in three places (ModLoader.search_dirs already loads from all of them):
##
##   inside the app       the mods a release ships with; replaced when the game updates, never removable
##   user://mods/<id>/    what a player installed here; survives updates, removable
##   a server's /mods     that server's business, not this screen's
##
## Every download is checked against the sha256 in the index before it is unpacked, and the index itself
## comes from the address built into the client (Updater.ALLOWED_HOSTS), never from a server - a mod is
## code that runs on whoever hosts the world.

const ModLoader = preload("res://engine/server/mod_loader.gd")
const Updater = preload("res://engine/client/updater.gd")
const Semver = preload("res://engine/shared/semver.gd")

## The index we last fetched, so the screen has something to show without the internet.
const CACHED_INDEX := "user://mod_cache/index.json"
## A mod may not be enormous: the whole catalogue is a few MB.
const MAX_PACKAGE_BYTES := 64 * 1024 * 1024

## What the player has, as [{id, name, version, description, game, depends, dir, removable, kind}].
static func installed() -> Array:
	var found := ModLoader.discover(ModLoader.search_dirs(PackedStringArray()))
	var out := []
	for id: String in found:
		var manifest: Dictionary = found[id]
		out.append({
			"id": id,
			"name": str(manifest.get("name", id)),
			"version": str(manifest.get("version", "0.0.0")),
			"description": str(manifest.get("description", "")),
			"authors": manifest.get("authors", []),
			"game": bool(manifest.get("game", false)),
			"kind": kind_of(manifest),
			"depends": manifest.get("depends", []),
			"dir": str(manifest.get("dir", "")),
			"removable": is_removable(str(manifest.get("dir", ""))),
		})
	out.sort_custom(func(a, b): return a.name.to_lower() < b.name.to_lower())
	return out


## What a mod is for, so the screen can group them: a game to play, an add-on for a game, a library other
## mods build on, or an example to read.
static func kind_of(manifest: Dictionary) -> String:
	var kind := str(manifest.get("kind", ""))
	if kind in ["game", "addon", "library", "example"]:
		return kind
	if bool(manifest.get("game", false)):
		return "game"
	return "library" if str(manifest.get("id", "")) == "base" else "addon"


## True for a mod the player installed themselves (the only ones Remove may touch).
static func is_removable(dir: String) -> bool:
	if dir.is_empty():
		return false
	var user_mods := ProjectSettings.globalize_path(ModLoader.USER_MODS).simplify_path()
	return ProjectSettings.globalize_path(dir).simplify_path().begins_with(user_mods)


## The index as it was last fetched ({version, mods: [...]}), or {} the first time.
static func cached_index() -> Dictionary:
	if not FileAccess.file_exists(CACHED_INDEX):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CACHED_INDEX))
	return parsed if parsed is Dictionary else {}


## Where the mod index lives: next to the update manifest, on the address built into the client.
static func index_url() -> String:
	return Updater.manifest_url().get_base_dir().path_join("mods.json")


## Checks an index and returns its entries as [{id, name, version, description, url, sha256, size, kind}],
## dropping anything malformed or from an address the client does not trust.
static func read_index(text: String) -> Array:
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary) or not (parsed.get("mods") is Array):
		return []
	var out := []
	for entry in parsed.mods:
		if not (entry is Dictionary):
			continue
		var id := str(entry.get("id", ""))
		var url := str(entry.get("url", ""))
		var sha256 := str(entry.get("sha256", "")).to_lower()
		var size := int(entry.get("size", 0))
		if id.is_empty() or not Updater.url_allowed(url) or sha256.length() != 64 or not sha256.is_valid_hex_number():
			continue
		if size <= 0 or size > MAX_PACKAGE_BYTES:
			continue
		out.append({
			"id": id,
			"name": str(entry.get("name", id)),
			"version": str(entry.get("version", "0.0.0")),
			"description": str(entry.get("description", "")),
			"authors": entry.get("authors", []),
			"kind": str(entry.get("kind", "addon")),
			"game": bool(entry.get("game", false)),
			"depends": entry.get("depends", []),
			"url": url,
			"sha256": sha256,
			"size": size,
		})
	out.sort_custom(func(a, b): return a.name.to_lower() < b.name.to_lower())
	return out


## Keeps an index for next time (so the screen works offline). Silently does nothing if it cannot.
static func cache_index(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(CACHED_INDEX.get_base_dir())
	var file := FileAccess.open(CACHED_INDEX, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


## The installed mods and the index as one list for the screen: [{..., state}], where state is
## "installed" (nothing to do), "update" (a newer version is offered), or "available" (not installed).
static func merge(installed_mods: Array, index: Array) -> Array:
	var by_id := {}
	for entry: Dictionary in installed_mods:
		var row: Dictionary = entry.duplicate(true)
		row.state = "installed"
		row.offered = ""
		by_id[row.id] = row
	for entry: Dictionary in index:
		if not by_id.has(entry.id):
			var row: Dictionary = entry.duplicate(true)
			row.state = "available"
			row.installed_version = ""
			row.removable = false
			by_id[row.id] = row
			continue
		var row: Dictionary = by_id[entry.id]
		row.url = entry.url
		row.sha256 = entry.sha256
		row.size = entry.size
		row.offered = entry.version
		row.depends = entry.depends  # the offered version's, not the installed one's: an update may have gained one
		if row.description.is_empty():
			row.description = entry.description
		# A bundled mod is replaced by a game update, not from here; only what the player installed updates.
		if row.removable and Semver.compare(str(entry.version), str(row.version)) > 0:
			row.state = "update"
	var out: Array = by_id.values()
	out.sort_custom(func(a, b): return [a.name.to_lower(), a.id] < [b.name.to_lower(), b.id])
	return out


## Unpacks a downloaded mod zip into user://mods/<id>/, replacing an older copy. Returns "" or the problem.
## The bytes must already have been checked against the index's sha256 (see Updater.verify).
static func install_package(bytes: PackedByteArray, expect_id := "") -> String:
	var temporary := "user://mod_cache/download-%d.zip" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(temporary.get_base_dir())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Could not write the download (%s)" % error_string(FileAccess.get_open_error())
	file.store_buffer(bytes)
	file.close()
	var problem := install_file(temporary, expect_id)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
	return problem


## Unpacks a mod zip from a path into user://mods/<id>/. Returns "" or the problem.
static func install_file(package_path: String, expect_id := "") -> String:
	var unpacked := ModLoader.unpack(package_path)
	if unpacked.has("error"):
		return str(unpacked.error)
	var manifest := ModLoader.read_manifest(unpacked.dir)
	if manifest.has("error"):
		return str(manifest.error)
	var id := str(manifest.id)
	if not expect_id.is_empty() and id != expect_id:
		return "That package holds '%s', not '%s'" % [id, expect_id]
	# The copy is built beside the installed one and swapped in only once it is whole, so a failure
	# halfway through an update leaves the working version in place instead of nothing at all.
	var target := ModLoader.USER_MODS.path_join(id)
	var staged := target + ".new"
	_remove_tree(staged)
	DirAccess.make_dir_recursive_absolute(staged)
	if not _copy_tree(unpacked.dir, staged):
		_remove_tree(staged)
		return "Could not put %s into %s" % [id, ProjectSettings.globalize_path(ModLoader.USER_MODS)]
	var previous := target + ".old"
	_remove_tree(previous)
	if DirAccess.dir_exists_absolute(target) and DirAccess.rename_absolute(ProjectSettings.globalize_path(target), ProjectSettings.globalize_path(previous)) != OK:
		_remove_tree(staged)
		return "%s is in use and could not be replaced" % id
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(staged), ProjectSettings.globalize_path(target)) != OK:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(previous), ProjectSettings.globalize_path(target))
		_remove_tree(staged)
		return "Could not put %s into %s" % [id, ProjectSettings.globalize_path(ModLoader.USER_MODS)]
	_remove_tree(previous)
	return ""


## Takes an installed mod off this computer. Only mods in user://mods may be removed - the ones inside the
## app come back with every update anyway. Returns "" or the problem.
static func remove(id: String) -> String:
	var found := ModLoader.discover(PackedStringArray([ModLoader.USER_MODS]))
	if not found.has(id):
		return "%s was not installed here (mods that come with the game cannot be removed)" % id
	var dir := str(found[id].dir)
	if not is_removable(dir):
		return "%s came with the game and cannot be removed" % id
	if not _remove_tree(dir):
		return "Could not remove %s" % ProjectSettings.globalize_path(dir)
	return ""


## Which installed mods need `id`, so the screen can warn before it is removed.
static func needed_by(id: String, installed_mods: Array) -> Array:
	var out := []
	for entry: Dictionary in installed_mods:
		if entry.id == id:
			continue
		for dep in entry.get("depends", []):
			var dep_id: String = str(dep.id) if dep is Dictionary else str(dep).get_slice("@", 0)
			if dep_id == id:
				out.append(str(entry.name))
				break
	return out


## The mods that have to be installed before `entry` can run, from what the index offers.
static func missing_dependencies(entry: Dictionary, installed_mods: Array, index: Array) -> Array:
	var have := {}
	for mod: Dictionary in installed_mods:
		have[mod.id] = true
	var offered := {}
	for mod: Dictionary in index:
		offered[mod.id] = mod
	var out := []
	var queue := [entry]
	var seen := {str(entry.get("id", "")): true}
	while not queue.is_empty():
		var current: Dictionary = queue.pop_front()
		for dep in current.get("depends", []):
			var dep_id: String = str(dep.id) if dep is Dictionary else str(dep).get_slice("@", 0)
			if dep_id.is_empty() or have.has(dep_id) or seen.has(dep_id):
				continue
			seen[dep_id] = true
			if offered.has(dep_id):
				out.append(offered[dep_id])
				queue.append(offered[dep_id])
			else:
				out.append({"id": dep_id, "name": dep_id, "missing": true})
	return out


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


static func _remove_tree(path: String) -> bool:
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	var ok := true
	for sub in dir.get_directories():
		ok = _remove_tree(path.path_join(sub)) and ok
	for file in dir.get_files():
		ok = DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file))) == OK and ok
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK and ok
