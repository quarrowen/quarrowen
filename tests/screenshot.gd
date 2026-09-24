extends Node
## Joins a server, waits for terrain to mesh, optionally runs chat commands, saves a screenshot and
## quits. Needs a real window:
##   godot --path . res://tests/screenshot.tscn -- --port=24600 --out=/tmp/shot.png \
##     [--yaw=0.8] [--pitch=-0.25] [--commands="/industry demo|/time night"] [--wait=3] [--menu=crafting]
##     [--camera=0|1|2] [--avatar='{"wear": {...}}' (join with) | --wear='{...}' (change in game)]
##     [--editor=hat (opens the avatar editor on a category)] [--swing=0.12 (capture that long into a swing)]
##     [--open=simple_machines:chest (place and open a block)] [--craft=simple_gear:wooden_pickaxe (recipe book on a recipe)]
##     [--guide=guidebook:wood (the guidebook on a page) [--search=text]] [--settings=Graphics (settings screen on a tab)]
##     [--look=firstlight:wick | --look=12,70,34 (aim at a creature or a point; beats guessing a yaw)]
##       [--look_wait=6 (seconds to wait for it to turn up - a companion may still be walking over)]
##       [--goto=4 (stand 4 m from it first; needs the server started with QW_ADMINS=<--name>)]
##       [--stand=133,12,127 (or stand exactly here instead - indoors, where the side matters)]

const GameClient = preload("res://engine/client/game_client.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")


func _ready() -> void:
	var options := {"port": "24600", "out": "user://screenshot.png", "yaw": "0.8", "pitch": "-0.25", "commands": "", "after": "", "wait": "3", "menu": "", "inventory": "", "hover": "-1", "mine": "", "camera": "0", "equip": "", "select": "-1", "avatar": "", "editor": "", "wear": "", "swing": "", "open": "", "craft": "", "station": "", "lab": "", "forge": "", "skill": "", "presses": "0", "meal": "", "guide": "", "search": "", "tip": "", "tutorials": "", "dev": "", "dev_ai": "", "settings": "", "players": "", "server": "", "map": "", "hud": "", "fps": "0", "name": "Camera", "look": "", "look_wait": "6", "goto": "", "stand": ""}
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
	# **`--look` aims the camera at something instead of you guessing an angle.** Testing an NPC, a
	# structure or a block used to mean firing screenshots at different yaws until the thing appeared -
	# a dozen renders to photograph a character standing two metres away. (the user, 2026-09-24: "being
	# able to get the test player to the correct spot and view and yaw will be helpful")
	if not String(options.look).is_empty():
		await _frame(client, options, float(options.look_wait))
	# Let a few inputs carry the new facing to the server before commands that build in front of us.
	await get_tree().create_timer(0.5).timeout
	for command in String(options.commands).split("|", false):
		Net.c_chat.rpc_id(1, command.strip_edges())
		await get_tree().create_timer(0.3).timeout
	if String(options.get("hud", "")) == "0":
		# --hud=0 for a picture of the world rather than of the interface.
		client._debug_label.visible = false
		client._controls_hint.visible = false
		if client._tutorial_hud != null:
			client._tutorial_hud.visible = false
		# The task list is part of the interface too. Missed when it was added this morning, and the
		# first picture that wanted a clean world had a quest log in the corner of it.
		if client._objective_hud != null:
			client._objective_hud.visible = false
	if not String(options.menu).is_empty():
		Net.c_open_menu.rpc_id(1, options.menu)
	if not String(options.map).is_empty():
		# The map screen: --map=1
		client.toggle_map()
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
		# Place a container block in front and open it: --open=simple_machines:furnace (fill it with --commands first).
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
		# Open the recipe book on a recipe: --craft=simple_gear:wooden_pickaxe (or "book").
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
		# Tools from parts at an open Tool Forge: --forge=base:pickaxe_head/base:iron,base:tool_handle/guidebook:wood,...
		# crafts each part recipe (give the materials with --commands), then opens the Assemble tab.
		for recipe_id in String(options.forge).split(","):
			Net.c_craft.rpc_id(1, client.recipes.index_of(recipe_id), 1)
			await get_tree().create_timer(0.4).timeout
		client._crafting_screen.set_forge_mode()
	if not String(options.skill).is_empty():
		# Craft by hand: --skill=simple_gear:iron_pickaxe (a recipe id) [--presses=3 space presses 0.7 s apart].
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
		# The guidebook: --guide=guidebook:wood (or "last") [--search=planks].
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
		client.on_tip({"id": "shot", "text": options.tip, "icon": "base:apple", "page": "guidebook:food", "seconds": 30.0})
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
	# **--after runs once the world is up, a moment before the shutter.** `--commands` runs first, which
	# is right for anything the world has to be built around - but a `/tp` there is useless, because the
	# player then falls for the whole wait and the picture is of wherever they landed. Every attempt to
	# photograph the lake came out as a picture of the beach. (2026-09-22)
	for command in String(options.get("after", "")).split("|", false):
		Net.c_chat.rpc_id(1, command.strip_edges())
		await get_tree().create_timer(0.25).timeout
	if not String(options.get("after", "")).is_empty():
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
	# **Frame it again at the last possible moment**, after the render-time measurement above, not
	# before it. The first pass happens before `--wait` and `--after`, because commands want to run
	# facing the right way - but anything that walks has moved by the time the shutter opens. A shot of
	# Wick came out as a picture of the grass he had been standing on, which reads exactly like a model
	# that is not rendering; and because a companion *follows*, the next one came out as his hat brim
	# from 0.7 m. Re-framing before the 120-frame warm-up was still too early - two seconds is a long
	# walk - so it goes here, with only the swing between it and the shutter. (2026-09-24)
	if not String(options.look).is_empty():
		await _frame(client, options, 0.0)
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(options.out)
	print("[screenshot] saved %s" % options.out)
	# --fps=N: hold the same view for N seconds and report what it cost to draw. A picture says what a
	# setting looks like and nothing about whether anyone can play with it on. (2026-09-21)
	var seconds := float(options.get("fps", "0"))
	if seconds > 0.0:
		await _measure(seconds)
	get_tree().quit()


