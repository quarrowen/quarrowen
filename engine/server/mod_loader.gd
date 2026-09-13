extends RefCounted
## Finds mods on disk and resolves load order from their dependencies.


## Returns id -> manifest for every valid mod folder in `dirs`. Manifests gain a `dir` key.
static func discover(dirs: PackedStringArray) -> Dictionary:
	var found := {}
	for dir in dirs:
		var access := DirAccess.open(dir)
		if access == null:
			continue
		for folder in access.get_directories():
			var mod_dir := dir.path_join(folder)
			var manifest_path := mod_dir.path_join("mod.json")
			if not FileAccess.file_exists(manifest_path):
				continue
			var manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			if not (manifest is Dictionary):
				push_error("[mods] Invalid JSON in %s" % manifest_path)
				continue
			var id := String(manifest.get("id", ""))
			if id != folder or not _is_valid_id(id):
				push_error("[mods] %s: id '%s' must match folder name and use [a-z0-9_]" % [manifest_path, id])
				continue
			if found.has(id):
				print("[mods] %s in %s is overridden by %s" % [id, mod_dir, found[id].dir])
				continue
			manifest.dir = mod_dir
			manifest.name = String(manifest.get("name", id))
			manifest.version = String(manifest.get("version", "0.0.0"))
			manifest.description = String(manifest.get("description", ""))
			manifest.depends = Array(manifest.get("depends", [])) if manifest.get("depends") is Array else []
			manifest.game = bool(manifest.get("game", false))
			var default_main := "main.js" if FileAccess.file_exists(mod_dir.path_join("main.js")) and not FileAccess.file_exists(mod_dir.path_join("main.gd")) else "main.gd"
			manifest.main = String(manifest.get("main", default_main))
			found[id] = manifest
	return found


## Returns manifests in load order (dependencies first), or an empty Array on error.
static func resolve(requested: PackedStringArray, available: Dictionary) -> Array:
	var order: Array = []
	var state := {}  # id -> 1 visiting, 2 done
	for id in requested:
		if not _visit(id, available, state, order, []):
			return []
	return order


static func _visit(id: String, available: Dictionary, state: Dictionary, order: Array, chain: Array) -> bool:
	if state.get(id) == 2:
		return true
	if state.get(id) == 1:
		push_error("[mods] Dependency cycle: %s -> %s" % [" -> ".join(chain), id])
		return false
	if not available.has(id):
		push_error("[mods] Missing mod '%s'%s" % [id, (" (required by %s)" % chain.back()) if not chain.is_empty() else ""])
		return false
	state[id] = 1
	for dep in available[id].depends:
		if not _visit(String(dep), available, state, order, chain + [id]):
			return false
	state[id] = 2
	order.append(available[id])
	return true


static func _is_valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 32:
		return false
	for c in id:
		if not (c in "abcdefghijklmnopqrstuvwxyz0123456789_"):
			return false
	return true
