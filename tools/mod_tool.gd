extends Node
## Mod author tools (run headless):
##   godot --headless --path . res://tools/mod_tool.tscn -- validate mods/my_mod [--mods-dir=dir] [--json]
##   godot --headless --path . res://tools/mod_tool.tscn -- pack mods/my_mod [--out=build/mods] [--skip-validate]
##   godot --headless --path . res://tools/mod_tool.tscn -- new my_mod [--name="My Mod"] [--lang=gdscript|js] [--kind=addon|game]
##                                                                     [--author=Name] [--dir=mods]
##   godot --headless --path . res://tools/mod_tool.tscn -- index build/release/v1.2.3/mods --base-url=https://quarrowen.com/v1.2.3/mods
##                                                                     [--out=build/release/mods.json] [--version=1.2.3]
##   godot --headless --path . res://tools/mod_tool.tscn -- docs [--out=docs/api]
##   godot --headless --path . res://tools/mod_tool.tscn -- owned
##   godot --headless --path . res://tools/mod_tool.tscn -- coverage
## validate: checks the manifest, files, scripts, a real load and every reference (exit code 1 on errors).
## pack: validates, then writes <out>/<id>-<version>.zip, which servers load from any mods folder.
## index: reads a folder of packed mods and writes mods.json, the list the game's mod screen reads (see
## docs/distribution.md). Every entry carries a sha256, so nothing is installed without matching it.

