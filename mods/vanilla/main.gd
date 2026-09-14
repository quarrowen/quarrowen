extends "res://engine/server/mod.gd"
## Classic creative sandbox on generated terrain.

const Terrain = preload("terrain.gd")
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
	api.register_sound("skeleton_hurt", "sounds/skeleton_hurt.wav")
	api.register_sound("skeleton_death", "sounds/skeleton_death.wav")
	api.register_sound("bow", "sounds/bow.wav", {"pitch_variance": 0.15})
	api.register_sound("colossus_stomp", "sounds/colossus_stomp.wav", {"range": 48.0})
	api.register_sound("colossus_roar", "sounds/colossus_roar.wav", {"range": 64.0})
	api.register_sound("colossus_hurt", "sounds/colossus_hurt.wav", {"range": 32.0})
	api.register_item("bone", {"display_name": "Bone", "icon": "textures/bone.png"})
	api.register_material("bone", {"display_name": "Bone", "item": "vanilla:bone", "color": "#e8e0c8", "tier": 1, "speed": 3.0,
		"durability": 90, "damage": 1.0, "handle": 1.4,
		"trait": {"name": "Jagged", "description": "+5% critical chance", "modifiers": [{"stat": "crit_chance", "amount": 0.05}]}})
	api.register_item("leather", {"icon": "textures/leather.png"})
	# Stitching leather armor by hand: follow the prompted directions in time.
	api.register_minigame("stitching", {"title": "Stitch by hand", "type": "sequence", "verb": "Stitch", "rounds": 6, "window": 1.4})
	for piece in [["helmet", "head", 1.0, 5], ["chestplate", "chest", 3.0, 8], ["leggings", "legs", 2.0, 7], ["boots", "feet", 1.0, 4]]:
		api.register_item("leather_%s" % piece[0], {"display_name": "Leather %s" % String(piece[0]).capitalize(),
			"icon": "textures/leather_%s.png" % piece[0], "equip_slot": piece[1], "durability": 80, "armor": {"armor": piece[2]}, "armor_texture": "textures/leather_armor.png"})
		api.register_recipe({"vanilla:leather": piece[3]}, "vanilla:leather_%s" % piece[0], 1, {"station": "crafting_table", "skill": "vanilla:stitching"})
	ids.porkchop = api.register_item("porkchop", {"display_name": "Raw Porkchop", "icon": "textures/porkchop.png",
		"food": {"hunger": 3, "saturation": 1.8, "color": "#f0a0a0"}})
	ids.cooked_porkchop = api.register_item("cooked_porkchop", {"display_name": "Cooked Porkchop", "icon": "textures/cooked_porkchop.png",
		"food": {"hunger": 8, "saturation": 12.8, "color": "#b87040"}})
	# Zombies drop rotten flesh: filling in a pinch, but it usually gives food poisoning (hunger drains faster).
	api.register_item("rotten_flesh", {"display_name": "Rotten Flesh", "icon": "textures/rotten_flesh.png",
		"food": {"hunger": 4, "saturation": 0.8, "color": "#7a8a40",
			"effects": [{"stat": "hunger_drain", "amount": 0.5, "seconds": 30, "chance": 0.8, "message": "Food poisoning!"}]}})
	api.register_process("smelting", "vanilla:porkchop", "vanilla:cooked_porkchop", 1, 8.0)
	api.register_entity("arrow", {"kind": "projectile", "sprite": "textures/arrow.png", "width": 0.25, "height": 0.25,
		"damage": 4, "gravity": 14.0, "lifetime": 4.0})

	# Zombies hunt in packs: they hear fighting and digging, call each other in, spread out around
	# their prey and circle while their claws recharge.
	ids.zombie = api.register_entity("zombie", {
		"kind": "mob", "model": "models/zombie.glb", "width": 0.6, "height": 1.85,
		"health": 20, "speed": 3.0, "drops": [["vanilla:rotten_flesh", 1, 0.8], ["base:coal", 1, 0.5], ["base:workbench_plans", 1, 0.03]],
		"sounds": {"hurt": "zombie_hurt", "death": "zombie_death", "ambient": "zombie_ambient"},
		"ai": {
			"preset": "hostile", "group": "undead", "aggression": 0.65, "intelligence": 0.55, "courage": 1.0,
			"sight_range": 20, "hearing_range": 18, "memory": 15, "alert_radius": 18,
			"attacks": [
				{"name": "claw", "type": "melee", "damage": 3, "range": 0.9, "windup": 0.35, "cooldown": 0.9},
				{"name": "lunge", "type": "leap", "damage": 4, "min_range": 2.5, "range": 5.0, "radius": 1.5, "windup": 0.5, "cooldown": 6.0, "weight": 0.6},
			],
		},
	})
	# Skeletons are careful archers: they keep their distance, strafe, lead their shots, dodge arrows
	# and back off when hurt.
	ids.skeleton = api.register_entity("skeleton", {
		"kind": "mob", "model": "models/skeleton.glb", "width": 0.6, "height": 1.8,
		"health": 16, "speed": 3.2, "drops": [["vanilla:bone", 2], ["vanilla:bone", 1, 0.5], ["base:forge_plans", 1, 0.05]],
		"sounds": {"hurt": "skeleton_hurt", "death": "skeleton_death"},
		"ai": {
			"preset": "archer", "group": "undead", "aggression": 0.6, "intelligence": 0.8, "agility": 0.55, "courage": 0.35,
			"sight_range": 24, "preferred_range": [7, 14],
			"attacks": [{"name": "shoot", "type": "ranged", "projectile": "vanilla:arrow", "damage": 4, "range": 18,
				"min_range": 1.5, "windup": 0.7, "cooldown": 1.8, "projectile_speed": 24, "spread": 3, "sound": "vanilla:bow"}],
		},
	})
	# Pigs graze in herds; hurting one makes the whole herd scatter.
	ids.pig = api.register_entity("pig", {
		"kind": "mob", "model": "models/pig.glb", "width": 0.9, "height": 0.9,
		"health": 10, "speed": 2.2, "persistent": true, "drops": [["vanilla:porkchop", 1], ["vanilla:porkchop", 1, 0.5], ["vanilla:leather", 1, 0.6]],
		"sounds": {"hurt": "pig_hurt", "death": "pig_death", "ambient": "pig_ambient"},
		"ai": {"preset": "passive", "group": "pigs", "alert_radius": 12, "wander_radius": 8},
	})
	# The Ancient Colossus: a boss 4x taller and 2x wider than a zombie, with telegraphed stomps and
	# punches, and a second phase that charges and raises undead.
	ids.colossus = api.register_entity("colossus", {
		"kind": "mob", "model": "models/colossus.glb", "width": 1.2, "height": 7.2,
		"health": 400, "speed": 2.4, "knockback_resistance": 0.95, "drops": [["base:iron_ore", 16], ["base:coal", 32]],
		"sounds": {"hurt": "colossus_hurt", "death": "colossus_roar"},
		"ai": {
			"preset": "boss", "group": "undead", "boss": {"name": "Ancient Colossus", "bar_range": 64},
			"sight_range": 40, "leash": 48, "step_up": 2, "max_drop": 4, "attack_interval": 1.2,
			"attacks": [
				{"name": "stomp", "type": "slam", "damage": 9, "radius": 5, "windup": 1.1, "cooldown": 5, "knockback": 12, "sound": "vanilla:colossus_stomp",
					"effect": "engine:dust"},
				{"name": "punch", "type": "melee", "damage": 11, "range": 2.2, "arc": 120, "windup": 0.7, "cooldown": 2.2, "knockback": 10},
			],
			"phases": [{
				"health_below": 0.5, "message": "The Ancient Colossus roars in fury!", "speed_multiplier": 1.35, "aggression": 1.0,
				"add_attacks": [
					{"name": "charge", "type": "charge", "damage": 14, "min_range": 6, "range": 24, "speed": 13, "duration": 1.5, "windup": 0.9, "cooldown": 9, "knockback": 14, "sound": "vanilla:colossus_roar",
						"windup_effect": "engine:smoke"},
					{"name": "raise_dead", "type": "summon", "entity": "vanilla:zombie", "count": 3, "max_summons": 4, "range": 40, "windup": 1.2, "cooldown": 18, "weight": 0.8},
				],
			}],
		},
	})
	# Monsters spawn in darkness (light 7 or less): the night surface, caves and unlit rooms. Torches keep them away.
	api.add_spawn_rule({"entity": "zombie", "category": "monster", "light": [0, 7], "on": ["base:grass", "base:dirt", "base:sand", "base:snow", "base:stone"],
		"max_nearby": 5, "max_total": 40, "chance": 0.25, "group": [1, 2]})
	api.add_spawn_rule({"entity": "skeleton", "category": "monster", "light": [0, 7], "on": ["base:grass", "base:stone", "base:snow"],
		"max_nearby": 2, "max_total": 16, "chance": 0.1})
	api.register_command("colossus", "Summon the Ancient Colossus nearby (admin)", func(player, _args):
		var forward := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
		var boss = api.spawn_entity("colossus", player.position + forward * 12.0 + Vector3(0, 1, 0), {"yaw": player.yaw + PI})
		if boss != null:
			boss.set_home(boss.position)
			api.play_sound("colossus_roar", boss.position)
			api.broadcast("The Ancient Colossus awakens!"), "admin")
	# Animals appear on sunny grass, a few at a time, and stay.
	api.add_spawn_rule({"entity": "pig", "category": "animal", "light": [9, 15], "place": "surface", "on": ["base:grass"],
		"max_nearby": 4, "max_total": 30, "chance": 0.08, "group": [1, 3]})
	api.on("block_break", func(ev):
		if ev.block == api.block("base:leaves") and randf() < APPLE_CHANCE:
			ev.drops.append([api.item("base:apple"), 1]))
	api.every(4.0, _mob_tick)


## Occasional mob noises, and zombies burn in daylight.
func _mob_tick() -> void:
	var daylight: float = api.get_daylight()
	for player in api.get_players():
		for mob in api.get_entities(player.position, 32.0):
			if randf() < 0.25 and mob.def.sounds.has("ambient"):
				api.play_sound(mob.def.sounds.ambient, mob.position + Vector3(0, 1, 0))
			if mob.type in [ids.zombie, ids.skeleton] and daylight > 0.75 and api.sees_sky(Vector3i(mob.position.floor()) + Vector3i.UP):
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
		player.give(api.item("base:wooden_pickaxe"))
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
