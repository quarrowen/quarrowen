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
		"width": 0.8, "height": 1.0, "health": 12, "speed": 2.2, "category": "misc", "persistent": true,
		"taming": {"items": ["base:apple"], "chance": 1.0, "follow_distance": 3.0, "teleport_distance": 16.0},
		"breeding": {"items": ["base:apple"], "cooldown": 5.0},
		"nameplate": {"show_health": true},
		"ai": {"preset": "passive", "wander_radius": 6}})
	ids.biter = api.register_entity("biter", {"kind": "mob", "display_name": "Biter",
		"width": 0.7, "height": 1.2, "health": 20, "speed": 3.0, "category": "monster",
		"nameplate": {"show_health": true, "color": "#ff8866"},
		"ai": {"preset": "hostile", "aggression": 0.9, "sight_range": 20,
			"attacks": [
				{"name": "bite", "type": "melee", "damage": 2.0, "range": 2.0, "windup": 0.2,
					"condition": {"condition": "venom", "seconds": 6.0, "level": 1}},
				{"name": "spit", "type": "ranged", "damage": 1.0, "range": 12.0, "min_range": 4.0,
					"projectile": "base:arrow" if api.entity_type("base:arrow") > 0 else "",
					"condition": {"condition": "venom", "seconds": 4.0}},
				{"name": "stamp", "type": "slam", "damage": 3.0, "radius": 3.0, "health_below": 0.5,
					"lingers": {"field": "scorch", "seconds": 6.0}}],
			"phases": [{"health_below": 0.5, "message": "The biter is angry", "speed_multiplier": 1.3}],
			"boss": {"name": "The Biter", "bar_range": 32}}})
	# A boss bar and phases need something that will not die on the first hit.
	api.add_spawn_rule({"entity": "biter", "max_light": 4, "weight": 1, "group": [1, 2]})


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
	ids.raft = api.register_entity("raft", {"kind": "mob", "display_name": "Raft",
		"width": 1.2, "height": 0.5, "health": 20, "speed": 1.0, "category": "misc", "persistent": true,
		"ai": {"preset": "none"},
		"vehicle": {"seats": 2, "speed": 6.0, "turn_speed": 4.0, "floats": true, "seat_height": 0.4}})
