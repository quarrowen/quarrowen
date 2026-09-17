extends RefCounted
## Finds mods on disk (folders and .zip packages) and resolves load order from their dependencies,
## checking versions.
##
## mod.json:
##   id, name, version ("1.2.0", semantic), description, authors [..], license, homepage,
##   game (listed as a playable game), main (main.gd or main.js),
##   engine: "^1.0"                       the mod API versions it works with (see Protocol.MOD_API_VERSION)
##   depends: ["base", "arcana@^1.2", {"id": "guild", "version": ">=1.0 <2"}]   or {"base": "^1.0"}
##   optional_depends: [...]              loaded first when installed, not required
##   conflicts: ["other_mod", "old_mod@<2"]
## Version ranges: engine/shared/semver.gd.
##
## Packages: a .zip holding mod.json at its root (or inside a single top folder) is unpacked
## once into user://mod_cache/<id>-<version>-<hash>/<id> and loaded like a folder. A folder with the same
## id in the same search directory wins over a package.

const Semver = preload("res://engine/shared/semver.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const PACKAGE_EXTENSIONS := ["zip"]
const CACHE_DIR := "user://mod_cache"
const USER_MODS := "user://mods"
## Manifest keys the engine reads (others are reported by the validator as possible typos).
const KNOWN_KEYS := ["id", "name", "version", "description", "authors", "license", "homepage", "kind", "main", "engine",
	"depends", "optional_depends", "conflicts", "tags", "icon"]
## What a mod is for, so the mod list can group it: a game to play, an add-on for one, a library other
## mods build on, or an example to read.
const KINDS := ["game", "addon", "library", "example"]

## Problems found by the last discover/resolve, as {mod, message} (also pushed as errors).
static var last_errors: Array = []


## Where mods are searched, highest priority first: configured folders, a `mods` folder next to the
## executable (exported builds ship mods there as plain files, since exports would otherwise repack
## the raw textures and models the server streams to clients), mods created in game (user://mods), then
## the project's own res://mods.
static func search_dirs(configured: PackedStringArray) -> PackedStringArray:
	var dirs := PackedStringArray()
	for dir in configured:
		if not dir.strip_edges().is_empty():
			dirs.append(dir.strip_edges())
	var exe_dir := OS.get_executable_path().get_base_dir()
	for candidate in [exe_dir.path_join("mods"), exe_dir.path_join("../Resources/mods").simplify_path()]:
		if DirAccess.dir_exists_absolute(candidate) and not dirs.has(candidate):
			dirs.append(candidate)
	if DirAccess.dir_exists_absolute(USER_MODS):
		dirs.append(USER_MODS)
	dirs.append("res://mods")
	return dirs


## Where the game's "Create a mod" puts new mods: the project's mods folder when running from the editor
## or source, otherwise user://mods.
static func creation_dir() -> String:
	return ProjectSettings.globalize_path("res://mods") if not OS.has_feature("template") else ProjectSettings.globalize_path(USER_MODS)


## Returns id -> manifest for every valid mod folder or package in `dirs`. Manifests gain `dir` (and
## `package` for zips).
static func discover(dirs: PackedStringArray) -> Dictionary:
	last_errors = []
	var found := {}
	for dir in dirs:
		var access := DirAccess.open(dir)
		if access == null:
			continue
		for folder in access.get_directories():
			var mod_dir := dir.path_join(folder)
			if not FileAccess.file_exists(mod_dir.path_join("mod.json")):
				continue
			var manifest := read_manifest(mod_dir)
			if manifest.has("error"):
				_problem(folder, manifest.error)
				continue
			if manifest.id != folder:
				_problem(folder, "%s: id '%s' must match the folder name" % [mod_dir.path_join("mod.json"), manifest.id])
				continue
			_add(found, manifest)
		for file in access.get_files():
			if not file.get_extension().to_lower() in PACKAGE_EXTENSIONS:
				continue
			var unpacked := unpack(dir.path_join(file))
			if unpacked.has("error"):
				_problem(file, unpacked.error)
				continue
			var manifest := read_manifest(unpacked.dir)
			if manifest.has("error"):
				_problem(file, manifest.error)
				continue
			manifest.package = dir.path_join(file)
			_add(found, manifest)
	return found


static func _add(found: Dictionary, manifest: Dictionary) -> void:
	if found.has(manifest.id):
		if ProjectSettings.globalize_path(found[manifest.id].dir).simplify_path() == ProjectSettings.globalize_path(manifest.dir).simplify_path():
			return  # the same folder reached through two search paths
		print("[mods] %s in %s is overridden by %s" % [manifest.id, manifest.get("package", manifest.dir), found[manifest.id].get("package", found[manifest.id].dir)])
		return
	found[manifest.id] = manifest


static func _problem(mod: String, message: String) -> void:
	last_errors.append({"mod": mod, "message": message})
	push_error("[mods] %s" % message)


## Reads and normalizes <dir>/mod.json. Returns the manifest, or {error}.
static func read_manifest(mod_dir: String) -> Dictionary:
	var path := mod_dir.path_join("mod.json")
	if not FileAccess.file_exists(path):
		return {"error": "%s is missing" % path}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"error": "%s: invalid JSON at line %d: %s" % [path, json.get_error_line(), json.get_error_message()]}
	if not (json.data is Dictionary):
		return {"error": "%s: expected an object" % path}
	var manifest: Dictionary = json.data
	var id := String(manifest.get("id", ""))
	if not _is_valid_id(id):
		return {"error": "%s: id '%s' must be 1-32 characters of a-z, 0-9 and _" % [path, id]}
	manifest.dir = mod_dir
	manifest.name = String(manifest.get("name", id))
	manifest.version = String(manifest.get("version", "0.0.0"))
	manifest.description = String(manifest.get("description", ""))
	manifest.engine = String(manifest.get("engine", ""))
	manifest.depends = parse_dependencies(manifest.get("depends", []))
	manifest.optional_depends = parse_dependencies(manifest.get("optional_depends", []))
	manifest.conflicts = parse_dependencies(manifest.get("conflicts", []))
	manifest.kind = String(manifest.get("kind", "")) if String(manifest.get("kind", "")) in KINDS else "addon"
	manifest.game = manifest.kind == "game"
	var default_main := "main.js" if FileAccess.file_exists(mod_dir.path_join("main.js")) and not FileAccess.file_exists(mod_dir.path_join("main.gd")) else "main.gd"
	manifest.main = String(manifest.get("main", default_main))
	return manifest


