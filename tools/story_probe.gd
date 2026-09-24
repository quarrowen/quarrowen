extends Node
## Starts a game, puts a player in it, and reports what the story did to them.
##
##   godot --headless --path . res://tools/story_probe.tscn -- [game]
##
## Firstlight's guide, objectives and conversations all happen *to a player joining*, which is the one
## thing a mod validation never does - `mod_tool validate` proves the mod loads, not that anything
## greets you. This is the cheapest way to see the first thirty seconds of the game without clicking
## through a menu, and the only way to check it before the pictures. (2026-09-24)

const GameServer = preload("res://engine/server/game_server.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")


func _ready() -> void:
	var game := "firstlight"
	for arg in OS.get_cmdline_user_args():
		if not String(arg).begins_with("-"):
			game = String(arg)

	var server := GameServer.new()
	add_child(server)
	# **Never user://.** `use_custom_user_dir` means that is the installed game's folder.
	var scratch: String = OS.get_environment("TMPDIR").path_join("quarrowen-story-%d" % Time.get_ticks_msec())
	var err: Error = server.start({"mods": PackedStringArray([game]),
		"world": "story_probe", "data_dir": scratch, "seed": 42, "offline": true})
	if err != OK:
		print("server start failed: %s" % error_string(err))
		return get_tree().quit(1)
	server.set_physics_process(false)

	server.ensure_area_loaded(Vector3(0.5, 70, 0.5))
	var p := ServerPlayer.new(server, 101, "Probe")
	p.player_id = "probe"
	p.state.position = Vector3(0.5, float(server.realm.block_ticks._column_height(0, 0) + 1), 0.5)
	server.players[101] = p
	# What the game does when somebody arrives.
	server.emit("player_join", {"player": p})
	await get_tree().process_frame

	print("")
	print("game:      %s" % game)
	print("standing:  %s" % p.state.position)
	var gameplay: Dictionary = server.gameplay
	print("rules:     hunger=%s flight=%s pvp=%s keep_inventory=%s" % [
		gameplay.get("hunger"), gameplay.get("flight"), gameplay.get("pvp"), gameplay.get("keep_inventory")])

	var guides: Array = server.entities.in_radius(p.state.position, 32.0)
	var named := []
	for e in guides:
		var owner := str(e.data.get("owner", ""))
		named.append("%s%s" % [str(e.def.name), " (yours)" if owner == p.player_id else ""])
	print("nearby:    %s" % (", ".join(named) if not named.is_empty() else "nothing"))

	# What the guide actually looks like, which a screenshot keeps failing to catch.
	for e in guides:
		if not str(e.def.name).ends_with(":wick"):
			continue
		var look: Dictionary = e.data.get("look", {}) if e.data.get("look") is Dictionary else {}
		print("wick look: tint=%s plate=%s" % [str(look.get("tint", {})), str(look.get("nameplate", {}))])
		print("wick at:   %s  (%.1f m from player)" % [e.body.position, e.body.position.distance_to(p.state.position)])

	var objectives: Array = server.objectives.of(p) if server.objectives.has_method("of") else []
	print("tasks:     %s" % (str(objectives) if not objectives.is_empty() else "none yet"))
	print("")
	get_tree().quit(0)
