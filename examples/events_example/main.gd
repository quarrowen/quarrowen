extends "res://engine/server/mod.gd"
## Events: the engine tells you what happened, and lets you change or refuse it. The full list is in the
## header of engine/server/mod_api.gd (or docs/api/index.html).
##
## Three things a handler can do, one of each below:
##   1. react - the event already happened, do something about it
##   2. change - rewrite a value in the event before the engine uses it
##   3. cancel - set ev.cancelled and the engine does not do it at all
##
## Try it: godot --path . -- --host=proving,events_example --dev

var api
## Bedrock is at 0; nobody should be allowed to mine the bottom of the world.
const PROTECTED_Y := 1


func setup(mod_api) -> void:
	api = mod_api
	_react()
	_change()
	_cancel()


## 1. React: the event is a fact, and this runs after it.
func _react() -> void:
	api.on("player_join", func(ev):
		if ev.first_time:
			ev.player.show_title("Welcome", "Your first time on this server", 4.0)
			ev.player.give(api.item("base:torch"), 8)
		else:
			ev.player.send_message("Welcome back, %s" % ev.player.name))
	# A mob died: who killed it, and with what, is in the event.
	api.on("entity_death", func(ev):
		if ev.attacker != null and ev.attacker.get("peer_id") != null:
			api.info("%s killed a %s" % [ev.attacker.name, ev.entity.def.display_name]))


## 2. Change: the value in the event is what the engine goes on to use, so rewriting it changes the
## outcome. Here: falling hurts half as much, and every mined block gives one extra coal.
func _change() -> void:
	api.on("player_damage", func(ev):
		if ev.cause == "fall":
			ev.amount = ev.amount * 0.5)
	api.on("block_break", func(ev):
		ev.drops.append([api.item("base:coal"), 1]))


## 3. Cancel: set `cancelled` and it does not happen. Only events documented as cancellable have it.
##
## A handler that cancels should say why, or a player just sees the world refuse them.
func _cancel() -> void:
	api.on("block_break", func(ev):
		if ev.position.y <= PROTECTED_Y and not ev.player.has_permission("admin"):
			ev.cancelled = true
			ev.player.send_message("The bottom of the world is protected."))
