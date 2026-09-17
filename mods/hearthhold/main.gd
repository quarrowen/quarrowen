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

var api
var dwellings := Dwellings.new()
var settlers := Settlers.new()
var charter := Charter.new()
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
	charter.setup(api, dwellings)
	settlers.setup(api, dwellings)
	_register_places()
	api.on("player_join", _on_join)
	api.on("ui_action", func(ev):
		if ev.ui_id == "hearthhold:talk" and str(ev.action).begins_with("recruit:"):
			settlers.recruit(ev.player, int(str(ev.action).get_slice(":", 1))))
	# Chapter two begins when the hearth is lit: the smoke is what somebody sees from the ridge.
	api.register_command("bramble", "Ask where Bramble was last seen", func(player, _args):
		player.send_message(settlers.whereabouts(player)))
	api.register_command("charter", "What the place needs next", func(player, _args): charter.show(player))
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
	# The outpost sits near where players start; the camp is a walk away, which is the point of it.
	api.register_structure("outpost", {"templates": [{"template": "outpost"}], "spacing": 1024,
		"place": "surface", "chance": 1.0, "biomes": []})
	api.register_structure("cold_camp", {"templates": [{"template": "cold_camp"}], "spacing": 192,
		"place": "surface", "chance": 0.6, "biomes": []})
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


func _on_join(ev: Dictionary) -> void:
	var player = ev.player
	player.set_creative(false)
	if ev.first_time:
		player.give(api.item("base:log"), 3)  # enough for the hearth, so chapter one cannot stall
		player.show_title("Hearthhold", "The valley is empty. It was not always.", 5.0)
