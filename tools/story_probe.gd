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

	# `active_for`, not `of`. It was `of` for a day, which does not exist - so the probe answered
	# "none yet" however many tasks the player was holding, and reported a working story as a broken
	# one. A `has_method` guard around a name nobody checked is a guard that hides the mistake.
	var objectives: Array = server.objectives.active_for(p)
	if objectives.is_empty():
		print("tasks:     none yet")
	for task in objectives:
		print("task:      %-24s step %d/%d  %s" % [String(task.get("display_name", "")),
			int(task.get("step", 0)) + 1, int(task.get("of", 1)), String(task.get("text", ""))])
	if OS.get_cmdline_user_args().has("--names"):
		var items := []
		for d in server.items.defs:
			items.append(str(d.get("name", "")))
		print("items:     %s" % ", ".join(items))
		var blocks := []
		for d in server.registry.defs:
			blocks.append(str(d.get("name", "")))
		print("blocks:    %s" % ", ".join(blocks))
	var problems := _reachable(server)
	print("")
	get_tree().quit(1 if not problems.is_empty() else 0)


## **Can the chain actually be finished with the gear the chain grants?**
##
## Asks the registries, walking the acts in order and carrying a running tool tier: every mining step
## is checked against the best pickaxe any earlier act has asked the player to make. It exists because
## the answer was no and nothing said so - "mine ten deepstone" sat at act 7, deepstone is tier 4, and
## the only act that grants a tier 4 pickaxe came later. A child following the story exactly would
## have stopped dead there, and the acts all validated perfectly. (2026-09-24)
func _reachable(server) -> Array:
	var Acts = load("res://mods/firstlight/acts.gd")
	if Acts == null:
		return []
	var have := 0  # best pickaxe tier the chain has asked for so far
	var problems := []
	for act in Acts.ACTS:
		for step in act.steps:
			var goal: Dictionary = step.get("goal", {})
			var named := [String(goal.get("is", ""))] + Array(goal.get("any", []))
			if String(goal.get("on", "")) == "break":
				for block_name in named:
					var id: int = server.registry.ids.get(String(block_name), -1)
					if id < 0:
						continue
					var needs := int(server.registry.defs[id].get("tier", 0))
					if needs > have:
						problems.append("%s asks for %s (tier %d) with only a tier %d pickaxe" % [
							String(act.id), block_name, needs, have])
			elif String(goal.get("on", "")) == "craft":
				for item_name in named:
					if not String(item_name).ends_with("_pickaxe"):
						continue
					var item_id: int = server.items.id_of(String(item_name))
					if item_id <= 0:
						continue
					var tool: Dictionary = server.items.get_def(item_id).get("tool", {})
					have = maxi(have, int(tool.get("tier", 0)))
	for line in problems:
		print("UNREACHABLE: %s" % line)
	if problems.is_empty():
		print("reachable: every mining step is within the pickaxe the chain has granted by then")
	return problems
