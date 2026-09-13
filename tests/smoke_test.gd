extends Node
## End-to-end test of the universal client against a running server:
##   godot --headless --path . -- --server --mods=vanilla --world=test_vanilla --port=24600 &
##   godot --headless --path . res://tests/smoke_test.tscn -- --port=24600 --game=vanilla
## --game selects game-specific checks (vanilla | skyblock). Exit code 0 = pass.

const GameClient = preload("res://engine/client/game_client.gd")
const BlockRegistry = preload("res://engine/shared/block_registry.gd")
const Chunk = preload("res://engine/shared/chunk.gd")

var _client
var _game := "vanilla"
var _failures: Array[String] = []


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
	await _wait_until(func(): return c.state.on_ground, 5.0)

	match _game:
		"vanilla":
			await _vanilla(c)
		"skyblock":
			await _skyblock(c)
		"industry":
			await _industry(c)
		"arcana":
			await _arcana(c)
		"guild":
			await _guild(c)

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


func _vanilla(c) -> void:
	_check(c.inventory.creative, "vanilla puts players in creative")
	_check(c.inventory.selected_block() == c.registry.id_of("base:grass"), "vanilla hotbar starts with grass")
	var start: Vector3 = c.state.position
	Input.action_press("move_forward")
	await get_tree().create_timer(1.5).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(1.0).timeout
	var moved := Vector2(c.state.position.x - start.x, c.state.position.z - start.z).length()
	print("[test] moved %.2f blocks, corrections %d" % [moved, c._correction_count])
	_check(moved > 1.0, "movement predicted and accepted")

	var feet: Vector3 = c.state.position
	var below := Vector3i(floori(feet.x), floori(feet.y) - 1, floori(feet.z))
	c.request_break(below)
	await get_tree().create_timer(1.0).timeout
	_check(c.world.get_block_v(below) == 0, "break confirmed")
	await _wait_until(func(): return c.state.on_ground, 3.0)
	var spot := _find_place_spot(c)
	c.select_slot(4)  # planks
	await get_tree().create_timer(0.2).timeout
	c.request_place(spot)
	await get_tree().create_timer(1.0).timeout
	_check(c.world.get_block_v(spot) == c.registry.id_of("base:planks"), "creative placement confirmed")
	_check(c.inventory.selected_block() == c.registry.id_of("base:planks"), "creative placement did not consume")


func _skyblock(c) -> void:
	_check(not c.inventory.creative, "skyblock puts players in survival")
	await _wait_until(func(): return c._server_ui.has_modal(), 3.0)
	_check(c._server_ui.has_modal(), "welcome dialog shown (server UI)")
	_check(c._server_ui._panels.has("skyblock:challenges"), "challenge panel shown (server UI)")
	c._on_ui_action("skyblock:welcome", "close")
	await get_tree().create_timer(0.5).timeout
	_check(not c._server_ui.has_modal(), "button action handled by server mod")

	var dirt: int = c.registry.id_of("base:dirt")
	var cobble: int = c.registry.id_of("base:cobblestone")
	_check(c.inventory.count_of(dirt) == 8, "starter items given (dirt=%d)" % c.inventory.count_of(dirt))

	var spot := _find_place_spot(c)
	c.select_slot(0)
	await get_tree().create_timer(0.2).timeout
	c.request_place(spot)
	await get_tree().create_timer(1.0).timeout
	_check(c.world.get_block_v(spot) == dirt, "survival placement confirmed")
	_check(c.inventory.count_of(dirt) == 7, "placement consumed an item (dirt=%d)" % c.inventory.count_of(dirt))

	var generator: int = c.registry.id_of("skyblock:generator")
	var gen_pos := _find_block_near(c, generator, 6)
	_check(gen_pos != Vector3i(0, -999, 0), "island has a generator")
	if gen_pos != Vector3i(0, -999, 0):
		var above := gen_pos + Vector3i.UP
		c.request_break(above)
		await get_tree().create_timer(0.5).timeout
		_check(c.inventory.count_of(cobble) == 1, "mined cobblestone went to inventory")
		await get_tree().create_timer(1.2).timeout
		_check(c.world.get_block_v(above) == cobble, "generator regrew cobblestone (mod scheduler)")
		c.request_break(gen_pos)
		await get_tree().create_timer(0.6).timeout
		_check(c.world.get_block_v(gen_pos) == generator, "mod vetoed breaking the generator")

	# Survival crafting: chop a log from the island tree, then craft planks in the engine menu.
	var log_id: int = c.registry.id_of("base:log")
	var log_pos := _find_block_near(c, log_id, 5)
	if log_pos != Vector3i(0, -999, 0):
		c.request_break(log_pos)
		await _wait_until(func(): return c.inventory.count_of(log_id) == 1, 3.0)
		_check(c.inventory.count_of(log_id) == 1, "chopped a log")
		Net.c_open_menu.rpc_id(1, "crafting")
		await _wait_until(func(): return c._server_ui._panels.has("engine:crafting"), 3.0)
		_check(c._server_ui._panels.has("engine:crafting"), "crafting menu opened")
		c._on_ui_action("engine:crafting", "craft:0")
		var planks: int = c.registry.id_of("base:planks")
		await _wait_until(func(): return c.inventory.count_of(planks) == 4, 3.0)
		_check(c.inventory.count_of(planks) == 4 and c.inventory.count_of(log_id) == 0, "crafted 4 planks from the log")
		c._on_ui_action("engine:crafting", "close")
		await get_tree().create_timer(0.4).timeout
	else:
		_fail("no log found near spawn")

	# Walk off the island into the void; the mod should return us home.
	var home: Vector3 = c.state.position
	c.yaw = PI  # face +Z along the island's long arm, away from the generator
	Input.action_press("move_forward")
	await get_tree().create_timer(2.5).timeout
	Input.action_release("move_forward")
	var fell := await _wait_until(func(): return c.state.position.y < 40.0, 4.0)
	var returned := await _wait_until(func(): return c.state.position.y > 60.0 and c.state.position.distance_to(home) < 4.0, 6.0)
	_check(fell and returned, "void fall teleported back to island (y=%.1f)" % c.state.position.y)


