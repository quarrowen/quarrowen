extends Node
## Asserts that the Proving Ground really exercised every capability:
##   godot --headless --path . res://tests/proving_test.tscn
##
## The mod *calling* the engine is not proof. `mod_tool validate` reported "0 errors" on a version of
## the mod that threw two script errors during setup, because a mod that fails to register something
## still loads. So this asks the engine what it ended up with, rather than asking the mod what it tried.

const GameServer = preload("res://engine/server/game_server.gd")
const ServerPlayer = preload("res://engine/server/server_player.gd")
const EntityRegistry = preload("res://engine/shared/entity_registry.gd")

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

	_coverage()
	_registries(server)
	_excludes()
	_javascript(server)
	_behaviour(server)
	server.queue_free()
	_finish()


## Whether this mod still deserves the sentence written about it.
##
## CLAUDE.md says the Proving Ground uses every capability the engine has, and that claim is the reason
## it exists. Measured for the first time on 2026-09-22 it was 40 of 56, with sixteen `register_*`
## never called in either language - `register_biome`, `register_sound`, `register_structure` and
## `register_minigame` among them, which are not corners but things games are made of.
##
## Nobody had lied; nobody had counted. Exactly how the JavaScript bridge reached 139 of 262. So the
## claim is a ratchet now instead of a sentence: `uncovered.txt` may only shrink, and a new capability
## that nothing here exercises fails this test.
func _coverage() -> void:
	var Coverage = preload("res://tools/proving_coverage.gd")
	var now: Array = Coverage.uncovered()
	var was: Array = Coverage.baseline()
	var added := now.filter(func(name): return not was.has(name))
	_check(added.is_empty(),
		"every capability is exercised here, or was already known not to be (new: %s)" % ", ".join(added))
	var closed := was.filter(func(name): return not now.has(name))
	_check(closed.is_empty(),
		"and tests/mods/proving/uncovered.txt has no stale entries - %s is covered now, regenerate with `mod_tool.tscn -- coverage`" % ", ".join(closed))


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

	# A model part that casts light. Asserted on the network table rather than on the definition,
	# because the whole capability is that it reaches the client - it was a NETWORK_FIELDS omission
	# away from being invisible, which is the failure this would not otherwise catch.
	var creatures = server.entities.registry
	var lit: Dictionary = creatures.to_network()[creatures.id_of("proving:flitter")]
	_check(lit.get("light") is Dictionary and float(lit.light.get("range", 0.0)) == 7.0
		and String(lit.light.get("part", "")) == "body",
		"a creature's model part can light the world, and the client is told")
	var silly: Dictionary = EntityRegistry._read_light({"part": "x", "range": 400.0, "energy": 99.0})
	_check(float(silly.range) == 16.0 and float(silly.energy) == 8.0,
		"and a mod asking for a range of 400 is clamped rather than ending the night")

	_check(server.multiblock_patterns.has("proving:engine"), "a multiblock pattern")
	_check(server.liquid_kinds.has(reg.id_of("proving:slime")), "a liquid")
	_check(server.links.kinds.has("proving:cable") and server.links.kinds.has("proving:aether"),
		"link kinds, wired and wireless")
	_check(server.realms.has("proving:deep"), "a second realm (%s)" % str(server.realms.keys()))
	_check(server.tags.exists("proving:stone_like"), "a tag")
	_check(server.modifiers.kinds.has("proving:keen"), "an item modifier")
	_check(server.effects.id_of("proving:puff") >= 0, "an effect")
	_check(server.weather.id_of("proving:haze") >= 0, "a weather")

	# The sixteen that had no user until the coverage ratchet was written. Asserted against the
	# registries rather than against the mod, because a mod that fails to register something still
	# loads - which is how `mod_tool validate` once reported "0 errors" on a Proving Ground that threw
	# two script errors during setup. (2026-09-22)
	_check(server.sounds.id_of("proving:chime") >= 0, "a sound")
	_check(server.items.stats.has("proving:resolve"), "a player stat")
	_check(server.items.slot_index("charm") >= 0, "an equipment slot of the mod's own")
	_check(server.roles.descriptions.has("proving.prove"), "a permission")
	_check(server.skill.defs.has("proving:steady"), "a crafting minigame")
	_check(server.loot.has("proving:bench_loot"), "a loot table under the older name")
	_check(server.items.id_of("proving:prover") >= 0, "an assembly, which registers its own item")
	_check(server.items.id_of("proving:head") >= 0 and server.items.id_of("proving:handle") >= 0,
		"and the part types it is built from")
	# Unqualified on purpose, unlike most mod-supplied names: the engine owns "tools", "blocks" and the
	# rest, recipes name a category as a plain string, and a mod qualified to "mod:tools" could only
	# ever make a *second* tab labelled Tools. Asserted as written so the next person does not "fix" it
	# into a qualified name and quietly split every shared tab in two. (2026-09-22)
	_check(server.recipes.categories.any(func(c): return String(c.name) == "proven"),
		"a recipe book tab, named without a namespace so tabs can be shared")
	# Joining a tab somebody else declared is a success, not a failure: the recipes go in either way,
	# and returning false was indistinguishable from "you passed an empty name".
	var mod_api = server.mod_instances.proving.api
	var tabs_before: int = server.recipes.categories.size()
	_check(mod_api.register_recipe_category("tools", {"display_name": "Ours"}),
		"and naming a tab that already exists succeeds rather than failing")
	_check(server.recipes.categories.size() == tabs_before, "without making a second tab of the same name")
	_check(server.recipes.categories.any(func(c): return String(c.name) == "tools" and String(c.display_name) == "Tools"),
		"the tab keeps the name its first declarer gave it")
	_check(not mod_api.register_recipe_category("", {}), "while a nameless tab is still refused")


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
	# The arena gear-set round trip, through methods that have **no hand-written binding at all** -
	# saveItems, clearInventory, loadItems, syncInventory, setMaxHealth and feed all reach JavaScript
	# only because Player is generated now. If generation broke, this is what would say so.
	var rock: int = server.registry.id_of("proving:rock")
	p.inventory.set_slot(5, rock, 12)
	p.set_max_health(20.0)
	server._commands.get("jskit", {}).get("handler", Callable()).call(p, PackedStringArray())
	_check(p.inventory.count_of(rock) == 12, "a generated Player method round-tripped their things")
	_check(p.max_health == 24.0, "and another one changed their health (%s)" % p.max_health)
	_check(not server.nameplates.plate_of(p).get("lines", []).is_empty(), "and wrote on a nameplate")


