extends Node
## Joins a server, waits for terrain to mesh, optionally runs chat commands, saves a screenshot and
## quits. Needs a real window:
##   godot --path . res://tests/screenshot.tscn -- --port=24600 --out=/tmp/shot.png \
##     [--yaw=0.8] [--pitch=-0.25] [--commands="/industry demo|/time night"] [--wait=3] [--menu=crafting]

const GameClient = preload("res://engine/client/game_client.gd")


func _ready() -> void:
	var options := {"port": "24600", "out": "user://screenshot.png", "yaw": "0.8", "pitch": "-0.25", "commands": "", "wait": "3", "menu": "", "inventory": "", "hover": "-1", "mine": "", "camera": "0", "equip": "", "select": "-1"}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2 and options.has(kv[0]):
			options[kv[0]] = kv[1]
	var client = GameClient.new()
	client.server_port = int(options.port)
	client.player_name = "Camera"
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
	get_viewport().get_texture().get_image().save_png(options.out)
	print("[screenshot] saved %s" % options.out)
	get_tree().quit()


func _meshed(client) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if client._welcomed and client._chunk_nodes.size() > 150 and client._mesh_dirty.is_empty() and client._mesh_jobs.is_empty():
			return
