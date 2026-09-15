extends Node
## Joins a server, waits for terrain to mesh, optionally runs chat commands, saves a screenshot and
## quits. Needs a real window:
##   godot --path . res://tests/screenshot.tscn -- --port=24600 --out=/tmp/shot.png \
##     [--yaw=0.8] [--pitch=-0.25] [--commands="/industry demo|/time night"] [--wait=3] [--menu=crafting]
##     [--camera=0|1|2] [--avatar='{"wear": {...}}' (join with) | --wear='{...}' (change in game)]
##     [--editor=hat (opens the avatar editor on a category)] [--swing=0.12 (capture that long into a swing)]
##     [--open=base:chest (place and open a block)] [--craft=base:wooden_pickaxe (recipe book on a recipe)]
##     [--guide=base:wood (the guidebook on a page) [--search=text]] [--settings=Graphics (settings screen on a tab)]

const GameClient = preload("res://engine/client/game_client.gd")


func _ready() -> void:
	var options := {"port": "24600", "out": "user://screenshot.png", "yaw": "0.8", "pitch": "-0.25", "commands": "", "wait": "3", "menu": "", "inventory": "", "hover": "-1", "mine": "", "camera": "0", "equip": "", "select": "-1", "avatar": "", "editor": "", "wear": "", "swing": "", "open": "", "craft": "", "station": "", "lab": "", "forge": "", "skill": "", "presses": "0", "meal": "", "guide": "", "search": "", "tip": "", "tutorials": "", "dev": "", "dev_ai": "", "settings": "", "players": "", "server": "", "name": "Camera"}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and options.has(kv[0]):
			options[kv[0]] = kv[1]
	var client = GameClient.new()
	client.server_port = int(options.port)
	client.player_name = String(options.name)
	client.avatar = JSON.parse_string(options.avatar) if not String(options.avatar).is_empty() else {}
	add_child(client)
	await _meshed(client)
	client.yaw = float(options.yaw)
	client.pitch = float(options.pitch)
	# Let a few inputs carry the new facing to the server before commands that build in front of us.
	await get_tree().create_timer(0.5).timeout
	for command in String(options.commands).split("|", false):
		Net.c_chat.rpc_id(1, command.strip_edges())
		await get_tree().create_timer(0.3).timeout
	if not String(options.menu).is_empty():
		Net.c_open_menu.rpc_id(1, options.menu)
	if not String(options.server).is_empty():
		# The admin server settings panel: --server=1
		client.open_server_panel()
	if not String(options.players).is_empty():
		# The players and roles panel: --players=1
		client._set_paused(true)
		client.open_players_panel()
		await get_tree().create_timer(1.0).timeout
	if not String(options.settings).is_empty():
		# The settings screen over the game on a tab: --settings=Controls
		client._set_paused(true)
		client.open_settings()
		await get_tree().process_frame
		client._settings_overlay.find_children("*", "VBoxContainer", true, false).filter(func(n): return n.has_method("show_tab"))[0].show_tab(options.settings)
	if not String(options.equip).is_empty():
		await get_tree().create_timer(0.8).timeout
		for slot in 36:
			var id: int = client.inventory.ids[slot]
			if id > 0 and not String(client.items.get_def(id).get("equip_slot", "")).is_empty():
				client.inventory_click(slot, 1, true)
				await get_tree().create_timer(0.2).timeout
	if int(options.select) >= 0:
		client.select_slot(int(options.select))
	client.camera_mode = int(options.camera)
	if not String(options.mine).is_empty():
		client.ignore_mouse_capture = true
		Input.action_press("break")  # hold break on whatever the camera looks at
	if not String(options.inventory).is_empty():
		await get_tree().create_timer(1.0).timeout
		client._set_inventory_open(true)
		client._inventory_screen._hovered = int(options.hover)
	if not String(options.open).is_empty():
		# Place a container block in front and open it: --open=base:furnace (fill it with --commands first).
		var id: int = client.items.id_of(options.open)
		Net.c_chat.rpc_id(1, "/give %s" % options.open)
		await get_tree().create_timer(0.8).timeout
		var slot: int = client.inventory.ids.find(id)
		if slot >= 9:
			for s in [slot, 8, slot]:
				client.inventory_click(s)
				await get_tree().create_timer(0.3).timeout
			slot = 8
		client.select_slot(slot)
		await get_tree().create_timer(0.4).timeout
		# Two blocks ahead on the ground, clear of the player.
		var ahead: Vector3 = client.state.position + Vector3(-sin(client.yaw), 0.0, -cos(client.yaw)) * 2.0
		var spot := Vector3i(floori(ahead.x), int(client.state.position.y) + 2, floori(ahead.z))
		while spot.y > 1 and client.registry.solid_lut[client.world.get_block_v(spot + Vector3i.DOWN)] == 0:
			spot.y -= 1
		if true:
			client.request_place(spot)
			await get_tree().create_timer(0.8).timeout
			Net.c_interact.rpc_id(1, spot)
			await get_tree().create_timer(0.8).timeout
	if String(options.station).begins_with("deposit"):
		# --station=deposit puts the first two hotbar stacks into the station's shared tray.
		for slot in [0, 1]:
			Net.c_station_coop.rpc_id(1, "deposit", slot)
			await get_tree().create_timer(0.4).timeout
	elif not String(options.station).is_empty():
		# Press a station screen button: --station=guide (then close the screen to see the world).
		Net.c_station_action.rpc_id(1, options.station)
		await get_tree().create_timer(0.8).timeout
		if options.station == "guide":
			client._set_crafting_open(false)
	if not String(options.craft).is_empty():
		# Open the recipe book on a recipe: --craft=base:wooden_pickaxe (or "book").
		if not client._crafting_screen.visible:
			client._set_crafting_open(true)
			await get_tree().create_timer(0.8).timeout
		var index: int = client.recipes.index_of(options.craft)
		if index >= 0:
			client._crafting_screen._select(index)
	if not String(options.lab).is_empty():
		# Experimentation grid: --lab=base:coal,-,-,base:stick (up to 9 cells, "-" empty), then Try.
		if not client._crafting_screen.visible:
			client._set_crafting_open(true)
			await get_tree().create_timer(0.8).timeout
		client._crafting_screen.set_lab_mode(true)
		var cells := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0])
		var names := String(options.lab).split(",")
		for i in mini(names.size(), 9):
			cells[i] = maxi(client.items.id_of(names[i]), 0) if names[i] != "-" else 0
		client._crafting_screen._grid_items = cells
		client._crafting_screen._palette_item = cells[0]
		client._crafting_screen.experiment_requested.emit(cells)
		await get_tree().create_timer(0.8).timeout
	if not String(options.forge).is_empty():
		# Tools from parts at an open Tool Forge: --forge=base:pickaxe_head/base:iron,base:tool_handle/base:wood,...
		# crafts each part recipe (give the materials with --commands), then opens the Assemble tab.
		for recipe_id in String(options.forge).split(","):
			Net.c_craft.rpc_id(1, client.recipes.index_of(recipe_id), 1)
			await get_tree().create_timer(0.4).timeout
		client._crafting_screen.set_forge_mode()
	if not String(options.skill).is_empty():
		# Craft by hand: --skill=base:iron_pickaxe (a recipe id) [--presses=3 space presses 0.7 s apart].
		Net.c_skill_craft.rpc_id(1, {"recipe": client.recipes.index_of(options.skill)}, false, false)
		await get_tree().create_timer(2.3).timeout
		for i in int(options.presses):
			for pressed in [true, false]:
				var key := InputEventKey.new()
				key.physical_keycode = KEY_SPACE
				key.pressed = pressed
				Input.parse_input_event(key)
				await get_tree().create_timer(0.1).timeout
			await get_tree().create_timer(0.6).timeout
	if not String(options.meal).is_empty():
		# A meal frozen mid-animation: --meal=base:bread:0.55 (item, then the moment as a fraction of eat_time).
		var parts := String(options.meal).rsplit(":", true, 1)
		var meal_item: int = client.items.id_of(parts[0])
		Net.c_chat.rpc_id(1, "/give %s" % parts[0])
		await get_tree().create_timer(0.8).timeout
		client.select_slot(client.inventory.ids.find(meal_item))
		await get_tree().create_timer(0.5).timeout
		var meal: Dictionary = client._meal_for(meal_item, {}, 0.0)
		meal.freeze = float(parts[1]) * float(meal.duration)
		client._view_model.start_meal(meal)
		client._self_avatar.start_meal(meal)
	if not String(options.guide).is_empty():
		# The guidebook: --guide=base:wood (or "last") [--search=planks].
		await get_tree().create_timer(1.0).timeout
		client._set_guide_open(true, "" if options.guide == "last" else options.guide)
		if not String(options.search).is_empty():
			client._guide_screen._search.text = options.search
			client._guide_screen._rebuild_contents()
	if not String(options.dev).is_empty():
		# The dev overlay on a tab: --dev=Logs|Errors|Inspect|Events|Perf|Draw [--dev_ai=1 shows mob AI].
		client._toggle_dev_overlay()
		var tabs: TabContainer = client._dev_overlay._tabs
		for i in tabs.get_tab_count():
			if tabs.get_tab_control(i).name == options.dev:
				tabs.current_tab = i
		if not String(options.dev_ai).is_empty():
			client._dev_overlay.draw_ai = true
			client._dev_overlay._subscribe()
		await get_tree().create_timer(0.5).timeout
		client._dev_pick()
	if not String(options.tip).is_empty():
		# A tip card as the server would send it: --tip="Some text"
		client.on_tip({"id": "shot", "text": options.tip, "icon": "base:apple", "page": "base:food", "seconds": 30.0})
	if not String(options.tutorials).is_empty():
		client._tutorial_hud.open_panel()  # --tutorials=1
	if not String(options.wear).is_empty():
		Net.c_set_avatar.rpc_id(1, JSON.parse_string(options.wear))  # in game, so server cosmetics apply too
		await get_tree().create_timer(0.5).timeout
	if not String(options.editor).is_empty():
		client.open_avatar_editor()
		client._avatar_editor._show_category(options.editor)
	await get_tree().create_timer(float(options.wait)).timeout
	await _meshed(client)
	if not String(options.mine).is_empty():
		await get_tree().create_timer(float(options.mine)).timeout  # let the crack grow
	var viewport_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	var cpu := 0.0
	var gpu := 0.0
	for i in 120:
		await get_tree().process_frame
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
	var size := get_viewport().get_texture().get_size()
	print("[screenshot] %dx%d render scale %.2f: fps %d, render cpu %.2f ms, gpu %.2f ms" % [size.x, size.y,
		get_viewport().scaling_3d_scale, Engine.get_frames_per_second(), cpu / 120.0, gpu / 120.0])
	if not String(options.swing).is_empty():
		client._self_swing()  # capture mid-swing to show trails
		await get_tree().create_timer(float(options.swing)).timeout
	get_viewport().get_texture().get_image().save_png(options.out)
	print("[screenshot] saved %s" % options.out)
	get_tree().quit()


func _meshed(client) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if client._welcomed and client._chunk_nodes.size() > 150 and client._mesh_dirty.is_empty() and client._mesh_jobs.is_empty():
			return
