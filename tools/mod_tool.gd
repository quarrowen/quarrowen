extends Node
## Mod author tools (run headless):
##   godot --headless --path . res://tools/mod_tool.tscn -- validate mods/my_mod [--mods-dir=dir] [--json]
##   godot --headless --path . res://tools/mod_tool.tscn -- pack mods/my_mod [--out=build/mods] [--skip-validate]
##   godot --headless --path . res://tools/mod_tool.tscn -- new my_mod [--name="My Mod"] [--lang=gdscript|js] [--kind=addon|game]
##                                                                     [--author=Name] [--dir=mods]
##   godot --headless --path . res://tools/mod_tool.tscn -- docs [--out=docs/api]
## validate: checks the manifest, files, scripts, a real load and every reference (exit code 1 on errors).
## pack: validates, then writes <out>/<id>-<version>.zip, which servers load from any mods folder.

const ModValidator = preload("res://engine/server/mod_validator.gd")
const ModLoader = preload("res://engine/server/mod_loader.gd")
const ModTemplates = preload("res://engine/server/mod_templates.gd")
const DocsGenerator = preload("res://tools/docs_generator.gd")


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
	if positional.size() >= 1 and positional[0] == "docs":
		var out := ProjectSettings.globalize_path(str(options.get("out", "res://docs/api")))
		var written := DocsGenerator.write(out)
		_out("wrote %s" % written)
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
		_out("next: godot --path . -- --host=%s --dev" % (positional[1] if created.game else "vanilla," + positional[1]))
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
