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

var api
var dwellings := Dwellings.new()
var settlers := Settlers.new()
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
	settlers.setup(api, dwellings)
	api.on("player_join", _on_join)
	api.on("ui_action", func(ev):
		if ev.ui_id == "hearthhold:talk" and str(ev.action).begins_with("recruit:"):
			settlers.recruit(ev.player, int(str(ev.action).get_slice(":", 1))))
	# Chapter two begins when the hearth is lit: the smoke is what somebody sees from the ridge.
	api.register_command("bramble", "Ask where Bramble was last seen", func(player, _args):
		player.send_message(settlers.whereabouts(player)))


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
	player.show_title("The hearth is lit", "Somebody kept this place once", 4.0)
	api.broadcast("%s lit the hearth at Hearthhold." % player.name)


func _on_join(ev: Dictionary) -> void:
	var player = ev.player
	player.set_creative(false)
	if ev.first_time:
		player.give(api.item("base:log"), 3)  # enough for the hearth, so chapter one cannot stall
		player.show_title("Hearthhold", "The valley is empty. It was not always.", 5.0)
