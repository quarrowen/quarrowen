extends "res://engine/server/mod.gd"
## Talking to players: a command they type, a panel on their screen, and buttons that come back to you.
##
## The panel is a description, not code: the server sends what it should look like and the client draws
## it, so a mod never ships UI code and a JavaScript mod can do exactly the same (see api docs).
##
## Try it: godot --path . -- --host=proving,ui_example --dev   then type /hello

var api
const PANEL := "ui_example:panel"
## How many times each player has pressed the button, kept in mod storage so it survives a restart.
var _counts := {}


func setup(mod_api) -> void:
	api = mod_api
	_counts = api.storage.get("counts", {})
	# A permission of your own, so a server can decide who may use this rather than it being admin-only.
	api.register_permission("ui_example.panel", "Open the example panel", ["member", "admin"])
	api.register_command("hello", "Show the example panel", _cmd_hello, "ui_example.panel")
	api.on("ui_action", _on_action)
	api.on("player_leave", func(ev): ev.player.hide_ui(PANEL))


func _cmd_hello(player, args: PackedStringArray) -> void:
	# Commands get the words after the command as args, already split.
	if args.size() > 0 and args[0] == "off":
		player.hide_ui(PANEL)
		player.send_message("Panel closed")
		return
	_show(player)


## A panel is a dictionary: where it sits, and what is in it. `action` on a button comes back as a
## ui_action event; "close" is handled by the client itself.
func _show(player) -> void:
	var count := int(_counts.get(player.player_id, 0))
	player.show_ui(PANEL, {
		"anchor": "center",
		"modal": true,
		"children": [
			{"type": "label", "text": "Hello, %s" % player.name, "size": 24, "color": "#8ecae6"},
			{"type": "label", "text": "You have pressed the button %d time%s." % [count, "" if count == 1 else "s"]},
			{"type": "spacer", "size": 6},
			{"type": "button", "text": "Press me", "action": "press"},
			{"type": "button", "text": "Give me a torch", "action": "torch"},
			{"type": "button", "text": "Close", "action": "close"},
		],
	})


## Every button press on any panel arrives here, so check which panel it came from.
func _on_action(ev: Dictionary) -> void:
	if ev.ui_id != PANEL:
		return
	match ev.action:
		"press":
			_counts[ev.player.player_id] = int(_counts.get(ev.player.player_id, 0)) + 1
			api.storage.counts = _counts  # mod storage is saved with the world
			_show(ev.player)  # showing it again with the same id replaces it
		"torch":
			ev.player.give(api.item("base:torch"), 1)
			ev.player.send_message("There you go")