func _industry(c) -> void:
	var r = c.registry
	var ids := {}
	for n in ["cable", "coal_generator", "lamp", "lamp_on", "battery", "miner"]:
		ids[n] = r.id_of("industry:" + n)
	_check(r.defs[ids.lamp_on].light == 15, "lamp_on emits light (registry replicated)")
	_check(r.defs[ids.coal_generator].render == r.Render.MODEL and r.interactive_lut[ids.coal_generator] == 1, "generator is an interactive model block")
	_check(c._model_meshes.has(ids.coal_generator), "generator glTF model downloaded and loaded")

	Net.c_chat.rpc_id(1, "/industry kit")
	await _wait_until(func(): return c.inventory.ids[0] == ids.cable, 3.0)
	_check(c.inventory.ids[1] == ids.coal_generator, "kit command filled the hotbar")

	# Lay generator - cable - lamp in a row on the ground next to the player.
	var row := _find_row(c, 3)
	_check(row.size() == 3, "found space for a machine row")
	if row.size() != 3:
		return
	for step in [[1, row[0]], [0, row[1]], [4, row[2]]]:
		c.select_slot(step[0])
		await get_tree().create_timer(0.2).timeout
		c.request_place(step[1])
		await get_tree().create_timer(0.4).timeout
	_check(c.world.get_block_v(row[0]) == ids.coal_generator and c.world.get_block_v(row[2]) == ids.lamp, "machines placed")
	await get_tree().create_timer(0.5).timeout
	var expected_facing: int = c.registry.facing_from_yaw(c.yaw)
	_check(c.get_block_state(row[0]) == expected_facing, "generator faces the player (state %d, expected %d)" % [c.get_block_state(row[0]), expected_facing])
	_check(c._arm_meshes.has(ids.cable), "cable arm model loaded")
	await _wait_until(func(): return not c._model_nodes.is_empty(), 3.0)
	_check(not c._model_nodes.is_empty(), "model blocks rendered as instances")
	var arm_instances := 0
	for nodes in c._model_nodes.values():
		for mmi in nodes:
			if mmi.multimesh.mesh == c._arm_meshes.get(ids.cable):
				arm_instances += mmi.multimesh.instance_count
	_check(arm_instances == 2, "cable draws arms toward generator and lamp (%d arms)" % arm_instances)

	await get_tree().create_timer(0.6).timeout
	_check(c.world.get_block_v(row[2]) == ids.lamp, "lamp stays off without power")
	Net.c_interact.rpc_id(1, row[0])
	await _wait_until(func(): return c._server_ui._panels.has("industry:machine"), 3.0)
	_check(c._server_ui._panels.has("industry:machine"), "right-click opened the generator panel")
	c._on_ui_action("industry:machine", "fuel")
	var lit := await _wait_until(func(): return c.world.get_block_v(row[2]) == ids.lamp_on, 3.0)
	_check(lit, "fuelled generator powered the lamp through the cable")
	c._on_ui_action("industry:machine", "close")
	await get_tree().create_timer(0.4).timeout
	_check(not c._server_ui.has_modal(), "panel closed")

	c.request_break(row[1])
	var off := await _wait_until(func(): return c.world.get_block_v(row[2]) == ids.lamp, 3.0)
	_check(off, "breaking the cable cut power to the lamp")


