extends Node
## The hub (services/hub) with a real game server: the server lists itself (signed, address proven by
## a status query), the menu's hub client browses and resolves its code, news comes through, forged
## announces are refused, and LAN discovery finds the server on this computer.
##   godot --headless --path . res://tests/hub_test.tscn -- --hub-bin=services/hub/target/release/voxelcraft-hub

const HubClient = preload("res://engine/client/menu/hub_client.gd")
const ServerPinger = preload("res://engine/client/menu/server_pinger.gd")
const InviteCode = preload("res://engine/shared/invite_code.gd")

var _failures := 0
var _pids: Array[int] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var hub_bin := ProjectSettings.globalize_path(str(args.get("hub-bin", "res://services/hub/target/release/voxelcraft-hub")))
	if not FileAccess.file_exists(hub_bin):
		print("[hub] SKIPPED (no hub binary at %s; build it with cargo build --release in services/hub)" % hub_bin)
		get_tree().quit(0)
		return
	var work := ProjectSettings.globalize_path("user://hub_test_%d" % Time.get_ticks_msec())
	DirAccess.make_dir_recursive_absolute(work.path_join("hub"))
	var news := FileAccess.open(work.path_join("hub/news.json"), FileAccess.WRITE)
	news.store_string(JSON.stringify([{"title": "Hub news", "body": "From the hub"}]))
	news.close()
	var hub_port := 24700 + randi() % 200
	var game_port := 25900 + randi() % 50 * 2
	OS.set_environment("HUB_BIND", "127.0.0.1:%d" % hub_port)
	OS.set_environment("HUB_DATA", work.path_join("hub"))
	OS.set_environment("HUB_ALLOW_PRIVATE", "1")
	_pids.append(OS.create_process(hub_bin, PackedStringArray()))
	var hub_url := "http://127.0.0.1:%d" % hub_port
	OS.set_environment("VOXEL_HUB", hub_url)
	var server_args := PackedStringArray()
	if not OS.has_feature("template"):
		server_args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	server_args.append_array(["--headless", "res://scenes/server.tscn", "--", "--mods=vanilla", "--port=%d" % game_port, "--name=Hub Test Server",
		"--hub=%s" % hub_url, "--tags=Test,Friendly", "--data-dir=%s" % work.path_join("server")])
	_pids.append(OS.create_process(OS.get_executable_path(), server_args))

	var client := HubClient.new()
	add_child(client)
	_check(HubClient.configured() and HubClient.hub_url() == hub_url, "the hub address comes from VOXEL_HUB")
	# The server lists itself once it is up and the hub has checked its address.
	var listed := {}
	var deadline := Time.get_ticks_msec() + 60000
	while listed.is_empty() and Time.get_ticks_msec() < deadline:
		client.list_servers("friendly")
		var answer: Array = await client.servers_received
		for s in answer[0]:
			if s.port == game_port:
				listed = s
		if listed.is_empty():
			await get_tree().create_timer(1.0).timeout
	_check(not listed.is_empty() and listed.name == "Hub Test Server" and listed.game == "vanilla" and listed.compatible
		and listed.tags == ["test", "friendly"] and listed.address == "127.0.0.1", "the server lists itself on the hub (%s)" % listed)
	var code: String = listed.get("code", "")
	_check(InviteCode.parse(code.to_lower()).get("hub_code", "") == code, "hub codes are recognised as invite codes (%s)" % code)
	client.list_servers("no such server")
	var none: Array = await client.servers_received
	_check(none[0].is_empty() and none[2] == "", "searching filters the list")
	client.resolve_code(code.replace("-", " "))
	var resolved: Array = await client.code_resolved
	_check(resolved[1] == "" and resolved[0].address == "127.0.0.1" and resolved[0].port == game_port and resolved[0].online, "a hub code resolves to the server")
	client.resolve_code("VC-000-000")
	var missing: Array = await client.code_resolved
	_check(not missing[1].is_empty(), "an unknown code is an error")
	client.fetch_news()
	var got_news: Array = await client.news_received
	_check(got_news[1] == "" and got_news[0].size() == 1 and got_news[0][0].title == "Hub news", "news comes from the hub")
	# Forgery: another key claiming this server's address cannot prove it; a bad signature is refused.
	var impostor := Crypto.new().generate_rsa(2048)
	var body := JSON.stringify({"key": impostor.save_to_string(true), "time": int(Time.get_unix_time_from_system()), "port": game_port, "name": "Fake"})
	var forged: Array = await _post(hub_url + "/v1/servers/announce", body, _sign(body, impostor))
	_check(forged[0] == 422 and str(forged[1]).contains("prove"), "an announce for someone else's address is refused (%s)" % [forged])
	var bad: Array = await _post(hub_url + "/v1/servers/announce", body, Marshalls.raw_to_base64(PackedByteArray([1, 2, 3])))
	_check(bad[0] == 401, "an announce with a bad signature is refused")
	# LAN discovery finds the server on this computer.
	var pinger := ServerPinger.new()
	var found := {}
	pinger.lan_found.connect(func(k, e): found[k] = e)
	pinger.discover_lan([game_port])
	deadline = Time.get_ticks_msec() + 3000
	while not found.has("this:%d" % game_port) and Time.get_ticks_msec() < deadline:
		pinger.update()
		await get_tree().process_frame
	var lan: Dictionary = found.get("this:%d" % game_port, {})
	_check(not lan.is_empty() and lan.info.name == "Hub Test Server" and lan.info.code == code, "LAN discovery finds the server, with its hub code")
	pinger.close()
	_stop_processes()
	OS.set_environment("VOXEL_HUB", "")
	_remove_tree(work)
	print("[hub] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _sign(body: String, key: CryptoKey) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body.to_utf8_buffer())
	return Marshalls.raw_to_base64(Crypto.new().sign(HashingContext.HASH_SHA256, ctx.finish(), key))


## [status, error text or parsed body]
func _post(url: String, body: String, signature: String) -> Array:
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url, PackedStringArray(["Content-Type: application/json", "X-Voxel-Signature: " + signature]), HTTPClient.METHOD_POST, body)
	var done: Array = await http.request_completed
	http.queue_free()
	var parsed = JSON.parse_string((done[3] as PackedByteArray).get_string_from_utf8())
	return [done[1], parsed.get("error", parsed) if parsed is Dictionary else parsed]


func _check(ok: bool, what: String) -> void:
	print("[hub] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _exit_tree() -> void:
	_stop_processes()


func _stop_processes() -> void:
	for pid in _pids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


static func _remove_tree(path: String) -> void:
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
