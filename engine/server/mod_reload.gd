extends RefCounted
## Reloading mods while the server runs.
##
## Quick reload (`reload(mod_id)`, /reload <mod>): forgets what the mod hooked in live (event handlers,
## commands, timers, block tick handlers, mob behaviours, spawn rules, recipes, guide pages, tutorials
## and tips) and runs its setup again from fresh copies of its scripts. Blocks, items and entities it
## registers again update in place (same ids); recipes keep their indices (dropped ones are marked
## removed). What cannot change live (new blocks/items/entities/sounds/effects, new files, world
## generation) is skipped and listed as needing a full reload. Clients get the new definitions, recipe
## book, guide and tutorials. Mod state kept in api.storage, player and entity data survives; plain
## script variables start over.
##
## File watcher (on with --dev, or /reload watch on): scripts and JSON changed in a mod folder reload
## that mod about half a second after the last change; changed textures, models, sounds or mod.json
## tell admins to run /reload full.
##
## Full reload (/reload full): see GameServer.request_full_reload (save, restart in place, clients
## reconnect).

const ModApi = preload("res://engine/server/mod_api.gd")
const JsMod = preload("res://engine/server/js_mod.gd")
const SCRIPT_EXTENSIONS := ["gd", "js", "json", "mjs"]
const ASSET_EXTENSIONS := ["png", "jpg", "glb", "gltf", "wav", "ogg", "mp3"]
const WATCH_INTERVAL := 1.0
const DEBOUNCE := 0.5
const MAX_WATCHED_FILES := 5000

var watching := false
var _server
var _mtimes := {}  # mod id -> {path: modified time}
var _pending := {}  # mod id -> {due, scripts, assets: []}
var _watch_timer := 0.0


func _init(game_server) -> void:
	_server = game_server


## Re-runs a mod's setup. Returns {ok, mod, ms, notes: [String], error}.
func reload(mod_id: String) -> Dictionary:
	var manifest: Dictionary = _server.mod_manifests.get(mod_id, {})
	if manifest.is_empty():
		return {"ok": false, "mod": mod_id, "error": "no mod named '%s' is loaded" % mod_id, "notes": []}
	var started := Time.get_ticks_msec()
	var is_js := String(manifest.main).get_extension() == "js"
	var script: Script = null
	if not is_js:
		# Compile first: a mod with a syntax error keeps running its old code.
		var path: String = manifest.dir.path_join(manifest.main)
		var compile_error := _recompile_scripts(manifest.dir, path)
		_server.dev_log.drain()
		script = load(path)
		if not compile_error.is_empty() or script == null or not script.can_instantiate():
			return _failed(mod_id, "%s; the old version keeps running" % (compile_error if not compile_error.is_empty() else "%s does not compile" % manifest.main), started)
	var errors_before := _error_count(mod_id)

	_forget(mod_id)
	var notes: Array[String] = []
	var error := ""
	if is_js:
		var js := JsMod.new(_server, manifest)
		js.api.reloading = true
		_server._js_mods = _server._js_mods.filter(func(m): return m.manifest.id != mod_id)
		if js.load() != OK:
			error = "setup failed (see /errors); the mod is unloaded until it loads again"
		else:
			_server._js_mods.append(js)
			_server.mod_instances[mod_id] = js
		notes.append_array(js.api.reload_notes)
	else:
		var api := ModApi.new(_server, manifest)
		api.reloading = true
		var instance = script.new()
		var old = _server.mod_instances.get(mod_id)
		_server._mods.erase(old)
		instance.setup(api)
		_server._mods.append(instance)
		_server.mod_instances[mod_id] = instance
		notes.append_array(api.reload_notes)
	var removed: int = _server.recipes.end_reload()
	_server.dev_log.drain()
	if error.is_empty() and _error_count(mod_id) > errors_before:
		error = "setup raised errors (see /errors); it may be half set up"
	if removed > 0:
		notes.append("%d recipe%s no longer registered (hidden)" % [removed, "" if removed == 1 else "s"])
	_server.after_mod_reload()
	var ms := Time.get_ticks_msec() - started
	var result := {"ok": error.is_empty(), "mod": mod_id, "ms": ms, "notes": notes, "error": error}
	if error.is_empty():
		_server.dev_log.add("info", "server", "Reloaded %s in %d ms" % [mod_id, ms])
	else:
		_server.dev_log.add("error", "server", "Reloading %s: %s" % [mod_id, error])
	for note in notes:
		_server.dev_log.add("warn", mod_id, note)
	_server.emit("mod_reloaded", {"mod": mod_id, "ok": result.ok, "notes": notes.duplicate(), "error": error})
	return result


## Reloads every mod in load order (dependencies first).
func reload_all() -> Array:
	var out := []
	for manifest in _server.mod_order:
		out.append(reload(manifest.id))
	return out


