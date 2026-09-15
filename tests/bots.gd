extends Node
## Load generator: connects many lightweight bot clients from one process. Each bot gets its own
## MultiplayerAPI branch with a private copy of the Net node, joins normally, then wanders, jumps
## and breaks blocks. Pair with a server started with --metrics to read tick cost and bandwidth.
##   godot --headless --path . res://tests/bots.tscn -- --port=24565 --bots=50 --seconds=60

const NetScript = preload("res://engine/net/net.gd")
const PlayerPhysics = preload("res://engine/shared/player_physics.gd")
const Protocol = preload("res://engine/shared/protocol.gd")
const Identity = preload("res://engine/shared/identity.gd")


class Bot:
	extends Node

	var net: Node
	var index := 0
	var joined := false
	var seq := 0
	var yaw := 0.0
	var position := Vector3.ZERO
	var peer_id := 0
	var bytes_in := 0
	var rng := RandomNumberGenerator.new()
	var recent: Array[PackedByteArray] = []
	var key: CryptoKey

	func start(address: String, port: int) -> void:
		rng.seed = index * 7919
		yaw = rng.randf() * TAU
		var api := SceneMultiplayer.new()
		get_tree().set_multiplayer(api, get_path())
		net = NetScript.new()
		net.name = "Net"
		net.client = self
		net.pin_servers = false
		add_child(net)
		# Bots use small throwaway keys; real clients keep a 2048-bit identity on disk.
		key = Crypto.new().generate_rsa(1024)
		api.connected_to_server.connect(func(): net.c_hello.rpc_id(1, Protocol.VERSION, "bot%03d" % index, Identity.public_pem(key)))
		net.create_client(address, port)

	func _physics_process(_delta: float) -> void:
		if not joined or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		seq += 1
		if rng.randf() < 0.01:
			yaw += rng.randf_range(-1.5, 1.5)
		var input := PlayerPhysics.PlayerInput.new()
		input.seq = seq
		input.move = Vector2(0.0, 1.0)
		input.yaw = yaw
		input.jump = rng.randf() < 0.05
		input.sprint = true
		var buf := StreamPeerBuffer.new()
		input.write(buf)
		recent.append(buf.data_array)
		if recent.size() > 3:
			recent.pop_front()
		var packet := PackedByteArray([recent.size()])
		for p in recent:
			packet.append_array(p)
		net.c_inputs.rpc_id(1, packet)
		if seq % 90 == 0:
			var front := position + Vector3(-sin(yaw), 0.5, -cos(yaw)) * 2.0
			net.c_break_block.rpc_id(1, Vector3i(floori(front.x), floori(front.y), floori(front.z)))

	# --- Net handler interface (subset used by bots; the rest are no-ops) ---
	func on_player_appearance(_a = null, _b = null, _c = null) -> void:
		pass

	func on_cosmetics(_a = null, _b = null, _c = null) -> void:
		pass

	func on_entities(_a = null, _b = null, _c = null, _d = null) -> void:
		pass

	func on_challenge(nonce: PackedByteArray) -> void:
		net.c_auth.rpc_id(1, Identity.sign(key, nonce))

	func on_server_info(_info, _content, _manifest) -> void:
		net.c_request_assets.rpc_id(1, PackedStringArray())
		net.c_ready.rpc_id(1)

	func on_welcome(id: int, spawn: Vector3, _yaw: float) -> void:
		peer_id = id
		position = spawn
		joined = true

	func on_chunk(_coord, payload: PackedByteArray, _states) -> void:
		bytes_in += payload.size()

	func on_snapshot(_tick, payload: PackedByteArray) -> void:
		bytes_in += payload.size()
		var buf := StreamPeerBuffer.new()
		buf.data_array = payload
		buf.get_32()
		position = Vector3(buf.get_float(), buf.get_float(), buf.get_float())

	func on_kick(reason: String) -> void:
		printerr("[bots] bot%03d kicked: %s" % [index, reason])

	func on_asset_piece(_a, _b, _c, _d) -> void: pass
	func on_rules(_r) -> void: pass
	func on_unload_chunk(_c) -> void: pass
	func on_block_changed(_p, _b, _s) -> void: pass
	func on_time(_t, _l) -> void: pass
	func on_inventory(_s, _sel, _c, _d = null) -> void: pass
	func on_player_joined(_id, _n) -> void: pass
	func on_player_left(_id) -> void: pass
	func on_chat(_t) -> void: pass
	func on_ui_show(_id, _s) -> void: pass
	func on_ui_hide(_id) -> void: pass
	func on_title(_t, _s, _sec) -> void: pass
	func on_assembled(_a = null, _b = null) -> void: pass
	func on_container_close() -> void: pass
	func on_container_open(_a = null) -> void: pass
	func on_container_update(_a = null) -> void: pass
	func on_content_update(_a = null) -> void: pass
	func on_crafted(_a = null, _b = null, _c = null) -> void: pass
	func on_crafting_open(_a = null, _b = null) -> void: pass
	func on_crafting_stock(_a = null) -> void: pass
	func on_dev(_a = null, _b = null) -> void: pass
	func on_dev_error(_a = null) -> void: pass
	func on_effect(_a = null, _b = null, _c = null) -> void: pass
	func on_entity_despawn(_a = null) -> void: pass
	func on_entity_event(_a = null, _b = null, _c = null) -> void: pass
	func on_entity_look(_a = null, _b = null) -> void: pass
	func on_entity_spawn(_a = null) -> void: pass
	func on_experiment_result(_a = null) -> void: pass
	func on_guide_open(_a = null) -> void: pass
	func on_guide_state(_a = null, _b = null, _c = null) -> void: pass
	func on_guide_unlocked(_a = null, _b = null) -> void: pass
	func on_health(_a = null, _b = null, _c = null, _d = null) -> void: pass
	func on_hunger(_a = null, _b = null) -> void: pass
	func on_known_recipes(_a = null, _b = null) -> void: pass
	func on_minigame(_a = null) -> void: pass
	func on_minigame_event(_a = null, _b = null, _c = null) -> void: pass
	func on_mining(_a = null, _b = null, _c = null) -> void: pass
	func on_player_eating(_a = null, _b = null) -> void: pass
	func on_player_event(_a = null, _b = null) -> void: pass
	func on_player_stats(_a = null) -> void: pass
	func on_recipe_learned(_a = null, _b = null) -> void: pass
	func on_roles_panel(_a = null) -> void: pass
	func on_selection(_a = null, _b = null, _c = null) -> void: pass
	func on_server_reloading(_a = null) -> void: pass
	func on_sleep(_a = null) -> void: pass
	func on_sound(_a = null, _b = null, _c = null, _d = null, _e = null) -> void: pass
	func on_station_label(_a = null, _b = null) -> void: pass
	func on_station_session(_a = null) -> void: pass
	func on_structure_guide(_a = null) -> void: pass
	func on_tip(_a = null) -> void: pass
	func on_transfer(_a = null, _b = null, _c = null, _d = null, _e = null) -> void: pass
	func on_tutorial(_a = null) -> void: pass
	func on_tutorial_event(_a = null, _b = null) -> void: pass
	func on_ugc_admin_list(_a = null, _b = null) -> void: pass


func _ready() -> void:
	var address := "127.0.0.1"
	var port := 24565
	var count := 20
	var seconds := 60.0
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() < 2:
			continue
		match kv[0]:
			"address": address = kv[1]
			"port": port = int(kv[1])
			"bots": count = int(kv[1])
			"seconds": seconds = float(kv[1])
	var bots: Array[Bot] = []
	for i in count:
		var bot := Bot.new()
		bot.name = "Bot%03d" % i
		bot.index = i
		add_child(bot)
		bot.start(address, port)
		bots.append(bot)
		await get_tree().create_timer(0.05).timeout
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < seconds * 1000.0:
		await get_tree().create_timer(5.0).timeout
		var joined: int = bots.filter(func(b): return b.joined).size()
		var kb: float = bots.reduce(func(acc, b): return acc + b.bytes_in, 0) / 1024.0
		print("[bots] %d/%d joined, %.0f KB received total" % [joined, count, kb])
	get_tree().quit()
