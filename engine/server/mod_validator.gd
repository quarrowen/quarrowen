extends RefCounted
## Checks a mod before it ships: the manifest, its files, that its scripts compile, that it loads, and
## that everything it registered refers to things that exist. Each issue is
## {level: "error" | "warning" | "hint", message, file, line}.
##
## - `validate(mod_dir, parent, search_dirs)`: everything, loading the mod (and its dependencies) in a
##   throwaway offline server added under `parent`. Used by tools/mod_tool.tscn (validate, pack).
## - `check_running(server, mod_id)`: the checks that need no load, against a running server (/validate).

const ModLoader = preload("res://engine/server/mod_loader.gd")
const Semver = preload("res://engine/shared/semver.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const KEY_ACTIONS := ["guide", "inventory", "crafting", "break", "place", "drop", "sprint", "jump", "chat", "pause", "camera", "dev",
	"move_forward", "move_back", "move_left", "move_right"]
const TEXTURE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const DATA_EXTENSIONS := ["gd", "js", "mjs", "json", "md", "txt", "ts", "d.ts"]


## Every check. Returns {mod, ok, issues: [...], counts: {error, warning, hint}}.
static func validate(mod_dir: String, parent: Node, search_dirs := PackedStringArray()) -> Dictionary:
	var issues: Array = []
	var manifest := ModLoader.read_manifest(mod_dir)
	if manifest.has("error"):
		issues.append(_issue("error", manifest.error, mod_dir.path_join("mod.json")))
		return _result(mod_dir.get_file(), issues)
	issues.append_array(check_manifest(mod_dir))
	issues.append_array(check_files(mod_dir, manifest))
	var script_issues := check_scripts(mod_dir)
	issues.append_array(script_issues)
	if not script_issues.is_empty() or not FileAccess.file_exists(mod_dir.path_join(manifest.main)):
		return _result(manifest.id, issues)  # it cannot load; the rest would only repeat that
	# Load it for real (with its dependencies) and look at what it registered.
	var dirs := PackedStringArray([mod_dir.get_base_dir()])
	dirs.append_array(search_dirs)
	var data_dir := "user://validate_%d_%d" % [Time.get_ticks_msec(), randi() % 10000]
	var server = load("res://engine/server/game_server.gd").new()
	parent.add_child(server)
	server.dev_log.set_level("all", "warn")
	var err: Error = server.start({"mods": PackedStringArray([manifest.id]), "mod_dirs": dirs, "world": "validate", "data_dir": data_dir,
		"seed": 1, "offline": true})
	server.set_physics_process(false)
	server.dev_log.drain()
	if err != OK:
		for e in ModLoader.last_errors:
			issues.append(_issue("error", e.message, mod_dir.path_join("mod.json")))
		issues.append(_issue("error", "the mod did not load (%s)" % error_string(err), mod_dir.path_join(manifest.main)))
	issues.append_array(_log_issues(server, manifest.id))
	if err == OK:
		issues.append_array(check_references(server, manifest.id))
		issues.append_array(check_unused_files(server, mod_dir, manifest))
	server.dev_log.close()
	parent.remove_child(server)
	server.free()
	_remove_tree(ProjectSettings.globalize_path(data_dir))
	return _result(manifest.id, issues)


## The checks that need no fresh load, on a running server.
static func check_running(server, mod_id: String) -> Dictionary:
	var manifest: Dictionary = server.mod_manifests.get(mod_id, {})
	if manifest.is_empty():
		return _result(mod_id, [_issue("error", "no mod named '%s' is loaded" % mod_id)])
	var issues: Array = []
	issues.append_array(check_manifest(manifest.dir))
	issues.append_array(check_files(manifest.dir, manifest))
	issues.append_array(_log_issues(server, mod_id))
	issues.append_array(check_references(server, mod_id))
	return _result(mod_id, issues)


