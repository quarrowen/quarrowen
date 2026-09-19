extends "res://engine/server/mod.gd"
## Classic creative sandbox on generated terrain.

const Biomes = preload("biomes.gd")
const Animals = preload("animals.gd")
const Monsters = preload("monsters.gd")
const VanillaStructures = preload("structures.gd")
const Guide = preload("guide.gd")
const Tutorial = preload("tutorial.gd")
const Cooking = preload("cooking.gd")
const Fishing = preload("fishing.gd")
const APPLE_CHANCE := 0.12
## How many monsters may be around each player, for the "monsters" setting.
const MONSTER_CAPS := {"none": 0, "few": 8, "normal": 24, "many": 48}

const HOTBAR := ["base:grass", "base:dirt", "base:stone", "base:cobblestone", "base:planks",
	"base:log", "base:glass", "base:brick", "base:sand"]

var api
var biomes := Biomes.new()
var animals := Animals.new()
var monsters := Monsters.new()
var structures := VanillaStructures.new()
var guide := Guide.new()
var tutorial := Tutorial.new()
var cooking := Cooking.new()
var fishing := Fishing.new()
## Whether this was the game being played when setup() ran. Kept because the answer used to be "no"
## for everybody at that moment, which silently switched the music off.
var music_setup_saw_game := false
var ids := {}


func setup(mod_api) -> void:
	api = mod_api
	biomes.setup(api)
	# What a host can change without editing this mod: the admin screen, /modsettings and the server's
	# mod_settings.json all end up here.
	api.register_settings({
		"monsters": {"label": "How many monsters", "type": "choice", "default": "normal",
			"choices": [["none", "None"], ["few", "A few"], ["normal", "Normal"], ["many", "Lots"]],
			"help": "Monsters still only appear in the dark. 'None' leaves the animals alone."},
		"day_minutes": {"label": "Minutes in a day", "type": "int", "default": 20, "min": 2, "max": 120,
			"help": "How long a full day and night takes for a new world."},
		"zombies_burn": {"label": "Zombies burn in daylight", "type": "bool", "default": true},
		"loot": {"label": "How much things drop", "type": "choice", "default": "normal",
			"choices": [["less", "Less"], ["normal", "Normal"], ["lots", "Lots"]],
			"help": "Multiplies what mobs, blocks and chests give. /loot can also turn one thing up for an event."},
		"apples_from_leaves": {"label": "Apples fall from leaves", "type": "bool", "default": true},
	})
	api.on("settings_changed", func(ev): if ev.mod == "vanilla": _apply_settings())
	# Stitching leather is the first crafting minigame anyone meets, well before iron, so the page that
	# explains quality has to be readable by then - otherwise a hover tooltip is the only explanation.
	api.on("item_pickup", func(ev):
		if ev.item == api.item("vanilla:leather"):
			api.unlock_guide_page(ev.player, "base:by_hand"))
	api.set_server_info({"name": "Vanilla Sandbox", "motd": "Welcome! Press G for the guide, or T then /help for commands."})
	api.set_spawn_handler(_spawn_position)
	api.on("player_join", _on_join)
	api.register_command("spawn", "Teleport to world spawn", func(player, _args): player.teleport(_spawn_position(player)))
	api.register_command("lowgravity", "Toggle low gravity for everyone (/fly is real flight)", _toggle_low_gravity, "admin")
	api.register_command("time", "day | night | noon | midnight | <0-1> | speed <seconds per day>", _cmd_time, "admin")
	# Everyone may switch modes in the sandbox (the engine's /gamemode is admin-only).
	api.register_command("gamemode", "survival | creative [player | all] - switch game mode ('all' also sets it for new players)", _cmd_gamemode)
	_setup_mobs()
	cooking.setup(api)
	fishing.setup(api)
	guide.setup(api)
	tutorial.setup(api)
	if not api.storage.get("time_initialized", false):
		api.storage.time_initialized = true
		api.set_world_time(0.3, float(api.setting("day_minutes")) * 60.0)  # start the morning of the first day


## Players start on open grassland (plains or savanna) near the world origin.
const SPAWN_BIOMES := ["vanilla:plains", "vanilla:savanna"]