## Recompiles every GDScript in the mod folder from its current source, in place (the cached Script
## objects preloads point at update too), the main script last. Returns "" or what failed.
func _recompile_scripts(dir: String, main_path: String) -> String:
	var paths := _scan(dir).keys().filter(func(p): return p.get_extension() == "gd" and p != main_path)
	paths.append(main_path)
	# Check everything compiles before swapping anything in.
	for path in paths:
		var probe := GDScript.new()
		probe.source_code = FileAccess.get_file_as_string(path)
		probe.resource_path = path.get_base_dir().path_join("__reload_probe_%s" % path.get_file())  # relative preloads resolve
		if probe.reload() != OK:
			# Errors in files preloading other mod files are reported against the file itself.
			return "%s does not compile" % path.get_file()
	for path in paths:
		if not ResourceLoader.has_cached(path):
			continue  # never loaded: the next load reads the new file
		var script: GDScript = load(path)
		script.source_code = FileAccess.get_file_as_string(path)
		var err := script.reload(true)
		if err != OK:
			return "%s failed to reload (%s)" % [path.get_file(), error_string(err)]
	return ""


func _failed(mod_id: String, error: String, started: int) -> Dictionary:
	_server.dev_log.add("error", "server", "Reloading %s: %s" % [mod_id, error])
	return {"ok": false, "mod": mod_id, "ms": Time.get_ticks_msec() - started, "notes": [], "error": error}


func _error_count(mod_id: String) -> int:
	var n := 0
	for e in _server.dev_log.errors.values():
		if e.source == mod_id and e.level == "error":
			n += e.count
	return n


## Removes the live hooks a mod registered (the parts setup registers again).
func _forget(mod_id: String) -> void:
	var s = _server
	for event in s._handlers.keys():
		s._handlers[event] = (s._handlers[event] as Array).filter(func(entry): return entry[2] != mod_id)
	for command in s._commands.keys():
		if s._commands[command].mod == mod_id:
			s._commands.erase(command)
	for id in s._tasks.keys():
		if s._tasks[id].get("owner", "") == mod_id:
			s._tasks.erase(id)
	for block in s.block_ticks.handlers.keys():
		if s.block_ticks.handlers[block].get("owner", "") == mod_id:
			s.block_ticks.handlers.erase(block)
	for behavior in s.entities.ai.custom_behaviors.keys():
		if s.entities.ai.custom_behaviors[behavior].get("owner", "") == mod_id:
			s.entities.ai.custom_behaviors.erase(behavior)
	var rules: Array[Dictionary] = s.entities.spawning.rules
	s.entities.spawning.rules = rules.filter(func(r): return r.get("owner", "") != mod_id)
	s.loot.forget(mod_id)  # pools this mod added to other mods' tables, or they pile up on every save
	s.recipes.begin_reload(mod_id)
	s.guide.registry.remove_owner(mod_id)
	s.tutorials.remove_owner(mod_id)
	s.milestones.remove_owner(mod_id)


# --- File watcher -----------------------------------------------------------------------------------

func set_watching(on: bool) -> void:
	watching = on
	_mtimes.clear()
	if on:
		for id in _server.mod_manifests:
			_mtimes[id] = _scan(_server.mod_manifests[id].dir)


func update(delta: float) -> void:
	if not watching:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for id in _pending.keys():
		var p: Dictionary = _pending[id]
		if now < p.due:
			continue
		_pending.erase(id)
		if not p.assets.is_empty():
			_server.tell_admins("Files changed in %s (%s): run /reload full to apply them" % [id, ", ".join(p.assets.slice(0, 3))])
		if p.scripts:
			var result := reload(id)
			_server.tell_admins(_summary(result))
	_watch_timer += delta
	if _watch_timer < WATCH_INTERVAL:
		return
	_watch_timer = 0.0
	for id in _server.mod_manifests:
		var fresh := _scan(_server.mod_manifests[id].dir)
		var old: Dictionary = _mtimes.get(id, {})
		var changed := []
		for path in fresh:
			if old.get(path, -1) != fresh[path]:
				changed.append(path)
		_mtimes[id] = fresh
		if changed.is_empty() or old.is_empty():
			continue
		var p: Dictionary = _pending.get(id, {"due": 0.0, "scripts": false, "assets": []})
		for path in changed:
			var ext: String = path.get_extension().to_lower()
			if path.get_file() == "mod.json" or ext in ASSET_EXTENSIONS:
				if not p.assets.has(path.get_file()):
					p.assets.append(path.get_file())
			elif ext in SCRIPT_EXTENSIONS:
				p.scripts = true
		p.due = now + DEBOUNCE
		_pending[id] = p


static func _summary(result: Dictionary) -> String:
	if not result.ok:
		return "Reload %s failed: %s" % [result.mod, result.error]
	var text := "Reloaded %s (%d ms)" % [result.mod, result.ms]
	if not result.notes.is_empty():
		text += " - " + "; ".join(result.notes.slice(0, 3))
	return text


## path -> modified time for the files in a mod folder (skipping Godot's import metadata).
func _scan(dir: String) -> Dictionary:
	var out := {}
	var stack := [dir]
	while not stack.is_empty() and out.size() < MAX_WATCHED_FILES:
		var current: String = stack.pop_back()
		var access := DirAccess.open(current)
		if access == null:
			continue
		for sub in access.get_directories():
			if not sub.begins_with("."):
				stack.append(current.path_join(sub))
		for file in access.get_files():
			if file.ends_with(".import") or file.ends_with(".uid") or file.begins_with("."):
				continue
			var path := current.path_join(file)
			out[path] = FileAccess.get_modified_time(path)
	return out
