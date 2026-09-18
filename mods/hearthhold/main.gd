extends "res://engine/server/mod.gd"
## Hearthhold: a valley whose light went out (see docs/hearthhold.md).
##
## Built on vanilla's world - the same biomes, animals and monsters - because the story is about coming
## back to a place people already lived in, not about a strange new one. What this game adds is a reason
## to be here: an outpost at the valley mouth, people scattered in the hills, and a light to relight.
##
## Phase 1 is chapters one and two: arrive, light the hearth, live through a night, walk out to the cold
## camp and bring Bramble home to a house you built her.

const Dwellings = preload("dwellings.gd")
const Settlers = preload("settlers.gd")
const Charter = preload("charter.gd")
const Guide = preload("guide.gd")
const Tutorial = preload("tutorial.gd")

var api
var dwellings := Dwellings.new()
var settlers := Settlers.new()
var charter := Charter.new()
var guide := Guide.new()
var tutorial := Tutorial.new()
var ids := {}


func setup(mod_api) -> void:
	api = mod_api
	api.set_server_info({"name": "Hearthhold", "motd": "The light went out. Find the people who left, and bring them home."})
	# A guided game, so everyone starts in survival: the story only works if the nights matter.
	api.set_gameplay({"keep_inventory": true, "tutorials": true})
	# base registers these sounds; every mod refers to them by name.
	var stone := {"break": "base:stone", "place": "base:stone", "step": "base:stone_step"}
	dwellings.setup(api, {"stone": stone, "wood": {"break": "base:wood", "place": "base:wood", "step": "base:wood_step"}})
	_register_hearth(stone)
	guide.setup(api)
	tutorial.setup(api)
	charter.setup(api, dwellings)
	settlers.setup(api, dwellings)
	_register_places()
	api.on("player_join", _on_join)
	# Everyone spawns, and respawns, at the outpost. Without this the world spawn was somewhere else
	# entirely and dying lost you the valley.
	api.set_spawn_handler(func(_player):
		# The valley is built here rather than waiting for player_join, because the spawn position is
		# chosen first: the very first player used to appear at the world origin and be teleported a
		# moment later, which meant a flash of the wrong place and a pocket of chunks generated for
		# nothing. Building it on demand means the first player opens their eyes in the yard.
		_build_the_valley()
		var at: Array = api.storage.outpost
		return Vector3(at[0], at[1] + 1, at[2] + 3))
	api.on("ui_action", func(ev):
		if ev.ui_id == "hearthhold:talk" and str(ev.action).begins_with("recruit:"):
			settlers.recruit(ev.player, int(str(ev.action).get_slice(":", 1))))
	# Chapter two begins when the hearth is lit: the smoke is what somebody sees from the ridge.
	api.register_command("bramble", "Ask where Bramble was last seen", func(player, _args):
		player.send_message(settlers.whereabouts(player)))
	api.register_command("charter", "What the place needs next", func(player, _args): charter.show(player))
	api.register_command("valley", "Which way the outpost is", func(player, _args):
		if not api.storage.has("outpost"):
			player.send_message("The valley has not been found yet.")
			return
		var at: Array = api.storage.outpost
		var to := Vector3(at[0], at[1], at[2])
		var away := int(to.distance_to(player.position))
		player.send_message("Hearthhold is %d blocks away, towards %s. It is marked on your map (M)."
			% [away, Settlers._compass(to - player.position)]))
	# Morning after the first night, which is chapter one finished.
	api.every(5.0, func():
		if api.storage.get("hearth_lit", false) and not api.storage.get("seen_morning", false) \
				and api.get_time_of_day() > 0.25 and api.get_time_of_day() < 0.35:
			api.storage.seen_morning = true
			api.broadcast("Morning. The hearth held."))


## The hearth at the outpost: cold when you arrive, and the first thing you put right. Lighting it is
## chapter one, and it is deliberately the smallest possible task - a child should finish something in
## their first ten minutes.
func _register_hearth(stone: Dictionary) -> void:
	ids.cold_hearth = api.register_block("cold_hearth", {"display_name": "Cold Hearth",
		"textures": {"top": "textures/hearth_cold.png", "side": "textures/hearth_side.png",
			"bottom": "textures/hearth_side.png"},
		"sounds": stone, "hardness": 3.0, "tool": "pickaxe", "interactive": true})
	ids.lit_hearth = api.register_block("lit_hearth", {"display_name": "Hearth",
		"textures": {"top": "textures/hearth_lit.png", "side": "textures/hearth_side.png",
			"bottom": "textures/hearth_side.png"},
		"sounds": stone, "hardness": 3.0, "tool": "pickaxe", "light": 14, "drops": "hearthhold:cold_hearth"})
	api.on("block_interact", func(ev):
		if ev.block != ids.cold_hearth:
			return
		ev.cancelled = true
		_light_hearth(ev.player, ev.position))