func _spawn_position(_player) -> Vector3:
	if not api.storage.has("spawn"):
		var gen = api.biome_generator()
		var spot := Vector2i(8, 8)
		var best := -1
		for r in range(0, 2048, 32):
			for a in 16:
				var x := 8 + int(cos(a * TAU / 16.0) * r)
				var z := 8 + int(sin(a * TAU / 16.0) * r)
				var biome: String = gen.biome_at(x, z)
				var score := 2 if SPAWN_BIOMES.has(biome) and gen.biome_at(x + 12, z) == biome and gen.biome_at(x - 12, z) == biome else \
					(1 if biome != "vanilla:ocean" and gen.surface_height(x, z) > 47 else 0)
				if score > best:
					best = score
					spot = Vector2i(x, z)
			if best == 2:
				break
		api.storage.spawn = [spot.x, spot.y]
	var at: Array = api.storage.spawn
	return Vector3(int(at[0]) + 0.5, api.surface_y(int(at[0]), int(at[1])) + 1, int(at[1]) + 0.5)


func _on_join(ev: Dictionary) -> void:
	var player = ev.player
	# Only when the sandbox *is* the game. Hearthhold builds on vanilla and wants its blocks and creatures,
	# not its welcome: a player in the valley was greeted as "Vanilla Sandbox" and had its panel in the
	# corner all game. (playtest, 2026-09-18)
	if not api.is_game():
		return
	if ev.first_time:
		_set_mode(player, String(api.storage.get("default_gamemode", "creative")), false)
	var creative: bool = player.is_creative()
	player.show_title("Vanilla Sandbox", "Build anything - blocks are unlimited" if creative else "Survive the night", 4.0)
	player.show_ui("vanilla:info", {
		"anchor": "top_right",
		"children": [
			{"type": "label", "text": "Vanilla Sandbox", "size": 18, "color": "#ffd166"},
			{"type": "label", "text": "%s mode  -  /spawn  /gamemode %s" % ["Creative" if creative else "Survival", "survival" if creative else "creative"]},
		],
	})


## Music by the clock: open and unhurried in daylight, lower and sparser after dark.
##
## Checked on a timer rather than on a "night fell" event because a player who joins at midnight, or
## who travels in from another world, has to get the right one too - and asking for the track that is
## already playing does nothing, so calling this every few seconds costs nothing.
func _setup_music() -> void:
	api.register_music("daylight", "music/daylight.ogg", {"volume": 0.9,
		"attribution": "Quarrowen placeholder, generated by tools/generate_music.py (CC0)"})
	api.register_music("night", "music/night.ogg", {"volume": 0.9,
		"attribution": "Quarrowen placeholder, generated by tools/generate_music.py (CC0)"})
	# Only when the sandbox is the game. A story built on vanilla chooses its own music, and two mods
	# both driving it means whoever ran last wins - here, a timer stamping on the story every 5 seconds.
	# The tracks stay registered either way, so a game like Hearthhold can ask for "vanilla:night".
	music_setup_saw_game = api.is_game()  # read by the test that this is answerable during setup()
	if not music_setup_saw_game:
		return
	api.every(5.0, func(): api.play_music(null, "night" if api.get_daylight() < 0.3 else "daylight", {"fade": 6.0}))


## The sound of being somewhere: wind in the open, a drip in the dark, water at the edge of a lake.
##
## Quiet and infrequent on purpose. This arrives unasked every twenty seconds or so, and the job is to
## be noticed once and then stop being noticed - a wind that announces itself is worse than silence.
func _setup_ambience() -> void:
	api.register_sound("wind", "sounds/wind.wav", {"range": 24.0, "pitch_variance": 0.08})
	api.register_sound("drip", "sounds/drip.wav", {"range": 14.0, "pitch_variance": 0.2})
	api.register_sound("lapping", "sounds/lapping.wav", {"range": 16.0, "pitch_variance": 0.06})
	api.register_ambience({"sound": "wind", "sky": true, "every": [22.0, 55.0], "volume": 0.45})
	# Underground only, and rarer than the wind: a drip you hear twice a minute is atmosphere, one you
	# hear every ten seconds is a tap nobody turned off.
	api.register_ambience({"sound": "drip", "sky": false, "depth": [0, 48], "every": [14.0, 40.0],
		"volume": 0.5, "chance": 0.7})
	# From the water rather than from inside your head, which is what `near` is for.
	api.register_ambience({"sound": "lapping", "near": ["base:water"], "radius": 7, "every": [9.0, 22.0],
		"volume": 0.4})