func _arcana(c) -> void:
	var shard: int = c.items.id_of("arcana:mana_shard")
	var blink: int = c.items.id_of("arcana:wand_of_blink")
	var light_wand: int = c.items.id_of("arcana:wand_of_light")
	var crystal: int = c.registry.id_of("arcana:mana_crystal_ore")
	var orb: int = c.registry.id_of("arcana:light_orb")
	_check(shard >= 65536 and c.items.is_usable(blink), "items replicated (shard %d, usable wand)" % shard)
	var found := 0
	for chunk in c.world.chunks.values():
		if Chunk.contains(chunk.blocks, crystal):
			found += 1
	_check(found > 0, "generation pass placed mana crystals in %d chunks" % found)
	await _wait_until(func(): return c._server_ui._panels.has("arcana:mana"), 3.0)
	_check(c._server_ui._panels.has("arcana:mana"), "mana HUD shown")

	Net.c_chat.rpc_id(1, "/arcana kit")
	await _wait_until(func(): return c.inventory.ids[1] == blink, 3.0)
	_check(c.inventory.ids[1] == blink and c.inventory.ids[2] == light_wand, "kit put wands in the hotbar")

	c.select_slot(1)
	c.pitch = 0.0
	await get_tree().create_timer(0.3).timeout
	var before: Vector3 = c.state.position
	c.use_selected_item()
	var moved := await _wait_until(func(): return c.state.position.distance_to(before) > 2.5, 3.0)
	_check(moved, "Wand of Blink teleported the player %.1f blocks" % c.state.position.distance_to(before))
	var label: Label = c._server_ui._panels["arcana:mana"].get_child(0).get_child(0)
	_check(label.text.contains("80") or label.text.contains("81") or label.text.contains("82"), "blink cost mana (%s)" % label.text)

	await _wait_until(func(): return c.state.on_ground, 3.0)
	c.select_slot(2)
	c.pitch = -1.2
	await get_tree().create_timer(0.4).timeout
	var target: Dictionary = c._target
	_check(target.hit, "aiming at the ground")
	if target.hit:
		var orb_pos: Vector3i = target.position + target.normal
		c.use_selected_item()
		var conjured := await _wait_until(func(): return c.world.get_block_v(orb_pos) == orb, 3.0)
		_check(conjured and c.registry.defs[orb].light == 15, "Wand of Light conjured a light orb")


