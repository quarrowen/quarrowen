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
	OS.set_environment("VOXEL_DATA_DIR", ProjectSettings.globalize_path("user://host_flow_test_%d" % Time.get_ticks_msec()))
	var main := Node.new()
	main.set_script(Main)
	add_child(main)
	var port := 25650 + randi() % 200
	main._host("vanilla", port, "Hoster")
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
	elif server_pid > 0:
		OS.kill(server_pid)
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
