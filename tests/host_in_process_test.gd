extends Node
## The same "Host game" flow as host_flow_test, with the world running **inside this process** rather
## than in a forked one:
##   godot --headless --path . res://tests/host_in_process_test.tscn
##
## **This path exists for iOS, and that is exactly why it is tested here.** iOS forbids
## `OS.create_process`, so a tablet can only host a world by running the server in the client's own
## process - and if the only way to reach that branch were to build, sign, install and read a log off a
## device, it would rot between the rare occasions anybody did. `QW_IN_PROCESS_SERVER=1` forces the
## same branch on a desktop, and this runs it on every commit. (2026-09-27)
##
## What it is really guarding is the division of one autoload: a `Net` node holds a single
## `multiplayer_peer`, so a server peer and a client peer cannot both be it. The server keeps the
## autoload and the client is handed a private copy on its own multiplayer branch. If that ever stops
## lining up, the symptom is a client that connects and is never greeted - which looks like a hang, not
## like a networking mistake.

const UserPaths = preload("res://engine/shared/user_paths.gd")
const Main = preload("res://engine/main.gd")

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var data_dir := ProjectSettings.globalize_path(UserPaths.path("host_in_process_test_%d" % OS.get_process_id()))
	OS.set_environment("QW_DATA_DIR", data_dir)
	OS.set_environment("QW_IN_PROCESS_SERVER", "1")
	_check(not Main.can_fork_a_server(), "the override makes this behave like a platform that cannot fork")

	var main := Node.new()
	main.set_script(Main)
	add_child(main)
	var port := 25900 + randi() % 200
	main._host("proving", port, "Hoster", PackedStringArray(["--mods-dir=tests/mods"]))

	_check(main._server_pid <= 0, "no second process was started")
	_check(main._local_server != null, "the world is a node in this process")
	# The whole point of the private branch: the client must not be talking through the autoload, which
	# the server is using for its own peer.
	var client = main._client
	_check(client != null and client.net != null and client.net != Net,
		"the client has its own networking node, not the autoload")

	var joined := await _wait(func(): return client != null and client._welcomed and client._can_simulate(), 60.0)
	_check(joined, "the client joined a world running in its own process")
	if joined:
		var admin := await _wait(func():
			for line in client._chat_log.get_children():
				if line.text.contains("You are an admin"):
					return true
			return false, 5.0)
		_check(admin, "and became admin through the launch token, as a forked host does")

		# **Where the camera is standing when a world changes.** The realm message carried only an id
		# and a name, so the client kept the old world's coordinates until some later snapshot moved
		# it - in a world whose chunks had just been unloaded, which draws as open sky. The floor was
		# measured at 434 ms to build, stream and mesh while screenshots four seconds later showed
		# nothing, and this is why. Asserted against the client's own position rather than a
		# photograph, which is what the note asking for this said it needed. (2026-09-30)
		var server = main._local_server._server  # the node hosts the GameServer; this is it
		var far := Vector3(220.5, 70.0, 220.5)
		var deep = server.add_realm("test:elsewhere", "Elsewhere")
		_check(deep != null, "a second world to step into")
		var p = server.players.values()[0] if not server.players.is_empty() else null
		_check(p != null, "the server knows about this player")
		if deep != null and p != null:
			var before: Vector3 = client.state.position
			_check(server.send_to_realm(p, "test:elsewhere", far), "the server moved them to it")
			# **The position is checked on the frame the world changes, not eventually.** A snapshot
			# from the server corrects it within a second or so either way, so waiting and then looking
			# passes whether this works or not - which is what the first version of this check did, and
			# it was a decoration. What is being measured is the gap: the frames between hearing about
			# the new world and standing in it, every one of which draws a torn-down world from the old
			# world's coordinates.
			var arrived_at := Vector3.INF
			var deadline := Time.get_ticks_msec() + 15000
			while Time.get_ticks_msec() < deadline:
				if client.realm == "test:elsewhere":
					arrived_at = client.state.position
					break
				await get_tree().process_frame
			_check(arrived_at != Vector3.INF, "the client heard about the new world")
			_check(arrived_at.distance_to(far) < 0.01,
				"and stands there on that very frame, not where the old world left it (%s, was %s)"
					% [arrived_at, before])
			_check(client._render_offset == Vector3.ZERO,
				"with no leftover smoothing dragging the camera back")

		client.disconnect_from_server()
		# Freed rather than killed - `_stop_local_server` has to end both kinds of world, or leaving one
		# would leave a server ticking inside the menu.
		var stopped := await _wait(func(): return main._local_server == null, 15.0)
		_check(stopped, "leaving stopped the world and freed it")
		_check(await _wait(func(): return main._menu.visible, 5.0), "leaving shows the menu again")

	_remove_tree(data_dir)
	print("[host-in-process] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _wait(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _check(ok: bool, what: String) -> void:
	print("[host-in-process] %s %s" % ["ok  " if ok else "FAIL", what])
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