func _measure(seconds: float) -> void:
	# A second of warm-up first: the frame after a screenshot is read back is never representative.
	await get_tree().create_timer(1.0).timeout
	var samples: Array[float] = []
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		samples.append(float(Engine.get_frames_per_second()))
	if samples.is_empty():
		return
	samples.sort()
	var total := 0.0
	for f in samples:
		total += f
	# The median as well as the mean: an average of 40 made of 60s and 15s is not 40 to play.
	print("[fps] avg %.1f  median %.1f  worst %.1f  best %.1f  (%d samples)" % [
		total / samples.size(), samples[samples.size() / 2], samples[0], samples[-1], samples.size()])


## Points the camera at a creature by type name ("firstlight:wick"), or at "x,y,z".
##
## Stand where the caller asked, then aim. Both halves are re-run immediately before the shutter, so
## the picture is of where the subject is rather than where it was.
func _frame(client, options: Dictionary, wait_seconds: float) -> void:
	var target := String(options.look)
	if not String(options.get("stand", "")).is_empty():
		await _stand_at(client, String(options.stand))
	elif not String(options.get("goto", "")).is_empty():
		await _go_to(client, target, float(options.goto), wait_seconds)
	await _look_at(client, target, wait_seconds)


## Waits for the thing to exist, because a companion may still be walking towards you when the client
## finishes joining - and a shot of where it was going to be is the same useless picture as a shot of
## the wrong direction.
func _look_at(client, target: String, wait_seconds: float) -> void:
	var point := await _wait_for(client, target, wait_seconds)
	if point == Vector3.INF:
		print("[screenshot] --look=%s found nothing; keeping the given yaw and pitch" % target)
		return
	var eye: Vector3 = client.state.position + Vector3(0.0, PlayerPhysics.EYE_HEIGHT, 0.0)
	var to: Vector3 = point - eye
	var flat := Vector2(to.x, to.z).length()
	if flat < 0.01:
		return
	# Forward is (-sin(yaw), 0, -cos(yaw)) - see the `ahead` calculation below - so this inverts it.
	client.yaw = atan2(-to.x, -to.z)
	client.pitch = clampf(atan2(to.y, flat), -1.5, 1.5)
	print("[screenshot] looking at %s (%.1f m away) yaw %.2f pitch %.2f" % [target, to.length(), client.yaw, client.pitch])
	await get_tree().create_timer(0.4).timeout


