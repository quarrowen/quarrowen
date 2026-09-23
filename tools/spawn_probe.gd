extends Node
## Measures whether a game's spawn rules can actually find anywhere to put a creature.
##
##   godot --headless --path . res://tools/spawn_probe.tscn -- [game]
##
## A spawn rule that never fires is silent: no error, no warning, no test failure - you find out by
## never meeting the creature. The Barrow Warden's first rule was very nearly in that state (surface,
## standing on stone, in a world whose every biome tops out in grass, sand, snow or gravel) and it was
## caught by reading `spawning.gd` rather than by anything automatic. This is the thing to run instead
## of reading it. (2026-09-23)
##
## It asks `find_spot` directly, once per attempt, rather than rolling `chance` - so the number it
## prints is "given the roll succeeded, how often is there anywhere to stand", which is the half a
## rule's author gets wrong. Multiply by `chance` for the real rate.

const GameServer = preload("res://engine/server/game_server.gd")

## Attempts per rule. `find_spot` itself makes six tries, so this is 2400 castings about.
const TRIES := 400
## Chunks loaded either side of the probe position. The spawn ring is 24-72 blocks, so this has to
## cover it or every rule reads as broken for a reason that is about the harness.
const CHUNK_RADIUS := 5


## Where the probe's world goes: a temporary directory, never the player's.
var _scratch := OS.get_environment("TMPDIR").path_join("quarrowen-spawn-probe-%d" % Time.get_ticks_msec())


func _ready() -> void:
	var game := "creative"
	for arg in OS.get_cmdline_user_args():
		if not String(arg).begins_with("-"):
			game = String(arg)
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray([game]),
		"world": "spawn_probe_%d" % Time.get_ticks_msec(),
		# **Never user://.** `project.godot` sets `use_custom_user_dir`, so `user://` from this checkout
		# is the installed game's folder and a probe run would leave a world in somebody's real save
		# list - which has happened three times and is the first rule in CLAUDE.md. A throwaway
		# directory, removed on the way out.
		"data_dir": _scratch, "seed": 42, "offline": true})
	if err != OK:
		print("server start failed: %s" % error_string(err))
		get_tree().quit(1)
		return
	server.set_physics_process(false)

	var here := Vector3(0.5, 0.0, 0.5)
	for cx in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
		for cz in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
			server._ensure_chunk(Vector2i(cx, cz))
	# Stand on whatever the generator put at the origin, so "surface" means something.
	here.y = float(server.realm.block_ticks._column_height(0, 0) + 1)
	print("probe standing at %s, %d chunks loaded" % [here, (CHUNK_RADIUS * 2 + 1) ** 2])

	var registry = server.entities.registry
	var blocks = server.registry
	print("")
	print("%-22s %-11s %-6s %7s  %s" % ["rule", "place", "when", "found", "standing on"])
	for rule: Dictionary in server.entities.spawning.rules:
		var name: String = registry.defs[int(rule.entity)].name
		var found := 0
		var ground := {}
		# **At the hour the rule is for, and for "any" at whichever hour works.** `find_spot` reads
		# daylight for the light check, so probing at the wrong time measures nothing: probed at night,
		# every animal rule read 0.0% - correct behaviour, since animals want light 9-15, and it would
		# have been reported as five bugs. An "any" rule only has to work at *some* hour, so it is
		# tried at both and reported at the better one; a row that says 0.0% then really is a rule that
		# can never place anything. (2026-09-23)
		var when := str(rule.get("time", "any"))
		var hours := {"day": 1.0, "night": 0.0} if when == "any" else {when: 1.0 if when == "day" else 0.0}
		var best := ""
		for hour: String in hours:
			var hits := 0
			var seen := {}
			for i in TRIES:
				var at: Vector3 = server.entities.spawning.find_spot(here, rule, float(hours[hour]))
				if at == Vector3.INF:
					continue
				hits += 1
				var under: int = server.world.get_block(floori(at.x), floori(at.y) - 1, floori(at.z))
				var under_name: String = blocks.defs[under].name if blocks.is_valid(under) else str(under)
				seen[under_name] = int(seen.get(under_name, 0)) + 1
			if hits > found or best.is_empty():
				found = hits
				ground = seen
				best = hour
		when = best if when == "any" else when
		var top: Array = ground.keys()
		top.sort_custom(func(a, b): return ground[a] > ground[b])
		var shown: Array = top.slice(0, 3).map(func(k): return "%s %d" % [k, ground[k]])
		print("%-22s %-11s %-6s %6.1f%%  %s" % [name, str(rule.get("place", "any")), when,
			100.0 * found / float(TRIES), ", ".join(shown) if not shown.is_empty() else "-"])
	print("")
	print("(world left in %s; TMPDIR is cleaned by the system)" % _scratch)
	get_tree().quit(0)
