extends "res://engine/server/mod.gd"
## Flat stone world (floor top at y = 9) with test mobs covering the engine AI features.

const FLOOR_Y := 9

var api


class FlatWorld:
	var template := PackedByteArray()

	func _init(stone: int, bedrock: int) -> void:
		template.resize(16 * 16 * 128 * 2)
		for y in FLOOR_Y + 1:
			for z in 16:
				for x in 16:
					template.encode_u16((x + (z << 4) + (y << 8)) << 1, bedrock if y == 0 else stone)

	func generate(chunk) -> void:
		chunk.blocks = template.duplicate()


func setup(mod_api) -> void:
	api = mod_api
	api.set_world_generator(FlatWorld.new(api.block("base:stone"), api.block("base:bedrock")))
	api.register_block("spikes", {"textures": "", "hazard": true, "solid": false, "render": "cutout"})
	api.register_entity("bolt", {"kind": "projectile", "damage": 3, "gravity": 4.0, "width": 0.2, "height": 0.2})
	api.register_entity("grunt", {"health": 20, "speed": 4.0, "ai": {"preset": "hostile", "intelligence": 0.7, "aggression": 0.9,
		"group": "arena", "memory": 20, "attacks": [{"name": "claw", "damage": 4, "range": 0.8, "windup": 0.4, "cooldown": 0.8}]}})
	api.register_entity("archer", {"health": 20, "speed": 4.0, "ai": {"preset": "archer", "group": "arena",
		"attacks": [{"name": "shoot", "type": "ranged", "projectile": "ai_arena:bolt", "damage": 3, "range": 18, "windup": 0.3, "cooldown": 0.8}]}})
	api.register_entity("giant", {"width": 1.2, "height": 7.2, "health": 200, "speed": 3.0, "knockback_resistance": 0.9,
		"ai": {"preset": "hostile", "step_up": 2, "group": "arena", "attacks": [{"name": "stomp", "type": "slam", "radius": 3, "damage": 6, "windup": 0.8}]}})
	api.register_entity("coward", {"health": 20, "speed": 4.0, "ai": {"preset": "hostile", "courage": 0.2, "group": "cowards",
		"attacks": [{"name": "poke", "damage": 1, "range": 0.8}]}})
	api.register_entity("boss", {"health": 100, "speed": 2.0, "width": 1.0, "height": 3.0,
		"ai": {"preset": "boss", "group": "arena", "boss": {"name": "Test Boss"},
			"attacks": [{"name": "slam", "type": "slam", "radius": 4, "damage": 5, "windup": 0.5, "cooldown": 0.5}],
			"phases": [{"health_below": 0.5, "message": "Phase two", "speed_multiplier": 1.5,
				"add_attacks": [{"name": "summon", "type": "summon", "entity": "ai_arena:grunt", "count": 2, "max_summons": 2, "range": 30, "windup": 0.2}]}]}})
	api.register_entity("guard", {"health": 20, "speed": 4.0, "ai": {"preset": "neutral", "group": "guards", "behaviors": ["ai_arena:patrol"]}})
	api.register_mob_behavior("patrol", {
		"score": func(brain): return 2.0 if brain.entity.data.has("patrol_to") else 0.0,
		"update": func(brain, _delta):
			brain.move_to(brain.entity.data.patrol_to, 1.0, 0.6)
			if brain.arrived():
				brain.entity.data.erase("patrol_to"),
	})
