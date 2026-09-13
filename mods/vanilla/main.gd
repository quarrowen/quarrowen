extends "res://engine/server/mod.gd"
## Classic creative sandbox on generated terrain.

const Terrain = preload("terrain.gd")

const HOTBAR := ["base:grass", "base:dirt", "base:stone", "base:cobblestone", "base:planks",
	"base:log", "base:glass", "base:brick", "base:sand"]

var api
var terrain


func setup(mod_api) -> void:
	api = mod_api
	terrain = Terrain.new(api)
	api.set_server_info({"name": "Vanilla Sandbox", "motd": "Welcome! Type /help for commands."})
	api.set_world_generator(terrain)
	api.set_spawn_handler(_spawn_position)
	api.on("player_join", _on_join)
	api.register_command("spawn", "Teleport to world spawn", func(player, _args): player.teleport(_spawn_position(player)))
	api.register_command("fly", "Toggle low gravity for everyone", _toggle_low_gravity, "admin")
	api.register_command("time", "day | night | noon | midnight | <0-1> | speed <seconds per day>", _cmd_time, "admin")
	if not api.storage.get("time_initialized", false):
		api.storage.time_initialized = true
		api.set_world_time(0.3, 1200.0)  # start the morning of a 20-minute day


func _spawn_position(_player) -> Vector3:
	var y: int = api.surface_y(8, 8)
	return Vector3(8.5, y + 1, 8.5)


func _on_join(ev: Dictionary) -> void:
	var player = ev.player
	if ev.first_time:
		player.set_creative(true)
		player.set_hotbar(HOTBAR.map(func(n): return api.block(n)))
	player.show_title("Vanilla Sandbox", "Build anything - blocks are unlimited", 4.0)
	player.show_ui("vanilla:info", {
		"anchor": "top_right",
		"children": [
			{"type": "label", "text": "Vanilla Sandbox", "size": 18, "color": "#ffd166"},
			{"type": "label", "text": "Creative mode  -  /spawn  /fly"},
		],
	})


func _cmd_time(player, args: PackedStringArray) -> void:
	if args.is_empty():
		player.send_message("Time of day: %.2f (daylight %d%%)" % [api.get_time_of_day(), roundi(api.get_daylight() * 100)])
		return
	var presets := {"day": 0.3, "noon": 0.5, "sunset": 0.74, "night": 0.9, "midnight": 0.0}
	if args[0] == "speed" and args.size() > 1:
		api.set_world_time(api.get_time_of_day(), maxf(float(args[1]), 0.0))
	elif presets.has(args[0]):
		api.set_world_time(presets[args[0]])
	elif args[0].is_valid_float():
		api.set_world_time(float(args[0]))
	else:
		player.send_message("Usage: /time day | night | noon | midnight | <0-1> | speed <seconds>")
		return
	api.broadcast("%s set the time to %s" % [player.name, " ".join(args)])


func _toggle_low_gravity(player, _args) -> void:
	# Physics rules are server-wide and pushed to every client, so this affects everyone.
	var low: bool = not api.storage.get("low_gravity", false)
	api.storage.low_gravity = low
	api.set_physics({"gravity": 8.0 if low else 32.0, "jump_velocity": 6.0 if low else 9.0})
	api.broadcast("%s turned low gravity %s" % [player.name, "on" if low else "off"])
