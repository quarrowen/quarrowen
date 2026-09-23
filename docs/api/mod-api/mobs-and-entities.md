# Mobs and entities

Part of the [Mod API reference](../mod-api.md). Mod API 1.0.0 · game 0.42.0


### `api.register_entity`

GDScript: `api.register_entity(entity_name: String, def: Dictionary) -> int`

JavaScript: `api.registerEntity(name: string, def: EntityDef): number`

Registers an entity type (mob, projectile, object). See EntityRegistry.register for keys. Model and
sprite paths are relative to the mod folder; sound names without a ":" are this mod's.
Returns the type id, or -1.

```gdscript
ids.grazer = api.register_entity("grazer", {"kind": "mob", "display_name": "Grazer",
	"width": 0.8, "height": 1.0, "health": 10, "speed": 2.2, "category": "animal", "persistent": true,
	"taming": {"items": ["proving:grain"], "chance": 1.0, "follow_distance": 3.0, "teleport_distance": 16.0},
	"breeding": {"items": ["proving:grain"], "cooldown": 5.0},
	"nameplate": {"show_health": true},
	# Drops, so it has a loot table another mod can extend - which is what extend_loot is for.
	"drops": [["proving:token", 1], ["proving:grain", 2]],
	"ai": {"preset": "passive", "wander_radius": 6}})
```

**See also:** `folder`, `is_excluded`, `qualified`, `register`, `register_asset`, `reload`

### `api.explode`

GDScript: `api.explode(position: Vector3, power: float, options := {}) -> Dictionary`

JavaScript: `api.explode(position, power, options)`

Sets off an explosion (see engine/server/explosions.gd): power ~3 is a mob blast. options: source,
break_blocks, drop_chance, damage (multiplier), effect, sound. Returns the explosion event.

**See also:** `blast_resistance`, `break_block`, `cast`, `damage`, `damage_player`, `get_block_v`

### `api.entity_type`

GDScript: `api.entity_type(entity_name: String) -> int`

JavaScript: `api.entityType(entityName)`

Entity type id by name ("vanilla:zombie", or a local name). -1 if unknown.

**See also:** `qualified`

### `api.spawn_entity`

GDScript: `api.spawn_entity(entity_name: String, position: Vector3, options := {})`

JavaScript: `api.spawnEntity(type: string, position: Vec3, options?: { yaw?: number; velocity?: Vec3; data?: Record<string, unknown> }): Entity | null`

Spawns an entity. options: yaw, velocity (Vector3), data (Dictionary), owner (player or entity,
for projectiles), **realm** (which world to put it in; the overworld by default). Returns the
entity or null.

`realm` matters for instances: without it every spawn landed in the overworld, so a dungeon could
be entered but never populated. (2026-09-21)

**See also:** `entity_type`, `qualified`, `register_instance`, `spawn`

### `api.spawn_projectile`

GDScript: `api.spawn_projectile(entity_name: String, from: Vector3, velocity: Vector3, owner = null, realm_id := "")`

JavaScript: `api.spawnProjectile(type: string, from: Vec3, velocity: Vec3, owner?: Player | Entity | null): Entity | null`

Fires a projectile entity from `from` with `velocity`, credited to `owner` (player or entity).

**See also:** `entity_type`, `qualified`, `register_instance`, `spawn`

### `api.get_entities`

GDScript: `api.get_entities(center: Vector3, radius: float, entity_name := "") -> Array`

JavaScript: `api.getEntities(center, radius, entityName)`

Living entities within `radius` of `center`, optionally only of one type.

**See also:** `entity_type`, `in_radius`

### `api.get_entity`

GDScript: `api.get_entity(entity_id: int)`

JavaScript: `api.getEntity(entityId)`

The entity with this id, or null if it is gone.

### `api.register_mob_behavior`

GDScript: `api.register_mob_behavior(behavior_name: String, def: Dictionary) -> void`

JavaScript: `api.registerMobBehavior(behaviorName, def)`