## Dependencies as [{id, version}] from ["id", "id@range", {id, version}] or {id: range}.
static func parse_dependencies(value) -> Array:
	var out := []
	if value is Dictionary:
		for id in value:
			out.append({"id": str(id), "version": str(value[id])})
	elif value is Array:
		for entry in value:
			if entry is Dictionary:
				out.append({"id": str(entry.get("id", "")), "version": str(entry.get("version", ""))})
			else:
				var text := str(entry)
				var at := text.find("@")
				out.append({"id": text.left(at) if at >= 0 else text, "version": text.substr(at + 1) if at >= 0 else ""})
	return out


## Returns manifests in load order (dependencies first), or an empty Array on error (see last_errors).
static func resolve(requested: PackedStringArray, available: Dictionary) -> Array:
	last_errors = []
	var order: Array = []
	var state := {}  # id -> 1 visiting, 2 done
	for id in requested:
		if not _visit(id, available, state, order, []):
			return []
	var loaded := {}
	for m in order:
		loaded[m.id] = m
	for m in order:
		if not m.engine.is_empty() and not Semver.satisfies(Protocol.MOD_API_VERSION, m.engine):
			_problem(m.id, "%s %s needs mod API %s, but this engine has %s" % [m.id, m.version, m.engine, Protocol.MOD_API_VERSION])
			return []
		for c in m.conflicts:
			if loaded.has(c.id) and (c.version.is_empty() or Semver.satisfies(loaded[c.id].version, c.version)):
				_problem(m.id, "%s conflicts with %s %s; remove one of them" % [m.id, c.id, loaded[c.id].version])
				return []
	return order


