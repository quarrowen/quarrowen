extends Node
## Asserts that the Proving Ground really exercised every capability:
##   godot --headless --path . res://tests/proving_test.tscn
##
## The mod *calling* the engine is not proof. `mod_tool validate` reported "0 errors" on a version of
## the mod that threw two script errors during setup, because a mod that fails to register something
## still loads. So this asks the engine what it ended up with, rather than asking the mod what it tried.

const GameServer = preload("res://engine/server/game_server.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")

const DATA_DIR := "user://proving_test"
var _failures := 0
var _checks := 0


func _ready() -> void:
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(["proving", "proving_js"]),
		"mod_dirs": PackedStringArray(["res://tests/mods"]),
		"world": "proving_%d" % Time.get_ticks_msec(), "data_dir": DATA_DIR, "seed": 42, "offline": true})
	_check(err == OK, "the Proving Ground starts as a game (%s)" % error_string(err))
	if err != OK:
		return _finish()
	server.set_physics_process(false)

	# The ground this mod generates, before anything else: a test standing on nothing measures falling.
	server.ensure_area_loaded(Vector3(0.5, 65, 0.5))
	var under: int = server.world.get_block(0, 64, 0)
	var above: int = server.world.get_block(0, 65, 0)
	_check(server.registry.is_valid(under) and server.registry.solid_lut[under] == 1,
		"there is solid ground at y=64 (%s)" % (server.registry.defs[under].name if server.registry.is_valid(under) else under))
	_check(above == 0, "and air above it (%d)" % above)

	# A requirement that is not met says so, and hands back something inert rather than a -1 that would
	# be written into the world as 65535 - which is UNLOADED, and reads as "no world here".
	var api = server.mod_instances.proving.api
	_check(api.require_block("proving:rock") == server.registry.id_of("proving:rock"),
		"require_block gives the id when the block is there")
	_check(api.block("proving:not_a_thing") == -1 and api.require_block("proving:not_a_thing") == 0,
		"and a probe says -1 where a requirement says air, loudly")

	_registries(server)
	_excludes()
	_javascript(server)
	_behaviour(server)
	server.queue_free()
	_finish()


## A game that takes most of a pack and refuses the rest. The exclusion has to happen before anything
## registers - a game loads *after* what it depends on, so by its own setup() the thing already exists.
func _excludes() -> void:
	var server := GameServer.new()
	add_child(server)
	var err: Error = server.start({"mods": PackedStringArray(["picky"]),
		"mod_dirs": PackedStringArray(["res://tests/mods"]),
		"world": "picky_%d" % Time.get_ticks_msec(), "data_dir": DATA_DIR, "seed": 42, "offline": true})
	_check(err == OK, "a game that excludes part of what it depends on still starts (%s)" % error_string(err))
	if err != OK:
		server.queue_free()
		return
	_check(server.registry.id_of("proving:lamp") < 0, "a named exclusion never gets an id")
	_check(server.registry.id_of("proving:slime") < 0 and server.registry.id_of("proving:slime_thin") < 0,
		"and a wildcard takes the whole family")
	_check(server.items.id_of("proving:grain") < 0, "items can be excluded too")
	# What survives is the point: excluding three things must not cost the rest.
	_check(server.registry.id_of("proving:rock") >= 0 and server.registry.id_of("proving:crate") >= 0
		and server.items.id_of("proving:token") >= 0, "everything not excluded is still there")
	# Extending: adding to a pack rather than forking it.
	var biter: int = server.entities.registry.id_of("proving:biter")
	var attacks: Array = server.entities.ai.config_for(biter).attacks
	_check(attacks.any(func(a): return String(a.name) == "kick"),
		"a mod adds an attack to another mod's creature (%s)" % str(attacks.map(func(a): return a.name)))
	_check(attacks.any(func(a): return String(a.name) == "bite"), "and the original attacks are still there")
	_check(attacks.any(func(a): return String(a.name) == "kick" and String(a.condition.get("condition", "")) == "proving:venom"),
		"the added attack's nested names were qualified, like any other")
	_check((server.entities.registry.defs[biter].drops as Array).size() == 3, "a drop can be added too")
	_check((server.registry.defs[server.registry.id_of("proving:crate")].drops as Array).size() >= 1,
		"and to a block")

	# A recipe naming an excluded item is dropped rather than half-registered.
	for recipe in server.recipes.recipes:
		_check(int(recipe.output) != server.items.id_of("proving:grain"), "no recipe outputs an excluded item")
	server.queue_free()


