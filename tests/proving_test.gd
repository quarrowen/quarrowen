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
	_area_tools(server, server.mod_instances.proving.api, p)
	_nested_inventories(server, server.mod_instances.proving.api, p)


## A bag and a shared store: two containers whose contents are not at a position.
func _nested_inventories(server, api, p) -> void:
	var satchel: int = server.items.id_of("proving:satchel")
	var rock: int = server.items.id_of("proving:rock")
	_check(satchel > 0, "an item can declare a container type")
	p.inventory.set_slot(0, satchel, 1)
	p.inventory.selected = 0
	_check(api.open_bag(p, 0), "and opening it gives a container screen")
	var bag = server.containers.at_key(server.containers.item_key(0), p)
	_check(bag != null and bag.size() == 9, "the bag has its own slots (%d)" % (bag.size() if bag else -1))
	bag.set_item(0, rock, 5, {})
	# The contents live in the *item's* data, which is what makes a bag hold what it holds wherever
	# it goes - so they must be in the inventory slot's data, not in a table beside it.
	_check(p.inventory.data[0].has("slots"), "and its contents are kept in the item's own data")
	_check(server.containers.holds_open_bag(p, 0), "the slot holding an open bag is locked")
	_check(not server.containers.holds_open_bag(p, 1), "but only that slot")
	# Carried away and back: the same five rocks, with nothing keeping the two in step.
	p.inventory.set_slot(3, p.inventory.ids[0], 1, p.inventory.data[0])
	p.inventory.clear_slot(0)
	server.containers.close(p, false)
	var moved = server.containers.at_key(server.containers.item_key(3), p)
	_check(moved != null and moved.get_item(0).count == 5, "and they travel with the item to another slot")

	# The shared store: the same contents opened by somebody else entirely.
	var vault = api.get_shared("vault")
	_check(vault != null and vault.size() == 18, "a shared store exists once it is declared")
	vault.set_item(0, rock, 7, {})
	var other := _player(server, 91, "Other")
	_check(api.open_shared(other, "vault"), "another player can open it")
	var theirs = server.containers.at_key(server.containers.store_key("proving:vault"), other)
	_check(theirs != null and theirs.get_item(0).count == 7,
		"and sees the same contents, with no position between them")
	server.containers.close(other, false)
	server.players.erase(91)


## Area tools, asked of the engine rather than of the mod: what came back, and what it did to the world.
func _area_tools(server, api, p) -> void:
	var rock: int = server.registry.id_of("proving:rock")
	# The three built-in shapes.
	var box: Array = api.area_cells("box", {"from": Vector3i(5, 66, 5), "to": Vector3i(7, 67, 7)})
	_check(box.size() == 18, "a box selects every cell between its corners (%d)" % box.size())
	var ball: Array = api.area_cells("sphere", {"position": Vector3i(5, 66, 5), "radius": 2.0})
	_check(ball.size() > 18 and ball.size() < 40, "a sphere selects a ball (%d)" % ball.size())
	# A vein follows one block kind and stops: three rocks in a row in open air above the ground,
	# with a fourth set apart. Above the ground because FlatGround is solid rock below y=61, where
	# "three rocks in a row" is three rocks in a world already made of them. (2026-09-21)
	for x in 3:
		server.set_block_authoritative(Vector3i(10 + x, 66, 10), rock)
	server.set_block_authoritative(Vector3i(14, 66, 10), rock)
	var vein: Array = api.area_cells("vein", {"position": Vector3i(10, 66, 10), "max": 64})
	_check(vein.size() == 3, "a vein follows its own kind and stops at the gap (%d)" % vein.size())
	# The shape the mod registered, found without it having to spell out its own id.
	var column: Array = api.area_cells("column", {"position": Vector3i(5, 66, 5), "height": 5})
	_check(column.size() == 5, "a mod's own shape is found by its bare name (%d)" % column.size())
	_check(api.area_cells("no_such_shape", {}).is_empty(), "and an unknown shape gives nothing back")
	# `max` is a cap, not a suggestion.
	_check(api.area_cells("box", {"from": Vector3i(5, 66, 5), "to": Vector3i(14, 75, 14), "max": 7}).size() == 7,
		"max caps what comes back")

	# Doing it. Creative, so the fill is not paid for out of an empty inventory.
	p.inventory.creative = true
	# Beside the box, not inside it: a solid block is refused in a cell a player is standing in, which
	# the next check proves on purpose.
	p.state.position = Vector3(2.5, 66, 2.5)
	p.edit_tokens = 15.0
	var filled: Dictionary = api.area_edit(p, box, {"block": rock})
	_check(filled.changed == 18, "an area edit changes every cell it is given (%d)" % filled.changed)
	_check(server.world.get_block_v(Vector3i(6, 66, 6)) == rock, "and the world really changed")
	# An area fill cannot wall a player in. Worth its own check because the cost of getting it wrong is
	# a child stuck inside a block, and the rule lives in place_block_for where nothing else tests it.
	api.area_edit(p, box, {"block": 0})
	var standing := Vector3i(floori(p.state.position.x), floori(p.state.position.y), floori(p.state.position.z))
	var over_player: Dictionary = api.area_edit(p, [standing], {"block": rock})
	_check(over_player.changed == 0 and server.world.get_block_v(standing) == 0,
		"and it refuses to place a solid block where somebody is standing")
	api.area_edit(p, box, {"block": rock})
	var cleared: Dictionary = api.area_edit(p, box, {"block": 0})
	_check(cleared.changed == 18, "and breaking them puts it back (%d)" % cleared.changed)
	_check(server.world.get_block_v(Vector3i(6, 66, 6)) == 0, "with the cells empty again")

	# The budget is the one that already exists: a selection costs cells/CELLS_PER_TOKEN tokens.
	p.edit_tokens = 0.0
	var broke: Dictionary = api.area_edit(p, box, {"block": rock})
	_check(broke.refused and broke.changed == 0, "an edit with no budget left is refused, with a reason")
	_check(not String(broke.reason).is_empty(), "and the reason is in words a player can be shown")

	# Too far away is refused as a whole, rather than per cell.
	p.edit_tokens = 15.0
	p.state.position = Vector3(500, 66, 500)
	var far: Dictionary = api.area_edit(p, box, {"block": rock})
	_check(far.refused and far.changed == 0, "a selection out of range is refused")
	p.state.position = Vector3(0.5, 65, 0.5)
	p.inventory.creative = false


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
