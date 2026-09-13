extends "res://engine/server/mod.gd"
## Classic creative sandbox on generated terrain.

const Terrain = preload("terrain.gd")
const PORKCHOP_HEAL := 6.0
const APPLE_CHANCE := 0.12

const HOTBAR := ["base:grass", "base:dirt", "base:stone", "base:cobblestone", "base:planks",
	"base:log", "base:glass", "base:brick", "base:sand"]

var api
var terrain
var ids := {}


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
	# Everyone may switch modes in the sandbox (the engine's /gamemode is admin-only).
	api.register_command("gamemode", "survival | creative - switch your game mode", _cmd_gamemode)
	_setup_mobs()
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
			{"type": "label", "text": "Creative mode  -  /spawn  /fly  /gamemode survival"},
		],
	})


func _setup_mobs() -> void:
	api.register_sound("zombie_ambient", "sounds/zombie_ambient.wav", {"range": 16.0})
	api.register_sound("zombie_hurt", "sounds/zombie_hurt.wav")
	api.register_sound("zombie_death", "sounds/zombie_death.wav")
	api.register_sound("pig_ambient", "sounds/pig_ambient.wav", {"range": 16.0})
	api.register_sound("pig_hurt", "sounds/pig_hurt.wav")
	api.register_sound("pig_death", "sounds/pig_death.wav")
	ids.porkchop = api.register_item("porkchop", {"display_name": "Porkchop", "icon": "textures/porkchop.png", "usable": true})
	ids.zombie = api.register_entity("zombie", {
		"kind": "mob", "model": "models/zombie.glb", "width": 0.6, "height": 1.85,
		"health": 20, "speed": 3.0, "ai": "hostile", "attack_damage": 3, "attack_range": 1.3, "attack_cooldown": 1.0,
		"sight_range": 20, "drops": [["base:coal", 1, 0.5]],
		"sounds": {"hurt": "zombie_hurt", "death": "zombie_death", "ambient": "zombie_ambient"},
	})
	ids.pig = api.register_entity("pig", {
		"kind": "mob", "model": "models/pig.glb", "width": 0.9, "height": 0.9,
		"health": 10, "speed": 2.2, "ai": "passive", "persistent": true, "drops": [["vanilla:porkchop", 1], ["vanilla:porkchop", 1, 0.5]],
		"sounds": {"hurt": "pig_hurt", "death": "pig_death", "ambient": "pig_ambient"},
	})
	api.add_spawn_rule({"entity": "zombie", "time": "night", "on": ["base:grass", "base:dirt", "base:sand", "base:snow", "base:stone"],
		"max_nearby": 5, "max_total": 40, "chance": 0.25})
	api.add_spawn_rule({"entity": "pig", "time": "day", "on": ["base:grass"], "max_nearby": 4, "max_total": 30, "chance": 0.08})
	api.on("item_use", func(ev):
		if ev.item == ids.porkchop:
			_eat(ev.player, ids.porkchop, PORKCHOP_HEAL))
	api.on("block_break", func(ev):
		if ev.block == api.block("base:leaves") and randf() < APPLE_CHANCE:
			ev.drops = [[api.item("base:apple"), 1]])
	api.every(4.0, _mob_tick)


func _eat(player, item: int, amount: float) -> void:
	if player.health >= player.max_health:
		player.show_title("", "You are not hungry", 1.0)
	elif player.is_creative() or player.take(item, 1):
		player.heal(amount)
		api.play_sound("base:eat", player.get_eye_position())


## Occasional mob noises, and zombies burn in daylight.
func _mob_tick() -> void:
	var daylight: float = api.get_daylight()
	for player in api.get_players():
		for mob in api.get_entities(player.position, 32.0):
			if randf() < 0.25 and mob.def.sounds.has("ambient"):
				api.play_sound(mob.def.sounds.ambient, mob.position + Vector3(0, 1, 0))
			if mob.type == ids.zombie and daylight > 0.75 and api.sees_sky(Vector3i(mob.position.floor()) + Vector3i.UP):
				mob.damage(4.0, null, "sun")


func _cmd_gamemode(player, args: PackedStringArray) -> void:
	if args.is_empty() or not args[0] in ["survival", "creative"]:
		player.send_message("Usage: /gamemode survival | creative")
		return
	if player.is_creative() == (args[0] == "creative"):
		player.send_message("You are already in %s mode" % args[0])
		return
	player.set_creative(args[0] == "creative")
	if args[0] == "survival":
		# The creative hotbar holds placeholder stacks; start survival with a small kit instead.
		player.clear_inventory()
		player.give(api.item("base:stone_sword"))
		player.give(api.item("base:planks"), 16)
		player.give(api.item("base:apple"), 3)
	else:
		player.set_hotbar(HOTBAR.map(func(n): return api.block(n)))
	player.send_message("Game mode: %s%s" % [args[0], " - watch out for zombies at night!" if args[0] == "survival" else ""])


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
