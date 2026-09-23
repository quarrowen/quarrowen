extends RefCounted
## Creatures, and everything that happens to them: AI, taming, orders, riding, conditions, fields.

var api
var ids: Dictionary


func setup(mod_api, id_table: Dictionary) -> void:
	api = mod_api
	ids = id_table
	_creatures()
	_conditions_and_fields()
	_companions_and_vehicles()


func _creatures() -> void:
	# A quiet one to tame and order about, and a hostile one whose bite leaves something behind. Between
	# them they cover the AI presets, phases, attacks, taming and breeding.
	ids.grazer = api.register_entity("grazer", {"kind": "mob", "display_name": "Grazer",
		"width": 0.8, "height": 1.0, "health": 10, "speed": 2.2, "category": "animal", "persistent": true,
		"taming": {"items": ["proving:grain"], "chance": 1.0, "follow_distance": 3.0, "teleport_distance": 16.0},
		"breeding": {"items": ["proving:grain"], "cooldown": 5.0},
		"nameplate": {"show_health": true},
		# Drops, so it has a loot table another mod can extend - which is what extend_loot is for.
		"drops": [["proving:token", 1], ["proving:grain", 2]],
		"ai": {"preset": "passive", "wander_radius": 6}})
	# One the whole server is told about: announced when it appears, marked on everybody's map and
	# compass while it is about, and taken away again when its time is up. Short minutes so a test can
	# sit through the clock running out rather than mock it. (2026-09-23)
	ids.quarry = api.register_entity("quarry", {"kind": "mob", "display_name": "Quarry",
		"width": 0.7, "height": 1.4, "health": 12, "speed": 2.0, "category": "monster", "persistent": true,
		"notable": {"announce": "A Quarry is about.", "slain": "%s got the Quarry.",
			"gone": "The Quarry has gone.", "color": "#ff66aa", "minutes": 0.05},
		"drops": [["proving:token", 2]],
		"ai": {"preset": "hostile", "aggression": 0.5}})
	ids.biter = api.register_entity("biter", {"kind": "mob", "display_name": "Biter",
		"width": 0.7, "height": 1.2, "health": 20, "speed": 3.0, "category": "monster",
		"nameplate": {"show_health": true, "color": "#ff8866"},
		# A drop with a chance, so "how often does this drop" is answerable.
		"drops": [["proving:token", 1, 0.5], ["proving:spoiled", 1]],
		"ai": {"preset": "hostile", "aggression": 0.9, "sight_range": 20,
			"attacks": [
				{"name": "bite", "type": "melee", "damage": 2.0, "range": 2.0, "windup": 0.2,
					"condition": {"condition": "venom", "seconds": 6.0, "level": 1}},
				{"name": "spit", "type": "ranged", "damage": 1.0, "range": 12.0, "min_range": 4.0,
					"projectile": "proving:dart",
					"condition": {"condition": "venom", "seconds": 4.0}},
				{"name": "stamp", "type": "slam", "damage": 3.0, "radius": 3.0, "health_below": 0.5,
					"lingers": {"field": "scorch", "seconds": 6.0}}],
			"phases": [{"health_below": 0.5, "message": "The biter is angry", "speed_multiplier": 1.3}],
			"boss": {"name": "The Biter", "bar_range": 32}}})
	# A boss bar and phases need something that will not die on the first hit.
	api.add_spawn_rule({"entity": "biter", "max_light": 4, "weight": 1, "group": [1, 2]})
	# An animal rule too: spawning is a capability with two halves, and the quiet half wants light.
	api.add_spawn_rule({"entity": "grazer", "min_light": 9, "weight": 1, "group": [1, 3], "on": ["proving:turf"]})
	# A wild one wears no collar; taming puts it on. Set on spawn rather than in the definition,
	# because `look` is per-creature state and taming is what changes it.
	api.on("entity_spawned", func(ev):
		if ev.entity.type == ids.grazer and not ev.entity.data.has("look"):
			ev.entity.set_look({"hide": ["collar"]}))
	# And taming puts it on. The engine does not decide what being tamed looks like, which is why this
	# is here rather than in taming.gd.
	api.on("entity_tamed", func(ev): ev.entity.set_look({"hide": []}))


func _conditions_and_fields() -> void:
	api.register_condition("venom", {"display_name": "Venom", "good": false, "color": "#89c24a",
		"tick": {"seconds": 1.0, "damage": 1.0, "cause": "venom"}, "max_level": 3})
	api.register_condition("haste", {"display_name": "Haste", "color": "#7fd6ff", "max_level": 3,
		"stacks": "extend", "modifiers": [{"stat": "move_speed", "amount": 0.2, "op": "multiply"}]})
	api.register_condition("mending", {"display_name": "Mending", "tick": {"seconds": 1.0, "heal": 1.0}})
	api.register_field("scorch", {"display_name": "Scorch", "radius": 3.0, "seconds": 8.0,
		"effect": "engine:smoke", "tick": {"seconds": 1.0, "damage": 1.0, "cause": "scorch"},
		"condition": {"condition": "venom", "seconds": 3.0}})
	api.register_field("respite", {"display_name": "Respite", "radius": 4.0, "seconds": 20.0,
		"effect": "engine:sparkle", "affects": "players", "except_owner": false,
		"tick": {"seconds": 1.0, "heal": 1.0}})


func _companions_and_vehicles() -> void:
	# An order beyond the engine's three, so the mod-registered path is covered as well.
	api.register_order("forage", {"display_name": "Forage here", "behavior": "proving:forage"})
	api.register_mob_behavior("forage", {
		"score": func(brain): return 0.2 if api.order_of(brain.entity) == "proving:forage" else 0.0,
		"update": func(brain, _delta): brain.stop(),
	})
	# Something that flies, which is the one kind of movement that is not about the ground. `gravity: 0`
	# because a flier drives its own height.
	ids.flitter = api.register_entity("flitter", {"kind": "mob", "display_name": "Flitter",
		"width": 0.4, "height": 0.4, "health": 4, "speed": 4.0, "gravity": 0.0, "category": "animal",
		"ai": {"preset": "passive", "wander_radius": 10, "fly": {"height": 6.0, "speed_up": 0.8}}})
	ids.raft = api.register_entity("raft", {"kind": "mob", "display_name": "Raft",
		"width": 1.2, "height": 0.5, "health": 20, "speed": 1.0, "category": "misc", "persistent": true,
		"ai": {"preset": "none"},
		"vehicle": {"seats": 2, "speed": 6.0, "turn_speed": 4.0, "floats": true, "seat_height": 0.4}})