static func _visit(id: String, available: Dictionary, state: Dictionary, order: Array, chain: Array) -> bool:
	if state.get(id) == 2:
		return true
	if state.get(id) == 1:
		_problem(id, "Dependency cycle: %s -> %s" % [" -> ".join(chain), id])
		return false
	if not available.has(id):
		_problem(id, "Missing mod '%s'%s" % [id, (" (required by %s)" % chain.back()) if not chain.is_empty() else ""])
		return false
	state[id] = 1
	var m: Dictionary = available[id]
	for dep in m.depends:
		if not available.has(dep.id):
			_problem(id, "%s needs mod '%s'%s, which is not installed" % [id, dep.id, " " + dep.version if not dep.version.is_empty() else ""])
			return false
		if not dep.version.is_empty() and not Semver.satisfies(available[dep.id].version, dep.version):
			_problem(id, "%s needs %s %s, but %s %s is installed" % [id, dep.id, dep.version, dep.id, available[dep.id].version])
			return false
		if not _visit(dep.id, available, state, order, chain + [id]):
			return false
	for dep in m.optional_depends:
		if available.has(dep.id) and state.get(dep.id) != 1 and (dep.version.is_empty() or Semver.satisfies(available[dep.id].version, dep.version)):
			if not _visit(dep.id, available, state, order, chain + [id]):
				return false
	state[id] = 2
	order.append(m)
	return true


## Unpacks a mod package into the cache (once per package content). Returns {dir} or {error}.
static func unpack(package_path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(package_path) != OK:
		return {"error": "%s is not a readable zip" % package_path}
	var files := zip.get_files()
	var prefix := ""
	if not files.has("mod.json"):
		var tops := {}
		for f in files:
			tops[f.get_slice("/", 0)] = true
		if tops.size() == 1 and files.has(tops.keys()[0] + "/mod.json"):
			prefix = tops.keys()[0] + "/"
		else:
			zip.close()
			return {"error": "%s has no mod.json at its root" % package_path}
	var manifest_text := zip.read_file(prefix + "mod.json").get_string_from_utf8()
	var manifest = JSON.parse_string(manifest_text)
	if not (manifest is Dictionary) or not _is_valid_id(str(manifest.get("id", ""))):
		zip.close()
		return {"error": "%s: mod.json is invalid or has a bad id" % package_path}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(FileAccess.get_file_as_bytes(package_path))
	var hash := ctx.finish().hex_encode().left(12)
	var id := str(manifest.id)
	var dir := CACHE_DIR.path_join("%s-%s-%s" % [id, str(manifest.get("version", "0.0.0")).validate_filename(), hash]).path_join(id)
	# mod.json is both the manifest and the "this was unpacked" marker, so it is written last: a run that
	# dies halfway leaves no marker and is unpacked again rather than being used half-finished.
	if not FileAccess.file_exists(dir.path_join("mod.json")):
		var ordered := Array(files)
		ordered.sort_custom(func(a, b): return int(str(a).ends_with("mod.json")) < int(str(b).ends_with("mod.json")))
		for f in ordered:
			if not f.begins_with(prefix) or f.ends_with("/"):
				continue
			var rel := str(f).substr(prefix.length())
			if rel.contains("..") or rel.begins_with("/"):
				continue  # never write outside the cache folder
			var target := dir.path_join(rel)
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			var out := FileAccess.open(target, FileAccess.WRITE)
			if out == null:
				zip.close()
				return {"error": "could not unpack %s into %s" % [package_path, target]}
			out.store_buffer(zip.read_file(f))
			out.close()
	zip.close()
	return {"dir": dir}


## Writes a mod folder into a .zip (mod.json at the root). Skips Godot's import metadata. Returns OK.
static func pack(mod_dir: String, zip_path: String) -> Error:
	var zip := ZIPPacker.new()
	DirAccess.make_dir_recursive_absolute(zip_path.get_base_dir())
	var err := zip.open(zip_path)
	if err != OK:
		return err
	var stack := [""]
	while not stack.is_empty():
		var rel: String = stack.pop_back()
		var access := DirAccess.open(mod_dir.path_join(rel))
		if access == null:
			continue
		for sub in access.get_directories():
			if not sub.begins_with("."):
				stack.append(rel.path_join(sub) if not rel.is_empty() else sub)
		for file in access.get_files():
			if file.ends_with(".import") or file.ends_with(".uid") or file.begins_with("."):
				continue
			var name := rel.path_join(file) if not rel.is_empty() else file
			zip.start_file(name)
			zip.write_file(FileAccess.get_file_as_bytes(mod_dir.path_join(name)))
			zip.close_file()
	return zip.close()


static func _is_valid_id(id: String) -> bool:
	if id.is_empty() or id.length() > 32:
		return false
	for c in id:
		if not (c in "abcdefghijklmnopqrstuvwxyz0123456789_"):
			return false
	return true