## Everything the mod registered actually reached a registry. One check per capability family, naming
## what is missing rather than just failing.
func _registries(server) -> void:
	var reg = server.registry
	for block in ["proving:plain", "proving:lamp", "proving:crate", "proving:bench", "proving:wire",
			"proving:switch", "proving:core", "proving:slime", "proving:slime_thin", "proving_js:js_block"]:
		_check(reg.id_of(block) >= 0, "block %s" % block)
	for item in ["proving:token", "proving:prod", "proving_js:js_item"]:
		_check(server.items.id_of(item) >= 0, "item %s" % item)
	for entity in ["proving:grazer", "proving:biter", "proving:raft"]:
		_check(server.entities.registry.id_of(entity) >= 0, "entity %s" % entity)

	_check(server.conditions.kinds.has("proving:venom") and server.conditions.kinds.has("proving:haste")
		and server.conditions.kinds.has("proving_js:js_chill"), "conditions, from both languages")
	_check(server.fields.kinds.has("proving:scorch") and server.fields.kinds.has("proving_js:js_puddle"),
		"fields, from both languages")
	_check(server.characters.kinds.has("proving:keeper") and server.characters.kinds.has("proving_js:js_keeper"),
		"characters, from both languages")
	_check(server.shops.kinds.has("proving:stall") and server.shops.kinds.has("proving_js:js_stall"),
		"shops, from both languages")
	_check(server.ledgers.kinds.has("proving:coins") and server.ledgers.kinds.has("proving_js:js_coins"),
		"ledgers, from both languages")
	_check(server.objectives.kinds.has("proving:errand") and server.objectives.kinds.has("proving_js:js_errand"),
		"objectives, from both languages")
	_check(server.companions.kinds.has("proving:forage") and server.companions.kinds.has("proving_js:js_wait"),
		"orders, from both languages")

	_check(server.multiblock_patterns.has("proving:engine"), "a multiblock pattern")
	_check(server.liquid_kinds.has(reg.id_of("proving:slime")), "a liquid")
	_check(server.links.kinds.has("proving:cable") and server.links.kinds.has("proving:aether"),
		"link kinds, wired and wireless")
	_check(server.realms.has("proving:deep"), "a second realm (%s)" % str(server.realms.keys()))
	_check(server.tags.exists("proving:stone_like"), "a tag")
	_check(server.modifiers.kinds.has("proving:keen"), "an item modifier")
	_check(server.effects.id_of("proving:puff") >= 0, "an effect")
	_check(server.weather.id_of("proving:haze") >= 0, "a weather")


## The JavaScript half reached the same engine. Most of what it calls has no hand-written binding, so
## this is the test that the generated table works end to end.
func _javascript(server) -> void:
	if not ClassDB.class_exists(&"NativeJsRuntime"):
		print("[proving] (no native extension: JavaScript checks skipped)")
		return
	_check(server.mod_instances.has("proving_js"), "the JavaScript mod loaded")
	var p := _player(server, 200, "Prover")
	server._commands.get("jsprove", {}).get("handler", Callable()).call(p, PackedStringArray())
	_check(server.ledgers.value_of(p, "proving_js:js_coins") == 5.0,
		"a JavaScript command moved a ledger (%s)" % server.ledgers.value_of(p, "proving_js:js_coins"))
	_check(server.objectives.has(p, "proving_js:js_errand"), "and gave an objective")
	_check(server.conditions.has(p, "proving_js:js_chill"), "and applied a condition")
	_check(not server.fields.at(p.state.position).is_empty(), "and put a field on the ground")
	_check(not server.nameplates.plate_of(p).get("lines", []).is_empty(), "and wrote on a nameplate")


## A few things that only show up when they run, rather than when they are registered.
func _behaviour(server) -> void:
	var p := _player(server, 201, "Walker")
	# A character, its shop, and the objective it hands over.
	_check(server.characters.talk(p, "proving:keeper"), "a conversation opens")
	server.on_ui_action(201, "engine:talk", "say:start:1")
	_check(server.objectives.has(p, "proving:errand"), "an option handed over an objective")
	server.characters.talk(p, "proving:keeper")
	server.on_ui_action(201, "engine:talk", "say:start:0")
	_check(p.ui_ids.has("engine:shop"), "another opened the stall")

	# A condition that ticks, and a field that hurts.
	p.health = 20.0
	p.hurt_timer = 0.0
	server.conditions.give(p, "proving:venom", {"seconds": 10.0})
	server._time += 1.1
	server.conditions.tick(0.1)
	_check(p.health < 20.0, "venom hurts on its own timer (%s)" % p.health)

	# Flight: the one kind of movement that is not about the ground.
	var flitter = server.entities.spawn(server.entities.registry.id_of("proving:flitter"),
		Vector3(30.5, 66, 30.5), {})
	_check(flitter != null, "something that flies")
	_check(flitter.brain != null and not flitter.brain.config.fly.is_empty(), "and knows it flies")
	# Told to go somewhere, it never asks the ground pathfinder: going over what a walker goes round is
	# the whole point.
	flitter.brain.move_to(Vector3(60.5, 66, 60.5), 1.0, 1.0)
	_check(flitter.brain.direct and flitter.brain.path.is_empty(), "a flier is never given a walking path")
	# Left alone below its preferred height, it climbs rather than settling on the ground.
	flitter.body.position = Vector3(30.5, 65.2, 30.5)
	flitter.body.velocity = Vector3.ZERO
	flitter.brain.move_goal = Vector3.INF
	for i in 30:
		flitter.brain._steer(0.05)
	_check(flitter.body.velocity.y > 0.1, "and climbs back to its height when it is too low (%.2f)" % flitter.body.velocity.y)

	# A creature, tamed, ordered, and ridden.
	var grazer = server.entities.spawn(server.entities.registry.id_of("proving:grazer"),
		p.state.position + Vector3(1, 0, 0), {})
	_check(grazer != null, "a creature spawns")
	server.entities.taming.tame(grazer, p)
	_check(server.companions.give(grazer, "proving:forage"), "and takes an order a mod registered")
	var raft = server.entities.spawn(server.entities.registry.id_of("proving:raft"),
		p.state.position + Vector3(1, 0, 0), {})
	_check(server.vehicles.mount(p, raft) and p.riding == raft.id, "and a raft can be ridden")
	server.vehicles.dismount(p)


func _player(server, peer_id: int, player_name: String) -> ServerPlayer:
	var p := ServerPlayer.new(server, peer_id, player_name)
	p.player_id = player_name.to_lower()
	p.state.position = Vector3(0.5, 65, 0.5)
	server.players[peer_id] = p
	return p


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print("[proving] %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _finish() -> void:
	print("[proving] %s (%d checks, %d failed)" % ["PASSED" if _failures == 0 else "FAILED", _checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
