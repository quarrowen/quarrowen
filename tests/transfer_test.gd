extends Node
## Server transfers end to end: two real servers that trust each other (network.json), a client started
## through the main menu code. /transfer sends the player from A to B with their inventory; /server brings
## them back.
##   godot --headless --path . res://tests/transfer_test.tscn

const Main = preload("res://engine/main.gd")
const TransferTicket = preload("res://engine/shared/transfer_ticket.gd")

var _failures := 0
var _pids: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var work := ProjectSettings.globalize_path("user://transfer_test_%d" % Time.get_ticks_msec())
	var port_a := 26400 + randi() % 100 * 2
	var port_b := port_a + 10
	OS.set_environment("QW_KNOWN_SERVERS_DIR", work.path_join("known_servers"))
	# Each server's identity exists before it starts, so each network.json can name the other.
	var ids := {}
	for server_name in ["a", "b"]:
		var identity: Array = Net.load_or_create_server_identity(work.path_join(server_name).path_join("identity"))
		ids[server_name] = TransferTicket.key_id(identity[0])
	for pair in [["a", "b", port_b, "Server B"], ["b", "a", port_a, "Server A"]]:
		var f := FileAccess.open(work.path_join(pair[0]).path_join("network.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"servers": {pair[1]: {"name": pair[3], "address": "127.0.0.1", "port": pair[2], "id": ids[pair[1]],
			"inventory": true, "hop": true}}}))
		f.close()
	for pair in [["a", port_a, "Server A"], ["b", port_b, "Server B"]]:
		var args := PackedStringArray()
		if not OS.has_feature("template"):
			args.append_array(["--path", ProjectSettings.globalize_path("res://")])
		args.append_array(["--headless", "res://scenes/server.tscn", "--", "--mods=proving,proving_js", "--mods-dir=tests/mods", "--port=%d" % pair[1], "--name=%s" % pair[2],
			"--data-dir=%s" % work.path_join(pair[0]), "--world=w", "--admins=Traveller", "--query-port=0"])
		_pids.append(OS.create_process(OS.get_executable_path(), args))

	# Which address a travelling client actually dials. A network.json full of 127.0.0.1 - which is what
	# link-servers.sh used to write - would otherwise send every player to their own computer.
	const GameClient = preload("res://engine/client/game_client.gd")
	_check(GameClient.resolve_transfer_address("127.0.0.1", "192.168.1.20") == "192.168.1.20",
		"a loopback destination becomes the host we are already connected to")
	_check(GameClient.resolve_transfer_address("localhost", "quarrowen.example") == "quarrowen.example",
		"and so does 'localhost'")
	_check(GameClient.resolve_transfer_address("10.0.0.5", "192.168.1.20") == "10.0.0.5",
		"a real address is left alone")
	_check(GameClient.resolve_transfer_address("127.0.0.1", "127.0.0.1") == "127.0.0.1",
		"playing on this computer, loopback is right and is kept")

	var main := Node.new()
	main.set_script(Main)
	add_child(main)
	await get_tree().create_timer(3.0).timeout
	main._start_client("127.0.0.1", port_a, "Traveller", "")
	var on_a := await _wait(func(): return main._client != null and main._client._welcomed and main._client.server_port == port_a, 60.0)
	_check(on_a, "joined server A")
	if not on_a:
		return _finish(work)
	var client = main._client
	Net.c_chat.rpc_id(1, "/gamemode survival")
	await _wait(func(): return not client.inventory.creative, 5.0)
	Net.c_chat.rpc_id(1, "/give proving:token 7")
	var iron: int = client.items.id_of("proving:token")
	_check(await _wait(func(): return client.inventory.count_of(iron) >= 7, 5.0), "got 7 tokens on A")
	# The worlds panel lists the linked server and travels there with one press.
	client.open_worlds_panel()
	var listed := await _wait(func(): return not client._worlds_panel.last_state.is_empty(), 5.0)
	var state: Dictionary = client._worlds_panel.last_state
	_check(listed and state.worlds.size() == 2 and state.worlds[0].here, "the worlds panel lists this server and the linked one")
	_check(listed and state.worlds.any(func(w): return w.key == "b" and w.allowed), "and offers travel to Server B")
	client.close_settings()

	Net.c_chat.rpc_id(1, "/transfer Traveller b")
	var on_b := await _wait(func(): return main._client != null and main._client != client and main._client._welcomed and main._client.server_port == port_b, 60.0)
	_check(on_b, "/transfer moved the player to server B")
	if on_b:
		var b = main._client
		_check(str(b.server_info.get("name", "")) == "Server B" and b.player_name == "Traveller", "the client is on Server B as the same player (%s, %s)" % [b.server_info.get("name", ""), b.player_name])
		var iron_b: int = b.items.id_of("proving:token")
		_check(await _wait(func(): return b.inventory.count_of(iron_b) >= 7, 5.0), "the tokens travelled along (%d)" % b.inventory.count_of(iron_b))
		var welcomed := await _wait(func():
			for line in b._chat_log.get_children():
				if line.text.contains("Welcome from Server A"):
					return true
			return false, 5.0)
		_check(welcomed, "server B greets the traveller from Server A")
		Net.c_chat.rpc_id(1, "/server a")
		var back := await _wait(func(): return main._client != null and main._client != b and main._client._welcomed and main._client.server_port == port_a, 60.0)
		_check(back, "/server a brought the player back")
		if back:
			var a2 = main._client
			_check(await _wait(func(): return a2.inventory.count_of(a2.items.id_of("proving:token")) >= 7, 5.0), "the tokens came back too, and were not duplicated on A")
			_check(a2.inventory.count_of(a2.items.id_of("proving:token")) == 7, "exactly 7 tokens (%d)" % a2.inventory.count_of(a2.items.id_of("proving:token")))
	main._client.disconnect_from_server()
	await get_tree().create_timer(1.0).timeout
	_finish(work)


func _finish(work: String) -> void:
	for pid in _pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()
	OS.set_environment("QW_KNOWN_SERVERS_DIR", "")
	_remove_tree(work)
	print("[transfer] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _wait(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _check(ok: bool, what: String) -> void:
	print("[transfer] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _exit_tree() -> void:
	for pid in _pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
