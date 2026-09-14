extends RefCounted
## Resolves a mob's `ai` definition into a complete, validated config. Mods write a preset name
## ("hostile") or a Dictionary that starts from a preset and overrides any field:
##
##   "ai": {
##     "preset": "hostile",        hostile | neutral | passive | archer | boss | wander | none
##     "aggression": 0.8,          0-1: how far it engages from, how often it attacks, how long it pursues
##     "courage": 0.4,             0-1: flees below (1 - courage) / 2 health; 1 never flees
##     "intelligence": 0.9,        0-1: flanking/surrounding, leading shots, predicting movement, dodging
##     "agility": 0.5,             0-1: chance to sidestep incoming projectiles
##     "sight_range": 24, "fov": 140, "hearing_range": 16, "memory": 12, "reaction_time": 0.3,
##     "group": "undead",          allies share alerts and never fight each other
##     "enemy_groups": ["villager"], other mob groups it attacks (players are always enemies of hostile mobs)
##     "alert_radius": 16,         allies within this distance join the fight
##     "chase_speed": 1.3,         speed multiplier while engaging
##     "preferred_range": [6, 12], ranged mobs keep this distance (defaults from their attacks)
##     "skittish": 0,              passive mobs flee from players closer than this
##     "leash": 0,                 return home when further than this (0 = roam); "reset_on_leash" heals
##     "step_up": 1, "max_drop": 3, "can_swim": false,
##     "attack_interval": 1.0,     minimum seconds between any two attacks (scaled by aggression)
##     "attacks": [ {...} ],       see ATTACK_DEFAULTS
##     "phases": [ {"health_below": 0.5, "message": "...", "speed_multiplier": 1.3, "aggression": 1,
##                  "add_attacks": [...], "attacks": [...]} ],
##     "boss": {"name": "Ancient Colossus", "bar_range": 48},
##     "behaviors": ["my_mod:guard"],   extra behaviors registered with register_mob_behavior
##     "climb": false,             walks up walls when blocked (spiders; pair with a high step_up)
##     "hop": {"interval": 1.0, "height": 1.2},   moves only in hops (slimes)
##     "day_temperament": "neutral",  temperament while it stands in bright daylight (spiders)
##     "fear_light": 9,            flees to darkness when the light where it stands (or a torch held
##                                 nearby) reaches this level; 0 = no fear
##   }

const TEMPERAMENTS := ["hostile", "neutral", "passive", "none"]
const ATTACK_TYPES := ["melee", "ranged", "leap", "charge", "slam", "summon", "explode", "custom"]

const BASE := {
	"temperament": "hostile",
	"aggression": 0.5,
	"courage": 0.8,
	"intelligence": 0.5,
	"agility": 0.0,
	"sight_range": 16.0,
	"fov": 150.0,
	"hearing_range": 12.0,
	"memory": 10.0,
	"reaction_time": 0.3,
	"think_interval": 0.25,
	"group": "",
	"enemy_groups": [],
	"alert_radius": 14.0,
	"chase_speed": 1.3,
	"wander_speed": 0.45,
	"wander_radius": 10.0,
	"preferred_range": [],
	"skittish": 0.0,
	"leash": 0.0,
	"reset_on_leash": false,
	"regen": 0.0,
	"step_up": 1,
	"max_drop": 3,
	"can_swim": false,
	"attack_interval": 1.0,
	"attacks": [],
	"phases": [],
	"boss": {},
	"behaviors": [],
	"climb": false,
	"hop": {},
	"day_temperament": "",
	"fear_light": 0,
}

const PRESETS := {
	"hostile": {"temperament": "hostile", "aggression": 0.6, "courage": 0.9, "intelligence": 0.5,
		"attacks": [{"name": "strike", "type": "melee"}]},
	"neutral": {"temperament": "neutral", "aggression": 0.5, "courage": 0.7, "attacks": [{"name": "strike", "type": "melee"}]},
	"passive": {"temperament": "passive", "aggression": 0.0, "courage": 0.0, "intelligence": 0.4, "attacks": []},
	"wander": {"temperament": "none", "aggression": 0.0, "courage": 1.0, "attacks": []},
	"none": {"temperament": "none", "aggression": 0.0, "courage": 1.0, "attacks": [], "wander_radius": 0.0},
	"archer": {"temperament": "hostile", "aggression": 0.55, "courage": 0.35, "intelligence": 0.8, "agility": 0.5,
		"sight_range": 24.0, "preferred_range": [7.0, 14.0],
		"attacks": [{"name": "shoot", "type": "ranged", "range": 18.0, "min_range": 2.0, "windup": 0.6, "cooldown": 1.6}]},
	"boss": {"temperament": "hostile", "aggression": 0.8, "courage": 1.0, "intelligence": 0.9, "sight_range": 32.0,
		"fov": 360.0, "hearing_range": 32.0, "memory": 60.0, "leash": 48.0, "reset_on_leash": true, "step_up": 2,
		"max_drop": 4, "attacks": [{"name": "smash", "type": "melee", "damage": 8.0, "windup": 0.7, "arc": 140.0}]},
}