## Looks once and then keeps looking until the deadline, so a zero wait still answers - which is what
## the aim taken immediately before the shutter needs.
func _wait_for(client, target: String, wait_seconds: float) -> Vector3:
	var deadline := Time.get_ticks_msec() + int(maxf(wait_seconds, 0.0) * 1000.0)
	while true:
		var point := _find(client, target)
		if point != Vector3.INF or Time.get_ticks_msec() >= deadline:
			return point
		await get_tree().create_timer(0.25).timeout
	return Vector3.INF


## **--goto stands you next to the thing before aiming at it.** Knowing the yaw is only half of it: a
## guide thirty metres off is four pixels tall however accurately the camera points at him. Teleports to
## `distance` metres back along the line you are already approaching from, so the shot keeps the
## direction the caller chose. (the user, 2026-09-24: "not just look, but can also teleport near the
## target right")
func _go_to(client, target: String, distance: float, wait_seconds: float) -> void:
	var point := await _wait_for(client, target, wait_seconds)
	if point == Vector3.INF:
		print("[screenshot] --goto: nothing called %s to stand near" % target)
		return
	var back: Vector3 = point - client.state.position
	back.y = 0.0
	if back.length() < 0.01:
		back = Vector3(0, 0, 1)  # already on top of it: back off southwards rather than divide by zero
	var stand: Vector3 = point - back.normalized() * maxf(distance, 0.5)
	stand.y = point.y + 1.0  # a little above it, so the drop settles us on whatever is underfoot
	if await _teleport(client, stand, "--goto"):
		print("[screenshot] standing at %s, %.1f m from %s" % [client.state.position,
			client.state.position.distance_to(point), target])


## **--stand puts the camera exactly where you say**, for when the direction matters as much as the
## distance. `--goto` backs off along the line you were already approaching from, which is right for a
## creature in the open and wrong indoors: photographing the altar it parked the camera hard against a
## pillar, and the picture was a wall. Underground, in a structure, or anywhere with a composition in
## mind, name the spot. (2026-09-24)
func _stand_at(client, where: String) -> void:
	var bits := where.split(",")
	if bits.size() != 3:
		print("[screenshot] --stand wants x,y,z")
		return
	var spot := Vector3(float(bits[0]), float(bits[1]), float(bits[2]))
	if await _teleport(client, spot, "--stand"):
		print("[screenshot] standing at %s" % client.state.position)


## Teleports and waits to actually be there. Judged against where we asked to be, not against how far
## we travelled: the pass immediately before the shutter often only has to shuffle a metre, and "it
## hardly moved" would report that as a refused command.
func _teleport(client, to: Vector3, what: String) -> bool:
	Net.c_chat.rpc_id(1, "/tp %.2f %.2f %.2f" % [to.x, to.y, to.z])
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
		if client.state.position.distance_to(to) < 2.0:
			break
	if client.state.position.distance_to(to) >= 2.0:
		print("[screenshot] %s: never arrived - is the server running with QW_ADMINS=%s?" % [what, client.player_name])
		return false
	await _meshed(client)  # the new place has to draw before the picture is worth taking
	return true


## "x,y,z" as a point, or the nearest creature of that type, aiming at the middle of it rather than its
## feet - a plate sits above the head and a 1.5 m guide photographed at ankle height is a picture of grass.
func _find(client, target: String) -> Vector3:
	if target.contains(","):
		var bits := target.split(",")
		if bits.size() == 3:
			return Vector3(float(bits[0]), float(bits[1]), float(bits[2]))
		return Vector3.INF
	var best := Vector3.INF
	var nearest := INF
	for view in client._entities.values():
		if str(view.type_def.get("name", "")) != target:
			continue
		var at: Vector3 = view.global_position + Vector3(0.0, float(view.height) * 0.6, 0.0)
		var d: float = at.distance_to(client.state.position)
		if d < nearest:
			nearest = d
			best = at
	return best


func _meshed(client) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if client._welcomed and client._chunk_nodes.size() > 150 and client._mesh_dirty.is_empty() and client._mesh_jobs.is_empty():
			return