## Rain, and a storm that is rain with the weight turned up.
##
## Weather is world state the engine keeps; what it looks like and when it arrives are here. It is
## written to be noticed and then lived with: showers are short and common, storms are rare and long,
## and the sky goes grey a while before either really settles in, because the engine fades it.
func _setup_weather() -> void:
	api.register_sound("rain_loop", "sounds/rain.wav", {"volume": 0.9})
	api.register_sound("storm_loop", "sounds/storm.wav", {"volume": 1.0})
	# A flat box of drops overhead, falling fast and straight, small and pale. The box is wider than it
	# is deep so the drops arrive across the view rather than down a funnel in front of the camera.
	var drops := {"amount": 240, "lifetime": 1.0, "speed": [17.0, 21.0], "direction": [0.0, -1.0, 0.0],
		"spread": 4.0, "size": [0.06, 0.06], "colors": ["#a8c8ecb0"], "shape": "box",
		"extents": [16.0, 0.5, 16.0], "texture": "square", "gravity": 6.0}
	api.register_weather("rain", {"emitter": drops, "sound": "rain_loop",
		"sky_tint": "#6d7a8a", "light_scale": 0.74, "fog": 0.25})
	var heavy := drops.duplicate()
	heavy.amount = 420
	heavy.speed = [22.0, 27.0]
	heavy.colors = ["#8fb0d4c8"]
	api.register_weather("storm", {"emitter": heavy, "sound": "storm_loop",
		"sky_tint": "#4a5464", "light_scale": 0.55, "fog": 0.45})

	# Only the game decides the sky. A story built on vanilla wants its own weather, or none.
	if not api.is_game():
		return
	# Checked often, changed rarely: a shower every twenty minutes or so, a storm perhaps once a day.
	api.every(60.0, func():
		if not api.get_weather().name.is_empty():
			return
		var roll := randf()
		if roll < 0.06:
			api.set_weather("storm", {"intensity": randf_range(0.7, 1.0), "seconds": randf_range(240.0, 480.0)})
		elif roll < 0.22:
			api.set_weather("rain", {"intensity": randf_range(0.4, 0.9), "seconds": randf_range(120.0, 360.0)}))


