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
		"combat":
			await _combat(c)

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

	# The rest works on flat open ground: generated plains roll and are full of tall grass.
	var yard := _find_open_ground(c, Vector2i(floori(c.state.position.x) + 16, floori(c.state.position.z)))
	Net.c_chat.rpc_id(1, "/tp %.1f %.1f %.1f" % [yard.x, yard.y, yard.z])
	await _wait_until(func(): return c.state.position.distance_to(yard) < 1.0 and c.state.on_ground, 5.0)
	await _clear_plants(c, 5)

	# Farming: till grass with a hoe, plant seeds on the farmland (crossed-quad plant block).
	Net.c_chat.rpc_id(1, "/give base:wooden_hoe")
	Net.c_chat.rpc_id(1, "/give base:wheat_seeds 4")
	var hoe: int = c.items.id_of("base:wooden_hoe")
	var seeds: int = c.items.id_of("base:wheat_seeds")
	await _wait_until(func(): return c.inventory.count_of(hoe) == 1 and c.inventory.count_of(seeds) >= 1, 3.0)
	var soil := _find_open_grass(c)
	_check(soil != Vector3i(0, -999, 0), "found open grass to farm")
	if soil != Vector3i(0, -999, 0):
		var farmland: int = c.registry.id_of("base:farmland")
		await _select_item(c, hoe)
		_aim_at(c, Vector3(soil) + Vector3(0.5, 0.98, 0.5))
		await get_tree().create_timer(0.3).timeout
		c.use_selected_item()
		_check(await _wait_until(func(): return c.world.get_block_v(soil) == farmland, 3.0), "the hoe tilled grass into farmland")
		await _select_item(c, seeds)
		_aim_at(c, Vector3(soil) + Vector3(0.5, 0.98, 0.5))
		await get_tree().create_timer(0.6).timeout  # let the server see the new selection
		c.use_selected_item()
		if not await _wait_until(func(): return c.world.get_block_v(soil + Vector3i.UP) == c.registry.id_of("base:wheat_0"), 1.5):
			c.use_selected_item()  # the first use can race the hotbar change
		var wheat: int = c.registry.id_of("base:wheat_0")
		_check(await _wait_until(func(): return c.world.get_block_v(soil + Vector3i.UP) == wheat, 3.0) \
			and c.registry.defs[wheat].render == c.BlockRegistry.Render.PLANT, "seeds planted wheat (a plant block)")

	# Containers: place a chest, open it, shift-click a stack in, see it in the container screen.
	Net.c_chat.rpc_id(1, "/give base:chest")
	var chest: int = c.items.id_of("base:chest")
	await _wait_until(func(): return c.inventory.count_of(chest) >= 1, 3.0)
	await _select_item(c, chest)
	await _wait_until(func(): return c.state.on_ground, 3.0)
	var chest_spot := _find_place_spot(c)
	c.request_place(chest_spot)
	_check(await _wait_until(func(): return c.world.get_block_v(chest_spot) == chest, 3.0), "placed a chest")
	Net.c_interact.rpc_id(1, chest_spot)
	_check(await _wait_until(func(): return c._inventory_screen.visible and c._inventory_screen.container.get("size", 0) == 27, 3.0),
		"right-clicking the chest opened its 27-slot screen")
	var stone_slot: int = c.inventory.ids.find(c.registry.id_of("base:stone"))
	if stone_slot >= 0:
		c.inventory_click(stone_slot, 1, true)
		_check(await _wait_until(func():
			var packed: PackedInt32Array = c._inventory_screen.container.get("slots", PackedInt32Array())
			return packed.size() == 54 and packed[0] == c.registry.id_of("base:stone"), 3.0), "shift-click moved stone into the chest")
	c._set_inventory_open(false)
	await get_tree().create_timer(0.3).timeout

	# Co-op station: place a crafting table (you own it), open it, put a stack in its shared tray.
	Net.c_chat.rpc_id(1, "/give base:crafting_table")
	var table_item: int = c.items.id_of("base:crafting_table")
	await _wait_until(func(): return c.inventory.count_of(table_item) >= 1, 3.0)
	await _select_item(c, table_item)
	var table_spot := _find_place_spot(c)
	c.request_place(table_spot)
	await _wait_until(func(): return c.world.get_block_v(table_spot) == table_item, 3.0)
	Net.c_interact.rpc_id(1, table_spot)
	_check(await _wait_until(func(): return c._crafting_screen.visible and c._crafting_screen.station.get("name") == "crafting_table", 3.0),
		"right-clicking a crafting table opens its station screen")
	_check(await _wait_until(func(): return c._crafting_screen.session.get("players", []).size() == 1, 3.0) \
		and c._crafting_screen.session.owner == c.player_name, "the station session lists you as present and as its owner")
	var deposit_slot := -1
	for i in 9:
		if c.inventory.ids[i] > 0 and c.inventory.counts[i] > 0:
			deposit_slot = i
			break
	Net.c_station_coop.rpc_id(1, "deposit", deposit_slot)
	_check(await _wait_until(func(): return c._crafting_screen.session.get("tray", []).size() == 1, 3.0), "a stack went into the shared tray")
	_check(c._crafting_screen.session.tray[0].by_name == c.player_name, "the tray remembers who contributed it")
	c._set_crafting_open(false)
	await get_tree().create_timer(0.3).timeout

	# Tools from parts: forge an iron head, a bone handle and a binding at a Tool Forge, then assemble.
	Net.c_chat.rpc_id(1, "/give base:tool_forge")
	Net.c_chat.rpc_id(1, "/give base:iron_ingot 8")
	Net.c_chat.rpc_id(1, "/give vanilla:bone 2")
	var forge_item: int = c.items.id_of("base:tool_forge")
	await _wait_until(func(): return c.inventory.count_of(forge_item) >= 1 and c.inventory.count_of(c.items.id_of("vanilla:bone")) >= 1, 3.0)
	await _select_item(c, forge_item)
	var forge_spot := _find_place_spot(c)
	c.request_place(forge_spot)
	await _wait_until(func(): return c.world.get_block_v(forge_spot) == forge_item, 3.0)
	Net.c_interact.rpc_id(1, forge_spot)
	_check(await _wait_until(func(): return c._crafting_screen.visible and c._crafting_screen._mode_forge.visible, 3.0),
		"a Tool Forge offers the Assemble tab")
	for recipe_id in ["base:pickaxe_head/base:iron", "base:tool_handle/vanilla:bone", "base:binding/base:iron"]:
		Net.c_craft.rpc_id(1, c.recipes.index_of(recipe_id), 1)
		await get_tree().create_timer(0.3).timeout
	var part_items: Array = ["base:pickaxe_head", "base:tool_handle", "base:binding"].map(func(n): return c.items.id_of(n))
	_check(await _wait_until(func(): return part_items.all(func(id): return c.inventory.count_of(id) >= 1), 3.0), "forged the three pickaxe parts")
	c._crafting_screen.set_forge_mode()
	await get_tree().process_frame
	var forged: int = c.items.id_of("base:forged_pickaxe")
	var part_slots := PackedInt32Array(part_items.map(func(id): return c.inventory.ids.find(id)))
	c._crafting_screen.assemble_requested.emit("base:forged_pickaxe", part_slots)
	_check(await _wait_until(func(): return c.inventory.count_of(forged) >= 1, 3.0), "assembled a pickaxe from parts")
	var forged_slot: int = c.inventory.ids.find(forged)
	if forged_slot >= 0:
		var forged_data: Dictionary = c.inventory.data[forged_slot]
		_check(forged_data.get("tool", {}).get("tier", 0) == 3 and c._item_icons.texture(forged, forged_data) is ImageTexture,
			"the forged pickaxe has iron-tier stats and a composed icon")

	# Crafting by hand: stitching a leather helmet starts the minigame; stopping still makes the item.
	Net.c_chat.rpc_id(1, "/give vanilla:leather 5")
	var helmet: int = c.items.id_of("vanilla:leather_helmet")
	var helmets_before: int = c.inventory.count_of(helmet)
	_check(c._crafting_screen.minigames.has("vanilla:stitching"), "minigames arrive with the content")
	Net.c_interact.rpc_id(1, table_spot)
	await _wait_until(func(): return c._crafting_screen.station.get("name") == "crafting_table", 3.0)
	await _wait_until(func(): return c.inventory.count_of(c.items.id_of("vanilla:leather")) >= 5, 3.0)
	c._crafting_screen.skill_requested.emit({"recipe": c.recipes.index_of("vanilla:leather_helmet")}, true, false)
	_check(await _wait_until(func(): return c._minigame_screen.is_active() and c._minigame_screen._phase() == "playing", 3.0),
		"stitch by hand opens the minigame")
	await get_tree().create_timer(0.5).timeout
	c._minigame_screen.input_sent.emit("quit", c._minigame_screen.game_time(), 0)
	_check(await _wait_until(func(): return c._minigame_screen._phase() == "done" and c.inventory.count_of(helmet) > helmets_before, 3.0),
		"stopping the minigame still makes a Standard helmet")
	c._minigame_screen.close()
	c._set_crafting_open(false)
	await get_tree().create_timer(0.3).timeout

	# Structures: select a box, save it as a template and place it again.
	Net.c_chat.rpc_id(1, "/struct pos1")
	await get_tree().create_timer(0.3).timeout
	c.yaw += 0.6
	await get_tree().create_timer(0.3).timeout
	Net.c_chat.rpc_id(1, "/struct pos2")
	_check(await _wait_until(func(): return c._selection_box != null and c._selection_box.visible, 3.0), "the structure selection box shows")
	Net.c_chat.rpc_id(1, "/struct save smoke_test_hut")
	_check(await _wait_until(func():
		for line in c._chat_log.get_children():
			if line.text.contains("Saved template world:smoke_test_hut"):
				return true
		return false, 3.0), "a selection saves as a template")

	# Farm animals: dyeing a sheep reaches other clients as a tinted wool part.
	Net.c_chat.rpc_id(1, "/give vanilla:dye_red")
	var red_dye: int = c.items.id_of("vanilla:dye_red")
	await _wait_until(func(): return c.inventory.count_of(red_dye) >= 1, 3.0)
	await _select_item(c, red_dye)
	Net.c_chat.rpc_id(1, "/summon vanilla:sheep")
	var sheep_id := await _wait_for_entity(c, "vanilla:sheep", 4.0)
	_check(sheep_id >= 0, "a sheep appeared")
	if sheep_id >= 0:
		await get_tree().create_timer(0.3).timeout
		Net.c_interact_entity.rpc_id(1, sheep_id)
		_check(await _wait_until(func():
			var view = c._entities.get(sheep_id)
			return view != null and view._part_meshes.has("wool") and view._part_meshes.wool.get_surface_override_material(0) != null, 3.0),
			"the dyed sheep's wool is tinted on the client")


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
		var pickaxe: int = c.items.id_of("base:wooden_pickaxe")
		_check(c.inventory.count_of(pickaxe) == 1, "starter kit has a wooden pickaxe")
		c.select_slot(c.inventory.ids.find(pickaxe))
		await get_tree().create_timer(0.3).timeout
		var started := Time.get_ticks_msec()
		await c.mine_block(above)
		await _wait_until(func(): return c.inventory.count_of(cobble) == 1, 2.0)
		_check(c.inventory.count_of(cobble) == 1, "mined cobblestone with the pickaxe (%.1f s)" % ((Time.get_ticks_msec() - started) / 1000.0))
		var wear: int = c.inventory.data[c.inventory.ids.find(pickaxe)].get("damage", 0)
		_check(wear == 1, "mining wore the pickaxe (damage %d)" % wear)
		await get_tree().create_timer(1.2).timeout
		_check(c.world.get_block_v(above) == cobble, "generator regrew cobblestone (mod scheduler)")
		await c.mine_block(gen_pos)
		await get_tree().create_timer(0.6).timeout
		_check(c.world.get_block_v(gen_pos) == generator, "mod vetoed breaking the generator")

	# Survival crafting: chop a log from the island tree, then craft planks in the engine menu.
	var log_id: int = c.registry.id_of("base:log")
	var log_pos := _find_block_near(c, log_id, 5)
	if log_pos != Vector3i(0, -999, 0):
		await c.mine_block(log_pos)
		await _wait_until(func(): return c.inventory.count_of(log_id) == 1, 3.0)
		_check(c.inventory.count_of(log_id) == 1, "chopped a log")
		c._set_crafting_open(true)
		_check(await _wait_until(func(): return c._crafting_screen.visible, 3.0), "crafting screen opened")
		var planks_recipe: int = c.recipes.index_of("base:planks")
		_check(planks_recipe >= 0 and c._crafting_screen.craftable_times(planks_recipe) == 1, "the recipe book knows a log makes planks once")
		var table_recipe: int = c.recipes.index_of("base:wooden_pickaxe")
		_check(c._crafting_screen.at_station(c.recipes.recipes[table_recipe]) == false, "pickaxes are marked as needing a crafting table")
		c.craft_recipe(planks_recipe)
		var planks: int = c.registry.id_of("base:planks")
		await _wait_until(func(): return c.inventory.count_of(planks) == 4, 3.0)
		_check(c.inventory.count_of(planks) == 4 and c.inventory.count_of(log_id) == 0, "crafted 4 planks from the log")
		_check(await _wait_until(func(): return c._toast.modulate.a > 0.5, 2.0), "a crafted toast popped up")
		c.pin_recipe(table_recipe)
		_check(c._pin_panel.visible and c._pin_rows.get_child_count() >= 3, "pinning a recipe shows its ingredients on the HUD")
		c.pin_recipe(-1)
		c._set_crafting_open(false)
		# Discovery: mining cobblestone taught gravel (blueprints are checked in the combat test).
		_check(c._crafting_screen.discovery and c._crafting_screen.known.has("base:gravel") and not c._crafting_screen.known.has("base:forge"),
			"picking up cobblestone discovered its recipes, blueprint ones stay hidden")

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
	# Work on flat open ground away from spawn (plains roll and have tall grass and cave openings).
	var yard := _find_open_ground(c, Vector2i(floori(c.state.position.x) - 16, floori(c.state.position.z) + 8))
	Net.c_chat.rpc_id(1, "/tp %.1f %.1f %.1f" % [yard.x, yard.y, yard.z])
	await _wait_until(func(): return c.state.position.distance_to(yard) < 1.0 and c.state.on_ground, 5.0)
	await _clear_plants(c, 5)
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
	await _wait_until(func(): return not c._model_nodes.is_empty(), 10.0)
	_check(not c._model_nodes.is_empty(), "model blocks rendered as instances")
	var count_arms := func() -> int:
		var arms := 0
		for nodes in c._model_nodes.values():
			for mmi in nodes:
				if mmi.multimesh.mesh == c._arm_meshes.get(ids.cable):
					arms += mmi.multimesh.instance_count
		return arms
	# The chunk remeshes after each placement; the GDScript mesher can take a moment.
	await _wait_until(func(): return count_arms.call() == 2, 10.0)
	var arm_instances: int = count_arms.call()
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
	# Effects and the mana HUD come on the reliable channel, which can trail the (unreliable) position update
	# while the world is still streaming right after joining.
	_check(await _wait_until(func(): return c.effects_seen.get("arcana:blink", 0) >= 2, 6.0), "blink effects played where you left and arrived")
	var label: Label = c._server_ui._panels["arcana:mana"].get_child(0).get_child(0)
	await _wait_until(func(): return not label.text.contains("100 /"), 6.0)
	_check(label.text.contains("80") or label.text.contains("81") or label.text.contains("82") or label.text.contains("83"), "blink cost mana (%s)" % label.text)

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

	c._set_crafting_open(true)
	await _wait_until(func(): return c._crafting_screen.visible, 3.0)
	for i in 3:
		c.craft_recipe(c.recipes.index_of("base:planks"))
		await get_tree().create_timer(0.3).timeout
	c._set_crafting_open(false)
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
	if not bought:  # the click can land while the board is being redrawn after the turn-in; try once more
		c._on_ui_action("guild:board", "buy:0")
		bought = await _wait_until(func(): return c.inventory.count_of(coin) == 3, 3.0)
	_check(bought and c.inventory.count_of(c.registry.id_of("base:glass")) >= 8, "shop sold glass for a coin (coins %d, glass %d, board open %s, last chat: %s)" % [
		c.inventory.count_of(coin), c.inventory.count_of(c.registry.id_of("base:glass")), c._server_ui._panels.has("guild:board"),
		c._chat_log.get_child(c._chat_log.get_child_count() - 1).text if c._chat_log.get_child_count() > 0 else ""])
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


