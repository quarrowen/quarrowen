extends RefCounted
## World backups: zip archives of a world's save folder, named <world>-YYYYmmdd-HHMMSS.zip.
## Saves write each file atomically (temp file + rename), so archiving while the server keeps running
## captures every file whole; the server flushes pending changes right before a backup starts.

const EXTENSION := ".zip"


static func timestamp() -> String:
	var t := Time.get_datetime_dict_from_system(true)
	return "%04d%02d%02d-%02d%02d%02d" % [t.year, t.month, t.day, t.hour, t.minute, t.second]


## Newest first. Each entry: {name, path, size, modified}.
static func list(backup_dir: String) -> Array:
	var result := []
	var dir := DirAccess.open(backup_dir)
	if dir == null:
		return result
	for file in dir.get_files():
		if not file.ends_with(EXTENSION):
			continue
		var path := backup_dir.path_join(file)
		var access := FileAccess.open(path, FileAccess.READ)
		result.append({"name": file, "path": path, "size": access.get_length() if access else 0,
			"modified": FileAccess.get_modified_time(path)})
	# Names embed a sortable UTC timestamp; fall back to it rather than mtimes, which copies reset.
	result.sort_custom(func(a, b): return a.name > b.name)
	return result


## Worker thread safe. Archives every file under `world_dir` into `zip_path`. Returns "" or an error.
static func create(world_dir: String, zip_path: String) -> String:
	DirAccess.make_dir_recursive_absolute(zip_path.get_base_dir())
	var tmp := zip_path + ".partial"
	var packer := ZIPPacker.new()
	var err := packer.open(tmp)
	if err != OK:
		return "could not create %s: %s" % [tmp, error_string(err)]
	var files := PackedStringArray()
	_collect(world_dir, "", files)
	for relative in files:
		if relative.ends_with(".tmp"):
			continue
		var bytes := FileAccess.get_file_as_bytes(world_dir.path_join(relative))
		if bytes.is_empty() and FileAccess.get_open_error() != OK:
			continue  # removed between listing and reading (e.g. a chunk reverted to generated terrain)
		packer.start_file(relative)
		packer.write_file(bytes)
		packer.close_file()
	packer.close()
	err = DirAccess.rename_absolute(tmp, zip_path)
	return "" if err == OK else "could not finalize %s: %s" % [zip_path, error_string(err)]


## Deletes the oldest backups beyond `keep`. Returns how many were removed.
static func prune(backup_dir: String, keep: int) -> int:
	var removed := 0
	var backups := list(backup_dir)
	for i in range(maxi(keep, 1), backups.size()):
		if DirAccess.remove_absolute(backups[i].path) == OK:
			removed += 1
	return removed


## Resolves "latest", a file name in `backup_dir`, or a path to an archive.
static func resolve(backup_dir: String, which: String) -> String:
	if which == "latest":
		var backups := list(backup_dir)
		return backups[0].path if not backups.is_empty() else ""
	for candidate in [which, backup_dir.path_join(which), backup_dir.path_join(which + EXTENSION)]:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


## Replaces `world_dir` with the archive's contents. The current world is moved aside (not deleted)
## to <world_dir>.before-restore-<timestamp>. Returns "" or an error.
static func restore(zip_path: String, world_dir: String) -> String:
	var reader := ZIPReader.new()
	var err := reader.open(zip_path)
	if err != OK:
		return "could not open %s: %s" % [zip_path, error_string(err)]
	var entries := reader.get_files()
	if not entries.has("world.json"):
		reader.close()
		return "%s is not a world backup (no world.json)" % zip_path
	var staging := world_dir + ".restoring"
	_remove_tree(staging)
	for entry in entries:
		if entry.ends_with("/"):
			continue
		# Reject absolute paths and traversal so an archive cannot write outside the world folder.
		if entry.begins_with("/") or entry.contains("..") or entry.contains("\\") or entry.contains(":"):
			reader.close()
			_remove_tree(staging)
			return "unsafe path in archive: %s" % entry
		var target := staging.path_join(entry)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			reader.close()
			return "could not write %s" % target
		file.store_buffer(reader.read_file(entry))
		file.close()
	reader.close()
	if DirAccess.dir_exists_absolute(world_dir):
		err = DirAccess.rename_absolute(world_dir, "%s.before-restore-%s" % [world_dir, timestamp()])
		if err != OK:
			return "could not move the current world aside: %s" % error_string(err)
	err = DirAccess.rename_absolute(staging, world_dir)
	return "" if err == OK else "could not move restored world into place: %s" % error_string(err)


## Folders inside a world that a backup has no business carrying. The log is the whole list: it is not
## part of the world, restoring it would overwrite the log of the server doing the restoring, and every
## archive would otherwise keep its own copy of who played and when.
const SKIP_DIRS := ["logs"]


static func _collect(root: String, relative: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(root.path_join(relative))
	if dir == null:
		return
	for file in dir.get_files():
		out.append(relative.path_join(file) if not relative.is_empty() else file)
	for sub in dir.get_directories():
		if relative.is_empty() and sub in SKIP_DIRS:
			continue
		_collect(root, relative.path_join(sub) if not relative.is_empty() else sub, out)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