func _setup_mobs() -> void:
	api.register_sound("zombie_ambient", "sounds/zombie_ambient.wav", {"range": 16.0})
	api.register_sound("zombie_hurt", "sounds/zombie_hurt.wav")
	api.register_sound("zombie_death", "sounds/zombie_death.wav")
	api.register_sound("pig_ambient", "sounds/pig_ambient.wav", {"range": 16.0})
	api.register_sound("pig_hurt", "sounds/pig_hurt.wav")
	api.register_sound("pig_death", "sounds/pig_death.wav")
	api.register_sound("skeleton_hurt", "sounds/skeleton_hurt.wav")
	api.register_sound("skeleton_death", "sounds/skeleton_death.wav")
	api.register_sound("bow", "sounds/bow.ogg", {"pitch_variance": 0.15})
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
	ids.porkchop = api.register_item("porkchop", {"display_name": "Raw Pork", "icon": "textures/porkchop.png",
		"food": {"hunger": 3, "saturation": 1.8, "color": "#f0a0a0"}})
	ids.cooked_porkchop = api.register_item("cooked_porkchop", {"display_name": "Roast Pork", "icon": "textures/cooked_porkchop.png",
		"food": {"hunger": 8, "saturation": 12.8, "color": "#b87040"}})
	# Zombies drop rotten flesh: filling in a pinch, but it usually gives food poisoning (hunger drains faster).
	api.register_item("rotten_flesh", {"display_name": "Spoiled Meat", "icon": "textures/rotten_flesh.png",
		"food": {"hunger": 4, "saturation": 0.8, "color": "#7a8a40",
			"effects": [{"stat": "hunger_drain", "amount": 0.5, "seconds": 30, "chance": 0.8, "message": "Food poisoning!"}]}})
	api.register_process("smelting", "vanilla:porkchop", "vanilla:cooked_porkchop", 1, 8.0)
	api.register_entity("arrow", {"kind": "projectile", "sprite": "textures/arrow.png", "width": 0.25, "height": 0.25,
		"damage": 4, "gravity": 14.0, "lifetime": 4.0})

	# Zombies hunt in packs: they hear fighting and digging, call each other in, spread out around
	# their prey and circle while their claws recharge.
	ids.zombie = api.register_entity("zombie", {
		"kind": "mob", "model": "models/zombie.glb", "width": 0.6, "height": 1.85,
		"health": 20, "speed": 3.0, "drops": [["vanilla:rotten_flesh", 1, 0.8], ["base:coal", 1, 0.5], ["base:workbench_plans", 1, 0.12]],
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
		"health": 16, "speed": 3.2, "drops": [["vanilla:bone", 2], ["vanilla:bone", 1, 0.5], ["base:forge_plans", 1, 0.15]],
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
		"breeding": {"food": ["base:apple"], "cooldown": 300, "grow_seconds": 600},  # pigs love apples
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
		if api.setting("apples_from_leaves") and ev.block == api.block("base:leaves") and randf() < APPLE_CHANCE:
			ev.drops.append([api.item("base:apple"), 1]))
	_apply_settings()
	animals.setup(api)
	monsters.setup(api)
	structures.setup(api)
	_first_kill_bonuses()
	_archery()
	_colossus_reward()
	_milestones()
	# Each monster gets its own way of saying it: kind, and about what happened rather than about anyone.
	api.add_death_messages("vanilla:boomshroom", ["%s was standing too close to %s", "%s heard %s pop"])
	api.add_death_messages("vanilla:night_stalker", ["%s was caught in the dark by %s", "%s blinked and %s was there"])
	api.add_death_messages("vanilla:colossus", ["%s was flattened by %s", "%s stood up to %s, briefly"])
	api.add_death_messages("vanilla:slime", ["%s was bounced on by %s", "%s got stuck to %s"])
	api.add_death_messages("vanilla:wolf", ["%s was chased down by %s"])
	api.add_death_messages("fall", ["%s came down faster than expected"])
	api.every(4.0, _mob_tick)
	_setup_music()
	# Not gated on api.is_game(), unlike the music. Music is one channel and two mods driving it means
	# one of them loses; ambience simply adds, and Hearthhold's valley wants wind in it as much as a
	# sandbox does.
	_setup_ambience()
	_setup_weather()


## Occasional mob noises, and zombies burn in daylight.
func _mob_tick() -> void:
	var daylight: float = api.get_daylight()
	var seen := {}  # a mob near several players still gets one turn
	for player in api.get_players():
		for mob in api.get_entities(player.position, 32.0):
			if seen.has(mob.id):
				continue
			seen[mob.id] = true
			if randf() < 0.25 and mob.def.sounds.has("ambient"):
				api.play_sound(mob.def.sounds.ambient, mob.position + Vector3(0, 1, 0))
			if api.setting("zombies_burn") and mob.type in [ids.zombie, ids.skeleton] and daylight > 0.75 \
					and api.sees_sky(Vector3i(mob.position.floor()) + Vector3i.UP):
				mob.damage(4.0, null, "sun")


## A bow, and something to shoot from it.
##
## Skeletons have shot at players since the start and players could not shoot back, which made every
## fight a matter of walking into range and taking the hits on the way. The draw is the whole point: a
## flicked bow is nearly useless and a full one is worth the second it costs, so shooting is a decision
## about timing rather than a button to hold down.
func _archery() -> void:
	api.register_item("arrow", {"display_name": "Arrow", "icon": "textures/arrow_item.png",
		"lore": ["Flint, a stick, and a feather off something."]})
	api.register_recipe({"base:stick": 1, "base:gravel": 1, "vanilla:feather": 1}, "vanilla:arrow", 4,
		{"station": "crafting_table", "category": "tools"})
	ids.bow = api.register_item("bow", {"display_name": "Bow", "icon": "textures/bow.png", "durability": 300,
		"max_stack": 1, "lore": ["Hold to draw. The longer you hold, the further it goes."],
		"charge": {"seconds": 1.0, "minimum": 0.2, "sound": "vanilla:bow"}})
	api.register_recipe({"base:stick": 3, "vanilla:leather": 3}, "vanilla:bow", 1, {"station": "crafting_table"})
	api.on("item_released", func(ev):
		if ev.item != ids.bow:
			return
		var arrow: int = api.item("vanilla:arrow")
		if ev.player.count_of(arrow) <= 0 and not ev.player.is_creative():
			ev.player.show_title("", "No arrows", 1.0)
			return
		if not ev.player.is_creative():
			ev.player.take(arrow, 1)
			ev.player.damage_item(ev.slot, 1, "use")
		# A full draw is fast and hurts; a hurried one drops short and glances off. The curve is squared
		# so the last part of the draw is worth more than the first, which is what makes waiting feel like
		# a choice rather than a delay.
		var power: float = 0.25 + 0.75 * ev.charge * ev.charge
		var shot = api.spawn_entity("arrow", ev.player.get_eye_position() + ev.direction * 0.6,
			{"velocity": ev.direction * (12.0 + 26.0 * power), "owner": ev.player})
		if shot != null:
			shot.data.damage = 2.0 + 7.0 * power
		api.play_sound("vanilla:bow", ev.player.position, 0.9, 0.9 + 0.3 * power))


## What the Colossus leaves, and what the valley remembers about it.
##
## It was the biggest thing in the game and the least acknowledged: four hundred health, two phases, an
## arena of its own, and it dropped rather less than a good afternoon in a cave. The fix is not a bigger
## pile of ore. It is one thing you cannot get any other way, worn where other people can see it.
func _colossus_reward() -> void:
	api.register_item("colossus_heart", {"display_name": "Colossus Heart",
		"icon": "textures/colossus_heart.png", "equip_slot": "trinket", "max_stack": 1,
		"lore": ["Still warm. Still, faintly, beating."],
		"glow": {"color": "#ff8844", "energy": 0.6, "light": 0},
		"modifiers": [{"stat": "max_health", "amount": 6.0, "op": "add"},
			{"stat": "knockback_resistance", "amount": 0.3, "op": "add"},
			{"stat": "armor", "amount": 2.0, "op": "add"}]})
	# A cosmetic rather than a helmet: armor wears out, and this should not.
	api.register_cosmetic("colossus_crown", {"category": "hat", "display_name": "Colossus crown", "color": "#6a5a3a",
		"unlocked": false, "description": "Vanilla: for bringing down the Ancient Colossus.", "boxes": [
			{"from": [-4.5, 0, -4.5], "size": [9, 2, 9]},
			{"from": [-4.5, 2, -4.5], "size": [1.5, 3, 1.5]}, {"from": [3, 2, -4.5], "size": [1.5, 3, 1.5]},
			{"from": [-4.5, 2, 3], "size": [1.5, 3, 1.5]}, {"from": [3, 2, 3], "size": [1.5, 3, 1.5]},
			{"from": [-1, 2, -4.5], "size": [2, 4, 1.5]}, {"from": [-1, 2, 3], "size": [2, 4, 1.5]}]})
	# The heart is rare enough that the engine announces it on its own (loot.gd RARE_CHANCE), so the kill
	# sparkles and goes to chat without a line of code here.
	api.extend_loot("mob:vanilla:colossus", {"pools": [
		{"rolls": 1, "guaranteed": true, "entries": [{"item": "vanilla:colossus_heart", "count": 1}]},
		{"rolls": 3, "entries": [{"item": "base:cobalt_ingot", "count": [2, 4]}, {"item": "base:deepstone", "count": [4, 8]}]}]})
	api.register_milestone("colossus", {"title": "The Colossus", "order": 40, "announce": true,
		"description": "You brought down the Ancient Colossus.",
		"icon": "vanilla:colossus_heart", "goal": {"type": "kill", "target": "vanilla:colossus"},
		"reward": {"cosmetic": "vanilla:colossus_crown"}})


## Milestones: the handful of things worth remembering about a world, one for each way a child might
## choose to play it. Deliberately few - a long list is a chore list, and the point is the opposite.
func _milestones() -> void:
	api.register_milestone("prospector", {"title": "Prospector", "order": 10,
		"description": "You found cobalt, deeper than most people dig.",
		"icon": "base:cobalt_ingot", "goal": {"type": "break", "target": "base:cobalt_ore"}})
	api.register_milestone("deepstone", {"title": "The Bottom of It", "order": 20,
		"description": "You cut deepstone out of the floor of the world.",
		"icon": "base:deepstone", "goal": {"type": "break", "target": "base:deepstone"}})
	api.register_milestone("cook", {"title": "Somebody Who Cooks", "order": 25,
		"description": "A dozen proper meals made for whoever was hungry.",
		"icon": "base:bowl", "goal": {"type": "craft", "count": 12, "target": ["vanilla:mushroom_stew",
			"vanilla:beef_stew", "vanilla:glowcap_soup", "vanilla:honey_cake", "vanilla:hearty_feast",
			"vanilla:clean_broth", "base:apple_pie"]}})
	# No target: anything placed counts, which is what "builder" should mean.
	api.register_milestone("builder", {"title": "Builder", "order": 30,
		"description": "A thousand blocks placed. Something must be standing by now.",
		"icon": "base:planks", "goal": {"type": "place", "count": 1000}})


## The first time a player meets each kind of creature, it leaves something extra behind: a small reward
## for going somewhere new, rather than for grinding the same field. `first_time` is per player and per
## table, so it happens once each, however many people are on the server.
func _first_kill_bonuses() -> void:
	for mob in [["pig", "base:apple"], ["cow", "base:apple"], ["chicken", "base:apple"], ["sheep", "base:apple"],
			["zombie", "base:iron_ingot"], ["skeleton", "base:iron_ingot"], ["slime", "base:coal"]]:
		api.extend_loot("mob:vanilla:%s" % mob[0], {"pools": [{"rolls": 1, "guaranteed": true,
			"when": {"first_time": true, "player": true},
			"entries": [{"item": mob[1], "count": [1, 2]}]}]})
	api.on("loot_first_time", func(ev):
		if ev.source != "entity" or not str(ev.table).begins_with("mob:vanilla:"):
			return
		ev.player.send_message("✦ Your first %s! It left something extra." % str(ev.table).substr(12).replace("_", " ")))


## Takes the host's settings into use, at startup and whenever one is changed while the server runs.
func _apply_settings() -> void:
	api.set_spawn_caps({"monster": MONSTER_CAPS.get(api.setting("monsters"), 24)})
	api.set_loot_rate({"less": 0.5, "normal": 1.0, "lots": 2.0}.get(api.setting("loot"), 1.0))


func _cmd_gamemode(player, args: PackedStringArray) -> void:
	var mode := args[0] if args.size() > 0 else ""
	if not mode in ["survival", "creative"]:
		player.send_message("Usage: /gamemode survival | creative [player | all]")
		return
	var who := args[1] if args.size() > 1 else ""
	if who.is_empty():
		if mode == "creative" and not player.has_permission("creative"):
			player.send_message("Creative mode is not available to you on this server")
			return
		if player.is_creative() == (mode == "creative"):
			player.send_message("You are already in %s mode" % mode)
			return
		_set_mode(player, mode)
		return
	if not player.has_permission("admin"):
		player.send_message("Only admins can change someone else's game mode")
		return
	if who.to_lower() == "all":
		# The whole server, now and for anyone who joins later.
		api.storage.default_gamemode = mode
		for other in api.get_players():
			_set_mode(other, mode)
		player.send_message("Everyone is now in %s mode, and new players start in it" % mode)
		return
	for other in api.get_players():
		if other.name.to_lower() == who.to_lower():
			_set_mode(other, mode)
			player.send_message("%s is now in %s mode" % [other.name, mode])
			return
	player.send_message("No player called '%s' is online" % who)


## Switches one player's mode, with the kit or the creative hotbar that goes with it.
func _set_mode(player, mode: String, tell := true) -> void:
	player.set_creative(mode == "creative")
	if mode == "survival":
		# The creative hotbar holds placeholder stacks; start survival with a small kit instead.
		player.clear_inventory()
		player.give(api.item("base:stone_sword"))
		player.give(api.item("base:wooden_pickaxe"))
		player.give(api.item("base:planks"), 16)
		player.give(api.item("base:apple"), 3)
	else:
		player.set_hotbar(HOTBAR.map(func(n): return api.block(n)))
	if tell:
		player.send_message("Game mode: %s%s" % [mode, " - watch out for zombies at night!" if mode == "survival" else ""])


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
