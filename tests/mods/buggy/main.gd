extends "res://engine/server/mod.gd"
## Fails on purpose: /crash reads a missing key, /complain logs at every level.

var api


func setup(mod_api) -> void:
	api = mod_api
	api.register_command("crash", "Read a missing key", func(_player, _args): _crash())
	api.register_command("complain", "Log at every level", func(_player, _args):
		api.debug("quiet detail")
		api.info("hello from buggy")
		api.warn("running low")
		api.error("something broke"))


func _crash() -> void:
	var settings := {}
	print(settings.volume)  # line 19: the error the test expects