func _guild(c) -> void:
	var board: int = c.registry.id_of("guild:quest_board")
	var coin: int = c.items.id_of("guild:gold_coin")
	var gold_ore: int = c.registry.id_of("guild:gold_ore")
	var meteorite: int = c.registry.id_of("guild:meteorite")
	_check(board > 0 and coin >= 65536 and c.registry.defs[meteorite].light == 13, "JavaScript mod registered blocks, items and light")
	var ore_chunks := 0
	for chunk in c.world.chunks.values():
		if Chunk.contains(chunk.blocks, gold_ore):
			ore_chunks += 1
	_check(ore_chunks > 0, "JavaScript ore pass generated gold ore in %d chunks" % ore_chunks)

	Net.c_chat.rpc_id(1, "/guild kit")
	await _wait_until(func(): return c.inventory.ids[0] == board, 3.0)
	_check(c.inventory.ids[0] == board, "JavaScript command filled the hotbar")
	var row := _find_row(c, 1)
	if row.is_empty():
		_fail("no space for the quest board")
		return
	c.select_slot(0)
	await get_tree().create_timer(0.2).timeout
	c.request_place(row[0])
	await get_tree().create_timer(0.6).timeout
	_check(c.world.get_block_v(row[0]) == board, "quest board placed")

	Net.c_interact.rpc_id(1, row[0])
	await _wait_until(func(): return c._server_ui._panels.has("guild:board"), 3.0)
	_check(c._server_ui._panels.has("guild:board"), "quest board UI opened (JavaScript block_interact)")
	c._on_ui_action("guild:board", "accept:artisan")
	await _wait_until(func(): return c._server_ui._panels.has("guild:tracker"), 3.0)
	_check(c._server_ui._panels.has("guild:tracker"), "quest accepted, tracker shown")
	c._on_ui_action("guild:board", "close")
	await get_tree().create_timer(0.3).timeout

	Net.c_open_menu.rpc_id(1, "crafting")
	await _wait_until(func(): return c._server_ui._panels.has("engine:crafting"), 3.0)
	for i in 3:
		c._on_ui_action("engine:crafting", "craft:0")
		await get_tree().create_timer(0.3).timeout
	c._on_ui_action("engine:crafting", "close")
	await get_tree().create_timer(0.5).timeout
	var tracker: Control = c._server_ui._panels.get("guild:tracker")
	var tracker_text: String = tracker.get_child(0).get_child(1).text if tracker else ""
	_check(tracker_text.contains("3/3"), "item_crafted events advanced the quest (%s)" % tracker_text)

	Net.c_interact.rpc_id(1, row[0])
	await _wait_until(func(): return c._server_ui._panels.has("guild:board"), 3.0)
	c._on_ui_action("guild:board", "turn_in")
	var paid := await _wait_until(func(): return c.inventory.count_of(coin) == 4, 3.0)
	_check(paid, "turning in paid 4 gold coins (%d)" % c.inventory.count_of(coin))
	c._on_ui_action("guild:board", "buy:0")
	var bought := await _wait_until(func(): return c.inventory.count_of(coin) == 3, 3.0)
	_check(bought and c.inventory.count_of(c.registry.id_of("base:glass")) >= 8, "shop sold glass for a coin")
	c._on_ui_action("guild:board", "close")
	await get_tree().create_timer(0.3).timeout

	Net.c_chat.rpc_id(1, "/guild meteor")
	var landed := await _wait_until(func():
		for chunk in c.world.chunks.values():
			if Chunk.contains(chunk.blocks, meteorite):
				return true
		return false, 4.0)
	_check(landed, "meteor landed (JavaScript world edits replicated)")
	Net.c_chat.rpc_id(1, "/guild top")
	await _wait_until(func(): return c._server_ui._panels.has("guild:leaderboard"), 3.0)
	var board_panel: Control = c._server_ui._panels.get("guild:leaderboard")
	var first_line: String = board_panel.get_child(0).get_child(1).text if board_panel else ""
	_check(first_line.contains("Bot_guild - 1"), "leaderboard from mod storage (%s)" % first_line)


## `length` air cells in a straight line with solid ground under each, within reach of the player
## but not overlapping them. Nearest candidate wins.
func _find_row(c, length: int) -> Array:
	var feet: Vector3 = c.state.position
	var base := Vector3i(floori(feet.x), floori(feet.y), floori(feet.z))
	var best := []
	var best_dist := INF
	for dy in [0, -1, 1]:
		for ox in range(-4, 5):
			for oz in range(-4, 5):
				for dir in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
					var cells := []
					for i in length:
						var p: Vector3i = base + Vector3i(ox, dy, oz) + dir * i
						var center := Vector3(p) + Vector3(0.5, 0.5, 0.5)
						if c.world.get_block_v(p) != 0 or c.registry.solid_lut[c.world.get_block_v(p + Vector3i.DOWN)] != 1 \
								or Vector2(center.x - feet.x, center.z - feet.z).length() < 1.5 \
								or center.distance_to(feet + Vector3(0, 1.62, 0)) > 4.5:
							break
						cells.append(p)
					var d := Vector2(ox, oz).length() + absi(dy)
					if cells.size() == length and d < best_dist:
						best = cells
						best_dist = d
	return best


## An air block within reach, beside the player, with a solid block under it.
func _find_place_spot(c) -> Vector3i:
	var feet: Vector3 = c.state.position
	var base := Vector3i(floori(feet.x), floori(feet.y), floori(feet.z))
	for dy in [0, 1, -1]:
		for dir in [Vector3i(2, 0, 0), Vector3i(-2, 0, 0), Vector3i(0, 0, 2), Vector3i(0, 0, -2), Vector3i(1, 0, -1), Vector3i(-1, 0, 1)]:
			var p: Vector3i = base + dir + Vector3i(0, dy, 0)
			if c.world.get_block_v(p) == 0 and c.registry.solid_lut[c.world.get_block_v(p + Vector3i.DOWN)] == 1:
				return p
	return base + Vector3i(0, 3, 0)


func _find_block_near(c, id: int, radius: int) -> Vector3i:
	var feet: Vector3 = c.state.position
	var base := Vector3i(floori(feet.x), floori(feet.y), floori(feet.z))
	for x in range(-radius, radius + 1):
		for y in range(-3, 4):
			for z in range(-radius, radius + 1):
				if c.world.get_block_v(base + Vector3i(x, y, z)) == id:
					return base + Vector3i(x, y, z)
	return Vector3i(0, -999, 0)


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