const ATTACK_DEFAULTS := {
	"name": "",
	"type": "melee",
	"damage": 3.0,
	"range": 1.0,         # reach from the mob's edge to the target's edge
	"min_range": 0.0,
	"cooldown": 1.0,
	"windup": 0.4,        # telegraph before it lands: players can dodge
	"recovery": 0.2,      # stands still after attacking
	"knockback": 6.0,
	"weight": 1.0,
	"arc": 100.0,         # melee: degrees in front that can be hit
	"radius": 3.0,        # slam / leap landing: area of effect
	"projectile": "",     # ranged: entity type name
	"projectile_speed": 22.0,
	"spread": 2.0,        # ranged: degrees of inaccuracy (less with intelligence)
	"count": 1,           # ranged: projectiles per shot; summon: entities per cast
	"entity": "",         # summon: entity type name
	"max_summons": 3,
	"speed": 12.0,        # charge: blocks per second
	"duration": 1.2,      # charge
	"health_below": 1.01, # only usable at or below this health fraction
	"health_above": -1.0,
	"sound": "",          # played when the wind-up starts
	"windup_effect": "",  # effect name (full, e.g. "engine:magic") following the mob during the wind-up
	"effect": "",         # effect when the attack lands: at the mob's front, or its feet for slam / summon
	"power": 3.0,         # explode: blast power; the mob is used up. Fizzles if the target got `fuse_escape` blocks away
	"fuse_escape": 2.5,
}


## Returns the resolved config. `ai` is a preset name, a Dictionary, or anything else (-> "wander").
## `resolve_entity` maps entity type names to ids (for projectiles and summons).
static func resolve(ai, def: Dictionary, resolve_entity: Callable) -> Dictionary:
	var overrides: Dictionary = ai if ai is Dictionary else {"preset": String(ai) if ai is String else "wander"}
	var preset_name := String(overrides.get("preset", "hostile" if ai is Dictionary else "wander"))
	var config := BASE.duplicate(true)
	config.merge(PRESETS.get(preset_name, PRESETS.wander).duplicate(true), true)
	for key in overrides:
		if key != "preset" and BASE.has(key):
			config[key] = overrides[key]
	# Legacy flat entity fields from the first entity API.
	if not (ai is Dictionary) or not overrides.has("attacks"):
		if def.has("attack_damage") and not config.attacks.is_empty() and config.attacks[0].get("type", "melee") == "melee":
			config.attacks[0]["damage"] = float(def.attack_damage)
			config.attacks[0]["range"] = maxf(float(def.get("attack_range", 1.4)) - float(def.get("width", 0.6)) * 0.5, 0.4)
			config.attacks[0]["cooldown"] = float(def.get("attack_cooldown", 1.0))
	if def.has("sight_range") and not overrides.has("sight_range"):
		config.sight_range = float(def.sight_range)
	return sanitize(config, resolve_entity)