## A few things that only show up when they run, rather than when they are registered.
func _behaviour(server) -> void:
	var p := _player(server, 201, "Walker")
	# A character, its shop, and the objective it hands over.
	_check(server.characters.talk(p, "proving:keeper"), "a conversation opens")
	server.on_ui_action(201, "engine:talk", "say:start:1")
	_check(server.objectives.has(p, "proving:errand"), "an option handed over an objective")
	# `order` sorts the list, so the one given second comes back first. The whole point is a story's
	# spine sitting above its errands however they were handed out, and chronological order is what
	# it has to beat - so the test gives them in the wrong order deliberately.
	server.objectives.give(p, "proving:daily")
	var list: Array = server.objectives.active_for(p)
	_check(list.size() >= 2 and String(list[0].name) == "proving:daily",
		"and `order` decides what the player reads first, not when it was given")
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
	# Handed over directly rather than fed: the engine had the behaviour and no way for a mod to ask
	# for it, which is what a story character who is a companion on sight needs. (2026-09-24)
	var mod_api = server.mod_instances.proving.api
	_check(mod_api.tame(grazer, p) and server.entities.taming.is_tamed(grazer),
		"a mod can make a creature somebody's companion without feeding it")
	_check(not mod_api.tame(null, p), "and asking about nothing is refused rather than crashing")
	_check(server.companions.give(grazer, "proving:forage"), "and takes an order a mod registered")
	var raft = server.entities.spawn(server.entities.registry.id_of("proving:raft"),
		p.state.position + Vector3(1, 0, 0), {})
	_check(server.vehicles.mount(p, raft) and p.riding == raft.id, "and a raft can be ridden")
	server.vehicles.dismount(p)
	_notable(server, p)
	_spawn_rules(server, p)
	_area_tools(server, server.mod_instances.proving.api, p)
	_nested_inventories(server, server.mod_instances.proving.api, p)
	_instances(server, server.mod_instances.proving.api, p)
	_sources_and_palette(server, server.mod_instances.proving.api, p)
	_wind(server, server.mod_instances.proving.api)
	_conflicts(server)