func _combat(c) -> void:
	# Other tests build and dig around the shared spawn; fight on untouched, dry, open ground.
	_arena = _find_open_ground(c, Vector2i(floori(c.state.position.x) + 32, floori(c.state.position.z)))
	await _return_to_arena(c)
	Net.c_chat.rpc_id(1, "/gameplay mob_spawning false")
	Net.c_chat.rpc_id(1, "/clearmobs 128")  # cave monsters from earlier tests
	Net.c_chat.rpc_id(1, "/time midnight")  # zombies burn in daylight
	Net.c_chat.rpc_id(1, "/gamemode survival")
	var sword: int = c.items.id_of("base:stone_sword")
	await _wait_until(func(): return not c.inventory.creative and c.inventory.count_of(sword) == 1, 3.0)
	_check(not c.inventory.creative and c.inventory.count_of(sword) == 1, "switched to survival with a sword")
	_check(c.health == 20.0 and c._hearts.visible, "health HUD shows 20 (%.1f)" % c.health)
	_check(await _wait_until(func(): return c.hunger == 20.0 and c._hunger_bar.visible, 3.0), "hunger HUD shows 20 (%.1f)" % c.hunger)

	# Hunger: eat an apple by holding use.
	var apple: int = c.items.id_of("base:apple")
	var had_apples: int = c.inventory.count_of(apple)  # a shared server: earlier runs may have left some
	Net.c_chat.rpc_id(1, "/hunger 10")
	Net.c_chat.rpc_id(1, "/give base:apple")
	await _wait_until(func(): return c.hunger == 10.0 and c.inventory.count_of(apple) == had_apples + 1, 3.0)
	var apples: int = c.inventory.count_of(apple)
	await _select_item(c, apple)
	await get_tree().create_timer(0.3).timeout
	Input.action_press("place")
	c.use_selected_item()
	_check(c._view_model.eating(), "eating starts the plate animation")
	_check(await _wait_until(func(): return c.hunger == 14.0 and c.inventory.count_of(apple) == apples - 1, 3.0),
		"holding use ate the apple (hunger %.1f, apples %d -> %d)" % [c.hunger, apples, c.inventory.count_of(apple)])
	_check(await _wait_until(func(): return not c._view_model.eating(), 2.0), "the eating animation ends with the meal")
	Input.action_release("place")
	Net.c_chat.rpc_id(1, "/feed")
	_check(c.entity_types.id_of("vanilla:pig") > 0 and c._entity_parts.get(c.entity_types.id_of("vanilla:pig"), []).size() == 6,
		"entity types and animated model parts replicated")
	await _select_item(c, sword)

	# A pig: chase it, kill it, pick up what it drops.
	var sounds_before: int = c._sounds.played
	Net.c_chat.rpc_id(1, "/summon vanilla:pig")
	var pig := await _wait_for_entity(c, "vanilla:pig", 4.0)
	_check(pig >= 0, "summoned pig replicated to the client")
	if pig >= 0:
		_check(await _fight(c, pig, 15.0), "killed the pig with the sword")
		var porkchop: int = c.items.id_of("vanilla:porkchop")
		_check(await _collect(c, porkchop, 10.0), "picked up the porkchop the pig dropped")
		_check(c._sounds.played > sounds_before, "combat played sounds (%d)" % (c._sounds.played - sounds_before))

	# A bounty zombie from the JavaScript guild mod: it attacks us; killing it pays coins.
	var coin: int = c.items.id_of("guild:gold_coin")
	var coins_before: int = c.inventory.count_of(coin)
	Net.c_chat.rpc_id(1, "/guild bounty")
	var zombie := await _wait_for_entity(c, "vanilla:zombie", 4.0)
	_check(zombie >= 0, "bounty zombie spawned by JavaScript")
	if zombie >= 0:
		var hurt := await _wait_until(func(): return c.health < 20.0, 4.0)
		if not hurt and c._entities.has(zombie):
			_teleport_near(c._entities[zombie].position)  # it may have got stuck on terrain
			hurt = await _wait_until(func(): return c.health < 20.0, 6.0)
		_check(hurt, "the zombie attacked (health %.1f)" % c.health)
		_check(await _fight(c, zombie, 15.0), "killed the zombie")
		var paid := await _wait_until(func(): return c.inventory.count_of(coin) >= coins_before + 5, 3.0)
		_check(paid, "bounty paid 5 coins via JavaScript entity_death")

	# Beds: set the respawn point by day, sleep through the night.
	# Fights chase mobs and teleport next to them: come back to the open ground for the next checks.
	await _return_to_arena(c)
	Net.c_chat.rpc_id(1, "/give base:bed")
	var bed: int = c.items.id_of("base:bed")
	await _wait_until(func(): return c.inventory.count_of(bed) >= 1, 3.0)
	await _select_item(c, bed)
	await _wait_until(func(): return c.state.on_ground, 3.0)
	# Face an open two-block strip so the head has room behind the foot.
	var bed_spot := Vector3i(0, -999, 0)
	var base := Vector3i(floori(c.state.position.x), floori(c.state.position.y), floori(c.state.position.z))
	for step in [2, 3, 1]:
		for dy in [0, 1, -1]:
			for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				var foot: Vector3i = base + d * step + Vector3i(0, dy, 0)
				var free := true
				for cell in [foot, foot + d]:
					var id: int = c.world.get_block_v(cell)
					free = free and (id == 0 or c.registry.defs[id].replaceable) and c.registry.solid_lut[c.world.get_block_v(cell + Vector3i.DOWN)] == 1
				if free and bed_spot.y == -999:
					bed_spot = foot
					c.yaw = atan2(-float(d.x), -float(d.z))
	if bed_spot.y == -999:
		print("[test] no room for a bed around %s" % base)
	c.request_place(bed_spot)
	var head_block: int = c.registry.id_of("base:bed_head")
	if await _wait_until(func(): return c.world.get_block_v(bed_spot) == bed and head_block in [
			c.world.get_block_v(bed_spot + Vector3i(1, 0, 0)), c.world.get_block_v(bed_spot + Vector3i(-1, 0, 0)),
			c.world.get_block_v(bed_spot + Vector3i(0, 0, 1)), c.world.get_block_v(bed_spot + Vector3i(0, 0, -1))], 3.0):
		Net.c_chat.rpc_id(1, "/time midnight")
		Net.c_chat.rpc_id(1, "/clearmobs 32")
		await get_tree().create_timer(0.5).timeout
		Net.c_interact.rpc_id(1, bed_spot)
		_check(await _wait_until(func(): return not c._sleep.is_empty() and c._sleep_panel.visible, 3.0),
			"lay down in a bed at night (%s)" % c._server_ui._subtitle.text)
		_check(await _wait_until(func(): return c._sleep.is_empty(), 8.0), "slept through the night and woke up")
		_check(c._time_of_day > 0.2 and c._time_of_day < 0.4, "it is morning after sleeping (%.2f)" % c._time_of_day)
		Net.c_chat.rpc_id(1, "/time midnight")  # zombies burn in daylight
	else:
		_fail("could not place a bed")

	# Eat the pig's porkchop.
	var porkchop: int = c.items.id_of("vanilla:porkchop")
	if c.inventory.count_of(porkchop) > 0:
		Net.c_chat.rpc_id(1, "/hunger 12")
		await _wait_until(func(): return c.hunger == 12.0, 3.0)
		await _select_item(c, porkchop)
		await get_tree().create_timer(0.2).timeout
		Input.action_press("place")
		c.use_selected_item()
		_check(await _wait_until(func(): return c.hunger == 15.0, 3.0), "eating the porkchop restored hunger (%.1f)" % c.hunger)
		Input.action_release("place")

	# Fall damage.
	Net.c_chat.rpc_id(1, "/heal")
	await _wait_until(func(): return c.health == 20.0, 2.0)
	await _wait_until(func(): return c.state.on_ground, 3.0)
	var ground: Vector3 = c.state.position
	var top := 127
	while top > 0 and c.world.get_block(floori(ground.x), top, floori(ground.z)) == 0:
		top -= 1  # land on the highest block in the column (trees included), 12 blocks down
	Net.c_chat.rpc_id(1, "/tp %.2f %d %.2f" % [ground.x, top + 13, ground.z])
	var fell := await _wait_until(func(): return c.health <= 17.0, 5.0)
	_check(fell, "fell 12 blocks and took fall damage (health %.1f)" % c.health)

	# Drop the sword with Q, then pick it back up.
	await _select_item(c, sword)
	await get_tree().create_timer(0.3).timeout
	c.drop_selected()
	_check(await _wait_until(func(): return c.inventory.count_of(sword) == 0, 2.0), "dropped the sword")
	_check(await _collect(c, sword, 10.0), "picked the dropped sword back up")

	# Inventory screen: move a stack from the hotbar into the main inventory.
	var from_slot: int = c.inventory.ids.find(sword)
	c._set_inventory_open(true)
	_check(c._inventory_screen.visible and not c._gameplay_input_enabled(), "inventory screen open")
	c.inventory_click(from_slot)
	await _wait_until(func(): return c.inventory.cursor_id == sword, 2.0)
	c.inventory_click(20)
	var moved := await _wait_until(func(): return c.inventory.ids[20] == sword and c.inventory.cursor_count == 0, 2.0)
	_check(moved, "moved the sword from hotbar slot %d to inventory slot 20" % from_slot)
	c.inventory_click(20, 1, true)
	_check(await _wait_until(func(): return c.inventory.ids[20] == 0 and c.inventory.count_of(sword) == 1, 2.0), "shift-click moved it back to the hotbar")
	c._set_inventory_open(false)

	# Equipment: wear a chestplate, see armor in stats and the HUD; mine stone with a pickaxe.
	await _return_to_arena(c)  # the fall test may have left us on a tree top
	Net.c_chat.rpc_id(1, "/give base:iron_chestplate")
	var chestplate: int = c.items.id_of("base:iron_chestplate")
	await _wait_until(func(): return c.inventory.count_of(chestplate) == 1, 2.0)
	c.inventory_click(c.inventory.ids.find(chestplate), 1, true)
	_check(await _wait_until(func(): return c.inventory.ids[c.inventory.equipment_index("chest")] == chestplate, 2.0), "shift-click wore the chestplate")
	_check(await _wait_until(func(): return c.stats.get("armor", 0.0) == 6.0 and c._armor_bar.visible, 2.0), "server stats and armor HUD show 6 armor")
	_check(await _wait_until(func(): return c._self_avatar._armor_material.albedo_texture != null and c._self_avatar._armor_meshes[0].visible, 2.0),
		"your avatar wears the chestplate texture")
	_check(c._self_avatar._held != null, "your avatar holds the selected item")
	var lines: PackedStringArray = c.ItemVisuals.tooltip_lines(c.items, chestplate, {})
	_check(lines.size() >= 3 and lines[1].contains("armor"), "tooltip lists armor and durability (%s)" % " | ".join(lines))
	Net.c_chat.rpc_id(1, "/give base:stone_pickaxe")
	var pickaxe: int = c.items.id_of("base:stone_pickaxe")
	if not await _select_item(c, pickaxe):
		_check(false, "the pickaxe never reached the hotbar (inventory full?)")
	await get_tree().create_timer(0.3).timeout
	var mine_target := _nearest_solid(c)
	c.mine_block(mine_target)  # runs on its own; watch the crack and the result
	await get_tree().create_timer(0.15).timeout
	_check(c._cracks.has(0), "mining shows the crack overlay")
	_check(await _wait_until(func(): return c.world.get_block_v(mine_target) == 0, 4.0), "survival mining broke the block")
	_check(await _wait_until(func():
		var slot: int = c.inventory.ids.find(pickaxe)
		return slot >= 0 and slot < c.inventory.data.size() and int(c.inventory.data[slot].get("damage", 0)) >= 1, 5.0),
		"breaking a block wore the pickaxe")

	# Blueprints: reading forge plans teaches the forge and uses them up.
	Net.c_chat.rpc_id(1, "/give base:forge_plans")
	var knew_forge: bool = c._crafting_screen.known.has("base:forge")
	var plans: int = c.items.id_of("base:forge_plans")
	if not await _select_item(c, plans):
		_check(false, "the forge plans never reached the hotbar (inventory full?)")
	await get_tree().create_timer(0.3).timeout
	c.use_selected_item()
	# This world may be played again by the same bot (REPEAT=), and a blueprint whose recipes are all known
	# is not used up - so what is checked is "you know the forge, and reading it did something" either way.
	var taught := await _wait_until(func(): return c._crafting_screen.known.has("base:forge") and (knew_forge or c.inventory.count_of(plans) == 0), 5.0)
	_check(taught, "reading forge plans taught the forge (known %s, plans left %d, knew it already %s)" % [
		c._crafting_screen.known.has("base:forge"), c.inventory.count_of(plans), knew_forge])

	# Experimentation grid: coal above a stick discovers torches.
	Net.c_chat.rpc_id(1, "/give base:coal 2")
	Net.c_chat.rpc_id(1, "/give base:stick 2")
	var coal: int = c.items.id_of("base:coal")
	var stick: int = c.items.id_of("base:stick")
	await _wait_until(func(): return c.inventory.count_of(coal) >= 1 and c.inventory.count_of(stick) >= 1, 3.0)
	c._set_crafting_open(true)
	await _wait_until(func(): return c._crafting_screen.visible, 3.0)
	c._crafting_screen.set_lab_mode(true)
	c._crafting_screen._grid_items = PackedInt32Array([coal, 0, 0, stick, 0, 0, 0, 0, 0])
	c._crafting_screen.experiment_requested.emit(c._crafting_screen._grid_items)
	_check(await _wait_until(func(): return c._crafting_screen.known.has("base:torch") and c._crafting_screen._lab_recipe >= 0, 3.0),
		"experimenting with coal over a stick discovered torches (%s)" % c._crafting_screen._lab_hint.text)
	c._set_crafting_open(false)

	# Wand of Sparks (arcana): a projectile that damages mobs.
	await _return_to_arena(c)
	Net.c_chat.rpc_id(1, "/give arcana:wand_of_sparks")
	var wand: int = c.items.id_of("arcana:wand_of_sparks")
	await _wait_until(func(): return c.inventory.count_of(wand) == 1, 2.0)
	Net.c_chat.rpc_id(1, "/summon vanilla:zombie")
	var target := await _wait_for_entity(c, "vanilla:zombie", 4.0)
	if target >= 0:
		await _select_item(c, wand)
		var shot := false
		for attempt in 6:
			var view = c._entities.get(target)
			if view == null:
				break
			_aim_at(c, view.position + Vector3(0, 1.0, 0))
			await get_tree().process_frame
			c.use_selected_item()
			if await _wait_until(func(): return c._entities.get(target) == null or c._entities[target]._hurt_until > 0.0 or c._entities[target].dying, 0.8):
				shot = true
				break
		_check(shot, "Wand of Sparks projectile hit the zombie")
		var burst := await _wait_until(func(): return c.effects_seen.has("arcana:spark_burst"), 2.0)
		_check(burst and c.effects_seen.has("arcana:cast"), "the wand's cast and impact effects played (%s)" % str(c.effects_seen.keys()))
		_check(c._view_model._held != null and c._view_model._held.get_child(0).material_overlay != null, "the wand glows in your hand")
		Net.c_chat.rpc_id(1, "/heal")
		await _select_item(c, sword)
		await _fight(c, target, 12.0)
		_check(c.effects_seen.has("engine:hit"), "sword hits made hit sparks")

	# Death and respawn.
	Net.c_chat.rpc_id(1, "/kill")
	_check(await _wait_until(func(): return c.dead and c._death_panel.visible, 3.0), "/kill shows the death screen")
	c.respawn()
	_check(await _wait_until(func(): return not c.dead and c.health == 20.0, 3.0), "respawned with full health")
	Net.c_chat.rpc_id(1, "/gameplay mob_spawning true")
	Net.c_chat.rpc_id(1, "/gamemode creative")
	await get_tree().create_timer(0.5).timeout


