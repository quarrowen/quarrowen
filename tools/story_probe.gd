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
	problems += await _walk(server, p)
	print("")
	get_tree().quit(1 if not problems.is_empty() else 0)


## **Walks the whole chain by firing the events the goals wait for.**
##
## For every act in order it emits the event each step is listening for, as many times as the step
## asks, then checks the act finished and the next one was handed over.
##
## **What it catches, tested by breaking each one on purpose:** a goal naming a block or item that
## does not exist (the commonest content typo - the id comes back -1 and matches nothing); a goal
## kind this file does not know how to fire; a step that does not advance on the right event, which
## is where `_score`'s filters and the qualified-name mismatch both live; an act that never finishes;
## and a chain that stops handing over the next act.
##
## **What it cannot catch, and this was checked rather than assumed:** an act watching the *wrong*
## event. `_fire` reads the same table the story reads, so pointing a goal at a different event kind
## changes both sides together and the walk sails past it. That claim was made here first and was
## wrong; breaking `"on": "eat"` to `"on": "tame"` still passed. Only playing it catches that.
##
## It is not a playthrough. It proves the wiring, which is where the bugs have actually been. Whether
## a player can find eight sunstone is a different question and ore generation answers it.
## (2026-09-24)
func _walk(server, p) -> Array:
	var Acts = load("res://mods/firstlight/acts.gd")
	var api = server._api_for("firstlight")
	if Acts == null or api == null:
		return []
	var problems := []
	print("")
	for act in Acts.ACTS:
		var act_id := String(act.id)
		if not api.has_objective(p, act_id):
			problems.append("%s was never handed over" % act_id)
			print("CHAIN STOPPED: %s was never handed over" % act_id)
			break
		var ok := true
		for i in (act.steps as Array).size():
			var step: Dictionary = act.steps[i]
			var before := _step_of(api, p, act_id)
			for _n in int(step.get("count", 1)):
				_fire(server, api, p, step.get("goal", {}))
			await get_tree().process_frame
			var after := _step_of(api, p, act_id)
			# -1 means the objective is gone, which for the last step is exactly right.
			if after == before and after != -1:
				problems.append("%s step %d did not advance (%s)" % [act_id, i + 1, String(step.text)])
				print("STUCK: %s step %d - %s" % [act_id, i + 1, String(step.text)])
				ok = false
				break
		if not ok:
			break
		if api.objective_finished(p, act_id) < 1:
			problems.append("%s never finished" % act_id)
			print("STUCK: %s never finished" % act_id)
			break
		print("walked:    %s" % act_id)
	if problems.is_empty():
		print("chain:     all %d acts walk to the end" % (Acts.ACTS as Array).size())
	return problems


## Which step of an objective a player is on, or -1 when they are not holding it.
func _step_of(api, p, objective_name: String) -> int:
	for task in api.objectives_of(p):
		if String(task.get("name", "")).ends_with(":" + objective_name):
			return int(task.get("step", -1))
	return -1


## Emits the event one goal is waiting for. Mirrors story.gd `_listen`; if that gains a kind, this
## has to gain it too, and the walk will say so by getting stuck.
func _fire(server, api, p, goal: Dictionary) -> void:
	var kind := String(goal.get("on", ""))
	var named := String(goal.get("is", ""))
	if named.is_empty() and goal.get("any") is Array and not (goal.any as Array).is_empty():
		named = String(goal.any[0])
	match kind:
		"break":
			server.emit("block_broken", {"player": p, "block": server.registry.ids.get(named, 1)})
		"place":
			server.emit("block_placed", {"player": p, "block": server.registry.ids.get(named, 1)})
		"craft":
			server.emit("item_crafted", {"player": p, "item": server.items.id_of(named), "count": 1})
		"carry":
			server.emit("item_pickup", {"player": p, "item": server.items.id_of(named), "count": 1})
		"eat":
			server.emit("player_eat", {"player": p, "item": server.items.id_of(named)})
		"tame":
			server.emit("entity_tamed", {"player": p})
		"night":
			server.emit("player_wake", {"player": p, "reason": "woke"})
		"notable":
			var rare = _a_rare_one(server, api, p)
			if rare != null:
				server.emit("entity_death", {"entity": rare, "cause": "hit", "attacker": p, "drops": []})
		"built":
			server.emit("multiblock_formed", {"realm": server.realm.id, "name": String(goal.get("name", "")),
				"controller": Vector3i(p.state.position), "origin": Vector3i(p.state.position), "cells": []})
		"depth":
			# A state rather than an event, so the story looks at it on a timer. Put the player there
			# and run the clock forward past the next tick.
			p.state.position.y = float(goal.get("below", 30.0)) - 5.0
			server._time += 5.1
			server._run_tasks()


## Something the whole server would be told about, spawned so `entity_death` carries a real type.
func _a_rare_one(server, api, p):
	for type_name in api.entity_types():
		if api.notable_of(String(type_name)).is_empty():
			continue
		var made = api.spawn_entity(String(type_name), p.state.position + Vector3(2.0, 0.0, 2.0))
		if made != null:
			return made
	return null


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