## Natural spawning: that a rule resolved what it named, and that it can find anywhere to put a creature.
##
## **This is the half nothing was asserting, and it is the half that fails silently.** A spawn rule
## that can never fire produces no error, no warning and no test failure - you find out by never
## meeting the creature. Two of them got written on 2026-09-23: one in a game, where `on` named blocks
## that are almost never at the surface, and one here, where three keys (`min_light`, `max_light`,
## `weight`) were not keys `spawning.gd` reads at all. Neither made a sound.
##
## So: the `on` list resolved to a real id, and `find_spot` both finds somewhere and gets the ground
## right. `tools/spawn_probe.tscn` does the same thing across a whole game when you want numbers.
func _spawn_rules(server, p) -> void:
	var rules: Array = server.entities.spawning.rules
	var grazer: int = server.entities.registry.id_of("proving:grazer")
	var rule := {}
	for entry: Dictionary in rules:
		if int(entry.entity) == grazer:
			rule = entry
	_check(not rule.is_empty(), "a mod's spawn rule reaches the spawner (%d rules)" % rules.size())
	if rule.is_empty():
		return
	# The silent failure itself: `add_spawn_rule` turns block *names* into ids and drops any that does
	# not resolve, so a typo leaves an empty list that quietly stops restricting anything.
	var turf: int = server.registry.id_of("proving:turf")
	_check((rule.on as Array) == [turf], "and its `on` list resolved to a block id rather than being dropped")
	# `light` is read as a pair, and this rule deliberately asks for one that is **not** the animal
	# default of [9, 15] - otherwise passing would prove only that the default happened to match. That
	# is exactly how three dead keys survived here unnoticed: `max_light: 4` was quietly getting the
	# monster default of 7, and everything looked fine.
	_check((rule.light as Array) == [10, 15], "and `light` was read as the pair spawning wants (%s)" % str(rule.light))

	# Somewhere to stand. The world here is flat turf, so every spot found must be on turf - which is
	# the assertion that a wrong `on` list would fail rather than merely under-deliver.
	for cx in range(-3, 4):
		for cz in range(-3, 4):
			server._ensure_chunk(Vector2i(cx, cz))
	var found := 0
	var wrong := 0
	for i in 60:
		# Daylight, because this rule is the animal half and animals want light 9-15. Probing at the
		# wrong hour measures nothing, which cost `spawn_probe` two runs to learn.
		var at: Vector3 = server.entities.spawning.find_spot(p.state.position, rule, 1.0)
		if at == Vector3.INF:
			continue
		found += 1
		if server.world.get_block(floori(at.x), floori(at.y) - 1, floori(at.z)) != turf:
			wrong += 1
	_check(found > 0, "and the spawner can find somewhere to put one (%d of 60 attempts)" % found)
	_check(wrong == 0, "every one of them standing on what the rule asked for (%d wrong)" % wrong)


