extends Node
## Identity and permission checks against a running server started with VOXEL_ADMINS=Admin:
##   godot --headless --path . res://tests/auth_test.tscn -- --port=25601
## Clients connect one after another with different identities.

const GameClient = preload("res://engine/client/game_client.gd")

var _port := 25601
var _failures := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			_port = int(arg.substr(7))
	_run.call_deferred()


func _run() -> void:
	# 1. A guest claims a name, gets saved items, cannot use admin commands.
	var guest = await _join("auth_guest", "Guest")
	if guest == null:
		return _finish()
	var chat := await _chat(guest, "/time night", "permission")
	_check(chat, "non-admin is refused /time")
	await _chat(guest, "/whoami", "player id")
	var guest_id := _last_line(guest).get_slice("player id ", 1).left(32)
	_check(guest_id.length() == 32, "player id derived from key (%s)" % guest_id)
	# Change the hotbar away from the default creative one so the restore check means something.
	var gold_ore: int = guest.registry.id_of("guild:gold_ore")
	Net.c_chat.rpc_id(1, "/guild kit")
	await _wait(func(): return guest.inventory.ids[3] == gold_ore, 3.0)
	var slot_item: int = guest.inventory.ids[3]
	_check(slot_item == gold_ore, "guest changed their hotbar")
	await _leave(guest)

	# 2. Someone else with a different key cannot take the name.
	var impostor = await _join("auth_impostor", "Guest", true)
	_check(impostor is String and impostor.contains("belongs to another player"), "different key cannot claim a taken name (%s)" % str(impostor))

	# 3. The original key gets its saved state back.
	guest = await _join("auth_guest", "Guest")
	if guest != null:
		_check(guest.inventory.ids[3] == slot_item, "saved data follows the identity key")
		await _leave(guest)

	# 4. A configured admin can use admin commands and /op others.
	var admin = await _join("auth_admin", "Admin")
	if admin != null:
		_check(await _chat(admin, "/time noon", "set the time"), "admin may use /time")
		await _leave(admin)

	# 5. A tampered signature is rejected.
	var tampered = await _join("auth_tampered", "Tampered", true, true)
	_check(tampered is String and tampered.contains("Authentication failed"), "bad signature rejected (%s)" % str(tampered))
	_finish()


## Returns the client once in-game, or the exit message String when `expect_failure`.
func _join(identity: String, player_name: String, expect_failure := false, tamper := false):
	var client = GameClient.new()
	client.server_port = _port
	client.player_name = player_name
	client.identity_name = identity
	client.ignore_mouse_capture = true
	var result := {"message": null}
	client.exited.connect(func(msg): result.message = msg)
	if tamper:
		client.test_signing_key = Crypto.new().generate_rsa(1024)
	add_child(client)
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if result.message != null:
			client.queue_free()
			return result.message if expect_failure else _fail_join(player_name, result.message)
		if client._welcomed and client._can_simulate():
			return client if not expect_failure else "joined unexpectedly"
	client.queue_free()
	return "timed out" if expect_failure else _fail_join(player_name, "timed out")


func _fail_join(player_name: String, message) -> Variant:
	_check(false, "%s could not join: %s" % [player_name, message])
	return null


func _wait(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _leave(client) -> void:
	client._leave("")
	client.queue_free()
	await get_tree().create_timer(0.8).timeout


func _chat(client, text: String, expect: String) -> bool:
	var before: int = client._chat_log.get_child_count()
	Net.c_chat.rpc_id(1, text)
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		for i in range(before, client._chat_log.get_child_count()):
			if client._chat_log.get_child(i).text.contains(expect):
				return true
	return false


func _last_line(client) -> String:
	var count: int = client._chat_log.get_child_count()
	return client._chat_log.get_child(count - 1).text if count > 0 else ""


func _check(ok: bool, what: String) -> void:
	print("[auth] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _finish() -> void:
	print("[auth] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