## Feet position on the surface near `around` where a 7x7 area is flat-ish, dry and has open sky.
## Back to the open ground the combat checks started on (and standing on it).
func _return_to_arena(c) -> void:
	Net.c_chat.rpc_id(1, "/tp %.1f %.1f %.1f" % [_arena.x, _arena.y, _arena.z])
	await _wait_until(func(): return c.state.position.distance_to(_arena) < 1.0 and c.state.on_ground, 5.0)


func _find_open_ground(c, around: Vector2i) -> Vector3:
	var best := Vector3(around.x + 0.5, 80, around.y + 0.5)
	var best_score := INF
	for ox in range(-12, 13, 3):
		for oz in range(-12, 13, 3):
			var heights := []
			var ok := true
			for dx in range(-3, 4):
				for dz in range(-3, 4):
					var x := around.x + ox + dx
					var z := around.y + oz + dz
					var y := 127
					while y > 0 and c.world.get_block(x, y, z) == 0:
						y -= 1
					var top: int = c.world.get_block(x, y, z)
					if top == 65535 or c.registry.liquid_lut[top] == 1 or c.registry.render_lut[top] == c.registry.Render.CUTOUT:
						ok = false  # unloaded, water or tree canopy
					heights.append(y)
			if not ok:
				continue
			var score: float = heights.max() - heights.min()
			if score < best_score:
				best_score = score
				best = Vector3(around.x + ox + 0.5, heights[24] + 1, around.y + oz + 0.5)
	return best