static func sanitize(config: Dictionary, resolve_entity: Callable) -> Dictionary:
	var c := config
	c.temperament = String(c.temperament) if String(c.temperament) in TEMPERAMENTS else "hostile"
	for key in ["aggression", "courage", "intelligence", "agility"]:
		c[key] = clampf(float(c[key]), 0.0, 1.0)
	c.sight_range = clampf(float(c.sight_range), 1.0, 96.0)
	c.fov = clampf(float(c.fov), 10.0, 360.0)
	c.hearing_range = clampf(float(c.hearing_range), 0.0, 96.0)
	c.memory = clampf(float(c.memory), 0.5, 600.0)
	c.reaction_time = clampf(float(c.reaction_time), 0.0, 3.0)
	c.think_interval = clampf(float(c.think_interval), 0.05, 2.0)
	c.group = String(c.group)
	c.enemy_groups = (c.enemy_groups as Array).map(func(g): return String(g)) if c.enemy_groups is Array else []
	c.alert_radius = clampf(float(c.alert_radius), 0.0, 96.0)
	c.chase_speed = clampf(float(c.chase_speed), 0.1, 4.0)
	c.wander_speed = clampf(float(c.wander_speed), 0.0, 2.0)
	c.wander_radius = clampf(float(c.wander_radius), 0.0, 64.0)
	c.skittish = clampf(float(c.skittish), 0.0, 64.0)
	c.leash = clampf(float(c.leash), 0.0, 512.0)
	c.reset_on_leash = bool(c.reset_on_leash)
	c.regen = clampf(float(c.regen), 0.0, 1000.0)
	c.step_up = clampi(int(c.step_up), 0, 8)
	c.max_drop = clampi(int(c.max_drop), 0, 32)
	c.can_swim = bool(c.can_swim)
	c.attack_interval = clampf(float(c.attack_interval), 0.0, 60.0)
	c.climb = bool(c.climb)
	c.hop = {"interval": clampf(float(c.hop.get("interval", 1.0)), 0.2, 10.0), "height": clampf(float(c.hop.get("height", 1.2)), 0.2, 6.0)} \
		if c.hop is Dictionary and not c.hop.is_empty() else {}
	c.day_temperament = String(c.day_temperament) if String(c.day_temperament) in TEMPERAMENTS else ""
	c.fear_light = clampi(int(c.fear_light), 0, 15)
	c.attacks = _attacks(c.attacks, resolve_entity)
	var phases := []
	for phase in (c.phases if c.phases is Array else []):
		if phase is Dictionary:
			var p: Dictionary = phase.duplicate(true)
			p.health_below = clampf(float(p.get("health_below", 0.5)), 0.0, 1.0)
			if p.has("attacks"):
				p.attacks = _attacks(p.attacks, resolve_entity)
			if p.has("add_attacks"):
				p.add_attacks = _attacks(p.add_attacks, resolve_entity)
			phases.append(p)
	phases.sort_custom(func(a, b): return a.health_below > b.health_below)
	c.phases = phases
	c.boss = c.boss if c.boss is Dictionary else {}
	c.behaviors = (c.behaviors as Array).map(func(b): return String(b)) if c.behaviors is Array else []
	var ranged_min := INF
	var ranged_max := 0.0
	for attack in c.attacks:
		if attack.type == "ranged":
			ranged_min = minf(ranged_min, maxf(attack.min_range + 3.0, attack.range * 0.4))
			ranged_max = maxf(ranged_max, attack.range * 0.8)
	if not (c.preferred_range is Array and c.preferred_range.size() == 2):
		c.preferred_range = [ranged_min, ranged_max] if ranged_max > 0.0 else []
	else:
		c.preferred_range = [float(c.preferred_range[0]), maxf(float(c.preferred_range[1]), float(c.preferred_range[0]))]
	return c


static func _attacks(list, resolve_entity: Callable) -> Array:
	var out := []
	for entry in (list if list is Array else []):
		if not (entry is Dictionary):
			continue
		var a := ATTACK_DEFAULTS.duplicate(true)
		a.merge(entry, true)
		a.type = String(a.type) if String(a.type) in ATTACK_TYPES else "melee"
		a.name = String(a.name) if not String(a.name).is_empty() else a.type
		for key in ["damage", "range", "min_range", "cooldown", "windup", "recovery", "knockback", "weight", "arc", "radius",
				"projectile_speed", "spread", "speed", "duration", "health_below", "health_above"]:
			a[key] = float(a[key])
		a.range = clampf(a.range, 0.0, 64.0)
		a.windup = clampf(a.windup, 0.0, 10.0)
		a.cooldown = clampf(a.cooldown, 0.0, 600.0)
		a.count = clampi(int(a.count), 1, 16)
		a.max_summons = clampi(int(a.max_summons), 0, 32)
		a.projectile_type = int(resolve_entity.call(String(a.projectile))) if not String(a.projectile).is_empty() else -1
		a.entity_type = int(resolve_entity.call(String(a.entity))) if not String(a.entity).is_empty() else -1
		out.append(a)
	return out