## A creature the whole server is told about: announced, marked, followed, and gone when its time is up.
##
## Asserted against the world markers rather than against the tracker's own list, because the marker is
## the part a player actually sees - it is what reaches the map screen and the compass. A tracker that
## counts correctly and writes no marker is the failure worth catching.
func _notable(server, p) -> void:
	var before: int = server.world_markers.size()
	var quarry = server.entities.spawn(server.entities.registry.id_of("proving:quarry"),
		p.state.position + Vector3(2, 0, 0), {})
	_check(quarry != null and server.sightings.count() == 1, "a notable creature is picked up when it spawns")
	var marker_id := ""
	for id: String in server.world_markers:
		if id.begins_with("engine:notable-"):
			marker_id = id
	_check(not marker_id.is_empty() and server.world_markers.size() == before + 1,
		"and puts one marker on everybody's map")
	var label := str(server.world_markers.get(marker_id, {}).get("label", ""))
	# The countdown rides in the label, so this is the whole of "the players can see the clock".
	_check(label.begins_with("Quarry") and (label.ends_with("s") or label.ends_with("m")),
		"whose label carries the name and the time left ('%s')" % label)

	# The marker follows the creature. A marker left where the thing spawned is the bug this exists to
	# rule out: it looks right for the first second and then quietly lies.
	quarry.body.position += Vector3(8, 0, 0)
	server.sightings.update()
	_check(server.world_markers[marker_id].position.distance_to(quarry.body.position) < 0.01,
		"and moves with it rather than staying where it appeared")

	# The clock running out takes the creature away as well as its marker - the point of the clock is
	# that a hunt nobody came on ends, rather than piling up on the map for ever.
	server._time += 600.0
	server.sightings.update()
	_check(not server.world_markers.has(marker_id) and server.sightings.count() == 0,
		"and both are gone when its time runs out")
	_check(not quarry.is_alive() or quarry.removed, "along with the creature itself")

	# Killed rather than timed out: the same clearing up, by the other road.
	var second = server.entities.spawn(server.entities.registry.id_of("proving:quarry"),
		p.state.position + Vector3(2, 0, 0), {})
	_check(server.sightings.count() == 1, "a second one is tracked in its turn")
	server.entities.kill(second, "player", p)
	_check(server.sightings.count() == 0 and server.world_markers.size() == before,
		"and killing it takes the marker off the map")