## A solid block within reach next to the player (the ground beside its feet).
func _nearest_solid(c) -> Vector3i:
	var base := Vector3i(floori(c.state.position.x), floori(c.state.position.y) - 1, floori(c.state.position.z))
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(1, 0, 1)]:
		var p: Vector3i = base + d
		if c.registry.breakable_lut[c.world.get_block_v(p)] == 1:
			return p
	return base


## Selects an item, waiting for it to arrive first (a /give is a round trip, and a loaded test machine can
## take a moment). Returns false if it never turned up, so a failing check says which step actually broke.
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
func _fight(c, entity_id: int, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	var won := false
	var last_close := Time.get_ticks_msec()
	while Time.get_ticks_msec() < deadline:
		var view = c._entities.get(entity_id)
		if view == null or view.dying:
			won = true
			break
		_aim_at(c, view.position + Vector3(0, view.height * 0.5, 0))
		var flat := Vector2(view.position.x - c.state.position.x, view.position.z - c.state.position.z).length()
		if flat < 3.0:
			last_close = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - last_close > 3000:
			# Chasing is best effort (slow CI machines, smart fleeing mobs): step next to it.
			_teleport_near(view.position)
			last_close = Time.get_ticks_msec()
		if flat > 2.2:
			Input.action_press("move_forward")
			Input.action_press("sprint")  # fleeing mobs are quick
		else:
			Input.action_release("move_forward")
			Input.action_release("sprint")
		if c.state.on_ground and flat > 2.2 and Vector2(c.state.velocity.x, c.state.velocity.z).length() < 0.5:
			Input.action_press("jump")
		else:
			Input.action_release("jump")
		if not c._entity_target.is_empty() and c._entity_target.id == entity_id and c._attack_timer <= 0.0:
			c.attack_target()
		await get_tree().process_frame
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Input.action_release("jump")
	print("[test] fight over (won %s) at %d fps, entity target %s" % [won, Engine.get_frames_per_second(), c._entity_target])
	return won


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


## Walks to the nearest dropped stack of `item` until it is in the inventory.
func _collect(c, item: int, timeout: float) -> bool:
	var start_count: int = c.inventory.count_of(item)
	var started := Time.get_ticks_msec()
	var deadline := started + int(timeout * 1000)
	var teleported := false
	var got := false
	while Time.get_ticks_msec() < deadline:
		if c.inventory.count_of(item) > start_count:
			got = true
			break
		if not teleported and Time.get_ticks_msec() - started > 4000:
			# Walking is best effort (the stack may have rolled into a hole); go straight to it.
			for id in c._entities:
				if c._entities[id].item_id == item:
					var at: Vector3 = c._entities[id].position
					Net.c_chat.rpc_id(1, "/tp %.2f %.2f %.2f" % [at.x, at.y + 0.2, at.z])
					teleported = true
					break
		var nearest = null
		for id in c._entities:
			var view = c._entities[id]
			if view.item_id == item and (nearest == null or view.position.distance_to(c.state.position) < nearest.position.distance_to(c.state.position)):
				nearest = view
		if nearest != null:
			_aim_at(c, nearest.position)
			var flat := Vector2(nearest.position.x - c.state.position.x, nearest.position.z - c.state.position.z).length()
			if flat > 0.6:
				Input.action_press("move_forward")
			else:
				Input.action_release("move_forward")
		await get_tree().process_frame
	Input.action_release("move_forward")
	return got


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


## A grass block with air above within reach, preferring ones not under the player.
func _clear_plants(c, radius: int) -> void:
	var feet: Vector3 = c.state.position
	var base := Vector3i(floori(feet.x), floori(feet.y), floori(feet.z))
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			for y in range(-3, 3):
				var p := base + Vector3i(x, y, z)
				var id: int = c.world.get_block_v(p)
				if id > 0 and id != 65535 and c.registry.defs[id].render == c.registry.Render.PLANT:
					Net.c_break_block.rpc_id(1, p)
					await get_tree().create_timer(0.08).timeout


func _find_open_grass(c) -> Vector3i:
	var grass: int = c.registry.id_of("base:grass")
	var tall_grass: int = c.registry.id_of("base:tall_grass")
	var feet: Vector3 = c.state.position
	var base := Vector3i(floori(feet.x), floori(feet.y), floori(feet.z))
	for r in range(2, 5):
		for x in range(-r, r + 1):
			for z in range(-r, r + 1):
				for y in range(-3, 2):
					var p := base + Vector3i(x, y, z)
					var above: int = c.world.get_block_v(p + Vector3i.UP)
					if c.world.get_block_v(p) == grass and (above == 0 or above == tall_grass) and c.world.get_block_v(p + Vector3i(0, 2, 0)) == 0:
						return p
	return Vector3i(0, -999, 0)


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