static func _result(mod_id: String, issues: Array) -> Dictionary:
	var counts := {"error": 0, "warning": 0, "hint": 0}
	for i in issues:
		counts[i.level] += 1
	issues.sort_custom(func(a, b): return ["error", "warning", "hint"].find(a.level) < ["error", "warning", "hint"].find(b.level))
	return {"mod": mod_id, "ok": counts.error == 0, "issues": issues, "counts": counts}


static func _issue(level: String, message: String, file := "", line := 0) -> Dictionary:
	return {"level": level, "message": message, "file": file, "line": line}


## Human-readable report lines.
static func report(result: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for i in result.issues:
		var where := ""
		if not str(i.file).is_empty():
			where = "  (%s%s)" % [i.file, ":%d" % i.line if int(i.line) > 0 else ""]
		lines.append("%-7s %s%s" % [i.level.to_upper(), i.message, where])
	lines.append("%s: %d error%s, %d warning%s, %d hint%s" % [result.mod, result.counts.error, "" if result.counts.error == 1 else "s",
		result.counts.warning, "" if result.counts.warning == 1 else "s", result.counts.hint, "" if result.counts.hint == 1 else "s"])
	return lines


# --- Manifest and files -----------------------------------------------------------------------------

static func check_manifest(mod_dir: String) -> Array:
	var issues := []
	var path := mod_dir.path_join("mod.json")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	var m := ModLoader.read_manifest(mod_dir)
	if m.has("error") or not (raw is Dictionary):
		return [_issue("error", m.get("error", "mod.json is not an object"), path)]
	if mod_dir.get_file() != m.id and not mod_dir.get_base_dir().begins_with(ModLoader.CACHE_DIR):
		issues.append(_issue("error", "the folder is '%s' but the id is '%s'; they must match" % [mod_dir.get_file(), m.id], path))
	for key in raw:
		if not key in ModLoader.KNOWN_KEYS:
			var hint := " (did you mean \"depends\"?)" if str(key) in ["dependencies", "requires", "deps"] else ""
			issues.append(_issue("warning", "unknown key \"%s\" in mod.json%s" % [key, hint], path))
	if not raw.has("version"):
		issues.append(_issue("warning", "no \"version\"; use a semantic version like \"1.0.0\"", path))
	elif not Semver.is_valid(m.version):
		issues.append(_issue("error", "version \"%s\" is not a semantic version (major.minor.patch)" % m.version, path))
	if m.description.is_empty():
		issues.append(_issue("hint", "add a \"description\" (shown in the Host menu and server list)", path))
	if not raw.has("name"):
		issues.append(_issue("hint", "add a display \"name\"", path))
	if not raw.has("authors") and not raw.has("author"):
		issues.append(_issue("hint", "add \"authors\"", path))
	# What this mod is, so the mod list and the download page can group it (see docs/mods_plan.md).
	if raw.has("kind") and not str(raw.kind) in ModLoader.KINDS:
		issues.append(_issue("error", "kind \"%s\" is not one of %s" % [raw.kind, ", ".join(ModLoader.KINDS)], path))
	elif raw.has("kind") and (str(raw.kind) == "game") != bool(raw.get("game", false)):
		issues.append(_issue("error", "kind \"%s\" and game: %s disagree; a game needs both" % [raw.kind, raw.get("game", false)], path))
	elif not raw.has("kind"):
		issues.append(_issue("hint", "add \"kind\": game, addon, library or example", path))
	if m.engine.is_empty():
		issues.append(_issue("warning", "no \"engine\" range; add \"engine\": \"^%s\" so incompatible engines refuse it clearly" % Protocol.MOD_API_VERSION.get_slice(".", 0) + ".0", path))
	elif not Semver.range_error(m.engine).is_empty():
		issues.append(_issue("error", "engine: %s" % Semver.range_error(m.engine), path))
	elif not Semver.satisfies(Protocol.MOD_API_VERSION, m.engine):
		issues.append(_issue("error", "engine %s does not include this engine's mod API %s" % [m.engine, Protocol.MOD_API_VERSION], path))
	for key in ["depends", "optional_depends", "conflicts"]:
		for dep in m[key]:
			if not ModLoader._is_valid_id(dep.id):
				issues.append(_issue("error", "%s: '%s' is not a mod id" % [key, dep.id], path))
			elif not Semver.range_error(dep.version).is_empty():
				issues.append(_issue("error", "%s %s: %s" % [key, dep.id, Semver.range_error(dep.version)], path))
			elif key == "depends" and dep.version.is_empty() and dep.id != m.id:
				issues.append(_issue("hint", "depends on %s without a version range (e.g. \"%s@^1.0\")" % [dep.id, dep.id], path))
			if dep.id == m.id:
				issues.append(_issue("error", "%s lists the mod itself" % key, path))
	if not FileAccess.file_exists(mod_dir.path_join(m.main)):
		issues.append(_issue("error", "the main script %s does not exist" % m.main, path))
	return issues


static func check_files(mod_dir: String, manifest: Dictionary) -> Array:
	var issues := []
	for path in _files(mod_dir):
		var rel: String = path.substr(mod_dir.length() + 1)
		var size := FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
		if size > Protocol.MAX_ASSET_SIZE:
			issues.append(_issue("error", "%s is %d MB; files sent to players must be under %d MB" % [rel, size / 1048576, Protocol.MAX_ASSET_SIZE / 1048576], path))
		var conventional: bool = rel.get_file().begins_with("README") or rel.get_file().begins_with("LICENSE") or rel.get_file().begins_with("CHANGELOG")
		if (rel != rel.to_lower() and not conventional) or rel.contains(" "):
			issues.append(_issue("hint", "%s: lowercase names without spaces avoid case problems on Linux servers" % rel, path))
		if path.get_extension().to_lower() in TEXTURE_EXTENSIONS and Image.load_from_file(path) == null:
			issues.append(_issue("error", "%s is not a readable image" % rel, path))
	return issues


## Compiles every GDScript in the mod (JavaScript is checked by loading it).
static func check_scripts(mod_dir: String) -> Array:
	var issues := []
	for path in _files(mod_dir):
		if path.get_extension() != "gd":
			continue
		var probe := GDScript.new()
		probe.source_code = FileAccess.get_file_as_string(path)
		probe.resource_path = path.get_base_dir().path_join("__validate_probe_%s" % path.get_file())
		if probe.reload() != OK:
			issues.append(_issue("error", "%s does not compile (the error above names the line)" % path.get_file(), path))
	return issues


static func _log_issues(server, mod_id: String) -> Array:
	var issues := []
	for e in server.dev_log.sorted_errors():
		if e.source == mod_id:
			issues.append(_issue("error" if e.level == "error" else "warning", "%s%s" % [e.message, " (×%d)" % e.count if e.count > 1 else ""], e.file, e.line))
	for e in server.dev_log.entries:
		if e.source == mod_id and e.level == "warn" and not e.has("error"):
			issues.append(_issue("warning", e.message))
	return issues


# --- References -------------------------------------------------------------------------------------

static func check_references(server, mod_id: String) -> Array:
	var issues := []
	var prefix := mod_id + ":"
	var item_ok := func(n: String) -> bool: return n.contains("*") or server.items.id_of(n) > 0
	var entity_ok := func(n: String) -> bool: return n.contains("*") or server.entities.registry.id_of(n) >= 0
	var sound_ok := func(n: String) -> bool: return n.is_empty() or server.sounds.id_of(n) >= 0
	for d in server.registry.defs:
		if not str(d.name).begins_with(prefix):
			continue
		for action in d.get("sounds", {}):
			if not sound_ok.call(d.sounds[action]):
				issues.append(_issue("warning", "block %s: %s sound '%s' is not registered" % [d.name, action, d.sounds[action]]))
		if d.get("drops") is String and not str(d.drops).is_empty() and not item_ok.call(d.drops):
			issues.append(_issue("error", "block %s drops '%s', which does not exist" % [d.name, d.drops]))
		if d.has("container") and not server.containers.types.has(d.container):
			issues.append(_issue("error", "block %s uses container '%s', which is not registered" % [d.name, d.container]))
		if d.get("pair") is Dictionary and server.registry.id_of(str(d.pair.block)) < 0:
			issues.append(_issue("error", "block %s pairs with '%s', which does not exist" % [d.name, d.pair.block]))
		if d.textures.all(func(t): return str(t).is_empty()) and str(d.get("model", "")).is_empty() and d.render != preload("res://engine/shared/block_registry.gd").Render.INVISIBLE:
			issues.append(_issue("hint", "block %s has no textures or model" % d.name))
	for d in server.items.defs:
		if not str(d.name).begins_with(prefix):
			continue
		for r in d.get("teaches", []):
			if server.recipes.index_of(str(r)) < 0:
				issues.append(_issue("error", "item %s teaches recipe '%s', which does not exist" % [d.name, r]))
		var food: Dictionary = d.get("food", {})
		if not str(food.get("remainder", "")).is_empty() and not item_ok.call(str(food.remainder)):
			issues.append(_issue("error", "item %s leaves '%s' after eating, which does not exist" % [d.name, food.remainder]))
		if str(d.icon).is_empty() and str(d.get("model", "")).is_empty():
			issues.append(_issue("hint", "item %s has no icon" % d.name))
	for d in server.entities.registry.defs:
		if not str(d.name).begins_with(prefix):
			continue
		for drop in d.get("drops", []):
			if drop is Array and not drop.is_empty() and drop[0] is String and not item_ok.call(drop[0]):
				issues.append(_issue("error", "entity %s drops '%s', which does not exist" % [d.name, drop[0]]))
		for action in d.get("sounds", {}):
			if not sound_ok.call(str(d.sounds[action])):
				issues.append(_issue("warning", "entity %s: %s sound '%s' is not registered" % [d.name, action, d.sounds[action]]))
	# Guide pages, tutorials and tips.
	var reg = server.guide.registry
	for c in reg.chapters:
		if c.get("owner", "") == mod_id and not c.icon.is_empty() and not item_ok.call(c.icon):
			issues.append(_issue("warning", "guide chapter %s: icon '%s' does not exist" % [c.id, c.icon]))
	for page in reg.pages:
		if page.get("owner", "") != mod_id:
			continue
		if reg.get_chapter(page.chapter).is_empty():
			issues.append(_issue("error", "guide page %s: chapter '%s' does not exist" % [page.id, page.chapter]))
		if not page.icon.is_empty() and not item_ok.call(page.icon):
			issues.append(_issue("warning", "guide page %s: icon '%s' does not exist" % [page.id, page.icon]))
		var u: Dictionary = page.unlock
		if u.has("item") and not item_ok.call(u.item) or u.has("recipe") and server.recipes.index_of(u.recipe) < 0 \
				or u.has("entity") and not entity_ok.call(u.entity) or u.has("page") and reg.get_page(u.page).is_empty():
			issues.append(_issue("error", "guide page %s unlocks with %s, which does not exist (the page can never open)" % [page.id, u]))
		for b in page.blocks:
			for n in (b.get("items") if b.get("items") is Array else []):
				if not item_ok.call(str(n)):
					issues.append(_issue("warning", "guide page %s shows item '%s', which does not exist" % [page.id, n]))
			if b.has("output") and not item_ok.call(str(b.output)):
				issues.append(_issue("warning", "guide page %s shows recipes for '%s', which does not exist" % [page.id, b.output]))
			if b.has("entity") and not entity_ok.call(str(b.entity)):
				issues.append(_issue("warning", "guide page %s shows entity '%s', which does not exist" % [page.id, b.entity]))
			if b.type == "link" and reg.get_page(str(b.page)).is_empty():
				issues.append(_issue("warning", "guide page %s links to '%s', which does not exist" % [page.id, b.page]))
			if b.type == "keys" and not str(b.get("action", "")) in KEY_ACTIONS:
				issues.append(_issue("warning", "guide page %s names key action '%s' (known: %s)" % [page.id, b.get("action"), ", ".join(KEY_ACTIONS)]))
	for t in server.tutorials.tutorials.values():
		if t.owner != mod_id:
			continue
		for step in t.steps:
			if not step.page.is_empty() and reg.get_page(step.page).is_empty():
				issues.append(_issue("warning", "tutorial %s, step \"%s\": guide page '%s' does not exist" % [t.id, step.title, step.page]))
			issues.append_array(_goal_issues(server, "tutorial %s, step \"%s\"" % [t.id, step.title], step.goal, item_ok, entity_ok))
	for tip in server.tutorials.tips.values():
		if tip.owner != mod_id:
			continue
		if not tip.page.is_empty() and reg.get_page(tip.page).is_empty():
			issues.append(_issue("warning", "tip %s: guide page '%s' does not exist" % [tip.id, tip.page]))
		issues.append_array(_goal_issues(server, "tip %s" % tip.id, tip.trigger, item_ok, entity_ok))
	return issues


static func _goal_issues(server, where: String, goal: Dictionary, item_ok: Callable, entity_ok: Callable) -> Array:
	var issues := []
	var field := str(goal.get("field", ""))
	if goal.type == "have":
		field = "item"
	for target in goal.get("target", []):
		var ok := true
		match field:
			"item": ok = item_ok.call(target)
			"block": ok = target.contains("*") or server.registry.id_of(target) > 0
			"entity", "baby": ok = entity_ok.call(target)
			"recipe": ok = server.recipes.index_of(target) >= 0
			"page": ok = not server.guide.registry.get_page(target).is_empty()
		if not ok:
			issues.append(_issue("error", "%s: goal target '%s' does not exist, so it can never be completed" % [where, target]))
	return issues


## Files in the mod folder that nothing loads (not a script, data file or registered asset).
static func check_unused_files(server, mod_dir: String, manifest: Dictionary) -> Array:
	var used := {}
	for a in server._assets.values():
		used[ProjectSettings.globalize_path(a.path).simplify_path()] = true
	var issues := []
	for path in _files(mod_dir):
		var ext: String = path.get_extension().to_lower()
		if ext in DATA_EXTENSIONS or path.get_file().begins_with("README") or path.get_file().begins_with("LICENSE"):
			continue
		var rel: String = path.substr(mod_dir.length() + 1)
		if not used.has(ProjectSettings.globalize_path(path).simplify_path()):
			issues.append(_issue("hint", "%s is never used (players would not download it)" % rel, path))
		elif ext in TEXTURE_EXTENSIONS:
			var img := Image.load_from_file(path)
			if img != null and (img.get_width() > Protocol.MAX_TEXTURE_SIZE or img.get_height() > Protocol.MAX_TEXTURE_SIZE):
				issues.append(_issue("warning", "%s is %dx%d; textures over %d pixels are refused by clients" % [rel, img.get_width(), img.get_height(), Protocol.MAX_TEXTURE_SIZE], path))
	return issues


static func _files(dir: String) -> Array:
	var out := []
	var stack := [dir]
	while not stack.is_empty():
		var current: String = stack.pop_back()
		var access := DirAccess.open(current)
		if access == null:
			continue
		for sub in access.get_directories():
			if not sub.begins_with("."):
				stack.append(current.path_join(sub))
		for file in access.get_files():
			if not (file.ends_with(".import") or file.ends_with(".uid") or file.begins_with(".")):
				out.append(current.path_join(file))
	return out


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
