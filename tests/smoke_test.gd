extends Node
## End-to-end test of the universal client against a running server:
##   godot --headless --path . -- --server --mods=proving,proving_js --world=test_proving --port=24600 &
##   godot --headless --path . res://tests/smoke_test.tscn -- --port=24600 --game=proving
##
## `--game` used to select between per-game check suites; there is one game now, so all it still does is
## name the bot (`Bot_proving`, which has to match an entry in the server's admin list). The six dead
## suites went with the games on 21 September 2026 - together they were 700 of this file's 1166 lines,
## none of it reachable. Exit code 0 = pass.

const GameClient = preload("res://engine/client/game_client.gd")
const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const Chunk = preload("res://engine/shared/chunk.gd")

var _client
var _game := "proving"
var _failures: Array[String] = []
var _arena := Vector3.ZERO


func _ready() -> void:
	var port := 24600
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.substr(7))
		elif arg.begins_with("--game="):
			_game = arg.substr(7)
	_client = GameClient.new()
	_client.server_port = port
	_client.player_name = "Bot_%s" % _game
	_client.identity_name = "bot_%s" % _game
	_client.ignore_mouse_capture = true
	_client.exited.connect(func(msg): _fail("client exited: %s" % msg); _finish())
	add_child(_client)
	_run.call_deferred()


func _run() -> void:
	if not await _wait_until(func(): return _client._can_simulate(), 20.0):
		_fail("never spawned (phase %d)" % _client.phase)
		return _finish()
	var c = _client
	print("[test] joined '%s' (%s): %d blocks, %d assets, downloaded %d bytes, spawn %s" % [
		c.server_info.get("name"), c.server_info.get("game"), c.registry.defs.size(), c._manifest.size(), c._download_total, c.state.position])
	_check(c.registry.defs.size() > 10, "received block registry")
	_check(not c._atlas.is_empty(), "built texture atlas from server assets")

	# Music, over a real connection. Two halves worth proving separately: that the soundtrack did NOT
	# join the download the player waited through, and that it arrives afterwards anyway.
	#
	# Unconditional now. This used to sit behind `if _game == "vanilla"`, and when the games were deleted
	# that stopped being true of anything - so the whole lazy-asset lane lost its only coverage silently,
	# which is the failure mode a gated check has and a plain one does not. The Proving Ground carries
	# the two tracks for exactly this reason. (2026-09-21)
	var tracks: int = c._music.registry.defs.size()
	_check(tracks >= 2, "the track list arrived with the rest of the content (%d)" % tracks)
	var music_bytes := 0
	for name: String in c._manifest:
		if c._manifest[name].get("lazy", false):
			music_bytes += int(c._manifest[name].size)
	_check(music_bytes > 100000, "the music is real and sizeable (%d bytes)" % music_bytes)
	# Not "the join download was small" - that only holds with a warm cache, and CI's is cold. The
	# property is that the join *passed over* every lazy byte, whatever was already on disk.
	_check(c.lazy_bytes_skipped == music_bytes,
		"and the join passed over every byte of it (%d skipped of %d)" % [c.lazy_bytes_skipped, music_bytes])
	# The server puts everyone on a track on a five-second timer and the client then fetches it.
	# Generous, because this asks "did it ever arrive", not "how fast": the whole suite runs several
	# servers at once and a tick that slows down stretches both the timer and the streaming. A
	# stopwatch tight enough to be meaningful here would only be measuring the machine's mood.
	var got := await _wait_until(func(): return c._music.playing >= 0, 90.0)
	_check(got, "the track was fetched after joining and started playing (wanted %d, playing %d, %d lazy bytes still missing)"
		% [c._music.wanted, c._music.playing, c.lazy_bytes_skipped if c._music.playing < 0 else 0])
	await _wait_until(func(): return c.state.on_ground, 5.0)

	await _proving(c)

	# Engine-level authority: an edit far out of reach must be rolled back.
	var far := Vector3i(floori(c.state.position.x) + 40, floori(c.state.position.y) - 1, floori(c.state.position.z))
	var far_before: int = c.world.get_block_v(far)
	if far_before != BlockRegistry.UNLOADED:
		var fake := 1 if far_before != 1 else 2
		c.world.set_block(far.x, far.y, far.z, fake)
		Net.c_break_block.rpc_id(1, far)
		await get_tree().create_timer(1.0).timeout
		_check(c.world.get_block_v(far) == far_before, "out-of-reach edit rolled back by server")
	_finish()


