extends Node
## Mod author tools (run headless):
##   godot --headless --path . res://tools/mod_tool.tscn -- validate mods/my_mod [--mods-dir=dir] [--json]
##   godot --headless --path . res://tools/mod_tool.tscn -- pack mods/my_mod [--out=build/mods] [--skip-validate]
## validate: checks the manifest, files, scripts, a real load and every reference (exit code 1 on errors).
## pack: validates, then writes <out>/<id>-<version>.zip, which servers load from any mods folder.

const ModValidator = preload("res://engine/server/mod_validator.gd")
const ModLoader = preload("res://engine/server/mod_loader.gd")


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
	if positional.size() < 2 or not positional[0] in ["validate", "pack"]:
		_out("usage: mod_tool.tscn -- validate <mod folder> [--mods-dir=dir] [--json]\n       mod_tool.tscn -- pack <mod folder> [--out=build/mods] [--skip-validate]")
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