## Where things come from, and the creative catalogue: the two halves of "what exists" that the
## recipe book cannot answer.
func _sources_and_palette(server, api, p) -> void:
	# Derived, not declared: the mod said grazers drop grain, so the engine already knows.
	var grain: int = server.items.id_of("proving:grain")
	var from: Array = api.sources_of(grain)
	var kinds := {}
	for entry: Dictionary in from:
		kinds[String(entry.kind)] = true
	_check(not from.is_empty(), "an item knows where it comes from without being told (%d sources)" % from.size())
	_check(kinds.has("creature") or kinds.has("block") or kinds.has("container"),
		"and the source was derived from a drop or a table (%s)" % ", ".join(kinds.keys()))
	# The declared half, for what nothing can infer.
	var token: Array = api.sources_of(server.items.id_of("proving:token"))
	var declared := false
	for entry: Dictionary in token:
		if String(entry.detail) == "handed over for a favour":
			declared = true
	_check(declared, "and a mod can declare a source nothing could work out")
	_check(api.sources_of(0).is_empty(), "asking about nothing gives nothing back")

	# `chance` is a real probability, not a label. The biter drops something spoiled every time and a
	# token half the time, and a player asking where a thing comes from is really asking how often.
	var certain := 0.0
	for entry: Dictionary in api.sources_of(server.items.id_of("proving:spoiled")):
		if String(entry.from) == "Biter":
			certain = float(entry.chance)
	var halved := 0.0
	for entry: Dictionary in api.sources_of(server.items.id_of("proving:token")):
		if String(entry.from) == "Biter":
			halved = float(entry.chance)
	_check(certain > 0.9, "a drop that always happens reads as certain (%.2f)" % certain)
	_check(halved > 0.3 and halved < 0.7, "and one that happens half the time reads as half (%.2f)" % halved)

	# **What the palette lists**, which is the half nobody was asserting. Taking was tested from the
	# day it was written; browsing was not, and browsing is the entire point of the screen.
	var groups: Dictionary = server.palette_groups()
	var listed := {}
	for key: String in groups:
		for id: int in groups[key]:
			listed[id] = String(key)
	_check(not groups.is_empty(), "the palette lists something at all (%d groups)" % groups.size())
	_check(listed.has(server.registry.id_of("proving:rock")),
		"the palette lists a block, which is most of what a builder wants from it")
	_check(listed.has(server.items.id_of("proving:token")), "and an item that is not a block")
	_check(String(listed.get(server.registry.id_of("proving:rock"), "")).ends_with("/Ground"),
		"a mod names the drawer its block sits in (%s)" % listed.get(server.registry.id_of("proving:rock"), "none"))
	# A block a player never carries - the far half of the pair - is not on offer, and asking for it
	# by id does not work either.
	var top: int = server.registry.id_of("proving:mast_top")
	_check(top > 0, "the pair's far half exists to be refused")
	_check(not listed.has(top), "a block that is placed rather than carried stays out of the palette")
	p.inventory.creative = true
	p.inventory.cursor_id = 0
	p.inventory.cursor_count = 0
	server.on_palette_take(p.peer_id, top, true)
	_check(p.inventory.cursor_count == 0, "and a client cannot take it by asking for its id")
	p.inventory.creative = false
	_check(listed.has(server.registry.id_of("proving:mast")), "while the half you do carry is on offer")

	# **A recipe can ask for any member of a tag, or for one thing exactly.** Both matter: a workbench
	# takes any plank, a fancy chest insists on oak. The tag form is expanded once every mod has loaded,
	# so it becomes one real recipe per member. (2026-09-23)
	var any_rubble := 0
	var rock_only := 0
	for recipe: Dictionary in server.recipes.recipes:
		if String(recipe.get("id", "")).contains("soil_from_any_rubble"):
			any_rubble += 1
		elif String(recipe.get("id", "")).contains("turf_from_rock_only"):
			rock_only += 1
	# One per member, each with the member's name on the end of its id, or they would overwrite
	# one another in the recipe book.
	_check(any_rubble == 2, "a recipe naming a tag becomes one per member (%d)" % any_rubble)
	_check(rock_only == 1, "and a recipe naming one thing stays one (%d)" % rock_only)

	# The palette: what a creative player may take. Server-owned, because it hands out items.
	p.inventory.creative = true
	p.inventory.cursor_id = 0
	p.inventory.cursor_count = 0
	var rock: int = server.items.id_of("proving:rock")
	server.on_palette_take(p.peer_id, rock, true)
	_check(p.inventory.cursor_id == rock and p.inventory.cursor_count > 1,
		"a creative player takes a full stack from the palette (%d x %d)" % [p.inventory.cursor_id, p.inventory.cursor_count])
	p.inventory.cursor_id = 0
	p.inventory.cursor_count = 0
	p.inventory.creative = false
	server.on_palette_take(p.peer_id, rock, true)
	_check(p.inventory.cursor_count == 0, "and a survival player does not")


## Content two mods both claim.
##
## Asserted against a stub rather than against two real mods, deliberately. A cross-mod collision needs
## two mods, and the only second mod here is the JavaScript half - which is skipped wherever the native
## extension is absent, so the assertion would quietly stop running in the fallback suite. This project
## has been bitten by silently-skipped assertions twice (music behind a game check, buckets behind a
## count) and both times they **stopped running rather than started failing**. A stub always runs.
func _conflicts(server) -> void:
	var Conflicts = preload("res://engine/server/conflicts.gd")
	_check(server.conflicts.find() is Array, "a live server can be asked what two mods both claim")

	var stub := StubWorld.new()
	stub.blocks = [{"name": "engine:air", "display_name": "Air"},
		{"name": "alpha:copper_ore", "display_name": "Copper Ore"},
		{"name": "beta:copper_ore", "display_name": "Copper Ore"},
		{"name": "alpha:own_twin", "display_name": "Twin"},
		{"name": "alpha:own_twin_two", "display_name": "Twin"},
		{"name": "alpha:tin", "display_name": "Tin Ore"},
		{"name": "beta:tin", "display_name": "tin-ore"}]
	stub.drops = {1: [[900, 1]], 2: [[900, 1]]}
	stub.realms = {"overworld": StubRealm.new([{"ore": 1}, {"ore": 2}])}
	var found: Array = Conflicts.new(stub).find()
	var kinds := found.map(func(c): return String(c.kind))
	_check(kinds.has("name"), "two mods naming a block the same is reported (%s)" % str(kinds))
	# Case, spacing and punctuation all reduce to the same thing: "Tin Ore" against "tin-ore" is a
	# near-miss, and a near-miss is worse than an exact match because the two sort apart in a list and
	# look deliberate. (user, 2026-09-22)
	_check(kinds.count("name") == 2, "a near-miss in case or punctuation counts too, but one mod's own pair does not (%d)" % kinds.count("name"))
	_check(kinds.has("ore"), "two mods generating different ore that drops the same item is reported")
	for clash: Dictionary in found:
		_check(String(clash.detail).contains("alpha:") and String(clash.detail).contains("beta:"),
			"and every report names both sides (%s)" % String(clash.detail))


