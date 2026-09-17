extends Node
## Reloading end to end: hosts a local --dev server with a small mod in a temporary folder, joins it,
## edits the mod (the file watcher reloads it), adds a block and runs /reload full, and checks the
## client comes back by itself with the new block.
##   godot --headless --path . res://tests/reload_test.tscn

const Main = preload("res://engine/main.gd")

const MOD_V1 := """extends "res://engine/server/mod.gd"

func setup(api) -> void:
	api.register_block("crate", {"textures": "", "hardness": 1.0})
	api.register_command("greet", "Say hi", func(player, _args): player.send_message("greeting v1"))
"""
const MOD_V2 := """extends "res://engine/server/mod.gd"

func setup(api) -> void:
	api.register_block("crate", {"textures": "", "hardness": 2.0})
	api.register_command("greet", "Say hi", func(player, _args): player.send_message("greeting v2"))
"""
const MOD_V3 := MOD_V2 + """	api.register_block("barrel", {"textures": ""})
"""

var _failures := 0
var _mod_dir := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var root := ProjectSettings.globalize_path("user://reload_test_%d" % Time.get_ticks_msec())
	OS.set_environment("QW_DATA_DIR", root.path_join("data"))
	_mod_dir = root.path_join("mods/liveblock")
	DirAccess.make_dir_recursive_absolute(_mod_dir)
	_write("mod.json", JSON.stringify({"id": "liveblock", "name": "Live block", "version": "1.0.0", "depends": ["base"]}))
	_write("main.gd", MOD_V1)
	var main := Node.new()
	main.set_script(Main)
	add_child(main)
	var port := 25850 + randi() % 100
	main._host("vanilla,liveblock", port, "Author", PackedStringArray(["--dev", "--mods-dir=%s" % root.path_join("mods")]))
	var server_pid: int = main._server_pid
	var client = main._client
	var joined := await _wait(func(): return client != null and client._welcomed and client._can_simulate(), 40.0)
	_check(joined, "joined the --dev server")
	if joined:
		_chat(main, "/greet")
		_check(await _chat_seen(main, "greeting v1", 5.0), "the mod's first version answers")
		# Save a new version: the dev file watcher reloads it.
		await get_tree().create_timer(1.1).timeout  # file times have one-second resolution
		_write("main.gd", MOD_V2)
		_check(await _chat_seen(main, "Reloaded liveblock", 10.0), "saving the script reloads the mod (watcher)")
		_chat(main, "/greet")
		_check(await _chat_seen(main, "greeting v2", 5.0), "the reloaded command runs the new code")
		# A new block needs a full reload: the client must come back by itself.
		await get_tree().create_timer(1.1).timeout
		_write("main.gd", MOD_V3)
		_check(await _chat_seen(main, "barrel needs a full reload", 10.0), "a new block asks for a full reload")
		_chat(main, "/reload full")
		var dropped := await _wait(func(): return main._client != client, 20.0)
		_check(dropped, "the client leaves for the full reload")
		var back := await _wait(func(): return main._client != null and main._client._welcomed and main._client._can_simulate(), 60.0)
		_check(back, "the client reconnects to the restarted server")
		if back:
			_check(main._client.registry.id_of("liveblock:barrel") > 0, "after the full reload the new block exists")
			_check(OS.is_process_running(server_pid), "the same server process restarted in place")
		if main._client != null:
			main._client.disconnect_from_server()
		await _wait(func(): return not OS.is_process_running(server_pid), 15.0)
	if OS.is_process_running(server_pid):
		OS.kill(server_pid)
	_remove_tree(root)
	print("[reload] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _write(file: String, text: String) -> void:
	var f := FileAccess.open(_mod_dir.path_join(file), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _chat(main, text: String) -> void:
	Net.c_chat.rpc_id(1, text)


func _chat_seen(main, needle: String, timeout: float) -> bool:
	return await _wait(func():
		if main._client == null:
			return false
		for line in main._client._chat_log.get_children():
			if line.text.contains(needle):
				return true
		return false, timeout)


func _wait(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _check(ok: bool, what: String) -> void:
	print("[reload] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