## The Proving Ground through a real client. Everything else here talks to a game that is about to be
## deleted; this is the one that stays, so it covers what only a real client can show - that blocks
## drawn with no texture still render, that a creature replicates, and that **riding works**, which
## nothing bundled could test before because nothing bundled was rideable.
func _proving(c) -> void:
	var rock: int = c.registry.id_of("proving:rock")
	var plain: int = c.registry.id_of("proving:plain")
	_check(rock > 0 and plain > 0, "the Proving Ground's own blocks reached the client")
	# No textures anywhere in that mod, so this is also the test that the magenta fallback works rather
	# than leaving a hole in the atlas.
	_check(c._atlas.uv.size() > 0, "the atlas built with no textures to put in it (%d entries)" % c._atlas.uv.size())

	# Build and break, through the ordinary client path.
	var under := Vector3i(floori(c.state.position.x), floori(c.state.position.y) - 1, floori(c.state.position.z))
	var spot := under + Vector3i(1, 1, 0)
	# c_place_block takes (position, yaw) and places whatever is *selected* - the block is not a
	# parameter. Passing it as one is silently wrong: the extra argument is dropped. (2026-09-21)
	if await _select_item(c, plain):
		Net.c_place_block.rpc_id(1, spot, 0.0)
		var placed := await _wait_until(func(): return c.world.get_block_v(spot) == plain, 5.0)
		_check(placed, "a block placed by the client is there on the server's word")
		# In creative for the break: the server times a survival break and refuses one that arrives
		# early, and this check is about the round trip rather than about mining speed.
		Net.c_chat.rpc_id(1, "/gamemode creative")
		await get_tree().create_timer(0.5).timeout
		Net.c_break_block.rpc_id(1, spot)
		_check(await _wait_until(func(): return c.world.get_block_v(spot) != plain, 5.0), "and breaking it takes it away")
		Net.c_chat.rpc_id(1, "/gamemode survival")
		await get_tree().create_timer(0.5).timeout

	# A creature, replicated.
	Net.c_chat.rpc_id(1, "/summon proving:grazer")
	var grazer := await _wait_for_entity(c, "proving:grazer", 6.0)
	_check(grazer >= 0, "a creature replicated to the client")

	# Riding. The vehicle capability shipped with its client half untested, because no bundled game had
	# anything to sit on. This is that test. (2026-09-21)
	Net.c_chat.rpc_id(1, "/summon proving:raft")
	var raft := await _wait_for_entity(c, "proving:raft", 6.0)
	_check(raft >= 0, "a raft replicated")
	if raft >= 0:
		Net.c_ride.rpc_id(1, raft)
		var aboard := await _wait_until(func(): return not c._riding.is_empty(), 5.0)
		_check(aboard, "the client was told it is riding (%s)" % ("" if aboard else _last_chat(c)))
		if aboard:
			# Sitting where the raft is drawn, rather than where the client would have walked to.
			var view = c._entities.get(raft)
			var near := await _wait_until(func():
				return view != null and c.state.position.distance_to(view.position) < 2.0, 5.0)
			_check(near, "and the rider follows the raft rather than predicting its own walk")
			Net.c_ride.rpc_id(1, raft)
			_check(await _wait_until(func(): return c._riding.is_empty(), 5.0), "and can get off again")

	# A panel the server drew, which is the UI path.
	Net.c_chat.rpc_id(1, "/panel")
	_check(await _wait_until(func(): return c._server_ui._panels.has("proving:corner"), 5.0),
		"a server-drawn panel reached the client")


func _last_chat(c) -> String:
	var log_node = c.get("_chat_log")
	if log_node == null or log_node.get_child_count() == 0:
		return "no message"
	return String(log_node.get_child(log_node.get_child_count() - 1).text)


func _select_item(c, item: int) -> bool:
	if not await _wait_until(func(): return c.inventory.ids.find(item) >= 0, 5.0):
		return false
	var slot: int = c.inventory.ids.find(item)
	if slot >= 9:
		# Hotbar full: swap it with the last hotbar slot through the inventory screen rules.
		c.inventory_click(slot)
		await _wait_until(func(): return c.inventory.cursor_id == item, 2.0)
		c.inventory_click(8)
		await _wait_until(func(): return c.inventory.ids[8] == item, 2.0)
		c.inventory_click(slot)
		await _wait_until(func(): return c.inventory.cursor_count == 0, 2.0)
		slot = 8
	if slot < 0 or slot >= 9:
		return false
	c.select_slot(slot)
	return await _wait_until(func(): return c.inventory.selected_item() == item, 2.0)


func _aim_at(c, target: Vector3) -> void:
	var d: Vector3 = target - (c.state.position + Vector3(0, 1.62, 0))
	c.yaw = atan2(-d.x, -d.z)
	c.pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -PI * 0.49, PI * 0.49)


## Id of the first replicated entity of `type_name`, or -1.
func _wait_for_entity(c, type_name: String, timeout: float) -> int:
	var found := [-1]
	await _wait_until(func():
		for id in c._entities:
			if c._entities[id].type_def.name == type_name and not c._entities[id].dying:
				found[0] = id
				return true
		return false, timeout)
	return found[0]


## Chases and attacks an entity until it dies. Returns true if it did.
## Where the last thing fought was standing when it died. A fleeing mob can die beyond the client's view,
## and then nothing it dropped is in c._entities to walk to - see _collect.


func _teleport_near(target: Vector3) -> void:
	var c = _client
	# A free spot next to the target at its height (not inside a hill, a tree or the target itself).
	for attempt in 8:
		var angle := TAU * attempt / 8.0 + randf() * 0.3
		var spot := target + Vector3(cos(angle), 0, sin(angle)) * 1.8
		var cell := Vector3i(floori(spot.x), floori(target.y + 0.1), floori(spot.z))
		var clear := true
		for dy in 2:
			var id: int = c.world.get_block_v(cell + Vector3i(0, dy, 0))
			clear = clear and (id == 0 or not c.registry.solid_lut[id] == 1)
		if clear and c.registry.solid_lut[c.world.get_block_v(cell + Vector3i.DOWN)] == 1:
			Net.c_chat.rpc_id(1, "/tp %.2f %.2f %.2f" % [spot.x, float(cell.y) + 0.05, spot.z])
			return
	Net.c_chat.rpc_id(1, "/tp %.2f %.2f %.2f" % [target.x + 1.8, target.y + 1.0, target.z])


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[test] ok   %s" % what)
	else:
		_fail(what)


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("[test] FAIL %s" % message)


func _finish() -> void:
	print("[test] %s" % ("PASSED" if _failures.is_empty() else "FAILED (%d)" % _failures.size()))
	get_tree().quit(0 if _failures.is_empty() else 1)