## The smallest thing `conflicts.gd` will accept: it reads a block registry, an item registry, realms
## and default drops, and nothing else.
class StubWorld:
	var blocks: Array = []
	var drops: Dictionary = {}
	var registry: StubRegistry
	var items: StubItems
	var realms: Dictionary

	func _init() -> void:
		registry = StubRegistry.new(self)
		items = StubItems.new()
		realms = {}

	func _default_drops(id: int) -> Array:
		return drops.get(id, [])


## A realm is only ever asked for its generation passes here.
class StubRealm:
	var generation_passes: Array = []
	var biome_generator = null
	func _init(passes: Array) -> void: generation_passes = passes


class StubRegistry:
	var world
	func _init(w) -> void: world = w
	var defs: Array:
		get: return world.blocks
	func is_valid(id: int) -> bool: return id >= 0 and id < world.blocks.size()


class StubItems:
	var defs: Array = []
	func name_of(id: int) -> String: return "alpha:ingot" if id == 900 else str(id)


## Wind: a world property a mod can set, and one the engine keeps moving when nobody does.
func _wind(server, api) -> void:
	api.set_wind(270.0, 0.8)
	var blowing: Dictionary = api.get_wind()
	_check(is_equal_approx(float(blowing.angle), 270.0) and is_equal_approx(float(blowing.strength), 0.8),
		"a mod sets which way the wind blows (%d deg at %.2f)" % [int(blowing.angle), float(blowing.strength)])
	api.set_wind(-45.0, 4.0)
	var clamped: Dictionary = api.get_wind()
	_check(is_equal_approx(float(clamped.angle), 315.0), "a heading wraps rather than going negative (%d)" % int(clamped.angle))
	_check(float(clamped.strength) <= 1.0, "and strength is a fraction, however hard a mod asks (%.2f)" % float(clamped.strength))
	# Held wind stays put: a storm's gale should not wander off halfway through.
	_check(not bool(server.wind_now.drifting), "the engine stops drifting the wind while a mod holds it")


