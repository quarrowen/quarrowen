extends Node
## Two real clients on one server. This process is "Alice"; it launches "Bob" as a second Godot
## process and both verify they see each other move, see each other's edits, receive chat and see
## each other's avatar cosmetics (Bob joins wearing a crown, then changes to a top hat).
##   godot --headless --path . res://tests/multiplayer_test.tscn -- --port=25601

const GameClient = preload("res://engine/client/game_client.gd")

var _port := 25601
var _role := "a"
var _result_path := ""
var _failures := 0
var _client


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			match kv[0]:
				"port": _port = int(kv[1])
				"role": _role = kv[1]
				"result": _result_path = kv[1]
	_client = GameClient.new()
	_client.server_port = _port
	_client.player_name = "Alice" if _role == "a" else "Bob"
	_client.identity_name = "mp_%s" % _role
	_client.ignore_mouse_capture = true
	_client.avatar = {} if _role == "a" else {"skin": "#8c5a3a", "wear": {
		"hat": {"id": "builtin:crown", "color": "#e8c040"}, "shirt": {"id": "builtin:tshirt", "color": "#d94c4c"}}}
	add_child(_client)
	(_alice if _role == "a" else _bob).call_deferred()


func _alice() -> void:
	if not await _wait(func(): return _client._can_simulate(), 20.0):
		_check(false, "Alice joined")
		return _finish()
	_result_path = ProjectSettings.globalize_path("user://multiplayer_result_%d.txt" % Time.get_ticks_msec())
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "res://tests/multiplayer_test.tscn",
		"--", "--port=%d" % _port, "--role=b", "--result=%s" % _result_path])
	var bob_pid := OS.create_process(OS.get_executable_path(), args)
	_check(bob_pid > 0, "launched Bob's client process")

	var sees_bob := await _wait(func(): return _remote("Bob") != null, 25.0)
	_check(sees_bob, "Alice sees Bob join")
	if sees_bob:
		var hat := func(id: String) -> bool:
			var bob = _remote("Bob")
			if bob == null or not bob.avatar.attachments.has("hat") or bob.avatar.attachments.hat.get_node_or_null("cosmetic_hat") == null:
				return false
			return _client._appearances.get(bob.peer_id, {}).get("avatar", {}).get("wear", {}).get("hat", {}).get("id", "") == id
		_check(await _wait(hat.bind("builtin:crown"), 10.0), "Alice sees Bob's crown")
		var bob_look: Dictionary = _client._appearances.get(_remote("Bob").peer_id, {}).get("avatar", {})
		var torso_front: Color = _client._looks.skin_image(bob_look).get_pixel(21, 24)  # skin layout: torso front
		_check(torso_front.r > 0.6 and torso_front.g < 0.45, "Bob's red t-shirt is on his skin (%s)" % torso_front)
		_write_result("change_hat", "1")
		_check(await _wait(hat.bind("builtin:top_hat"), 10.0), "Alice sees Bob change to a top hat")

	if sees_bob:
		var start: Vector3 = _remote("Bob").position
		var moved := await _wait(func(): return _remote("Bob") != null and _remote("Bob").position.distance_to(start) > 2.0, 15.0)
		_check(moved, "Alice sees Bob walk (interpolated snapshots)")

	var placed := await _wait(func(): return _read_result().has("placed"), 20.0)
	if placed:
		var p: PackedStringArray = _read_result().placed.split(",")
		var pos := Vector3i(int(p[0]), int(p[1]), int(p[2]))
		var planks: int = _client.registry.id_of("base:planks")
		_check(await _wait(func(): return _client.world.get_block_v(pos) == planks, 5.0), "Alice sees Bob's placed block")
	else:
		_check(false, "Bob placed a block")

	Net.c_chat.rpc_id(1, "hello bob")
	var bob_heard := await _wait(func(): return _read_result().get("chat", "") == "ok", 10.0)
	_check(bob_heard, "Bob received Alice's chat")
	var bob_saw := await _wait(func(): return _read_result().has("saw_alice"), 5.0)
	_check(bob_saw, "Bob saw Alice")
	_write_result("done", "1")
	await _wait(func(): return not OS.is_process_running(bob_pid), 10.0)
	var gone := await _wait(func(): return _remote("Bob") == null or not _remote("Bob").visible, 10.0)
	_check(gone, "Bob's avatar removed after he left")
	DirAccess.remove_absolute(_result_path)
	_finish()


func _bob() -> void:
	if not await _wait(func(): return _client._can_simulate(), 20.0):
		get_tree().quit(1)
		return
	if await _wait(func(): return _remote("Alice") != null, 10.0):
		_write_result("saw_alice", "1")
	await _wait(func(): return _read_result().has("change_hat"), 20.0)
	var changed: Dictionary = _client.avatar.duplicate(true)
	changed.wear.hat = {"id": "builtin:top_hat", "color": "#2a2a2a"}
	Net.c_set_avatar.rpc_id(1, changed)
	# Place a plank next to where we stand, then walk so Alice sees movement.
	_client.select_slot(4)
	await get_tree().create_timer(0.3).timeout
	var feet: Vector3 = _client.state.position
	var target := Vector3i(floori(feet.x) + 2, floori(feet.y), floori(feet.z))
	for dy in [0, 1, -1, 2]:
		var candidate := target + Vector3i(0, dy, 0)
		if _client.world.get_block_v(candidate) == 0 and _client.registry.solid_lut[_client.world.get_block_v(candidate + Vector3i.DOWN)] == 1:
			target = candidate
			break
	_client.request_place(target)
	await get_tree().create_timer(0.5).timeout
	_write_result("placed", "%d,%d,%d" % [target.x, target.y, target.z])
	_client.yaw = PI * 0.5
	Input.action_press("move_forward")
	Input.action_press("jump")  # hop over steps in rolling terrain
	await get_tree().create_timer(2.0).timeout
	Input.action_release("jump")
	Input.action_release("move_forward")
	var heard := await _wait(func():
		for line in _client._chat_log.get_children():
			if line.text.contains("hello bob"):
				return true
		return false, 15.0)
	_write_result("chat", "ok" if heard else "missing")
	await _wait(func(): return _read_result().has("done"), 20.0)
	get_tree().quit(0)


func _remote(player_name: String):
	for remote in _client._remote_players.values():
		for child in remote.get_children():
			if child is Label3D and child.text == player_name:
				return remote
	return null


func _read_result() -> Dictionary:
	var out := {}
	if FileAccess.file_exists(_result_path):
		for line in FileAccess.get_file_as_string(_result_path).split("\n", false):
			out[line.get_slice("=", 0)] = line.get_slice("=", 1)
	return out


func _write_result(key: String, value: String) -> void:
	var existing := FileAccess.get_file_as_string(_result_path) if FileAccess.file_exists(_result_path) else ""
	var file := FileAccess.open(_result_path, FileAccess.WRITE)
	file.store_string(existing + "%s=%s\n" % [key, value])
	file.close()


func _wait(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _check(ok: bool, what: String) -> void:
	print("[multiplayer] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _finish() -> void:
	print("[multiplayer] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