## Lighting it costs what the last warden asked for on the board: firewood.
func _light_hearth(player, pos: Vector3i) -> void:
	var logs: int = api.item("base:log")
	if player.count_of(logs) < 3:
		player.send_message("The hearth is cold. It wants firewood - three logs would do it.")
		return
	player.take(logs, 3)
	api.set_block(pos, ids.lit_hearth)
	api.play_sound("engine:craft", Vector3(pos) + Vector3.ONE * 0.5)
	api.play_effect("engine:sparkle", Vector3(pos) + Vector3(0.5, 1.0, 0.5), {"scale": 1.2})
	api.storage.hearth_lit = true
	player.show_title("The hearth is lit", "Somebody kept this place once", 4.0)
	api.broadcast("%s lit the hearth at Hearthhold." % player.name)


## Where the story happens: the outpost you arrive at, and the camp somebody walked away from.
func _register_places() -> void:
	for place in ["outpost", "cold_camp"]:
		api.register_structure_template(place, "structures/%s.json" % place)
	# Both are placed by hand rather than left to world generation: a story needs to know where its own
	# outpost is, and how far the walk to the camp is, because that walk is the whole of chapter two.
	# What the last warden left, and what Bramble has: little, and worth having.
	api.register_loot("warden", {"pools": [
		{"rolls": 1, "guaranteed": true, "entries": [{"item": "base:bread", "count": [2, 3]}]},
		{"rolls": 1, "entries": [{"item": "base:torch", "count": [4, 8], "weight": 3},
			{"item": "base:wooden_pickaxe", "weight": 1}, {"empty": true, "weight": 1}]},
	]})
	api.register_loot("camp", {"pools": [
		{"rolls": 1, "guaranteed": true, "entries": [{"item": "base:bowl", "count": [2, 2]}]},
		{"rolls": 1, "entries": [{"item": "vanilla:red_mushroom", "count": [1, 3], "weight": 2},
			{"item": "base:apple", "weight": 1}]},
	]})


## How far Bramble is: far enough that getting there and back is a journey, near enough that a child does
## not give up. Worth tuning after the first playtest - it is the number the design rests on.
const CAMP_DISTANCE := 150.0


## Builds the valley's two places the first time anyone arrives, and remembers where they are.
func _build_the_valley() -> void:
	if api.storage.has("outpost"):
		return
	var spot := _level_ground_near(Vector3i(0, 0, 0), 48)
	api.place_structure("outpost", spot - Vector3i(6, 0, 6))  # the template's middle, not its corner
	api.storage.outpost = [spot.x, spot.y, spot.z]
	# The camp is in a direction nobody chose, so no two worlds send you the same way.
	var angle := randf() * TAU
	var away := Vector3i(int(cos(angle) * CAMP_DISTANCE), 0, int(sin(angle) * CAMP_DISTANCE))
	var camp := _level_ground_near(spot + away, 24)
	api.place_structure("cold_camp", camp - Vector3i(3, 0, 3))
	api.storage.camp = [camp.x, camp.y, camp.z]
	settlers.place_bramble(Vector3(camp) + Vector3(0.5, 1.0, 0.5))
	api.info("Hearthhold: outpost at %s, Bramble's camp at %s" % [str(spot), str(camp)])


## The flattest spot within `radius` of a point, so a building does not end up half buried or on stilts.
func _level_ground_near(around: Vector3i, radius: int) -> Vector3i:
	var best := Vector3i(around.x, api.surface_y(around.x, around.z) + 1, around.z)
	var best_spread := 999
	for step in range(0, radius, 6):
		for angle in 8:
			var x := around.x + int(cos(angle * TAU / 8.0) * step)
			var z := around.z + int(sin(angle * TAU / 8.0) * step)
			var low := 999
			var high := -999
			for probe in [Vector2i(-5, -5), Vector2i(5, -5), Vector2i(-5, 5), Vector2i(5, 5), Vector2i(0, 0)]:
				var y: int = api.surface_y(x + probe.x, z + probe.y)
				low = mini(low, y)
				high = maxi(high, y)
			if high - low < best_spread and low > 40:
				best_spread = high - low
				best = Vector3i(x, high + 1, z)
			if best_spread == 0:
				return best
	return best


func _on_join(ev: Dictionary) -> void:
	var player = ev.player
	player.set_creative(false)
	_build_the_valley()
	if api.storage.has("outpost"):
		var at: Array = api.storage.outpost
		if ev.first_time:
			player.teleport(Vector3(at[0], at[1] + 1, at[2] + 3))
		# The valley is the whole game, so it is marked on the map and the compass for good. A player who
		# died and respawned somewhere else could not find it again and had no way to look it up: the
		# only record of where it was had gone to the server's log. (playtest, 2026-09-18)
		api.set_map_marker(player, "outpost", {"label": "Hearthhold", "position": Vector3(at[0], at[1], at[2]),
			"color": "#ffb454"})
	if ev.first_time:
		# Hearthhold is a survival story - the night is the antagonist, and creative removes it. Vanilla
		# used to decide this, which put a first-time player in the valley in creative mode. A game that
		# builds on another one has to say what it wants rather than inherit it. (playtest, 2026-09-18)
		player.set_creative(false)
		player.clear_inventory()
		player.give(api.item("base:log"), 3)  # enough for the hearth, so chapter one cannot stall
		# Coal for the first torch. The valley is dark, the first night comes quickly, and a child who
		# cannot make light on night one is a child who stops playing. The rest they must find.
		player.give(api.item("base:coal"), 4)
		player.show_title("Hearthhold", "The valley is empty. It was not always.", 5.0)