const ModValidator = preload("res://engine/server/mod_validator.gd")
const ModLoader = preload("res://engine/server/mod_loader.gd")
const ModTemplates = preload("res://engine/server/mod_templates.gd")
const DocsGenerator = preload("res://tools/docs_generator.gd")
const Protocol = preload("res://engine/shared/protocol.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var positional := Array(args).filter(func(a): return not a.begins_with("--"))
	var options := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			options[kv[0]] = kv[1] if kv.size() > 1 else "true"
	if positional.size() >= 2 and positional[0] == "index":
		_index(ProjectSettings.globalize_path(str(positional[1])), options)
		return
	if positional.size() >= 1 and positional[0] == "docs":
		var out := ProjectSettings.globalize_path(str(options.get("out", "res://docs/api")))
		_out("wrote %s" % DocsGenerator.write(out))
		_out("wrote %s" % DocsGenerator.write_engine(out))
		for path in DocsGenerator.write_markdown(out):
			_out("wrote %s" % path)
		get_tree().quit(0)
		return
	if positional.size() >= 1 and positional[0] == "coverage":
		var Coverage = preload("res://tools/proving_coverage.gd")
		_out("wrote %s (%d capabilities the Proving Ground does not exercise)" % [Coverage.OUT, Coverage.write()])
		get_tree().quit(0)
		return
	if positional.size() >= 1 and positional[0] == "owned":
		var Encapsulation = preload("res://tools/encapsulation.gd")
		_out("wrote %s (%d reaching past an owner)" % [Encapsulation.OUT, Encapsulation.write()])
		get_tree().quit(0)
		return
	if positional.size() >= 1 and positional[0] == "bindings":
		var BindingsGenerator = preload("res://tools/bindings_generator.gd")
		_out("wrote %s (%d methods)" % [BindingsGenerator.OUT, BindingsGenerator.write()])
		for name in (BindingsGenerator.build().refused as Dictionary):
			_out("  stays GDScript-only: %s - %s" % [name, BindingsGenerator.build().refused[name]])
		var unbound: Array = DocsGenerator.unbound_js()
		var file := FileAccess.open(DocsGenerator.UNBOUND, FileAccess.WRITE)
		file.store_string(DocsGenerator.UNBOUND_HEADER + "\n".join(unbound) + "\n")
		file.close()
		_out("wrote %s (%d unbound)" % [DocsGenerator.UNBOUND, unbound.size()])
		for name in DocsGenerator.unkept_js():
			_out("warning: the TypeScript declares %s but js_mod.gd has no host method for it" % name)
		get_tree().quit(0)
		return
	if positional.size() >= 2 and positional[0] == "new":
		var parent := ProjectSettings.globalize_path(str(options.get("dir", "res://mods")))
		var created := ModTemplates.create(parent, {"id": str(positional[1]), "name": options.get("name", ""), "language": options.get("lang", "gdscript"),
			"kind": options.get("kind", "addon"), "author": options.get("author", "")})
		if not created.ok:
			_out("error: %s" % created.error)
			get_tree().quit(1)
			return
		_out("created %s (%s %s):" % [created.dir, created.language, "game" if created.game else "add-on"])
		for f in created.files:
			_out("  " + f)
		# Nothing may default to a game - they were deleted, and naming one here sent a new add-on
		# author to a mod that does not exist. An add-on needs a game to sit in, and only the author
		# knows which. (2026-09-22)
		_out("next: godot --path . -- --host=%s --dev" % positional[1] if created.game else
			"next: install a game, then: godot --path . -- --host=<game>,%s --dev" % positional[1])
		get_tree().quit(0)
		return
	if positional.size() < 2 or not positional[0] in ["validate", "pack"]:
		_out("usage: mod_tool.tscn -- validate <mod folder> [--mods-dir=dir] [--json]\n       mod_tool.tscn -- pack <mod folder> [--out=build/mods] [--skip-validate]\n       mod_tool.tscn -- new <id> [--name=] [--lang=gdscript|js] [--kind=addon|game] [--dir=mods]\n       mod_tool.tscn -- docs [--out=docs/api]")
		get_tree().quit(2)
		return
	var mod_dir := _resolve(str(positional[1]))
	if mod_dir.is_empty():
		_out("error: %s is not a mod folder (no mod.json)" % positional[1])
		get_tree().quit(2)
		return
	var search := PackedStringArray(str(options.get("mods-dir", "")).split(",", false))
	var result := {}
	if positional[0] == "validate" or options.get("skip-validate", "") != "true":
		result = ModValidator.validate(mod_dir, self, search)
		if options.get("json", "") == "true":
			_out(JSON.stringify(result, "  "))
		else:
			_out("\n".join(ModValidator.report(result)))
		if positional[0] == "validate":
			get_tree().quit(0 if result.ok else 1)
			return
		if not result.ok:
			_out("not packed: fix the errors first (or --skip-validate)")
			get_tree().quit(1)
			return
	var manifest := ModLoader.read_manifest(mod_dir)
	var out_dir := ProjectSettings.globalize_path(str(options.get("out", "res://build/mods")))
	var zip_path := out_dir.path_join("%s-%s.zip" % [manifest.id, manifest.version])
	var err := ModLoader.pack(mod_dir, zip_path)
	if err != OK:
		_out("error: could not write %s (%s)" % [zip_path, error_string(err)])
		get_tree().quit(1)
		return
	_out("packed %s %s -> %s (%d KB)" % [manifest.id, manifest.version, zip_path, FileAccess.get_file_as_bytes(zip_path).size() / 1024])
	get_tree().quit(0)


## Writes the mod index from a folder of packed zips: what each mod is, what it needs, where to get it and
## what it should hash to. Reading the zips (not their file names) keeps the index honest.
func _index(zip_dir: String, options: Dictionary) -> void:
	var dir := DirAccess.open(zip_dir)
	if dir == null:
		_out("error: %s is not a folder of packed mods" % zip_dir)
		get_tree().quit(2)
		return
	var base_url := str(options.get("base-url", "")).rstrip("/")
	var files := Array(dir.get_files()).filter(func(f): return str(f).get_extension().to_lower() == "zip")
	files.sort()
	var entries := []
	for file: String in files:
		var path := zip_dir.path_join(file)
		var unpacked := ModLoader.unpack(path)
		if unpacked.has("error"):
			_out("error: %s" % unpacked.error)
			get_tree().quit(1)
			return
		var manifest := ModLoader.read_manifest(unpacked.dir)
		if manifest.has("error"):
			_out("error: %s" % manifest.error)
			get_tree().quit(1)
			return
		var bytes := FileAccess.get_file_as_bytes(path)
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(bytes)
		var depends := []
		for dep in manifest.depends:
			depends.append("%s@%s" % [dep.id, dep.version] if not str(dep.version).is_empty() else str(dep.id))
		entries.append({
			"id": manifest.id,
			"name": manifest.name,
			"version": manifest.version,
			"description": manifest.description,
			"authors": manifest.get("authors", []),
			"kind": manifest.kind,
			"game": manifest.game,
			"depends": depends,
			"engine": manifest.engine,
			"url": "%s/%s" % [base_url, file],
			"sha256": digest.finish().hex_encode(),
			"size": bytes.size(),
		})
	var out_path := ProjectSettings.globalize_path(str(options.get("out", "res://build/release/mods.json")))
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var out_file := FileAccess.open(out_path, FileAccess.WRITE)
	if out_file == null:
		_out("error: could not write %s" % out_path)
		get_tree().quit(1)
		return
	out_file.store_string(JSON.stringify({"version": str(options.get("version", Protocol.GAME_VERSION)), "mods": entries}, "\t") + "\n")
	out_file.close()
	_out("wrote %s (%d mods)" % [out_path, entries.size()])
	get_tree().quit(0)


## A folder path, or a mod id under res://mods.
func _resolve(target: String) -> String:
	for candidate in [target, ProjectSettings.globalize_path("res://").path_join(target), "res://mods".path_join(target)]:
		if FileAccess.file_exists(str(candidate).path_join("mod.json")):
			return str(candidate).trim_suffix("/")
	return ""


## Tool output goes to stdout with a marker, so it stands out from the engine's own logging.
func _out(text: String) -> void:
	for line in text.split("\n"):
		print("[mod_tool] " + line)
