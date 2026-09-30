extends Node
## Firstlight's descent, asserted rather than photographed:
##
##   godot --headless --path . res://tests/descent_test.tscn
##
## **Content, and tested as content on purpose.** The usual rule here is to assert the capability and
## not the mod, because a test that names content dies with the content. The descent is the exception
## worth making: it is the one thing in 1.0 a player is meant to come back to, its four pieces (the
## way marks are earned and spent, the boss, the run on screen, the sound) are rules rather than
## capabilities, and each of them is invisible when it breaks. A gate that stops refusing, a boss that
## silently fails to spawn and a panel that never appears all look exactly like a working descent from
## the outside. (2026-09-30)

const GameServer = preload("res://engine/server/game_server.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")

var _failures := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var server := GameServer.new()
	add_child(server)
	# **Never user://**: `use_custom_user_dir` makes that the installed game's own folder.
	var scratch: String = OS.get_environment("TMPDIR").path_join("quarrowen-descent-%d" % OS.get_process_id())
	var err: Error = server.start({"mods": PackedStringArray(["firstlight"]),
		"world": "descent_test", "data_dir": scratch, "seed": 42, "offline": true})
	if err != OK:
		print("[descent] FAIL server start: %s" % error_string(err))
		return _finish(scratch)
	server.set_physics_process(false)

	server.ensure_area_loaded(Vector3(0.5, 70, 0.5))
	var p := ServerPlayer.new(server, 101, "Probe")
	p.player_id = "probe"
	p.state.position = Vector3(0.5, float(server.realm.block_ticks._column_height(0, 0) + 1), 0.5)
	server.players[101] = p
	server.emit("player_join", {"player": p})
	await get_tree().process_frame

	var mod = server.mod_instances.get("firstlight")
	_check(mod != null, "firstlight loaded")
	if mod == null:
		return _finish(scratch)
	var descent = mod.descent

	# **Harsh is refused before it is affordable**, which is the whole of the gate. A first run has to
	# be gentle, so risking everything is something worked up to rather than picked from a menu.
	_check(not descent.enter(p, true), "harsh is refused with no marks")
	_check(descent.problem.contains("depth marks"), "and says what it costs (%s)" % descent.problem)
	_check(descent.depth_of(p) == 0, "and did not start a run anyway")

	_check(descent.enter(p, false), "a gentle descent opens")
	_check(descent.depth_of(p) == 1, "on floor 1")
	_check(int(p.data.get("firstlight:deepest", 0)) == 1, "the deepest floor is recorded")

	# Down to ten, which crosses the boss floors twice. Ten is also exactly what harsh costs, so this
	# run is the shortest one that buys the thing refused above - **two boss floors of nerve**, which is
	# the shape the gate is meant to have.
	for want in range(2, 11):
		_check(descent._open(p, want), "floor %d opens" % want)
	_check(descent.depth_of(p) == 10, "ten floors down")
	_check(int(p.data.get("firstlight:deepest", 0)) == 10, "and the deepest floor followed")

	_check(_wardens_on(server, descent, p) == 1, "the Warden stands on floor 10")
	# And nowhere else: a floor between the boss floors is a walk, not a fight.
	_check(descent._open(p, 11), "floor 11 opens")
	_check(_wardens_on(server, descent, p) == 0, "and not on floor 11")

	# Coming out pays the floor reached. Marks are the only currency and this is their only source, so
	# dying pays nothing - which is what makes the way up worth taking.
	var before: float = descent.api.balance_of(p, "marks")
	descent.out(p)
	var earned: float = descent.api.balance_of(p, "marks") - before
	_check(descent.depth_of(p) == 0, "coming out ends the run")
	_check(is_equal_approx(earned, 11.0), "and pays the floor reached (%s)" % earned)

	# Which is now enough for the thing that was refused at the start.
	_check(descent.enter(p, true), "harsh opens once it is paid for")
	_check(is_equal_approx(descent.api.balance_of(p, "marks"), 1.0), "and the marks are spent")
	descent.abandon(p)

	_finish(scratch)


func _finish(scratch: String) -> void:
	print("[descent] %s" % ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	_remove_tree(scratch)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, what: String) -> void:
	print("[descent] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


## Bosses in the floor this run is on. Each floor is its own instance and the one behind is closed, so
## this is always a question about exactly one realm.
func _wardens_on(server, descent, p) -> int:
	var here: String = String(descent.runs[p.player_id].instance)
	var realm = server.realms.get(here)
	if realm == null:
		return -1
	var found := 0
	for e in realm.entities.entities.values():
		if String(e.def.name) == "base:barrow_warden":
			found += 1
	return found


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
