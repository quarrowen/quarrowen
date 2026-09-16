extends "res://engine/server/mod.gd"
## What comes out of things (docs/loot.md). Everything here is deliberately small: read it top to bottom
## and you have seen the whole capability.
##
## Try it: godot --path . -- --host=vanilla,loot_example --dev

var api


func setup(mod_api) -> void:
	api = mod_api
	_a_table()
	_conditions()
	_nested()
	_extending_someone_elses_mob()
	_rolling_it_yourself()


## The shape of a table: pools that roll on their own, entries with a weight inside their pool.
func _a_table() -> void:
	api.register_loot("chest", {
		"pools": [
			# Always a little something: this pool has no "empty", so it always gives.
			{"rolls": [1, 3], "entries": [
				{"item": "base:coal", "count": [1, 4], "weight": 3},
				{"item": "base:stick", "count": [2, 6], "weight": 2},
			]},
			# And rarely, one good thing. "empty" is the miss, which is how a chance below 1 is written:
			# 1 in 20 here, because the weights are 1 against 19.
			{"rolls": 1, "entries": [
				{"item": "base:iron_ingot", "count": [1, 2], "weight": 1},
				{"empty": true, "weight": 19},
			]},
		],
	})


## `when` on a pool or on a single entry. Every condition listed has to hold.
func _conditions() -> void:
	api.register_loot("deep_rock", {
		"pools": [
			# Only what a player mined with an iron tool, and only underground.
			{"rolls": 1, "when": {"tool": {"material": "iron"}, "depth": [0, 40]}, "entries": [
				{"item": "base:iron_ingot", "weight": 1},
			]},
			# An entry can carry its own condition: coal at night, sticks the rest of the time.
			{"rolls": 1, "entries": [
				{"item": "base:coal", "weight": 1, "when": {"time": "night"}},
				{"item": "base:stick", "weight": 1},
			]},
		],
	})


## An entry can roll another table instead of giving an item, so a "junk" table is written once.
func _nested() -> void:
	api.register_loot("junk", {"pools": [{"rolls": 1, "entries": [
		{"item": "base:stick", "count": [1, 3]},
		{"item": "base:dirt", "count": [1, 2]},
	]}]})
	api.register_loot("mixed", {"pools": [{"rolls": 2, "entries": [
		{"table": "loot_example:junk", "weight": 9},
		{"item": "base:iron_ingot", "weight": 1},
	]}]})


## Adding to a table another mod owns, without forking it. A mob's own table is "mob:<entity name>";
## a block's is "block:<block name>". This one gives every pig a small chance of an apple.
func _extending_someone_elses_mob() -> void:
	api.extend_loot("mob:vanilla:pig", {"pools": [
		{"rolls": 1, "when": {"killed_by": "player"}, "entries": [
			{"item": "base:apple", "weight": 1},
			{"empty": true, "weight": 9},
		]},
	]})


## Rolling a table from code, for anything the engine does not roll for you (a reward, a prize crate,
## a fishing line). The context is what conditions look at.
func _rolling_it_yourself() -> void:
	api.register_command("prize", "Roll the example chest table", func(player, _args):
		for stack in api.roll_loot("chest", {"player": player, "position": player.position, "cause": "player"}):
			player.give(stack[0], stack[1], stack[2])
		player.send_message("Rolled the chest table - check your pack"))
