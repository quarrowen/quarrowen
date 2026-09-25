extends Node
## Measures what an oversized RPC costs the server, which the security notes said "needs measuring".
##
##   godot --headless --path . res://tools/rpc_flood.tscn -- --port=25971 [--mb=8]
##
## Connects like any client and sends a very large string to a handler reachable *before*
## authentication, which is the worst case: no identity, no cost to the sender. Godot decodes the
## packet before our handler runs and truncates, so the question is not whether the value is kept -
## it is not - but what the decode itself costs.

const GameClient = preload("res://engine/client/game_client.gd")


func _ready() -> void:
	var port := 25971
	var megabytes := 8
	var times := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.substr(7))
		elif arg.begins_with("--mb="):
			megabytes = int(arg.substr(5))
		elif arg.begins_with("--times="):
			times = int(arg.substr(8))
	var client = GameClient.new()
	client.server_port = port
	client.player_name = "Flooder"
	client.auto_capture_mouse = false
	add_child(client)
	await get_tree().create_timer(3.0).timeout
	if not multiplayer.has_multiplayer_peer():
		print("[flood] never connected")
		return get_tree().quit(1)
	var huge := "A".repeat(megabytes * 1024 * 1024)
	print("[flood] sending %d MB to c_transfer_ticket (pre-auth)" % megabytes)
	var before := Time.get_ticks_msec()
	for i in times:
		Net.c_transfer_ticket.rpc_id(1, huge, "x")
		await get_tree().create_timer(0.8).timeout
	await get_tree().create_timer(4.0).timeout
	print("[flood] still connected after send: %s (%d ms)" % [multiplayer.has_multiplayer_peer(), Time.get_ticks_msec() - before])
	get_tree().quit(0)