Registers a mob behaviour that mobs listing it in ai.behaviors can choose. `def`:
score:  Callable(brain) -> float   utility each think; the highest scoring behaviour runs.
Engine scores: idle 0.05, wander 0.1, investigate 0.4, search <= 0.65, engage 0.7-0.9,
return_home 0.95+, flee 1.05, scripted 1.2
update: Callable(brain, delta)     called each think while it runs; use brain.move_to / stop /
look_at, brain.target, brain.entity, brain.can_see_target(), brain.health_fraction()
stop:   Callable(brain)            optional, when another behaviour takes over

```gdscript
api.register_mob_behavior("forage", {
	"score": func(brain): return 0.2 if api.order_of(brain.entity) == "proving:forage" else 0.0,
	"update": func(brain, _delta): brain.stop(),
})
```

**See also:** `qualified`

### `api.make_noise`

GDScript: `api.make_noise(position: Vector3, radius: float, source = null) -> void`

JavaScript: `api.makeNoise(position, radius, source)`

Lets mobs hear something at `position` (they come to investigate). `source` may be a player.

**See also:** `category`, `place`

### `api.add_spawn_rule`

GDScript: `api.add_spawn_rule(def: Dictionary) -> void`

JavaScript: `api.addSpawnRule(rule: SpawnRule): void`

Natural spawning. def: entity (name), category ("monster" | "animal" | "ambient" | "misc"; default
from the mob's AI), light [min, max] (0-15; monsters default to [0, 7] so torches keep them away,
animals to [9, 15]), place ("any" | "surface" | "underground"), time ("night" | "day" | "any"), on
(block names the mob may stand on; default any), group [min, max] (pack size), max_nearby (per
player), max_total, chance (per player per second), min_distance, max_distance. See
engine/server/spawning.gd for caps and despawning.

```gdscript
api.add_spawn_rule({"entity": "biter", "group": [1, 2]})
```

**See also:** `add_rule`, `block`, `entity_type`, `is_excluded`, `qualified`

### `api.set_spawn_caps`

GDScript: `api.set_spawn_caps(caps: Dictionary) -> void`

JavaScript: `api.setSpawnCaps(caps)`

How many mobs of each category may be around each player: {monster, animal, ambient, misc}.

```gdscript
var apply_caps := func(): api.set_spawn_caps({"monster": int(caps.get(String(api.setting("monsters")), 24))})
```

**See also:** `set_caps`

### `api.require_entity`

GDScript: `api.require_entity(entity_name: String) -> int`

JavaScript: `api.requireEntity(entityName)`

As require_block, for an entity type.

**See also:** `entity_type`

### `api.extend_entity`

GDScript: `api.extend_entity(entity_name: String, additions: Dictionary) -> bool`

JavaScript: `api.extendEntity(entityName, additions)`

Adds to a creature another mod owns, without forking it: a new attack on their boss, another drop,
an extra behaviour.

api.extend_entity("proving:grazer", {"ai": {"attacks": [{"name": "kick", "type": "melee"}]}})

**Additive only, and that is the whole design.** Appending to a list is commutative: three mods can
each add an attack and the result does not depend on which loaded last. "Set the health to 40" is
not, and supporting it would mean inventing a conflict system nobody asked for. What can be added:
`ai.attacks`, `ai.behaviors`, `ai.phases` and `drops`. Anything else is refused and says so.

Takes effect for creatures spawned afterwards. One already walking about keeps the brain it was
given, which is why this belongs in `setup()` rather than halfway through a game.

**See also:** `entity_type`, `is_excluded`, `qualified`

### `api.set_spawn_handler`

GDScript: `api.set_spawn_handler(handler: Callable) -> void`

JavaScript: `api.setSpawnHandler(handler)`

Where a player who has never played here before starts: `handler(player) -> Vector3`.

This runs before the world around it is loaded, so it is also the right place to *build* the thing
the player should open their eyes on. Placing a structure from `player_join` instead is too late -
the player has already been put at the old position and sees themselves moved. (playtest, 2026-09-18)

```gdscript
api.set_spawn_handler(func(_player): return Vector3(0.5, GROUND_Y + 1, 0.5))
```
