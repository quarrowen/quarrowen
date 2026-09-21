extends Node
## The menu's "Host game" flow: launches a local server process, joins it, becomes admin through the
## admin token, then stops the server when leaving.
##   godot --headless --path . res://tests/host_flow_test.tscn

const Main = preload("res://engine/main.gd")

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Keep the hosted world out of the real user data folder.
	var data_dir := ProjectSettings.globalize_path("user://host_flow_test_%d" % Time.get_ticks_msec())
	OS.set_environment("QW_DATA_DIR", data_dir)
	var main := Node.new()
	main.set_script(Main)
	add_child(main)
	var port := 25650 + randi() % 200
	main._host("proving", port, "Hoster", PackedStringArray(["--mods-dir=tests/mods"]))
	var server_pid: int = main._server_pid
	_check(server_pid > 0 and OS.is_process_running(server_pid), "server process launched (pid %d)" % server_pid)

	var client = main._client
	var joined := await _wait(func(): return client != null and client._welcomed and client._can_simulate(), 40.0)
	_check(joined, "host client joined its own server")
	if joined:
		var admin := await _wait(func():
			for line in client._chat_log.get_children():
				if line.text.contains("You are an admin"):
					return true
			return false, 5.0)
		_check(admin, "host became admin via the launch token")
		client.disconnect_from_server()
		var stopped := await _wait(func(): return not OS.is_process_running(server_pid), 15.0)
		_check(stopped, "leaving stopped the hosted server")
		var worlds: Array = preload("res://engine/client/menu/world_list.gd").list(data_dir)
		_check(worlds.size() == 1 and worlds[0].game == "proving" and worlds[0].mods == ["proving"] and worlds[0].last_played > 0,
			"the hosted world shows in the menu's world list")
		_check(await _wait(func(): return main._menu.visible, 5.0), "leaving shows the menu again")
	elif server_pid > 0:
		OS.kill(server_pid)
	_remove_tree(data_dir)
	print("[host] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _wait(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _check(ok: bool, what: String) -> void:
	print("[host] %s %s" % ["ok  " if ok else "FAIL", what])
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
