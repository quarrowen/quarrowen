extends RefCounted
## Night and cave monsters built on engine mob traits:
## - spider: climbs walls, leaps at you, leaves you alone in bright daylight unless provoked; drops string
## - slime: hops around caves; big slimes split into medium ones and those into small ones
## - night stalker: a rare, fast hunter of the darkest nights and deepest caves that flees from light
##   and from anyone holding a torch; drops shadow essence
## - boomshroom: a walking mushroom that sneaks up, hisses and explodes (breaking blocks unless the
##   mob_griefing rule is off); run before the fuse burns down. Drops boom spores when killed

var api
var ids := {}


func setup(mod_api) -> void:
	api = mod_api
	for sound in ["spider_ambient", "spider_hurt", "slime_hop", "slime_hurt", "stalker_ambient", "stalker_screech"]:
		api.register_sound(sound, "sounds/%s.wav" % sound, {"pitch_variance": 0.1})
	api.register_item("string", {"display_name": "String", "icon": "textures/string.png"})
	api.register_item("slimeball", {"display_name": "Slimeball", "icon": "textures/slimeball.png"})
	api.register_item("boom_spores", {"display_name": "Boom Spores", "icon": "textures/boom_spores.png", "lore": ["Handle with care."]})
	ids.boomshroom = api.register_entity("boomshroom", {"kind": "mob", "model": "models/boomshroom.glb", "display_name": "Boomshroom",
		"width": 0.8, "height": 1.4, "health": 14, "speed": 2.6, "category": "monster",
		"drops": [["vanilla:boom_spores", 1, 0.8], ["vanilla:boom_spores", 1, 0.3]],
		"sounds": {"hurt": "slime_hurt", "death": "slime_hurt", "ambient": "spider_ambient"},
		"ai": {"preset": "hostile", "group": "boomshrooms", "aggression": 0.8, "intelligence": 0.5, "courage": 1.0, "chase_speed": 1.2,
			"attacks": [{"name": "burst", "type": "explode", "range": 1.2, "windup": 1.5, "power": 3.0, "fuse_escape": 2.5,
				"sound": "engine:fuse", "windup_effect": "engine:smoke"}]}})
	api.add_spawn_rule({"entity": "boomshroom", "category": "monster", "light": [0, 7], "on": ["base:grass", "base:dirt", "base:stone", "base:sand", "base:snow"],
		"max_nearby": 2, "max_total": 10, "chance": 0.06})
	api.register_item("shadow_essence", {"display_name": "Shadow Essence", "icon": "textures/shadow_essence.png",
		"lore": ["Cold to the touch. It shies from the light."]})

	ids.spider = api.register_entity("spider", {"kind": "mob", "model": "models/spider.glb", "width": 1.3, "height": 0.9, "health": 16, "speed": 3.0,
		"category": "monster", "drops": [["vanilla:string", 1, 0.8], ["vanilla:string", 1, 0.4]],
		"sounds": {"hurt": "spider_hurt", "death": "spider_hurt", "ambient": "spider_ambient"},
		"ai": {"preset": "hostile", "group": "spiders", "aggression": 0.7, "intelligence": 0.6, "courage": 0.9,
			"climb": true, "step_up": 8, "max_drop": 6, "day_temperament": "neutral",
			"attacks": [
				{"name": "bite", "type": "melee", "damage": 2.5, "range": 0.8, "windup": 0.3, "cooldown": 1.0},
				{"name": "pounce", "type": "leap", "damage": 3.0, "min_range": 2.0, "range": 5.0, "radius": 1.4, "windup": 0.45, "cooldown": 4.0, "weight": 0.7},
			]}})
	api.add_spawn_rule({"entity": "spider", "category": "monster", "light": [0, 7], "on": ["base:grass", "base:dirt", "base:stone", "base:sand", "base:snow"],
		"max_nearby": 3, "max_total": 16, "chance": 0.1})

	# Slimes: three sizes of one model; each splits into the next size down.
	var sizes := [["slime", "Slime", 2.0, 16.0, 4.0, "vanilla:slime_medium", []],
		["slime_medium", "Slime", 1.0, 6.0, 2.0, "vanilla:slime_small", []],
		["slime_small", "Small Slime", 0.5, 1.0, 0.0, "", [["vanilla:slimeball", 1, 0.6]]]]
	for size in sizes:
		var attacks := [{"name": "squish", "type": "melee", "damage": size[4], "range": 0.4, "windup": 0.2, "cooldown": 1.0}] if size[4] > 0.0 else []
		var def := {"kind": "mob", "model": "models/slime.glb", "display_name": size[1], "scale": size[2], "width": size[2] * 0.9, "height": size[2] * 0.9,
			"health": size[3], "speed": 2.2 + (2.0 - size[2]) * 0.5, "category": "monster", "drops": size[6],
			"sounds": {"hurt": "slime_hurt", "death": "slime_hurt", "ambient": "slime_hop"},
			"ai": {"preset": "hostile", "group": "slimes", "aggression": 0.6, "intelligence": 0.2, "courage": 1.0,
				"hop": {"interval": 1.1 + size[2] * 0.3, "height": 0.8 + size[2] * 0.3}, "attacks": attacks}}
		if size[4] <= 0.0:
			def.ai.preset = "wander"  # the smallest ones just bounce about
		if not String(size[5]).is_empty():
			def.split = {"entity": size[5], "count": [2, 3]}
		ids[size[0]] = api.register_entity(size[0], def)
	api.add_spawn_rule({"entity": "slime", "category": "monster", "light": [0, 7], "place": "underground", "on": ["base:stone"],
		"max_nearby": 2, "max_total": 6, "chance": 0.03})

	ids.stalker = api.register_entity("night_stalker", {"kind": "mob", "model": "models/night_stalker.glb", "display_name": "Night Stalker",
		"width": 0.6, "height": 2.2, "health": 24, "speed": 4.4, "category": "monster",
		"drops": [["vanilla:shadow_essence", 1], ["vanilla:shadow_essence", 1, 0.3]],
		"sounds": {"hurt": "stalker_screech", "death": "stalker_screech", "ambient": "stalker_ambient", "attack": "stalker_screech"},
		"ai": {"preset": "hostile", "group": "stalkers", "aggression": 1.0, "intelligence": 0.9, "agility": 0.8, "courage": 0.7,
			"chase_speed": 1.5, "sight_range": 32, "fear_light": 9,
			"attacks": [{"name": "rend", "type": "melee", "damage": 5.0, "range": 1.0, "windup": 0.35, "cooldown": 1.1}]}})
	api.add_spawn_rule({"entity": "night_stalker", "category": "monster", "light": [0, 3], "time": "night",
		"on": ["base:grass", "base:dirt", "base:stone", "base:snow"], "max_nearby": 1, "max_total": 2, "chance": 0.01, "min_distance": 30})
	api.add_spawn_rule({"entity": "night_stalker", "category": "monster", "light": [0, 3], "place": "underground",
		"on": ["base:stone"], "max_nearby": 1, "max_total": 2, "chance": 0.005, "min_distance": 30})