## Instances: a realm with a lifetime. The lifetime is the part worth asserting - a dimension that
## never goes away is just a dimension.
func _instances(server, api, p) -> void:
	var realms_before: int = server.realms.size()
	var run: String = api.open_instance("trial", {"data": {"why": "testing"}})
	_check(not run.is_empty(), "an instance opens and is named (%s)" % run)
	_check(server.realms.size() == realms_before + 1, "and it is a realm of its own")
	_check(server.realms[run].ephemeral, "an ephemeral one, so nothing of it is written to disk")
	_check(api.instance_data(run).get("why") == "testing", "and it carries what the mod kept with it")

	# Two runs of the same kind are two worlds, not two names for one.
	var second: String = api.open_instance("trial", {})
	_check(second != run and server.realms.has(second), "a second run is a second world (%s)" % second)

	# Going in remembers where you were; coming out puts you there.
	var was_realm: String = String(p.realm_id)
	var was_at: Vector3 = p.state.position
	_check(api.enter_instance(p, run, Vector3(0.5, 66, 0.5)), "a player can go in")
	_check(String(p.realm_id) == run and api.instance_of(p) == run, "and is in it")
	_check(api.leave_instance(p), "and can come back out")
	_check(String(p.realm_id) == was_realm and p.state.position.distance_to(was_at) < 0.01,
		"to exactly where they were, not to spawn")
	_check(api.instance_of(p) == "", "and is no longer in one")

	# Full means full.
	var solo: String = api.open_instance("trial", {})
	var a := _player(server, 92, "A_one")
	var b := _player(server, 93, "B_two")
	var c := _player(server, 94, "C_three")
	_check(api.enter_instance(a, solo, Vector3(0.5, 66, 0.5)) and api.enter_instance(b, solo, Vector3(0.5, 66, 0.5)),
		"two players fill a two-player instance")
	_check(not api.enter_instance(c, solo, Vector3(0.5, 66, 0.5)), "and a third is turned away")
	_check(String(c.realm_id) == was_realm, "who is left where they were, not half moved")

	# Closing puts everybody still inside back, and takes the realm away.
	_check(api.close_instance(solo), "closing it works")
	_check(String(a.realm_id) == was_realm and String(b.realm_id) == was_realm,
		"and everybody inside is put back")
	_check(not server.realms.has(solo), "and the realm is gone")
	for peer in [92, 93, 94]:
		server.players.erase(peer)

	# Empty is not finished: it closes on its own only after empty_seconds (5 in the Proving Ground).
	server.instances.update(0.0)
	_check(server.realms.has(run), "an empty instance does not close the moment it empties")
	server.instances.live[run].empty_since = server._time - 99.0
	server.instances.update(0.0)
	_check(not server.realms.has(run), "but it does once it has been empty long enough")
	# Can a dungeon actually be built inside one? Blocks, creatures and dropped loot all have to land
	# in the instance's realm rather than the overworld - which is what they used to do. (2026-09-21)
	var inside: String = api.open_instance("trial", {})
	var room := Vector3i(4, 66, 4)
	api.set_block(room, server.registry.id_of("proving:rock"), inside)
	_check(server.realms[inside].world.get_block_v(room) == server.registry.id_of("proving:rock"),
		"a block can be placed inside an instance")
	_check(server.realm.world.get_block_v(room) != server.registry.id_of("proving:rock"),
		"and it did not land in the overworld instead")
	var guard = api.spawn_entity("proving:grazer", Vector3(4.5, 67, 4.5), {"realm": inside})
	_check(guard != null and server.realms[inside].entities.entities.has(guard.id),
		"a creature can be spawned inside it")
	api.drop_item(server.items.id_of("proving:grain"), 3, Vector3(4.5, 67, 4.5), inside)
	_check(server.realms[inside].entities.in_radius(Vector3(4.5, 67, 4.5), 3.0).size() >= 1,
		"and loot can be dropped in it")
	api.close_instance(inside)
	api.close_instance(second)

	# Loot into a container in one call, which is what a chest appearing after a boss dies wants.
	var chest_at := Vector3i(2, 66, 2)
	api.set_block(chest_at, server.registry.id_of("proving:crate"))
	var chest = api.get_container(chest_at)
	_check(chest != null, "a container to fill")
	if chest != null:
		var n: int = api.fill_container(chest, "proving:crate_loot", {})
		_check(n > 0, "fill_container puts loot in it (%d stacks)" % n)
		# Filling again leaves what is already in there alone rather than starting over.
		var first: Dictionary = chest.get_item(0)
		api.fill_container(chest, "proving:crate_loot", {})
		_check(chest.get_item(0).item == first.item and chest.get_item(0).count == first.count,
			"and filling it twice does not overwrite what is already there")


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
	# Put them somewhere known and clear it first. Reading their live position and trusting the cell
	# to be empty failed about one fallback run in three: they are a simulated body, so by the time
	# this ran they had drifted into a cell that already held something and the refusal could not be
	# told apart from an ordinary "there is already a block there". (2026-09-21)
	var standing := Vector3i(3, 66, 3)
	p.state.position = Vector3(standing) + Vector3(0.5, 0.0, 0.5)
	api.set_block(standing, 0)
	api.set_block(standing + Vector3i.UP, 0)
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
